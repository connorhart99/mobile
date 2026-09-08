import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/puzzle/offline_vault_filler.dart';
import 'package:lichess_mobile/src/model/puzzle/offline_vault_prefs.dart';
import 'package:lichess_mobile/src/model/puzzle/offline_vault_storage.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/puzzle/vault_session_screen.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
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

/// Full settings screen for the offline vault.
///
/// One mode active at a time (count, MB target, or all). Nothing is stored
/// until Save is tapped; the app bar always goes back without saving.
/// Built only from shared app widgets.
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

    return PlatformScaffold(
      appBar: PlatformAppBar(title: const Text('Offline vault')),
      body: ListView(
        children: [
          ListSection(
            header: const Text('Goal'),
            footer: const Text(
              'One choice at a time. Sizes open inline. Nothing changes until you tap Save.',
            ),
            children: [
              RadioGroup<OfflineVaultMode>(
                groupValue: _mode,
                onChanged: (m) => setState(() => _mode = m ?? _mode),
                child: Column(
                  children: [
                    const RadioListTile<OfflineVaultMode>(
                      title: Text('Puzzle count'),
                      subtitle: Text('Keep an exact number of puzzles.'),
                      value: OfflineVaultMode.count,
                    ),
                    if (_mode == OfflineVaultMode.count)
                      _InlineSizeChoices(_countOptions, _count, (n) => setState(() => _count = n)),
                    const RadioListTile<OfflineVaultMode>(
                      title: Text('Storage size'),
                      subtitle: Text('Fill up to a size in MB.'),
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
                      title: Text('Everything'),
                      subtitle: Text('Keep the whole set. Needs lots of space and Wi-Fi.'),
                      value: OfflineVaultMode.all,
                    ),
                  ],
                ),
              ),
            ],
          ),
          ListSection(
            header: const Text('On this phone'),
            children: [
              if (fill.running) _FillProgress(fill: fill),
              if (fill.error.isNotEmpty)
                ListTile(title: const Text('Last message'), subtitle: Text(fill.error)),
              stats.when(
                data: (s) => Column(
                  children: [
                    ListTile(title: const Text('Goal'), trailing: Text('${s.target}')),
                    ListTile(title: const Text('Stored'), trailing: Text('${s.kept}')),
                    ListTile(title: const Text('Solved'), trailing: Text('${s.done}')),
                  ],
                ),
                loading: () => const ListTile(title: Text('Stored'), trailing: Text('…')),
                error: (_, _) => const ListTile(title: Text('Stored'), trailing: Text('?')),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                    child: const Text('Stop'),
                  )
                else
                  OutlinedButton(
                    onPressed: () => ref.read(offlineVaultFillerProvider.notifier).start(),
                    child: const Text('Download now'),
                  ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: fill.running
                      ? null
                      : () => ref.read(offlineVaultFillerProvider.notifier).sync(),
                  child: const Text('Sync solved'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: _wipe, child: const Text('Delete stored puzzles')),
              ],
            ),
          ),
        ],
      ),
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
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: value),
        ],
      ),
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
      padding: const EdgeInsets.fromLTRB(56.0, 0, 16.0, 8.0),
      child: Wrap(
        spacing: 8.0,
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
