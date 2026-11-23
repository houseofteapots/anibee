import 'package:anibee/settings_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 0.2.11: the new player/download settings — autoplay countdown
/// (3/5/10s, clamped), auto-delete watched downloads (default ON).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async => null,
    );
  });

  test('autoplay countdown defaults to 5 and clamps to 3..10', () async {
    final SettingsStore store = await SettingsStore.load();
    expect(store.autoplayCountdownSeconds, 5);
    await store.setAutoplayCountdownSeconds(3);
    expect(store.autoplayCountdownSeconds, 3);
    await store.setAutoplayCountdownSeconds(10);
    expect(store.autoplayCountdownSeconds, 10);
    await store.setAutoplayCountdownSeconds(1);
    expect(store.autoplayCountdownSeconds, 3);
    await store.setAutoplayCountdownSeconds(99);
    expect(store.autoplayCountdownSeconds, 10);
    await store.setAutoplayCountdownSeconds(5);
  });

  test('auto-delete watched downloads defaults to ON', () async {
    final SettingsStore store = await SettingsStore.load();
    expect(store.autoDeleteDownloads, isTrue);
    await store.setAutoDeleteDownloads(false);
    expect(store.autoDeleteDownloads, isFalse);
    await store.setAutoDeleteDownloads(true);
    expect(store.autoDeleteDownloads, isTrue);
  });
}
