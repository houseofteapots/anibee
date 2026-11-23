import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/oauth_service.dart';
import 'top_notification.dart';

/// Mutable holder for the sheet's last URL: a swipe-down dismiss pops
/// the sheet with a null result (bypassing [_OAuthLoginSheetState._close]),
/// so the diagnostic URL is written here as well and read back by
/// [showOAuthLogin] when the result is null.
class _LastUrlHolder {
  String? url;
}

/// Result of an OAuth login sheet: the redirect Uri when the provider
/// answered, plus the LAST URL the webview reached (0.2.8 diagnostic).
/// The last URL is what proves where a failed flow died — authorize
/// page, login page, PIN page, localhost redirect, or closed early —
/// and the caller puts it in the failure notification.
class OAuthLoginResult {
  const OAuthLoginResult({this.redirect, this.lastUrl});

  final Uri? redirect;
  final String? lastUrl;
}

/// OAuth login as a bottom-sheet webview (0.2.3, matches the user's
/// reference: header "anilist.co" + lock icon, "Sign in to AniList to
/// sync what you watch.", the provider's own login/authorize page as
/// the sheet content, Close button bottom-right).
///
/// The app does NOT build a login form — when logged out, AniList /
/// MAL themselves show their own login page (Email/Password +
/// Cloudflare check) first, then the authorize step.
///
/// 0.2.8 (Zeus-mirror): both providers redirect to
/// `http://localhost` — exactly how Zeus's working login on this phone
/// does it. The redirect is intercepted three ways: the navigation
/// delegate, URL-change observation (fires for server redirects the
/// policy check misses — Zeus needed the same fallback natively),
/// and the resource-error callback (the localhost load itself fails
/// with no server listening, and the error still carries the full
/// redirect URL). The PIN page and the legacy `anibee://` redirects
/// stay as fallbacks. The user never leaves the app and no external
/// browser round-trip is needed.
///
/// Manual fallback (0.2.8): the sheet has a "paste token/code" button.
/// AniList's PIN page prints the token on screen — the user copies it
/// and pastes it here. For MAL the sheet shows the last redirect URL
/// (copyable), from which the code is pasted. Either way the sheet
/// returns a synthetic redirect Uri and the caller's normal validation
/// runs on it.
Future<OAuthLoginResult> showOAuthLogin({
  required BuildContext context,
  required String title,
  required String authUrl,
  required String redirectScheme,
  String? domain,
  String? subtitle,
  String? pasteLabel,
  String? malState,
}) {
  final String host = domain ?? Uri.parse(authUrl).host;
  final _LastUrlHolder lastUrlHolder = _LastUrlHolder();
  return showModalBottomSheet<OAuthLoginResult>(
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
        pasteLabel: pasteLabel,
        malState: malState,
        lastUrlHolder: lastUrlHolder,
      );
    },
  ).then(
    (OAuthLoginResult? result) =>
        result ?? OAuthLoginResult(redirect: null, lastUrl: lastUrlHolder.url),
  );
}

class _OAuthLoginSheet extends StatefulWidget {
  const _OAuthLoginSheet({
    required this.title,
    required this.domain,
    required this.subtitle,
    required this.authUrl,
    required this.redirectScheme,
    this.pasteLabel,
    this.malState,
    required this.lastUrlHolder,
  });

  final String title;
  final String domain;
  final String subtitle;
  final String authUrl;
  final String redirectScheme;
  final String? pasteLabel;
  final String? malState;
  final _LastUrlHolder lastUrlHolder;

  @override
  State<_OAuthLoginSheet> createState() => _OAuthLoginSheetState();
}

class _OAuthLoginSheetState extends State<_OAuthLoginSheet> {
  late final WebViewController _controller;
  bool _loading = true;

  /// 0.2.6: the sheet must pop exactly once — the token can now
  /// arrive via several paths, and a second pop would dismiss the
  /// underlying Settings screen.
  bool _returned = false;

