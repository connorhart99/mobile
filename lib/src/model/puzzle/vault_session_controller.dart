import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/puzzle/offline_vault_storage.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle.dart';

final vaultSessionControllerProvider =
    NotifierProvider.autoDispose<VaultSessionController, VaultSessionState>(
      VaultSessionController.new,
      name: 'VaultSessionControllerProvider',
    );

/// Standard initial position, for state before the first puzzle loads.
const kInitialFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

class VaultSessionState {
  const VaultSessionState({
    required this.current,
    required this.position,
    required this.moveIndex,
    required this.won,
    required this.solved,
    required this.failed,
    required this.emptyVault,
  });

  factory VaultSessionState.initial() {
    return VaultSessionState(
      current: null,
      position: Chess.fromSetup(Setup.parseFen(kInitialFen)),
      moveIndex: -1,
      won: null,
      solved: 0,
      failed: 0,
      emptyVault: false,
    );
  }

  final LitePuzzle? current;
  final Position position;
  final int moveIndex;
  final bool? won;
  final int solved;
  final int failed;
  final bool emptyVault;

  Move? get lastMove =>
      moveIndex < 0 || current == null ? null : Move.parse(current!.solution[moveIndex]);

  VaultSessionState copyWith({
    LitePuzzle? current,
    Position? position,
    int? moveIndex,
    bool? won,
    int? solved,
    int? failed,
    bool? emptyVault,
    bool clearCurrent = false,
    bool clearWon = false,
  }) {
    return VaultSessionState(
      current: clearCurrent ? null : (current ?? this.current),
      position: position ?? this.position,
      moveIndex: moveIndex ?? this.moveIndex,
      won: clearWon ? null : (won ?? this.won),
      solved: solved ?? this.solved,
      failed: failed ?? this.failed,
      emptyVault: emptyVault ?? this.emptyVault,
    );
  }
}

class VaultSessionController extends Notifier<VaultSessionState> {
  @override
  VaultSessionState build() {
    Future.microtask(loadNext);
    return VaultSessionState.initial();
  }

  Future<void> loadNext() async {
    final userId = ref.read(authControllerProvider)?.user.id;
    final storage = await ref.read(offlineVaultStorageProvider.future);
    final next = await storage.fetchNextLite(userId: userId);
    if (!ref.mounted) return;
    if (next == null) {
      state = state.copyWith(clearCurrent: true, emptyVault: true);
      return;
    }
    final firstMove = Move.parse(next.solution.first)!;
    final position = Chess.fromSetup(Setup.parseFen(next.fen)).play(firstMove);
    state = state.copyWith(
      current: next,
      position: position,
      moveIndex: 0,
      emptyVault: false,
      clearWon: true,
    );
  }

  Future<void> onUserMove(Move move) async {
    final puzzle = state.current;
    if (puzzle == null || state.won != null || state.emptyVault) return;
    if (state.moveIndex + 1 >= puzzle.solution.length) return;

    final expected = Move.parse(puzzle.solution[state.moveIndex + 1]);
    if (move != expected) {
      state = state.copyWith(won: false, failed: state.failed + 1);
      await _markDone(puzzle, win: false);
      return;
    }

    final newPosition = state.position.play(move);
    final newMoveIndex = state.moveIndex + 1;
    if (newMoveIndex >= puzzle.solution.length - 1) {
      state = state.copyWith(position: newPosition, moveIndex: newMoveIndex, won: true);
      state = state.copyWith(solved: state.solved + 1);
      await _markDone(puzzle, win: true);
      return;
    }

    state = state.copyWith(position: newPosition, moveIndex: newMoveIndex);

    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!ref.mounted) return;
    if (state.current?.id != puzzle.id || state.won != null) return;
    if (state.moveIndex + 1 >= puzzle.solution.length) return;

    final reply = Move.parse(puzzle.solution[state.moveIndex + 1])!;
    state = state.copyWith(position: state.position.play(reply), moveIndex: state.moveIndex + 1);
  }

  Future<void> giveUp() async {
    final puzzle = state.current;
    if (puzzle == null || state.won != null) return;
    state = state.copyWith(won: false, failed: state.failed + 1);
    await _markDone(puzzle, win: false);
  }

  Future<void> next() async {
    state = state.copyWith(moveIndex: -1, clearWon: true);
    await loadNext();
  }

  Future<void> _markDone(LitePuzzle puzzle, {required bool win}) async {
    final userId = ref.read(authControllerProvider)?.user.id;
    final storage = await ref.read(offlineVaultStorageProvider.future);
    await storage.markDone(userId: userId, puzzleId: puzzle.id.value, win: win);
  }
}
