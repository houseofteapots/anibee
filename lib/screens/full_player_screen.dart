import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../player/trailer_player.dart';
import '../settings_store.dart';

/// Full player screen — same libmpv Player instance as the inline trailer.
/// Entered from the Detail banner side button, by tapping the inline
/// player, or from PLAY / an episode row.
class FullPlayerScreen extends StatefulWidget {
  const FullPlayerScreen({
    super.key,
    required this.trailer,
    required this.store,
    required this.title,
    required this.label,
  });

  final TrailerPlayer trailer;
  final SettingsStore store;
  final String title;
  final String label;

  @override
  State<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends State<FullPlayerScreen> {
  bool _controlsVisible = true;
  Timer? _hideTimer;

  Player get _player => widget.trailer.player;

  @override
  void initState() {
    super.initState();
    _player.setRate(widget.store.playbackSpeed);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  String _format(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        onDoubleTapDown: (TapDownDetails details) {
          final double width = MediaQuery.of(context).size.width;
          final int seek = widget.store.doubleTapSeek;
          if (details.globalPosition.dx < width / 2) {
            _player.seek(
              _player.state.position - Duration(seconds: seek),
            );
          } else {
            _player.seek(
              _player.state.position + Duration(seconds: seek),
            );
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Video(controller: widget.trailer.controller),
            if (_controlsVisible) ...<Widget>[
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.black.withValues(alpha: 0.55),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.65),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 48,
                left: 16,
                right: 16,
                child: Row(
                  children: <Widget>[
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            widget.label,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _SpeedButton(
                      player: _player,
                      store: widget.store,
                    ),
                  ],
                ),
              ),
              Center(
                child: StreamBuilder<bool>(
                  stream: _player.stream.playing,
                  initialData: false,
                  builder: (
                    BuildContext context,
                    AsyncSnapshot<bool> snapshot,
                  ) {
                    final bool playing = snapshot.data ?? false;
                    return IconButton(
                      iconSize: 72,
                      icon: Icon(
                        playing
                            ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_filled_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        if (playing) {
                          _player.pause();
                        } else {
                          _player.play();
                        }
                      },
                    );
                  },
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 32,
                child: StreamBuilder<Duration>(
                  stream: _player.stream.position,
                  initialData: Duration.zero,
                  builder: (
                    BuildContext context,
                    AsyncSnapshot<Duration> posSnap,
                  ) {
                    return StreamBuilder<Duration>(
                      stream: _player.stream.duration,
                      initialData: Duration.zero,
                      builder: (
                        BuildContext context,
                        AsyncSnapshot<Duration> durSnap,
                      ) {
                        final Duration position =
                            posSnap.data ?? Duration.zero;
                        final Duration duration =
                            durSnap.data ?? Duration.zero;
                        final double max =
                            duration.inMilliseconds.toDouble();
                        return Column(
                          children: <Widget>[
                            Slider(
                              value: position.inMilliseconds
                                  .toDouble()
                                  .clamp(0, max == 0 ? 1 : max),
                              max: max == 0 ? 1 : max,
                              onChanged: (double value) {
                                _player.seek(
                                  Duration(milliseconds: value.toInt()),
                                );
                              },
                            ),
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: <Widget>[
                                Text(
                                  _format(position),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  _format(duration),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SpeedButton extends StatelessWidget {
  const _SpeedButton({required this.player, required this.store});

  final Player player;
  final SettingsStore store;

  static const List<double> _speeds = <double>[0.5, 1.0, 1.25, 1.5, 2.0];

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () async {
        final double current = store.playbackSpeed;
        final int nextIndex =
            (_speeds.indexOf(current) + 1) % _speeds.length;
        final double next = _speeds[nextIndex];
        await store.setPlaybackSpeed(next);
        await player.setRate(next);
      },
      child: Text(
        '${store.playbackSpeed}x',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
