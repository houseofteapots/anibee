import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/oauth_service.dart';

/// OAuth login as a bottom-sheet webview (0.2.3, matches the user's
/// reference: header "anilist.co" + lock icon, "Sign in to AniList to
/// sync what you watch.", the provider's own login/authorize page as
/// the sheet content, Close button bottom-right).
///
/// The app does NOT build a login form — when logged out, AniList /
/// MAL themselves show their own login page (Email/Password +
/// Cloudflare check) first, then the authorize step. AniList answers
/// on its default PIN page (no redirect_uri is sent — 0.2.5: sending
/// one made AniList reject the authorize request with
/// unsupported_grant_type even when the registered redirect matched),
/// and that PIN URL is intercepted here and returned to the caller
/// as the Uri; the caller parses the token out of its fragment. MAL
/// still redirects to the custom `anibee://` scheme, intercepted the
/// same way. The user never leaves the app and no external browser
/// round-trip is needed.
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
        subtitle: subtitle ?? 'Sign in to $host to sync what you watch.',
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

  /// Readable OAuth error detected in the loaded page (0.2.5): the
  /// provider answers a bad authorize request with a raw JSON error
  /// body instead of its login page. When set, the sheet shows this
  /// text, never the raw JSON.
  String? _oauthError;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            final Uri uri = Uri.parse(request.url);
            // 0.2.5 PIN flow: the AniList token comes back on the
            // PIN page (https://anilist.co/api/v2/oauth/pin), not
            // on the custom scheme — intercept it the same way.
            // The custom-scheme redirect stays as a fallback.
            if (uri.scheme == widget.redirectScheme ||
                OAuthService.isAnilistPinUrl(uri)) {
              Navigator.of(context).pop(uri);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageFinished: (String url) async {
            // The provider may have answered with an OAuth error JSON
            // (e.g. AniList's unsupported_grant_type when the redirect
            // URI registered on the client doesn't match): read the
            // page text and translate it before the raw JSON is shown.
            String? error;
            try {
              final Object result = await _controller
                  .runJavaScriptReturningResult('document.body.innerText');
              error = _errorFromPageText(result is String ? result : null);
            } catch (_) {
              error = null;
            }
            if (!mounted) return;
            setState(() {
              _loading = false;
              _oauthError = error;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.authUrl));
  }

  /// Pull a readable OAuth error out of a page's visible text: the
  /// text must parse as JSON with an `error` field, else null (a
  /// normal HTML login page never matches). Pure logic, unit-tested
  /// via [OAuthService.readableOAuthError].
  String? _errorFromPageText(String? text) {
    if (text == null) return null;
    String raw = text.trim();
    // runJavaScriptReturningResult may return the string JSON-encoded
    // (wrapped in quotes) — unwrap one layer.
    if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
      try {
        final Object? decoded = jsonDecode(raw);
        if (decoded is String) raw = decoded.trim();
      } catch (_) {}
    }
    if (!raw.startsWith('{')) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final String? code = decoded['error'] as String?;
      if (code == null || code.isEmpty) return null;
      return OAuthService.readableOAuthError(
        provider: widget.domain.contains('myanimelist')
            ? 'MyAnimeList'
            : 'AniList',
        error: code,
        message: decoded['message'] as String?,
      );
    } catch (_) {
      return null;
    }
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
                  const Icon(Icons.lock_rounded, color: Colors.white, size: 20),
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
                  if (_oauthError != null)
                    Container(
                      color: const Color(0xFF17171F),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Icon(
                            Icons.error_outline_rounded,
                            color: Color(0xFFFFC531),
                            size: 32,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _oauthError!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2A2A35),
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    ),
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
