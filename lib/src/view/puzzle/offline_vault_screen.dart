import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/puzzle/offline_vault_filler.dart';
import 'package:lichess_mobile/src/model/puzzle/offline_vault_prefs.dart';
import 'package:lichess_mobile/src/model/puzzle/offline_vault_storage.dart';
import 'package:lichess_mobile/src/network/connectivity.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/puzzle/vault_session_screen.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:material_ui/material_ui.dart';

/// Human label for the current vault goal. Hardcoded English until stable.
String offlineVaultLabel(OfflineVaultPrefs prefs) {
  return switch (prefs.mode) {
    OfflineVaultMode.count => '${prefs.countTarget} puzzles',
    OfflineVaultMode.mb => '${prefs.mbTarget} MB (~${prefs.targetCount} puzzles)',
    OfflineVaultMode.all => 'All puzzles',
  };
}

/// Vault settings on one screen, no scroll.
///
/// Goal radios open their sizes inline. Nothing is stored until Save.
/// Solved rows sync on their own when online and signed in.
class OfflineVaultScreen extends ConsumerStatefulWidget {
  const OfflineVaultScreen({super.key});

  static Route<dynamic> buildRoute() {
    return buildScreenRoute(screen: const OfflineVaultScreen());
  }

  @override
  ConsumerState<OfflineVaultScreen> createState() => _OfflineVaultScreenState();
}

class _OfflineVaultScreenState extends ConsumerState<OfflineVaultScreen> {
  late OfflineVaultMode _mode;
  late int _count;
  late int _mb;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(offlineVaultPrefsProvider);
    _mode = prefs.mode;
    _count = prefs.countTarget;
    _mb = prefs.mbTarget == 0 ? 50 : prefs.mbTarget;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(offlineVaultFillerProvider.notifier)
          .autoSyncIfNeeded(isOnline: ref.read(isDeviceOnlineProvider));
    });
  }

  bool get _dirty {
    final prefs = ref.read(offlineVaultPrefsProvider);
    return _mode != prefs.mode || _count != prefs.countTarget || _mb != prefs.mbTarget;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final notifier = ref.read(offlineVaultPrefsProvider.notifier);
    switch (_mode) {
      case OfflineVaultMode.count:
        await notifier.setCount(_count);
      case OfflineVaultMode.mb:
        await notifier.setMb(_mb);
      case OfflineVaultMode.all:
        await notifier.setAll();
    }
    if (!mounted) return;
    setState(() => _saving = false);
    showSnackBar(context, 'Offline vault goal saved.');
    Navigator.of(context).pop();
  }

  Future<void> _wipe() async {
    final userId = ref.read(authControllerProvider)?.user.id;
    final storage = await ref.read(offlineVaultStorageProvider.future);
    await storage.wipe(userId: userId);
    ref.invalidate(offlineVaultStatsProvider);
    if (!mounted) return;
    showSnackBar(context, 'Stored vault puzzles deleted.');
  }

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(offlineVaultStatsProvider);
    final fill = ref.watch(offlineVaultFillerProvider);
    final kept = stats.value?.kept ?? 0;
    final done = stats.value?.done ?? 0;
    final target = stats.value?.target ?? 0;

    return PlatformScaffold(
      appBar: PlatformAppBar(
        title: const Text('Offline vault'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'wipe') _wipe();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'wipe', child: Text('Delete stored puzzles')),
            ],
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RadioGroup<OfflineVaultMode>(
              groupValue: _mode,
              onChanged: (m) => setState(() => _mode = m ?? _mode),
              child: Column(
                mainAxisSize: .min,
                children: [
                  const RadioListTile<OfflineVaultMode>(
                    dense: true,
                    title: Text('Puzzle count'),
                    value: OfflineVaultMode.count,
                  ),
                  if (_mode == OfflineVaultMode.count)
                    _InlineSizeChoices(_countOptions, _count, (n) => setState(() => _count = n)),
                  const RadioListTile<OfflineVaultMode>(
                    dense: true,
                    title: Text('Storage size'),
                    value: OfflineVaultMode.mb,
                  ),
                  if (_mode == OfflineVaultMode.mb)
                    _InlineSizeChoices(
                      _mbOptions,
                      _mb,
                      (n) => setState(() => _mb = n),
                      suffix: ' MB',
                    ),
                  const RadioListTile<OfflineVaultMode>(
                    dense: true,
                    title: Text('Everything'),
                    value: OfflineVaultMode.all,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: .spaceAround,
              children: [
                _Stat(label: 'Goal', value: '$target'),
                _Stat(label: 'Stored', value: '$kept'),
                _Stat(label: 'Solved', value: '$done'),
              ],
            ),
            if (fill.running) ...[
              const SizedBox(height: 4),
              _FillProgress(fill: fill),
            ] else if (fill.error.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(fill.error, style: const TextStyle(fontSize: 12)),
            ],
            const Spacer(),
            FilledButton(
              onPressed: _dirty && !_saving ? _save : null,
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: kept > 0 && !fill.running
                  ? () => Navigator.of(context).push(OfflineVaultSessionScreen.buildRoute())
                  : null,
              child: const Text('Play offline'),
            ),
            const SizedBox(height: 8),
            if (fill.running)
              OutlinedButton(
                onPressed: () => ref.read(offlineVaultFillerProvider.notifier).stop(),
                child: const Text('Stop download'),
              )
            else
              OutlinedButton(
                onPressed: () => ref.read(offlineVaultFillerProvider.notifier).start(),
                child: const Text('Download now'),
              ),
          ],
        ),
      ),
    );
  }
}

