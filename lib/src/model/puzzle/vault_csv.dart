import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle.dart';

/// Maps lichess puzzle DB CSV rows to [LitePuzzle].
///
/// DB header:
/// `PuzzleId,FEN,Moves,Rating,RatingDeviation,Popularity,NbPlays,Themes,GameUrl,OpeningTags`
/// `Moves` is the full UCI line: first move is the opponent setup move
/// (auto-played), the rest is the solution. Same shape as the storm API
/// `line`, so mapping is direct.
typedef VaultCsvRow = ({LitePuzzle puzzle, ISet<String> themes});

/// Splits one CSV line on commas, honouring double-quoted fields.
List<String> splitCsvLine(String line) {
  final fields = <String>[];
  final buf = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == '"') {
      if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
        buf.write('"');
        i++;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (c == ',' && !inQuotes) {
      fields.add(buf.toString());
      buf.clear();
    } else {
      buf.write(c);
    }
  }
  fields.add(buf.toString());
  return fields;
}

/// Parses one DB data line (header excluded). Returns null when the line
/// is blank or malformed, so bad rows never stop an import.
VaultCsvRow? parseVaultCsvLine(String line) {
  if (line.isEmpty) return null;
  final f = splitCsvLine(line);
  if (f.length < 8) return null;
  final id = f[0].trim();
  final fen = f[1].trim();
  final moves = f[2].trim().split(' ').where((m) => m.isNotEmpty).toIList();
  final rating = int.tryParse(f[3].trim());
  if (id.isEmpty || fen.isEmpty || moves.isEmpty || rating == null) return null;
  final themes = f[7].trim().split(' ').where((t) => t.isNotEmpty).toISet();
  return (
    puzzle: LitePuzzle(id: PuzzleId(id), fen: fen, solution: moves, rating: rating),
    themes: themes,
  );
}

/// Row goal from an MB target using a measured bytes-per-row average.
int mbToRowCount(int mb, {int bytesPerRow = 500}) {
  final n = (mb * 1024 * 1024) ~/ bytesPerRow;
  return n.clamp(100, 6000000);
}
