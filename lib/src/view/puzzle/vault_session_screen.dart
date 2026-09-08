import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/puzzle/vault_session_controller.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/widgets/board.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:material_ui/material_ui.dart';

class OfflineVaultSessionScreen extends ConsumerStatefulWidget {
  const OfflineVaultSessionScreen({super.key});

  static Route<dynamic> buildRoute() {
    return buildScreenRoute(screen: const OfflineVaultSessionScreen());
  }

  @override
  ConsumerState<OfflineVaultSessionScreen> createState() => _OfflineVaultSessionScreenState();
}

class _OfflineVaultSessionScreenState extends ConsumerState<OfflineVaultSessionScreen> {
  late final ChessboardController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ChessboardController(game: _buildGameData());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  PlayerSide _playerSide(VaultSessionState state) {
    if (state.current == null || state.won != null) {
      return PlayerSide.none;
    }
    return state.position.turn == Side.white ? PlayerSide.white : PlayerSide.black;
  }

  GameData _buildGameData() {
    final state = ref.read(vaultSessionControllerProvider);
    final boardPreferences = ref.read(boardPreferencesProvider);
    return buildGameData(
      fen: state.position.fen,
      variant: Variant.standard,
      position: state.position,
      playerSide: _playerSide(state),
      lastMove: state.lastMove,
      castlingMethod: boardPreferences.castlingMethod,
      boardHighlights: boardPreferences.boardHighlights,
    );
  }

  void _applyBoardUpdate() {
    _controller.updatePosition(_buildGameData());
  }

  @override
  Widget build(BuildContext context) {
    final boardPreferences = ref.watch(boardPreferencesProvider);
    final sessionState = ref.watch(vaultSessionControllerProvider);

    ref.listen(
      vaultSessionControllerProvider.select(
        (s) => (fen: s.position.fen, lastMoveUci: s.lastMove?.uci, side: _playerSide(s)),
      ),
      (_, _) => _applyBoardUpdate(),
    );
    ref.listen(
      boardPreferencesProvider.select((p) => (p.castlingMethod, p.boardHighlights)),
      (_, _) => _applyBoardUpdate(),
    );

    final defaultSettings = boardPreferences.toBoardSettings(Variant.standard);

    return PlatformScaffold(
      appBar: PlatformAppBar(title: const Text('Offline vault')),
      body: sessionState.emptyVault
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Vault is empty. Set a goal on the Offline vault screen.'),
                    const SizedBox(height: 16.0),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Back'),
                    ),
                  ],
                ),
              ),
            )
          : sessionState.current == null
          ? const Center(child: CircularProgressIndicator.adaptive())
          : LayoutBuilder(
              builder: (context, constraints) {
                final boardSize = constraints.maxWidth < constraints.maxHeight
                    ? constraints.maxWidth
                    : constraints.maxHeight - 200.0;
                return SingleChildScrollView(
                  child: Column(
                    children: [
                      BoardWidget(
                        size: boardSize,
                        controller: _controller,
                        onMove: (move, {viaDragAndDrop}) =>
                            ref.read(vaultSessionControllerProvider.notifier).onUserMove(move),
                        orientation: sessionState.position.turn,
                        settings: defaultSettings,
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            Text('Rating: ${sessionState.current!.rating}'),
                            const SizedBox(height: 8.0),
                            if (sessionState.won == true) const Text('Solved!'),
                            if (sessionState.won == false) const Text('Failed'),
                            const SizedBox(height: 8.0),
                            Text('Solved: ${sessionState.solved} Failed: ${sessionState.failed}'),
                            const SizedBox(height: 16.0),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                OutlinedButton(
                                  onPressed: sessionState.won != null
                                      ? null
                                      : () => ref
                                            .read(vaultSessionControllerProvider.notifier)
                                            .giveUp(),
                                  child: const Text('Give up'),
                                ),
                                if (sessionState.won != null)
                                  FilledButton(
                                    onPressed: () =>
                                        ref.read(vaultSessionControllerProvider.notifier).next(),
                                    child: const Text('Next'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