/// One compact Goal/Stored/Solved cell.
class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      children: [
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: .w600)),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

/// Live fill progress. Plain widget class per project style rules.
class _FillProgress extends StatelessWidget {
  const _FillProgress({required this.fill});

  final VaultFillState fill;

  @override
  Widget build(BuildContext context) {
    final label = switch (fill.phase) {
      'server' => 'Fetching ${fill.kept}/${fill.target}…',
      'file-download' =>
        fill.dlTotal > 0
            ? 'File ${(fill.dlDone / 1048576).toStringAsFixed(0)}/${(fill.dlTotal / 1048576).toStringAsFixed(0)} MB…'
            : 'File ${(fill.dlDone / 1048576).toStringAsFixed(0)} MB…',
      'file-import' => 'Saving ${fill.kept}/${fill.target}…',
      'sync' => 'Syncing solved…',
      _ => 'Working…',
    };
    final value = fill.phase == 'file-download' && fill.dlTotal > 0
        ? (fill.dlDone / fill.dlTotal).clamp(0.0, 1.0)
        : fill.target > 0
        ? fill.progress
        : null;
    return Column(
      crossAxisAlignment: .start,
      mainAxisSize: .min,
      children: [
        Text(label, style: const TextStyle(fontSize: 12)),
        LinearProgressIndicator(value: value),
      ],
    );
  }
}

const _countOptions = [100, 500, 1000, 5000, 20000, 100000];
const _mbOptions = [10, 50, 100, 250, 500, 1000];

/// Inline size choices shown under the selected goal.
/// A widget class (not a helper function) per project style rules.
class _InlineSizeChoices extends StatelessWidget {
  const _InlineSizeChoices(this.options, this.selected, this.onPick, {this.suffix = ''});

  final List<int> options;
  final int selected;
  final void Function(int) onPick;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(52.0, 0, 8.0, 4.0),
      child: Wrap(
        spacing: 6.0,
        runSpacing: 2.0,
        children: [
          for (final n in options)
            ChoiceChip(
              label: Text('$n$suffix'),
              selected: n == selected,
              onSelected: (_) => onPick(n),
            ),
        ],
      ),
    );
  }
}
