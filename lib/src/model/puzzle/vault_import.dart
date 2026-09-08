import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:libcompress/libcompress.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/puzzle/vault_csv.dart';
import 'package:path_provider/path_provider.dart';

/// Public puzzle DB dump. CC0 licensed.
const kVaultDbUrl = 'https://database.lichess.org/lichess_db_puzzle.csv.zst';

/// Rows inserted per DB batch during import.
const kVaultImportBatchSize = 500;

/// File read chunk size during import. Small enough to keep memory flat.
const kVaultReadChunkSize = 1024 * 1024;

/// Progress callback: received bytes (or decoded rows), total (-1 unknown).
typedef VaultProgress = void Function(int done, int total);

/// Downloads the puzzle DB file with resume support.
/// Returns the local file. Throws on unrecoverable HTTP errors.
Future<File> downloadVaultDb({VaultProgress? onProgress, bool Function()? shouldStop}) async {
  final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/vault');
  await dir.create(recursive: true);
  final file = File('${dir.path}/lichess_db_puzzle.csv.zst');
  var have = await file.exists() ? await file.length() : 0;

  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(kVaultDbUrl));
    if (have > 0) req.headers.set(HttpHeaders.rangeHeader, 'bytes=$have-');
    final resp = await req.close();
    if (resp.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
      return file; // Already complete.
    }
    if (resp.statusCode == HttpStatus.ok) {
      have = 0; // Server ignored resume: restart.
    } else if (resp.statusCode != HttpStatus.partialContent && resp.statusCode != HttpStatus.ok) {
      throw HttpException('DB download failed: ${resp.statusCode}');
    }
    final total = resp.contentLength < 0 ? -1 : have + resp.contentLength;
    final sink = file.openWrite(mode: have > 0 ? FileMode.append : FileMode.write);
    try {
      await for (final chunk in resp) {
        if (shouldStop?.call() ?? false) break;
        sink.add(chunk);
        have += chunk.length;
        onProgress?.call(have, total);
      }
    } finally {
      await sink.flush();
      sink.close();
    }
    return file;
  } finally {
    client.close();
  }
}

/// One parsed import row, slim enough to cross cheaply in batches.
typedef VaultImportRow = ({
  PuzzleId id,
  String fen,
  IList<String> moves,
  int rating,
  ISet<String> themes,
});

/// Incremental zstd→lines bridge over libcompress streaming decode.
/// Memory stays flat: blocks decode and emit one at a time.
class ZstdVaultDecoder {
  Stream<String> bindLines(Stream<List<int>> input) {
    final bytes = input.map((c) => c is Uint8List ? c : Uint8List.fromList(c));
    return ZstdStreamCodec(
      maxSize: null,
    ).decompress(bytes).cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter());
  }
}

/// Streams a downloaded .zst DB file through the decoder and yields parsed
/// rows in batches. Memory stays flat: only one batch plus buffers live.
Stream<List<VaultImportRow>> streamVaultDbFile(File file, {bool Function()? shouldStop}) async* {
  final codec = ZstdVaultDecoder();
  var batch = <VaultImportRow>[];
  var firstLine = true;
  await for (final line in codec.bindLines(file.openRead())) {
    if (shouldStop?.call() ?? false) break;
    if (firstLine) {
      firstLine = false; // Skip the CSV header.
      continue;
    }
    final row = parseVaultCsvLine(line);
    if (row == null) continue;
    batch.add((
      id: row.puzzle.id,
      fen: row.puzzle.fen,
      moves: row.puzzle.solution,
      rating: row.puzzle.rating,
      themes: row.themes,
    ));
    if (batch.length >= kVaultImportBatchSize) {
      yield batch;
      batch = <VaultImportRow>[];
    }
  }
  if (batch.isNotEmpty) yield batch;
}
