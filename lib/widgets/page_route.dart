import 'package:flutter/material.dart';

/// One smooth page transition for the whole app (M1.1): a short
/// slide-from-right + fade, eased — never an abrupt jump. Used for every
/// push: Detail, Settings sub-screens, Player, Lock setup.
class SmoothPageRoute<T> extends PageRouteBuilder<T> {
  SmoothPageRoute({required WidgetBuilder builder})
      : super(
          pageBuilder:
              (BuildContext context, Animation<double> animation,
                      Animation<double> secondaryAnimation) =>
                  builder(context),
          transitionsBuilder:
              (BuildContext context, Animation<double> animation,
                  Animation<double> secondaryAnimation, Widget child) {
            final Animation<double> curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0.06, 0),
                    end: Offset.zero,
                  ).animate(curved),
              child: FadeTransition(opacity: curved, child: child),
            );
          },
          transitionDuration: const Duration(milliseconds: 320),
          reverseTransitionDuration: const Duration(milliseconds: 280),
        );
}
