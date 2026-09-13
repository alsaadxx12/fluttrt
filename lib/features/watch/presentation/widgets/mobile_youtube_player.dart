import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../../../../core/constants/app_colors.dart';

class MobileYouTubePlayer extends StatefulWidget {
  final String videoId;
  final VoidCallback? onEnded;
  final ValueChanged<bool>? onFullscreenChanged;

  const MobileYouTubePlayer({
    super.key,
    required this.videoId,
    this.onEnded,
    this.onFullscreenChanged,
  });

  @override
  State<MobileYouTubePlayer> createState() => MobileYouTubePlayerState();
}

class MobileYouTubePlayerState extends State<MobileYouTubePlayer> {
  late final WebViewController _controller;
  bool _isReady = false;
  bool _hasError = false;
  void Function()? _hideCustomWidgetCallback;
  bool _isCustomFullscreenActive = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.black)
        ..setUserAgent(
          // Standard modern mobile Chrome user-agent without 'wv' WebView tag to bypass Error 152
          'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
        )
        ..addJavaScriptChannel(
          'PlayerBridge',
          onMessageReceived: (JavaScriptMessage msg) {
            if (msg.message == 'ENDED') {
              widget.onEnded?.call();
            } else if (msg.message == 'FS_ENTER') {
              widget.onFullscreenChanged?.call(true);
            } else if (msg.message == 'FS_EXIT') {
              widget.onFullscreenChanged?.call(false);
            }
          },
        );

      final platform = _controller.platform;
      if (platform is AndroidWebViewController) {
        platform.setMediaPlaybackRequiresUserGesture(false);

        // Native HTML5 video fullscreen handler for Android WebView
        platform.setCustomWidgetCallbacks(
          onShowCustomWidget: (Widget customWidget, void Function() callback) {
            _hideCustomWidgetCallback = callback;
            _isCustomFullscreenActive = true;
            widget.onFullscreenChanged?.call(true);

            SystemChrome.setPreferredOrientations([
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]);
            SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

            Navigator.of(context).push(
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (ctx) {
                  return PopScope(
                    canPop: true,
                    onPopInvokedWithResult: (didPop, _) {
                      if (didPop) {
                        _onExitCustomFullscreen();
                      }
                    },
                    child: Scaffold(
                      backgroundColor: Colors.black,
                      body: Stack(
                        children: [
                          Positioned.fill(child: customWidget),
                          Positioned(
                            top: 16,
                            left: 16,
                            child: SafeArea(
                              child: Material(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(24),
                                child: IconButton(
                                  icon: const Icon(Icons.fullscreen_exit_rounded, color: Colors.white, size: 26),
                                  tooltip: 'تصغير الشاشة',
                                  onPressed: () {
                                    Navigator.of(ctx).pop();
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
          onHideCustomWidget: () {
            if (_isCustomFullscreenActive) {
              _onExitCustomFullscreen();
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            }
          },
        );
      }

      await _loadVideoHtml(widget.videoId);

      if (mounted) {
        setState(() {
          _isReady = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  void _onExitCustomFullscreen() {
    _isCustomFullscreenActive = false;
    _hideCustomWidgetCallback?.call();
    widget.onFullscreenChanged?.call(false);

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future<void> _loadVideoHtml(String videoId) async {
    final html = '''<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <meta name="referrer" content="strict-origin-when-cross-origin">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body { width: 100%; height: 100%; overflow: hidden; background-color: #000000; }
    #player { width: 100%; height: 100%; border: none; position: absolute; top: 0; left: 0; }
  </style>
</head>
<body>
  <iframe
    id="player"
    src="https://www.youtube-nocookie.com/embed/$videoId?autoplay=1&enablejsapi=1&playsinline=1&rel=0&modestbranding=1"
    referrerpolicy="strict-origin-when-cross-origin"
    allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share; fullscreen"
    allowfullscreen>
  </iframe>
  <script>
    // Listen to YouTube player state changes via postMessage
    window.addEventListener('message', function(event) {
      try {
        var data = (typeof event.data === 'string') ? JSON.parse(event.data) : event.data;
        if (data && data.event === 'onStateChange' && data.info === 0) {
          if (window.PlayerBridge) {
            window.PlayerBridge.postMessage('ENDED');
          }
        }
      } catch (e) {}
    });

    document.addEventListener('fullscreenchange', function() {
      if (window.PlayerBridge) {
        window.PlayerBridge.postMessage(document.fullscreenElement ? 'FS_ENTER' : 'FS_EXIT');
      }
    });
  </script>
</body>
</html>''';

    await _controller.loadHtmlString(
      html,
      baseUrl: 'https://www.youtube-nocookie.com',
    );
  }

  /// Programmatic toggle of fullscreen from Flutter UI
  Future<void> toggleFullscreen() async {
    await _controller.runJavaScript('''
      if (document.fullscreenElement) {
        document.exitFullscreen();
      } else {
        var el = document.getElementById('player');
        if (el && el.requestFullscreen) {
          el.requestFullscreen();
        }
      }
    ''');
  }

  @override
  void didUpdateWidget(covariant MobileYouTubePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoId != widget.videoId && _isReady) {
      _controller.runJavaScript('''
        var frame = document.getElementById('player');
        if (frame) {
          frame.src = 'https://www.youtube-nocookie.com/embed/${widget.videoId}?autoplay=1&enablejsapi=1&playsinline=1&rel=0&modestbranding=1';
        } else {
          location.reload();
        }
      ''');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 40),
            const SizedBox(height: 10),
            const Text(
              'تعذر تشغيل الفيديو، يرجى المحاولة لاحقاً',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _hasError = false;
                  _isReady = false;
                });
                _initPlayer();
              },
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('إعادة المحاولة'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          ],
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        WebViewWidget(
          controller: _controller,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
        ),
        if (!_isReady)
          Container(
            color: Colors.black,
            child: const Center(
              child: SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                  strokeWidth: 3,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
