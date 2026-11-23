import 'dart:convert';

import 'package:anibee/app_shell.dart';
import 'package:anibee/services/airing_notifications.dart';
import 'package:anibee/services/airing_service.dart';
import 'package:anibee/services/anilist_service.dart';
import 'package:anibee/services/app_services.dart';
import 'package:anibee/services/debrid_service.dart';
import 'package:anibee/services/download_service.dart';
import 'package:anibee/services/miruro_resolver.dart';
import 'package:anibee/services/oauth_service.dart';
import 'package:anibee/services/provider_config.dart';
import 'package:anibee/settings_store.dart';
import 'package:anibee/widgets/glass_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 0.2.16 KEYBOARD HIDES THE NAV (user 2026-11-24 01:51, Search
/// screenshot with the keyboard open): while typing in Search, the
/// Scaffold resized for the keyboard and the bottom-Positioned nav
/// pill rode up, sitting ON TOP of the search results — overlapping
/// the poster grid and hiding poster titles behind it. The shell now
/// hides the pill entirely while the keyboard is open
/// (`MediaQuery.viewInsets.bottom > 0`) and shows it again when the
/// keyboard closes. Covers both nav styles and all 5 tabs.
///
/// Harness notes: the real AppShell is pumped (store + config +
/// services built the way detail_poster_test does it — mocked
/// SharedPreferences + mocked secure-storage channel, mocked
/// AniList client returning empty Pages so Home's movie/airing
/// loads finish instantly). No pumpAndSettle — Home's hero has a
/// 5 s auto-timer; explicit pumps only. `runAsync` for the loads:
/// ProviderConfigService.load() does a real remote fetch.
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

  http.Response emptyPage() => http.Response.bytes(
        utf8.encode(jsonEncode(<String, dynamic>{
          'data': <String, dynamic>{
            'Page': <String, dynamic>{'media': <dynamic>[]},
          },
        })),
        200,
      );

  Future<void> pumpShell(
    WidgetTester tester, {
    required double keyboardHeight,
  }) async {
    // 800 pt wide (not 390): Home's hero Details/Watch Now Row
    // overflows by ~38 px at 390 in the test font (its metrics are
    // wider than the phone's) — a test-env-only artifact; the user's
    // screenshots show both buttons fitting on the 390 pt phone.
    // The keyboard-hide behaviour does not depend on width.
    tester.view.physicalSize = const Size(800, 844);
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final SettingsStore store =
        (await tester.runAsync<SettingsStore>(() => SettingsStore.load()))!;
    final ProviderConfigService config = (await tester
            .runAsync<ProviderConfigService>(
                () => ProviderConfigService.load()))!;
    final AniListService anilist = AniListService(
      client: MockClient((http.Request req) async => emptyPage()),
    );
    final AppServices services = AppServices(
      anilist: anilist,
      miruro: MiruroResolver(anilist: anilist),
      debrid: DebridService(),
      oauth: OAuthService(),
      downloads: DownloadService(),
      airing: AiringService(anilist: anilist),
      airingNotifications: AiringNotifications(),
      configService: config,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: AppShell(
          store: store,
          configService: config,
          services: services,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('nav is visible and tappable with the keyboard closed',
      (WidgetTester tester) async {
    await pumpShell(tester, keyboardHeight: 0);
    expect(find.byType(GlassNavBar), findsOneWidget);
    // Tap the Search tab — the Search screen's field appears, which
    // proves the pill is not just painted but tappable.
    await tester.tap(find.text('Search'));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('nav is hidden while the keyboard is open',
      (WidgetTester tester) async {
    await pumpShell(tester, keyboardHeight: 300);
    expect(find.byType(GlassNavBar), findsNothing);
  });

  testWidgets('nav returns when the keyboard closes',
      (WidgetTester tester) async {
    await pumpShell(tester, keyboardHeight: 300);
    expect(find.byType(GlassNavBar), findsNothing);
    tester.view.viewInsets = const FakeViewPadding(bottom: 0);
    await tester.pump();
    expect(find.byType(GlassNavBar), findsOneWidget);
  });
}
