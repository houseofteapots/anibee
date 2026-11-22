import 'package:flutter/material.dart';

/// In-app logo: loads from the repo's raw GitHub URL so the logo can change
/// without an app update; falls back to the bundled asset.
/// (The iOS home-screen icon stays bundled — iOS rule, changing it needs
/// a rebuild.)
///
/// NOTE: the repo is private, so the raw URL returns 404 without auth and
/// the bundled fallback is used. If the logo is ever hosted publicly, the
/// remote one wins automatically — no code change needed.
const String kRemoteLogoUrl =
    'https://raw.githubusercontent.com/sezkc16/anibee/main/assets/logo.jpg';

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, required this.size, this.borderRadius = 8});

  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final Widget fallback = Image.asset(
      'assets/logo.jpg',
      width: size,
      height: size,
      fit: BoxFit.cover,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Image.network(
        kRemoteLogoUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        loadingBuilder:
            (
              BuildContext context,
              Widget child,
              ImageChunkEvent? loadingProgress,
            ) {
              if (loadingProgress == null) return child;
              return fallback;
            },
        errorBuilder: (
          BuildContext context,
          Object error,
          StackTrace? stackTrace,
        ) => fallback,
      ),
    );
  }
}
