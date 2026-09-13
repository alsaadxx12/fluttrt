import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../data/shahid_models.dart';

/// Opens an item on Shahid's own website inside the app. Nothing is extracted
/// or stripped: Shahid's player, ads, sign-in and subscription checks all run
/// exactly as they do in a browser. Free (AVOD) channels play for guests; VIP
/// titles show Shahid's own subscribe screen.
class ShahidWebScreen extends StatefulWidget {
  final ShahidItem item;

  const ShahidWebScreen({super.key, required this.item});

  @override
  State<ShahidWebScreen> createState() => _ShahidWebScreenState();
}

class _ShahidWebScreenState extends State<ShahidWebScreen> {
  late final WebViewController _controller;
  int _progress = 0;
  Widget? _fullscreenWidget;
  OnHideCustomWidgetCallback? _hideFullscreen;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          onNavigationRequest: (request) {
            final u = request.url.toLowerCase();
            // App-store / intent hand-offs have nowhere to go inside a WebView.
            if (u.startsWith('intent:') ||
                u.startsWith('market:') ||
                u.contains('play.google.com') ||
                u.contains('apps.apple.com')) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );

    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
      platform.setCustomWidgetCallbacks(
        onShowCustomWidget: (widget, onHide) {
          setState(() {
            _fullscreenWidget = widget;
            _hideFullscreen = onHide;
          });
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        },
        onHideCustomWidget: _leaveFullscreenUi,
      );
    }

    _controller.loadRequest(Uri.parse(widget.item.pageUrl));
  }

  void _leaveFullscreenUi() {
    if (mounted) {
      setState(() {
        _fullscreenWidget = null;
        _hideFullscreen = null;
      });
    }
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _handleBack() async {
    if (_fullscreenWidget != null) {
      try {
        _hideFullscreen?.call();
      } catch (_) {}
      _leaveFullscreenUi();
      return;
    }
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: _fullscreenWidget != null
          ? Scaffold(backgroundColor: Colors.black, body: _fullscreenWidget)
          : Scaffold(
              backgroundColor: const Color(0xFF07090E),
              appBar: AppBar(
                backgroundColor: const Color(0xFF0D111A),
                foregroundColor: Colors.white,
                elevation: 0,
                title: Row(
                  children: [
                    if (widget.item.isLive)
                      Container(
                        margin: const EdgeInsetsDirectional.only(end: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE50914),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'LIVE',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
                        ),
                      ),
                    Expanded(
                      child: Text(
                        widget.item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: _handleBack,
                ),
                actions: [
                  IconButton(
                    tooltip: 'إعادة التحميل',
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: () => _controller.reload(),
                  ),
                ],
              ),
              body: Stack(
                children: [
                  WebViewWidget(controller: _controller),
                  if (_progress < 100)
                    LinearProgressIndicator(
                      value: _progress / 100,
                      minHeight: 2,
                      backgroundColor: Colors.transparent,
                      valueColor: const AlwaysStoppedAnimation(Color(0xFFE50914)),
                    ),
                ],
              ),
            ),
    );
  }
}
