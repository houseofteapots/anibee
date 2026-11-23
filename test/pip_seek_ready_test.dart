import 'package:anibee/screens/full_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// 0.2.12 PiP restart: `_enterPip` used to seek the PiP player
/// immediately after `open`, before the HLS stream had loaded, so
/// the seek didn't stick and playback started at 0. Now it waits
/// for a real duration first ([waitForDuration]), then seeks, then
/// reads the position back and re-seeks once if [seekNeedsRetry]
/// says it didn't stick. These are the pure helpers — the real
/// PiP round-trip cannot be proven on the VM (no iOS PiP), only
/// on the phone.
void main() {
  group('waitForDuration', () {
    test('returns true once the duration becomes real', () async {
      int calls = 0;
      final bool ready = await waitForDuration(
        () async {
          calls++;
          return calls < 3 ? Duration.zero : const Duration(seconds: 24);
        },
        timeout: const Duration(seconds: 5),
        pollInterval: const Duration(milliseconds: 10),
      );
      expect(ready, isTrue);
      expect(calls, 3);
    });

    test('returns false on timeout when the duration never arrives',
        () async {
      final bool ready = await waitForDuration(
        () async => Duration.zero,
        timeout: const Duration(milliseconds: 50),
        pollInterval: const Duration(milliseconds: 10),
      );
      expect(ready, isFalse);
    });
  });

  group('seekNeedsRetry', () {
    test('target deep in, position still ~0 → retry', () {
      expect(
        seekNeedsRetry(
          target: const Duration(minutes: 12),
          position: const Duration(milliseconds: 300),
        ),
        isTrue,
      );
    });

    test('position near the target → no retry', () {
      expect(
        seekNeedsRetry(
          target: const Duration(minutes: 12),
          position: const Duration(minutes: 11, seconds: 58),
        ),
        isFalse,
      );
    });

    test('target near the start → no retry (seeking to ~0 is fine)', () {
      expect(
        seekNeedsRetry(
          target: const Duration(seconds: 3),
          position: Duration.zero,
        ),
        isFalse,
      );
      expect(
        seekNeedsRetry(
          target: const Duration(seconds: 5),
          position: Duration.zero,
        ),
        isFalse,
      );
    });

    test('boundary: target just over 5 s, position just under 2 s',
        () {
      expect(
        seekNeedsRetry(
          target: const Duration(seconds: 6),
          position: const Duration(seconds: 1, milliseconds: 900),
        ),
        isTrue,
      );
      expect(
        seekNeedsRetry(
          target: const Duration(seconds: 6),
          position: const Duration(seconds: 2),
        ),
        isFalse,
      );
    });
  });
}