  /// 0.2.8 diagnostic: the last URL the webview reached. Updated on
  /// every navigation, URL change and page finish — the caller shows
  /// it when login fails, so the next phone test proves where the
  /// flow died.
  String? _lastUrl;

  /// Pop the sheet once with [uri]. Every return path goes through
  /// here.
  void _return(Uri uri) {
    if (_returned || !mounted) return;
    _returned = true;
    Navigator.of(context)
        .pop(OAuthLoginResult(redirect: uri, lastUrl: _lastUrl));
  }

  /// Close without a redirect — still report the last URL so the
  /// caller can tell a mid-flow death from an immediate Close.
  void _close() {
    if (_returned || !mounted) return;
    _returned = true;
    Navigator.of(context)
        .pop(OAuthLoginResult(redirect: null, lastUrl: _lastUrl));
  }

  void _noteUrl(String? url) {
    if (url == null || url.isEmpty) return;
    _lastUrl = url;
    widget.lastUrlHolder.url = url;
  }

  /// True when [uri] is one of the redirect shapes the sheet must
  /// intercept: the Zeus-mirror localhost redirect, the AniList PIN
  /// page, or the legacy custom scheme.
  bool _isRedirect(Uri uri) {
    return OAuthService.isLocalRedirect(uri) ||
        OAuthService.isAnilistPinUrl(uri) ||
        uri.scheme == widget.redirectScheme;
  }

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
          onPageStarted: (String url) {
            _noteUrl(url);
          },
          onNavigationRequest: (NavigationRequest request) {
            final Uri uri = Uri.parse(request.url);
            _noteUrl(request.url);
            // 0.2.8 Zeus-mirror: intercept the localhost redirect
            // (plus the PIN page and the legacy custom scheme).
            if (_isRedirect(uri)) {
              _return(uri);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          // 0.2.6: onNavigationRequest does not always fire for the
          // post-authorize redirect (and may strip the fragment) —
          // that is the 0.2.5 phone failure (Authorize tapped, still
          // "no token returned"). onUrlChange fires on every URL
          // change including fragment changes and server redirects
          // the policy check misses, so capture the token here too.
          onUrlChange: (UrlChange change) {
            final String? url = change.url;
            if (url == null || url.isEmpty) return;
            _noteUrl(url);
            final Uri uri = Uri.parse(url);
            if (_isRedirect(uri)) {
              // AniList shapes carry the token in the fragment;
              // the MAL localhost redirect carries `code` in the
              // query. Only return when the URL actually carries
              // something to parse, so an empty localhost hit (user
              // error page) does not end the flow early.
              if (OAuthService.parseAnilistRedirect(uri) != null ||
                  uri.queryParameters.containsKey('code')) {
                _return(uri);
              }
            }
          },
          // 0.2.8: the localhost redirect has no server listening,
          // so its load FAILS — and the resource error still carries
          // the full redirect URL (token/code intact). This is the
          // third capture path, for when the navigation delegate
          // and the URL change both miss a server redirect.
          onWebResourceError: (WebResourceError error) {
            final String? url = error.url;
            if (url == null || url.isEmpty) return;
            _noteUrl(url);
            final Uri uri = Uri.parse(url);
            if (_isRedirect(uri)) {
              if (OAuthService.parseAnilistRedirect(uri) != null ||
                  uri.queryParameters.containsKey('code')) {
                _return(uri);
              }
            }
          },
          onPageFinished: (String url) async {
            _noteUrl(url);
            // The provider may have answered with an OAuth error JSON
            // (e.g. AniList's unsupported_grant_type when the redirect
            // URI registered on the client doesn't match): read the
            // page text and translate it before the raw JSON is shown.
            String? error;
            try {
              final Object result = await _controller
                  .runJavaScriptReturningResult('document.body.innerText');
              final String? text = result is String ? result : null;
              // 0.2.6: the PIN page prints the token on screen — if
              // the redirect was not intercepted (or its fragment
              // was lost), take the token from the page body instead
              // of leaving the user on a dead page.
              if (OAuthService.isAnilistPinUrl(Uri.parse(url))) {
                final String? token = OAuthService.extractTokenFromPinPageText(
                  text,
                );
                if (token != null && token.isNotEmpty) {
                  _return(
                    Uri.parse(
                      'https://anilist.co/api/v2/oauth/pin'
                      '#access_token=$token',
                    ),
                  );
                  return;
                }
              }
              error = _errorFromPageText(text);
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

  /// Manual paste fallback (0.2.8): the automatic capture failed, so
  /// the user pastes the token (AniList PIN page shows it on screen)
  /// or the MAL code (copied from the last-URL line below). The sheet
  /// returns a synthetic redirect Uri and the caller's normal
  /// validation runs on it — a bad paste fails there with the usual
  /// message, never silently.
  Future<void> _showPasteDialog() async {
    final bool isMal = widget.malState != null;
    final TextEditingController controller = TextEditingController();
    String? error;
    final String? pasted = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialog) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E2A),
              title: Text(
                isMal ? 'Paste your MAL code' : 'Paste your AniList token',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    isMal
                        ? 'MAL ne login ke baad jo code diya, use yahan paste karo (ya poora redirect link).'
                        : 'AniList PIN page pe jo token dikha, use copy karke yahan paste karo (ya poora PIN link).',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Paste here',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF17171F),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  if (error != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      style: const TextStyle(
                        color: Color(0xFFFFC531),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    final String text = controller.text.trim();
                    if (isMal) {
                      final ({String? code, String? state}) parsed =
                          OAuthService.extractMalCodeFromText(text);
                      if (parsed.code == null) {
                        setDialog(() {
                          error =
                              'Code nahi mila — poora link ya code paste karo.';
                        });
                        return;
                      }
                      Navigator.of(context).pop(
                        'code:${parsed.code}:'
                        '${parsed.state ?? widget.malState}',
                      );
                    } else {
                      final String? token =
                          OAuthService.extractTokenFromPinPageText(text);
                      final String candidate = token ?? text;
                      if (candidate.length < 40 || candidate.contains(' ')) {
                        setDialog(() {
                          error = 'Token nahi mila — PIN page se poora token copy karo.';
                        });
                        return;
                      }
                      Navigator.of(context).pop('token:$candidate');
                    }
                  },
                  child: const Text(
                    'Connect',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    if (pasted == null || !mounted) return;
    if (pasted.startsWith('token:')) {
      final String token = pasted.substring('token:'.length);
      _return(Uri.parse('${OAuthService.anilistRedirect}#access_token=$token'));
    } else if (pasted.startsWith('code:')) {
      final List<String> parts = pasted.split(':');
      final String code = parts.length > 1 ? parts[1] : '';
      final String state = parts.length > 2 ? parts[2] : '';
      _return(
        Uri.parse('${OAuthService.localRedirect}/?code=$code&state=$state'),
      );
    }
  }

  /// The last URL, when it is a redirect shape — shown so the user can
  /// copy the MAL code out of it (and so the next phone test can see
  /// where the flow got). Login/authorize page URLs are not shown:
  /// they carry nothing to copy.
  bool get _showLastUrl {
    final String? url = _lastUrl;
    if (url == null) return false;
    final Uri uri = Uri.parse(url);
    return _isRedirect(uri) && url != widget.authUrl;
  }

  String _shortUrl(String url) {
    return url.length <= 72 ? url : '${url.substring(0, 72)}…';
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
                            onPressed: _close,
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
            // 0.2.8: the last redirect URL, copyable — the MAL code
            // lives in it when the automatic capture misses.
            if (_showLastUrl)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Last page: ${_shortUrl(_lastUrl!)}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: _lastUrl!));
                        TopNotification.show(context, 'Link copied');
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.copy_rounded,
                          size: 16,
                          color: Colors.white54,
                        ),
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
                  if (widget.pasteLabel != null)
                    TextButton(
                      onPressed: _showPasteDialog,
                      child: Text(
                        widget.pasteLabel!,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else
                    const Text(
                      '•••',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  TextButton(
                    onPressed: _close,
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
