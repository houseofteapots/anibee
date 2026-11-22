import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// OAuth login as a bottom-sheet webview (0.2.3, matches the user's
/// reference: header "anilist.co" + lock icon, "Sign in to AniList to
/// sync what you watch.", the provider's own login/authorize page as
/// the sheet content, Close button bottom-right).
///
/// The app does NOT build a login form — when logged out, AniList /
/// MAL themselves show their own login page (Email/Password +
/// Cloudflare check) first, then the authorize step, then the
/// redirect to the custom `anibee://` scheme, which is intercepted
/// here and returned to the caller as the full redirect Uri. The
/// caller parses the token/code out of it. The user never leaves the
/// app and no external browser round-trip is needed.
Future<Uri?> showOAuthLogin({
  required BuildContext context,
  required String title,
  required String authUrl,
  required String redirectScheme,
  String? domain,
  String? subtitle,
}) {
  final String host = domain ?? Uri.parse(authUrl).host;
  return showModalBottomSheet<Uri?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF17171F),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (BuildContext context) {
      return _OAuthLoginSheet(
        title: title,
        domain: host,
        subtitle:
            subtitle ?? 'Sign in to $host to sync what you watch.',
        authUrl: authUrl,
        redirectScheme: redirectScheme,
      );
    },
  );
}

class _OAuthLoginSheet extends StatefulWidget {
  const _OAuthLoginSheet({
    required this.title,
    required this.domain,
    required this.subtitle,
    required this.authUrl,
    required this.redirectScheme,
  });

  final String title;
  final String domain;
  final String subtitle;
  final String authUrl;
  final String redirectScheme;

  @override
  State<_OAuthLoginSheet> createState() => _OAuthLoginSheetState();
}

class _OAuthLoginSheetState extends State<_OAuthLoginSheet> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            final Uri uri = Uri.parse(request.url);
            if (uri.scheme == widget.redirectScheme) {
              Navigator.of(context).pop(uri);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.authUrl));
  }

  @override
  Widget build(BuildContext context) {
    final double height = MediaQuery.of(context).size.height * 0.92;
    return SafeArea(
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF3A3A48),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.lock_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.domain,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                widget.subtitle,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Stack(
                children: <Widget>[
                  WebViewWidget(controller: _controller),
                  if (_loading)
                    const Center(child: CircularProgressIndicator()),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  const Text(
                    '•••',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Close',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
