import 'package:flutter_test/flutter_test.dart';

import 'player_skip_times_harness.dart';

/// 0.2.9 Skip Intro: the fetch runs once the real duration loads,
/// with episodeLength. Real libmpv + real 5 s video-only clip.
/// One media test per file (see the harness comment).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(configureSkipTestBindings);

  testWidgets('fetch runs once the real duration loads, with length', (
    WidgetTester tester,
  ) async {
    final SkipPlayerHarness h = SkipPlayerHarness();
    await h.pumpPlayer(tester, anime: mha, aniSkip: h.recordingSkipService());
    await h.openTestClip(tester);
    expect(await h.waitForSkip(tester), isTrue);
    expect(h.skipRequests.length, 1);
    expect(h.skipRequests.first.url.path, '/v2/skip-times/31964/1');
    expect(h.skipRequests.first.url.queryParameters['episodeLength'], '5');
    expect(h.playerState(tester).skipTimesAwaitingDurationForTest, isFalse);
    final dynamic times = h.playerState(tester).skipTimesForTest;
    expect(times.op.startTime, 91.915);
    expect(times.op.endTime, 189.394);
    expect(times.ed.startTime, 1313);
    await h.disposePlayer(tester);
  });
}
