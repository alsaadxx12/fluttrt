import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';
import '../../../../core/constants/app_colors.dart';

class WindowsYouTubePlayer extends StatefulWidget {
  final String videoId;
  final VoidCallback? onEnded;
  final ValueChanged<bool>? onFullscreenChanged;

  const WindowsYouTubePlayer({
    super.key,
    required this.videoId,
    this.onEnded,
    this.onFullscreenChanged,
  });

  @override
  State<WindowsYouTubePlayer> createState() => WindowsYouTubePlayerState();
}

class WindowsYouTubePlayerState extends State<WindowsYouTubePlayer> {
  final WebviewController _controller = WebviewController();
  bool _isReady = false;
  bool _hasError = false;
  StreamSubscription? _messageSub;
  StreamSubscription? _fullscreenSub;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      await _controller.initialize();

      // Set standard Edge browser User-Agent so YouTube doesn't flag WebView
      await _controller.setUserAgent(
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0',
      );
      await _controller.setBackgroundColor(Colors.black);
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);

      _messageSub = _controller.webMessage.listen((msg) {
        if (msg == 'ENDED') {
          widget.onEnded?.call();
        } else {
          debugPrint('WebView message: $msg');
        }
      });

      // Listen to HTML5 fullscreen requests from YouTube's player button
      _fullscreenSub = _controller.containsFullScreenElementChanged.listen((isFullScreen) {
        widget.onFullscreenChanged?.call(isFullScreen);
      });

      // Write HTML host with strict-origin referrer to solve Error 153
      final cacheDir = Directory('${Directory.systemTemp.path}\\yt_player_${widget.videoId}');
      if (!cacheDir.existsSync()) {
        cacheDir.createSync(recursive: true);
      }

      await _writeHtml(cacheDir, widget.videoId);

      // Map secure virtual host to folder for valid HTTPS origin and Referer headers
      await _controller.addVirtualHostNameMapping(
        'localhost',
        cacheDir.path,
        WebviewHostResourceAccessKind.allow,
      );

      await _controller.loadUrl('https://localhost/index.html');

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

  Future<void> _writeHtml(Directory dir, String videoId) async {
    final file = File('${dir.path}\\index.html');
    final html = '''<!DOCTYPE html>
<html lang="en">
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
    // Automatically blur active element after 2.5 seconds of inactivity so YouTube controls autohide
    var idleTimer = null;
    function scheduleBlur() {
      clearTimeout(idleTimer);
      idleTimer = setTimeout(function() {
        if (document.activeElement) {
          document.activeElement.blur();
        }
      }, 2500);
    }

    window.addEventListener('mousemove', scheduleBlur);
    window.addEventListener('load', scheduleBlur);

    // Listen to YouTube player state changes via postMessage
    window.addEventListener('message', function(event) {
      try {
        var data = (typeof event.data === 'string') ? JSON.parse(event.data) : event.data;
        if (data) {
          if (data.event === 'onStateChange' && data.info === 0) {
            if (window.chrome && window.chrome.webview) {
              window.chrome.webview.postMessage('ENDED');
            }
          }
        }
      } catch (e) {}
    });
  </script>
</body>
</html>''';
    await file.writeAsString(html);
  }

  /// Programmatic toggle of fullscreen from Flutter UI
  Future<void> toggleFullscreen() async {
    await _controller.executeScript('''
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
  void didUpdateWidget(covariant WindowsYouTubePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoId != widget.videoId && _isReady) {
      _controller.executeScript('''
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
  void dispose() {
    _messageSub?.cancel();
    _fullscreenSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, color: AppColors.error, size: 40),
              SizedBox(height: 10),
              Text(
                'تعذر تحميل مشغل الفيديو',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isReady) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(
              color: Color(0xFFFF0000),
              strokeWidth: 3.5,
            ),
          ),
        ),
      );
    }

    return MouseRegion(
      onExit: (_) {
        // When cursor exits player area in Flutter, clear hover & blur active element in WebView2
        _controller.executeScript('''
          try {
            if (document.activeElement) document.activeElement.blur();
            window.dispatchEvent(new Event('blur'));
            var f = document.getElementById('player');
            if (f) {
              f.blur();
              f.dispatchEvent(new MouseEvent('mouseleave', { bubbles: true, clientX: -9999, clientY: -9999 }));
              f.dispatchEvent(new MouseEvent('mouseout', { bubbles: true, clientX: -9999, clientY: -9999 }));
            }
          } catch(e) {}
        ''');
      },
      child: Webview(
        _controller,
        permissionRequested: (url, permissionKind, isUserInitiated) =>
            WebviewPermissionDecision.allow,
      ),
    );
  }
}
