import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/puzzle/offline_vault_prefs.dart';
import 'package:lichess_mobile/src/model/puzzle/offline_vault_storage.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/widgets/adaptive_choice_picker.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:lichess_mobile/src/widgets/settings.dart';
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

  Future<void> _pickSize() async {
    if (_mode == OfflineVaultMode.count) {
      const choices = [100, 500, 1000, 5000, 20000, 100000];
      int sel = _count;
      await showChoicePicker(
        context,
        choices: choices,
        selectedItem: choices.contains(sel) ? sel : 1000,
        labelBuilder: (t) => Text(t.toString()),
        onSelectedItemChanged: (int? n) {
          if (n != null) sel = n;
        },
      );
      if (mounted) setState(() => _count = sel);
    } else if (_mode == OfflineVaultMode.mb) {
      const choices = [10, 50, 100, 250, 500, 1000];
      int sel = _mb;
      await showChoicePicker(
        context,
        choices: choices,
        selectedItem: choices.contains(sel) ? sel : 50,
        labelBuilder: (t) => Text('$t MB'),
        onSelectedItemChanged: (int? n) {
          if (n != null) sel = n;
        },
      );
      if (mounted) setState(() => _mb = sel);
    }
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
    final storage = await ref.read(offlineVaultStorageProvider.future);
    await storage.wipe(userId: null, angle: 'mix');
    ref.invalidate(offlineVaultStatsProvider);
    if (!mounted) return;
    showSnackBar(context, 'Stored vault puzzles deleted.');
  }

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(offlineVaultStatsProvider);
    final draft = OfflineVaultPrefs(mode: _mode, mbTarget: _mb, countTarget: _count);

    return PlatformScaffold(
      appBar: PlatformAppBar(title: const Text('Offline vault')),
      body: ListView(
        children: [
          ListSection(
            header: const Text('Goal'),
            footer: const Text(
              'One choice at a time. Nothing changes until you tap Save. Download and play land in the next update.',
            ),
            children: [
              RadioGroup<OfflineVaultMode>(
                groupValue: _mode,
                onChanged: (m) => setState(() => _mode = m ?? _mode),
                child: const Column(
                  children: [
                    RadioListTile<OfflineVaultMode>(
                      title: Text('Puzzle count'),
                      subtitle: Text('Keep an exact number of puzzles.'),
                      value: OfflineVaultMode.count,
                    ),
                    RadioListTile<OfflineVaultMode>(
                      title: Text('Storage size'),
                      subtitle: Text('Fill up to a size in MB.'),
                      value: OfflineVaultMode.mb,
                    ),
                    RadioListTile<OfflineVaultMode>(
                      title: Text('Everything'),
                      subtitle: Text('Keep the whole set. Needs lots of space and Wi-Fi.'),
                      value: OfflineVaultMode.all,
                    ),
                  ],
                ),
              ),
              SettingsListTile(
                settingsLabel: const Text('Size'),
                settingsValue: offlineVaultLabel(draft),
                enabled: _mode != OfflineVaultMode.all,
                onTap: _mode == OfflineVaultMode.all ? null : _pickSize,
              ),
            ],
          ),
          ListSection(
            header: const Text('On this phone'),
            children: [
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
                OutlinedButton(onPressed: _wipe, child: const Text('Delete stored puzzles')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
