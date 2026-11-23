import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Top notification banner (0.2.8): replaces every bottom SnackBar in
/// the app. A floating dark-glass banner at the TOP of the screen —
/// small icon + message (+ an optional smaller detail line, used for
/// the login diagnostic's last URL) — slides/fades in, auto-dismisses
/// after ~3s, tappable to dismiss. One banner at a time: showing a
/// new one replaces the previous.
class TopNotification {
  static OverlayEntry? _entry;
  static Timer? _timer;

  static void show(
    BuildContext context,
    String message, {
    bool success = false,
    bool neutral = false,
    String? detail,
    Duration duration = const Duration(seconds: 3),
  }) {
    hide();
    final OverlayState? overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    _entry = OverlayEntry(
      builder: (BuildContext context) {
        return _TopBanner(
          message: message,
          detail: detail,
          success: success,
          neutral: neutral,
          onDismiss: hide,
        );
      },
    );
    overlay.insert(_entry!);
    _timer = Timer(duration, hide);
  }

  static void hide() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }
}

class _TopBanner extends StatefulWidget {
  const _TopBanner({
    required this.message,
    required this.detail,
    required this.success,
    required this.neutral,
    required this.onDismiss,
  });

  final String message;
  final String? detail;
  final bool success;
  final bool neutral;
  final VoidCallback onDismiss;

  @override
  State<_TopBanner> createState() => _TopBannerState();
}

class _TopBannerState extends State<_TopBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.6),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _fade = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color primaryText = isDark
        ? AppTheme.textPrimaryDark
        : AppTheme.textPrimaryLight;
    final Color secondaryText = isDark
        ? AppTheme.textSecondaryDark
        : AppTheme.textSecondaryLight;
    final double top = MediaQuery.of(context).padding.top + 12;
    return Positioned(
      top: top,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: GestureDetector(
            onTap: widget.onDismiss,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xD91E1E2A)
                        : Colors.white.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        // 0.2.9: an empty state is not a warning —
                        // neutral shows a grey info icon, never the
                        // yellow error icon.
                        widget.success
                            ? Icons.check_circle_rounded
                            : widget.neutral
                            ? Icons.info_outline_rounded
                            : Icons.error_outline_rounded,
                        size: 20,
                        color: widget.success
                            ? AppTheme.success
                            : widget.neutral
                            ? secondaryText
                            : const Color(0xFFFFC531),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              widget.message,
                              style: TextStyle(
                                color: primaryText,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                height: 1.35,
                                // 0.2.10: explicit none — the phone
                                // renders a yellow underline under
                                // this text and no Dart code draws
                                // one; harden the style directly.
                                decoration: TextDecoration.none,
                              ),
                            ),
                            if (widget.detail != null) ...<Widget>[
                              const SizedBox(height: 3),
                              Text(
                                widget.detail!,
                                style: TextStyle(
                                  color: secondaryText,
                                  fontSize: 12,
                                  height: 1.35,
                                  decoration: TextDecoration.none,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
