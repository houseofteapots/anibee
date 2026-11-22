import 'package:flutter/cupertino.dart';

/// App-wide push route: the standard iOS push (slide from right) via
/// CupertinoPageRoute, which ALSO gives the native left-edge swipe-back
/// gesture for free — interactive, follows the finger, cancels on
/// release — on every pushed screen (Detail, Player, Settings
/// sub-screens, Lock setup). The back arrow button stays as well.
/// (The old PageRouteBuilder slide+fade had no swipe-back at all.)
class SmoothPageRoute<T> extends CupertinoPageRoute<T> {
  SmoothPageRoute({required super.builder});
}
