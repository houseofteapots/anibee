import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:reicon_flutter/reicon_flutter.dart';

/// A Reicon icon (reicon.dev, MIT, 2,700+ handcrafted icons) rendered
/// from the official `reicon_flutter` path data via flutter_svg.
/// Pass path data from `Reicon.outline.<name>` / `Reicon.filled.<name>`.
class ReiconIcon extends StatelessWidget {
  const ReiconIcon(
    this.pathData, {
    super.key,
    this.size = 22,
    this.color,
  });

  final String pathData;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Color c =
        color ?? IconTheme.of(context).color ?? Colors.white;
    final String hex =
        '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
    return SvgPicture.string(
      reiconSvg(pathData, size: size.toInt(), color: hex),
      width: size,
      height: size,
    );
  }
}
