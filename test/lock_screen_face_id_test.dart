import 'package:anibee/screens/lock_screen.dart';
import 'package:anibee/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 0.2.9 Face ID auto-prompt: in unlock mode, when Face ID is
/// enabled, the prompt fires automatically as soon as the lock
/// screen appears — no tap on the Face ID button, no PIN. A failed /
/// cancelled prompt stays silently on the PIN keypad (no error loop,
/// no repeated prompt); the button retries, the PIN always works.
/// Setup mode is unchanged (manual flow only).
class FakeLocalAuth extends LocalAuthentication {
  FakeLocalAuth({this.canCheck = true, this.result = true});

  final bool canCheck;
  final bool result;
  int authenticateCalls = 0;

  @override
  Future<bool> get canCheckBiometrics async => canCheck;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    // local_auth 3.x: the platform-specific message classes
    // (IOSAuthMessages etc.) no longer exist, and the public barrel
    // does not export AuthMessages — so the parameter is widened to
    // Iterable<Object?> (a valid supertype of the base's
    // Iterable<AuthMessages>) instead of importing the transitive
    // platform-interface package. The fake ignores this parameter;
    // the default is an empty list.
    Iterable<Object?> authMessages = const <Object?>[],
    bool biometricOnly = false,
    bool sensitiveTransaction = true,
    bool persistAcrossBackgrounding = false,
  }) async {
    authenticateCalls++;
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall call) async => null,
    );
  });

  Future<SettingsStore> loadStore({bool faceId = false}) async {
    final SettingsStore store = await SettingsStore.load();
    store.faceIdEnabled = faceId;
    return store;
  }

  Future<void> pumpLock(
    WidgetTester tester, {
    required SettingsStore store,
    required LockMode mode,
    LocalAuthentication? auth,
    VoidCallback? onUnlocked,
  }) async {
    // Phone-sized viewport: the lock screen's Column overflows the
    // default 600pt test height by ~40px (it is laid out for a
    // phone screen, ~932pt tall).
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: LockScreen(
          mode: mode,
          store: store,
          auth: auth,
          onUnlocked: onUnlocked,
        ),
      ),
    );
    // The auto-prompt runs in a post-frame callback, then the fake
    // authenticate resolves.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('unlock mode + Face ID on: auto-prompts and unlocks', (
    WidgetTester tester,
  ) async {
    final FakeLocalAuth auth = FakeLocalAuth(result: true);
    bool unlocked = false;
    await pumpLock(
      tester,
      store: await loadStore(faceId: true),
      mode: LockMode.unlock,
      auth: auth,
      onUnlocked: () => unlocked = true,
    );
    expect(auth.authenticateCalls, 1);
    expect(unlocked, isTrue);
  });

  testWidgets('unlock mode + Face ID off: no auto-prompt, PIN stays', (
    WidgetTester tester,
  ) async {
    final FakeLocalAuth auth = FakeLocalAuth(result: true);
    bool unlocked = false;
    await pumpLock(
      tester,
      store: await loadStore(faceId: false),
      mode: LockMode.unlock,
      auth: auth,
      onUnlocked: () => unlocked = true,
    );
    expect(auth.authenticateCalls, 0);
    expect(unlocked, isFalse);
    expect(find.text('Enter Passcode'), findsOneWidget);
  });

  testWidgets('setup mode: no auto-prompt even with Face ID on', (
    WidgetTester tester,
  ) async {
    final FakeLocalAuth auth = FakeLocalAuth(result: true);
    await pumpLock(
      tester,
      store: await loadStore(faceId: true),
      mode: LockMode.setup,
      auth: auth,
    );
    expect(auth.authenticateCalls, 0);
    expect(find.text('Set Passcode'), findsOneWidget);
  });

  testWidgets('cancelled auto-prompt: silent PIN keypad, button retries', (
    WidgetTester tester,
  ) async {
    final FakeLocalAuth auth = FakeLocalAuth(result: false);
    bool unlocked = false;
    await pumpLock(
      tester,
      store: await loadStore(faceId: true),
      mode: LockMode.unlock,
      auth: auth,
      onUnlocked: () => unlocked = true,
    );
    // One automatic attempt, then silence — no error, no loop.
    expect(auth.authenticateCalls, 1);
    expect(unlocked, isFalse);
    expect(find.text('Enter Passcode'), findsOneWidget);
    expect(find.text('Face ID failed. Enter your passcode.'), findsNothing);
    // The Face ID button retries on tap.
    await tester.tap(find.text('Face ID'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(auth.authenticateCalls, 2);
    expect(unlocked, isFalse);
  });
}
