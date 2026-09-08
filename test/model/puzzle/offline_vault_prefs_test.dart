import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/puzzle/offline_vault_prefs.dart';

void main() {
  group('OfflineVaultPrefs.targetCount', () {
    test('count mode passes through clamped', () {
      expect(
        const OfflineVaultPrefs(
          mode: OfflineVaultMode.count,
          mbTarget: 0,
          countTarget: 1000,
        ).targetCount,
        1000,
      );
    });

    test('mb mode maps through row size', () {
      const prefs = OfflineVaultPrefs(mode: OfflineVaultMode.mb, mbTarget: 50, countTarget: 100);
      expect(prefs.targetCount, greaterThan(100000));
    });

    test('all means everything', () {
      expect(
        const OfflineVaultPrefs(
          mode: OfflineVaultMode.all,
          mbTarget: 0,
          countTarget: 100,
        ).targetCount,
        6000000,
      );
    });
  });

  test('needsFileImport flips past the server ceiling', () {
    const small = OfflineVaultPrefs(mode: OfflineVaultMode.count, mbTarget: 0, countTarget: 1000);
    const big = OfflineVaultPrefs(mode: OfflineVaultMode.count, mbTarget: 0, countTarget: 20000);
    expect(small.needsFileImport, isFalse);
    expect(big.needsFileImport, isTrue);
  });

  test('json round trip', () {
    const prefs = OfflineVaultPrefs(mode: OfflineVaultMode.mb, mbTarget: 50, countTarget: 100);
    expect(OfflineVaultPrefs.fromJson(prefs.toJson()), isA<OfflineVaultPrefs>());
    expect(OfflineVaultPrefs.fromJson(prefs.toJson()).mode, OfflineVaultMode.mb);
  });
}
