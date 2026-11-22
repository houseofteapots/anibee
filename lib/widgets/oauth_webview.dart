import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// In-app OAuth login webview. Intercepts the redirect to the custom
/// `anibee://` scheme and returns the full redirect Uri to the caller,
/// which parses the token/code out of it. The user never leaves the app
/// and no external browser round-trip is needed.
Future<Uri?> showOAuthLogin({
  required BuildContext context,
  required String title,
  required String authUrl,
  required String redirectScheme,
}) {
  return Navigator.of(context).push<Uri?>(
    MaterialPageRoute<Uri?>(
      builder: (BuildContext context) => _OAuthWebViewScreen(
        title: title,
        authUrl: authUrl,
        redirectScheme: redirectScheme,
      ),
    ),
  );
}

class _OAuthWebViewScreen extends StatefulWidget {
  const _OAuthWebViewScreen({
    required this.title,
    required this.authUrl,
    required this.redirectScheme,
  });

  final String title;
  final String authUrl;
  final String redirectScheme;

  @override
  State<_OAuthWebViewScreen> createState() => _OAuthWebViewScreenState();
}

class _OAuthWebViewScreenState extends State<_OAuthWebViewScreen> {
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
