import 'package:flutter_test/flutter_test.dart';

import 'player_skip_times_harness.dart';

/// 0.2.9 Skip Intro fixes, proven through the real player:
///
/// 1. AniSkip 400s without `episodeLength`, and the duration is
///    usually still 0 when the fetch runs at init / episode switch —
///    so the fetch is now DEFERRED until the real duration is known
///    and never sent without it; a duration listener retries once
///    the duration arrives (position ticks are the backup — they
///    never advance in this headless env, so the duration listener
///    is what actually fires the retry). Verified live: no
///    episodeLength -> 400 "episodeLength NaN"; MHA S1 EP1 (mal
///    31964, len 1420) -> found:true, op 91.915-189.394.
/// 2. Most catalogue titles have neither a malId nor an anilistId,
///    so the fetch never started — the AniList id is now resolved
///    by title first (same helper as the season selector), then the
///    MAL id from it.
///
/// This file holds the NO-media deferral test only. The real-media
/// tests live in their own files (one per file — see the harness
/// comment for why).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(configureSkipTestBindings);

  testWidgets('no fetch while the duration is unknown (deferred)', (
    WidgetTester tester,
  ) async {
    final SkipPlayerHarness h = SkipPlayerHarness();
    await h.pumpPlayer(tester, anime: mha, aniSkip: h.recordingSkipService());
    // Duration is 0 (no media loaded): nothing was sent to AniSkip
    // — the old code sent the request WITHOUT episodeLength and
    // AniSkip 400d it.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();
    expect(h.skipRequests, isEmpty);
    expect(h.playerState(tester).skipTimesAwaitingDurationForTest, isTrue);
    expect(h.playerState(tester).skipTimesForTest, isNull);
    await h.disposePlayer(tester);
  });
}
