import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/puzzle/offline_vault_prefs.dart';
import 'package:lichess_mobile/src/model/puzzle/offline_vault_storage.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_preferences.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_repository.dart';
import 'package:lichess_mobile/src/model/puzzle/vault_import.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:logging/logging.dart';

/// Server-path ceiling: bigger goals use the puzzle file import instead.
/// Storm batches are small and unrated, so large server fills would hammer
/// the server and take forever.
const kVaultServerFillMax = 5000;

/// Delay between fill requests, to spread load on the server.
const _kFillDelay = Duration(milliseconds: 300);

/// Fill progress. Plain class on purpose: no codegen step needed.
class VaultFillState {
  const VaultFillState({
    this.running = false,
    this.kept = 0,
    this.target = 0,
    this.phase = '',
    this.error = '',
    this.dlDone = 0,
    this.dlTotal = -1,
  });

  final bool running;
  final int kept;
  final int target;
  final String phase;
  final String error;

  /// File download bytes (phase `file-download`). Total -1 when unknown.
  final int dlDone;
  final int dlTotal;

  double get progress => target <= 0 ? 0 : (kept / target).clamp(0.0, 1.0);

  VaultFillState copyWith({
    bool? running,
    int? kept,
    int? target,
    String? phase,
    String? error,
    int? dlDone,
    int? dlTotal,
  }) => VaultFillState(
    running: running ?? this.running,
    kept: kept ?? this.kept,
    target: target ?? this.target,
    phase: phase ?? this.phase,
    error: error ?? this.error,
    dlDone: dlDone ?? this.dlDone,
    dlTotal: dlTotal ?? this.dlTotal,
  );
}

final offlineVaultFillerProvider = NotifierProvider<OfflineVaultFiller, VaultFillState>(
  OfflineVaultFiller.new,
  name: 'OfflineVaultFillerProvider',
);

/// Fills the vault to the configured goal, one small batch at a time.
///
/// Works logged out: the storm endpoint needs no account. Never throws:
/// failures stop the fill and land in [VaultFillState.error].
class OfflineVaultFiller extends Notifier<VaultFillState> {
  final Logger _log = Logger('OfflineVaultFiller');
  bool _stop = false;

  @override
  VaultFillState build() => const VaultFillState();

  void stop() {
    _stop = true;
  }

  /// Starts a fill to the configured goal: server batches for small goals,
  /// puzzle-file download plus import for big ones.
  Future<void> start() async {
    if (state.running) return;
    _stop = false;
    final prefs = ref.read(offlineVaultPrefsProvider);
    if (prefs.targetCount > kVaultServerFillMax) {
      await _fillFromFile(prefs.targetCount);
    } else {
      await _fillFromServer(prefs.targetCount);
    }
    ref.invalidate(offlineVaultStatsProvider);
  }

  Future<void> _fillFromServer(int target) async {
    state = VaultFillState(running: true, target: target, phase: 'server');
    try {
      final userId = ref.read(authControllerProvider)?.user.id;
      final storage = await ref.read(offlineVaultStorageProvider.future);
      final repository = ref.read(puzzleRepositoryProvider);
      var kept = await storage.countKept(userId: userId);
      var stillSame = 0;
      while (kept < target) {
        if (_stop) break;
        try {
          final resp = await repository.storm();
          if (resp.puzzles.isEmpty) break;
          await storage.insertLiteBatch(
            userId: userId,
            puzzles: resp.puzzles,
            themesById: const {},
          );
        } catch (e, st) {
          _log.warning('Vault server fill failed', e, st);
          state = state.copyWith(error: 'Fill stopped: no link or server said no.');
          break;
        }
        final now = await storage.countKept(userId: userId);
        stillSame = now == kept ? stillSame + 1 : 0;
        kept = now;
        // Server repeats itself when out of fresh puzzles: stop, don't spin.
        if (stillSame >= 3) break;
        state = state.copyWith(kept: kept);
        await Future<void>.delayed(_kFillDelay);
      }
      state = state.copyWith(kept: kept);
      ref.invalidate(offlineVaultStatsProvider);
    } finally {
      state = state.copyWith(running: false, phase: '');
    }
  }

  /// File path: download the DB dump once (resumes), then stream rows in.
  /// `target` of 6000000 (mode `all`) means no cap.
  Future<void> _fillFromFile(int target) async {
    state = VaultFillState(running: true, target: target, phase: 'file-download');
    final cap = target >= 6000000 ? null : target;
    try {
      final userId = ref.read(authControllerProvider)?.user.id;
      final storage = await ref.read(offlineVaultStorageProvider.future);
      final file = await downloadVaultDb(
        onProgress: (done, total) {
          if (state.running) state = state.copyWith(dlDone: done, dlTotal: total);
        },
        shouldStop: () => _stop,
      );
      if (_stop) return;
      var kept = await storage.countKept(userId: userId);
      state = state.copyWith(phase: 'file-import', kept: kept);
      await for (final batch in streamVaultDbFile(file, shouldStop: () => _stop)) {
        if (_stop) break;
        if (cap != null && kept >= cap) break;
        var rows = batch;
        if (cap != null && kept + rows.length > cap) {
          rows = rows.sublist(0, cap - kept);
        }
        await storage.insertLiteBatch(
          userId: userId,
          puzzles: [
            for (final r in rows)
              LitePuzzle(id: r.id, fen: r.fen, solution: r.moves, rating: r.rating),
          ],
          themesById: {for (final r in rows) r.id: r.themes},
        );
        kept = await storage.countKept(userId: userId);
        state = state.copyWith(kept: kept);
      }
      await storage.prune(userId: userId, keep: cap ?? kept);
      kept = await storage.countKept(userId: userId);
      state = state.copyWith(kept: kept);
      ref.invalidate(offlineVaultStatsProvider);
    } catch (e, st) {
      _log.warning('Vault file import failed', e, st);
      if (state.running) state = state.copyWith(error: 'Import stopped: $e');
    } finally {
      state = state.copyWith(running: false, phase: '');
    }
  }

  /// Pushes solved vault rows when signed in, drops them, tops up.
  /// Logged out: keeps local progress, reports that sync needs sign-in.
  Future<void> sync() async {
    if (state.running) return;
    final userId = ref.read(authControllerProvider)?.user.id;
    if (userId == null) {
      state = state.copyWith(error: 'Sign in to sync solved vault puzzles.');
      return;
    }
    state = const VaultFillState(running: true, phase: 'sync');
    try {
      final storage = await ref.read(offlineVaultStorageProvider.future);
      final difficulty = ref.read(puzzlePreferencesProvider).difficulty;
      final done = await storage.fetchDoneBatch(userId: userId, limit: 50);
      if (done.isNotEmpty) {
        final solved = IList([
          for (final r in done)
            PuzzleSolution(
              id: PuzzleId((r['puzzleId'] as String?) ?? ''),
              win: (r['win'] as num?)?.toInt() == 1,
              rated: (r['rated'] as num?)?.toInt() == 1,
            ),
        ]);
        try {
          await ref.withClient(
            (client) =>
                PuzzleRepository(client).solveBatch(nb: 0, solved: solved, difficulty: difficulty),
          );
        } catch (e, st) {
          _log.warning('Vault sync failed', e, st);
          state = state.copyWith(error: 'Sync stopped: no link or server said no.');
          return;
        }
      }
      final target = ref.read(offlineVaultPrefsProvider).targetCount;
      await storage.prune(userId: userId, keep: target);
      ref.invalidate(offlineVaultStatsProvider);
    } finally {
      state = state.copyWith(running: false, phase: '');
    }
  }
}
