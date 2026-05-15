import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:hive_flutter/hive_flutter.dart';

class OpenWebuiPage extends StatefulWidget {
  const OpenWebuiPage({super.key});

  @override
  State<OpenWebuiPage> createState() => _OpenWebuiPageState();
}

class _OpenWebuiPageState extends State<OpenWebuiPage> {
  InAppWebViewController? _webViewController;
  bool _isLoading = true;
  bool _isConnected = true;

  String get _openwebuiUrl {
    final box = Hive.box('settings');
    return box.get('openwebuiAddress', defaultValue: 'http://localhost:3000');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final canGoBack = await _webViewController?.canGoBack() ?? false;
        if (canGoBack) {
          _webViewController?.goBack();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              InAppWebView(
                initialUrlRequest: URLRequest(
                  url: WebUri(_openwebuiUrl),
                ),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  allowsInlineMediaPlayback: true,
                  mediaPlaybackRequiresUserGesture: false,
                  mixedContentMode:
                      MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                  allowsBackForwardNavigationGestures: true,
                  userAgent: 'LlamaSeek/1.4.0 (iOS; Flutter)',
                  transparentBackground: true,
                ),
                onWebViewCreated: (controller) {
                  _webViewController = controller;
                },
                onLoadStart: (controller, url) {
                  if (mounted) setState(() => _isLoading = true);
                },
                onLoadStop: (controller, url) {
                  if (mounted) {
                    setState(() {
                      _isLoading = false;
                      _isConnected = true;
                    });
                  }
                },
                onReceivedError: (controller, request, error) {
                  if (request.isForMainFrame ?? false) {
                    if (mounted) {
                      setState(() {
                        _isLoading = false;
                        _isConnected = false;
                      });
                    }
                  }
                },
                onReceivedServerTrustAuthRequest:
                    (controller, challenge) async {
                  // Allow self-signed certs for local servers
                  return ServerTrustAuthResponse(
                    action: ServerTrustAuthResponseAction.PROCEED,
                  );
                },
                shouldOverrideUrlLoading: (controller, action) async {
                  final url = action.request.url;
                  if (url == null) return NavigationActionPolicy.CANCEL;

                  final openwebuiHost = Uri.parse(_openwebuiUrl).host;

                  // Allow navigation within open-webui
                  if (url.host == openwebuiHost || url.host.isEmpty) {
                    return NavigationActionPolicy.ALLOW;
                  }

                  // External links open in system browser
                  return NavigationActionPolicy.CANCEL;
                },
              ),
              // Loading indicator
              if (_isLoading)
                const Center(child: CircularProgressIndicator()),
              // Connection error overlay
              if (!_isConnected && !_isLoading)
                _ConnectionOverlay(
                  serverUrl: _openwebuiUrl,
                  onRetry: () {
                    setState(() => _isLoading = true);
                    _webViewController?.reload();
                  },
                  onChangeServer: () {
                    Navigator.pushNamed(context, '/settings');
                  },
                ),
              // Settings button overlay
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: Colors.transparent,
                  child: IconButton(
                    icon: Icon(
                      Icons.settings_outlined,
                      color:
                          Theme.of(context).colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.8),
                      padding: const EdgeInsets.all(8),
                      minimumSize: const Size(36, 36),
                    ),
                    onPressed: () =>
                        Navigator.pushNamed(context, '/settings'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionOverlay extends StatelessWidget {
  final String serverUrl;
  final VoidCallback onRetry;
  final VoidCallback onChangeServer;

  const _ConnectionOverlay({
    required this.serverUrl,
    required this.onRetry,
    required this.onChangeServer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                'Cannot connect to Open-webui',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                serverUrl,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Make sure Open-webui is running and accessible.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: onChangeServer,
                child: const Text('Change Server'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
