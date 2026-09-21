import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_windows/webview_windows.dart' as win_web;
import 'package:window_manager/window_manager.dart';
import 'package:youtube_downloader/features/sports/presentation/widgets/match_score_line.dart';
import '../../data/models/sports_models.dart';
import '../providers/sports_provider.dart';
import '../lineup_layout.dart';
import '../../../../core/constants/app_palette.dart';

class PlayerChannelItem {
  final String id;
  final String name;
  final String? logo;

  /// Our own feed, shown with the app's icon rather than a broadcaster mark.
  final bool isAppSource;
  final String? streamUrl;
  final String? subtitle;
  final Map<String, String>? headers;
  final bool isWebStream;

  const PlayerChannelItem({
    required this.id,
    required this.name,
    this.logo,
    this.isAppSource = false,
    this.streamUrl,
    this.subtitle,
    this.headers,
    this.isWebStream = false,
  });
}

class SportsPlayerScreen extends ConsumerStatefulWidget {
  final SportMatchItem match;
  final String? directUrl;
  final Map<String, String>? headers;
  final SportsChannel? initialSportsChannel;

  const SportsPlayerScreen({
    super.key,
    required this.match,
    this.directUrl,
    this.headers,
    this.initialSportsChannel,
  });

  @override
  ConsumerState<SportsPlayerScreen> createState() => _SportsPlayerScreenState();
}

class _SportsPlayerScreenState extends ConsumerState<SportsPlayerScreen> with WidgetsBindingObserver {
  VideoPlayerController? _videoController;
  Player? _desktopPlayer;
  VideoController? _desktopVideoController;
  final List<StreamSubscription> _desktopSubscriptions = [];
  WebViewController? _webController;
  win_web.WebviewController? _winWebController;
  StreamSubscription? _winFullscreenSub;
  bool _winWebInitialized = false;
  bool _isLoadingStream = true;
  bool _isStreamBuffering = false;
  bool _isWebActive = false;
  String? _streamErrorMessage;
  bool _isLandscape = false;
  bool _controlsVisible = true;
  bool _isPlaying = true;
  Timer? _hideControlsTimer;
  int _streamLoadToken = 0;
  BoxFit _videoFit = BoxFit.fill;
  String? _fitToastText;
  Timer? _fitToastTimer;

  String get _videoFitTitle {
    switch (_videoFit) {
      case BoxFit.fill:
        return 'ملء الشاشة بالكامل';
      case BoxFit.cover:
        return 'تكبير مع الحفاظ على النسبة';
      case BoxFit.contain:
        return 'الأبعاد الأصلية (16:9)';
      default:
        return 'ملء الشاشة';
    }
  }

  void _cycleVideoFit() {
    setState(() {
      if (_videoFit == BoxFit.fill) {
        _videoFit = BoxFit.cover;
      } else if (_videoFit == BoxFit.cover) {
        _videoFit = BoxFit.contain;
      } else {
        _videoFit = BoxFit.fill;
      }
    });
    _showFitToast(_videoFitTitle);
    _scheduleHideControls();
  }

  void _showFitToast(String text) {
    _fitToastTimer?.cancel();
    setState(() => _fitToastText = text);
    _fitToastTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _fitToastText = null);
    });
  }

  int _selectedTab = 0; // 0: التشكيلة (Lineup), 1: الأحداث (Events), 2: الإحصائيات (Stats), 3: معلومات (Info)
  int _pitchTeamIndex = 0; // 0: Home Team, 1: Away Team

  List<PlayerChannelItem> _channels = [];
  String _activeChannelId = '';
  bool _loadingChannels = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    _setupChannelsAndStream();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      final views = WidgetsBinding.instance.platformDispatcher.views;
      if (views.isNotEmpty) {
        final isLandscapeNow = views.first.physicalSize.width > views.first.physicalSize.height;
        if ((_isLandscape || isLandscapeNow) && mounted) {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        } else if (!_isLandscape && !isLandscapeNow && mounted) {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        }
      }
    }
  }

  /// Coming back from the background in fullscreen leaves the bars showing too.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && _isLandscape && mounted) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(const AssetImage('assets/images/app_logo.png'), context);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideControlsTimer?.cancel();
    _winFullscreenSub?.cancel();
    _fitToastTimer?.cancel();
    _videoController?.dispose();
    for (final s in _desktopSubscriptions) {
      s.cancel();
    }
    _desktopPlayer?.stop();
    _desktopPlayer?.dispose();
    _winWebController?.dispose();
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        windowManager.setFullScreen(false);
      } catch (_) {}
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  void _setFullscreen(bool fullscreen) async {
    final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    setState(() => _isLandscape = fullscreen);
    if (isDesktop) {
      try {
        await windowManager.setFullScreen(fullscreen);
      } catch (_) {}
      if (!fullscreen && _winWebController != null && _winWebInitialized) {
        _winWebController?.executeScript('if (document.fullscreenElement) document.exitFullscreen();').catchError((_) {});
      }
    } else {
      SystemChrome.setEnabledSystemUIMode(
        fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
      if (fullscreen) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        // Immediately flip back upright to portrait mode
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
        // After returning upright, allow sensor rotation again
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (mounted && !_isLandscape) {
            SystemChrome.setPreferredOrientations([
              DeviceOrientation.portraitUp,
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]);
          }
        });
      }
    }
  }

  void _exitFullscreen() => _setFullscreen(false);

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    if (!_isPlaying) return;
    _hideControlsTimer = Timer(const Duration(seconds: 7), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHideControls();
  }

  static const String _adBlockAndCleanupJs = r'''
  (function() {
    window.__isTV = true;
    window.open = function() { return null; };
    window.alert = function() { return true; };
    window.confirm = function() { return true; };
    window.prompt = function() { return null; };

    var styleId = 'sports-ad-blocker-style-v3';
    var style = document.getElementById(styleId);
    if (!style) {
      style = document.createElement('style');
      style.id = styleId;
      style.innerHTML = `
        [class*="telegram" i], [id*="telegram" i],
        [class*="tg-" i], [id*="tg-" i], [class*="tg_" i], [id*="tg_" i],
        a[href*="t.me" i], a[href*="telegram" i], a[href*="whatsapp" i],
        .tg-modal, .tg-banner, .tg-card, .popup-overlay, .modal-backdrop,
        div[style*="z-index: 9999"], div[style*="z-index: 99999"], div[style*="z-index: 2147483647"],
        .albaplayer_name, .embed-btn, .embed-modal, .embed-content, .embed-copy-btn, .btn-embed,
        #topbar, #bottomBar, [class*="bottom-banner" i], [id*="bottom-banner" i],
        [class*="app-banner" i], [id*="app-banner" i] {
          display: none !important;
          visibility: hidden !important;
          opacity: 0 !important;
          pointer-events: none !important;
          width: 0 !important;
          height: 0 !important;
          max-height: 0 !important;
          overflow: hidden !important;
        }
        html, body {
          background: #000 !important;
          width: 100% !important;
          height: 100% !important;
          overflow: hidden !important;
          margin: 0 !important;
          padding: 0 !important;
        }
      `;
      (document.head || document.documentElement).appendChild(style);
    }

    function purgeAds() {
      try {
        var tgLinks = document.querySelectorAll('a[href*="t.me"], a[href*="telegram"], a[href*="bit.ly"], a[href*="1xbet"]');
        tgLinks.forEach(function(a) {
          var cur = a;
          for (var i = 0; i < 6 && cur && cur !== document.body; i++) {
            if (cur.querySelector && cur.querySelector('video')) break;
            var pos = window.getComputedStyle(cur).position;
            if (pos === 'fixed' || pos === 'absolute' || cur.tagName === 'DIV' || cur.tagName === 'SECTION') {
              cur.style.display = 'none';
              cur.remove();
              return;
            }
            cur = cur.parentElement;
          }
          a.style.display = 'none';
          a.remove();
        });

        var adKeywords = [
          'المراهنات',
          'توقعات | مراهنات',
          'مراهنات كرة القدم',
          'انضم لأكثر من',
          'انضم الآن',
          'توقعات مجانية',
          'نسبة نجاح',
          'حمل تطبيقنا',
          'SIR TV على جوجل بلاي',
          'تأكد من اللوغو',
          'على جوجل بلاي'
        ];
        var candidates = document.querySelectorAll('div, section, aside, p, span, a, button');
        candidates.forEach(function(el) {
          if (el.querySelector && el.querySelector('video')) return;
          var text = el.innerText || el.textContent || '';
          for (var k = 0; k < adKeywords.length; k++) {
            if (text.indexOf(adKeywords[k]) !== -1) {
              var target = el;
              while (target.parentElement && target.parentElement !== document.body) {
                var p = target.parentElement;
                if (p.querySelector && p.querySelector('video')) break;
                var pos = window.getComputedStyle(p).position;
                if (pos === 'fixed' || pos === 'absolute' || p.offsetWidth < window.innerWidth * 0.95) {
                  target = p;
                } else {
                  break;
                }
              }
              target.style.display = 'none';
              target.remove();
              break;
            }
          }
        });

        document.querySelectorAll('button, div, span').forEach(function(el) {
          if (el.querySelector && el.querySelector('video')) return;
          var txt = (el.innerText || el.textContent || '').trim();
          var style = window.getComputedStyle(el);
          if ((txt === '×' || txt === 'X' || txt === 'x') && (style.position === 'fixed' || style.position === 'absolute')) {
            el.remove();
          }
        });

        document.querySelectorAll('button, a, div').forEach(function(el) {
          var txt = (el.innerText || '').trim();
          if (txt === '< / >' || txt === '</>' || txt === '⟳' || txt === '↻') {
            var style = window.getComputedStyle(el);
            if (style.position === 'absolute' || style.position === 'fixed') {
              el.style.display = 'none';
              el.remove();
            }
          }
        });

        document.querySelectorAll('iframe').forEach(function(frame) {
          try {
            var doc = frame.contentDocument || frame.contentWindow.document;
            if (doc && !doc.getElementById(styleId)) {
              var fStyle = doc.createElement('style');
              fStyle.id = styleId;
              fStyle.innerHTML = style.innerHTML;
              (doc.head || doc.documentElement).appendChild(fStyle);
            }
          } catch (_) {}
        });

        boostVideoQuality();
      } catch (_) {}
    }

    function boostVideoQuality() {
      try {
        if (window.player && window.player.core) {
          var container = window.player.core.activeContainer;
          if (container && container.playback && container.playback._hls) {
            var hls = container.playback._hls;
            hls.capLevelToPlayerSize = false;
            hls.autoLevelCapping = -1;
            if (hls.levels && hls.levels.length > 0) {
              hls.currentLevel = hls.levels.length - 1;
            }
          }
        }
        if (window.Hls && window.Hls.instances) {
          window.Hls.instances.forEach(function(hls) {
            try {
              hls.capLevelToPlayerSize = false;
              hls.autoLevelCapping = -1;
              if (hls.levels && hls.levels.length > 0) {
                hls.currentLevel = hls.levels.length - 1;
              }
            } catch (_) {}
          });
        }
        document.querySelectorAll('video').forEach(function(v) {
          v.style.imageRendering = '-webkit-optimize-contrast';
          v.style.imageRendering = 'crisp-edges';
          v.style.filter = 'none';
        });
      } catch (_) {}
    }

    purgeAds();
    if (!window.__sportsAdPurgeInterval) {
      window.__sportsAdPurgeInterval = setInterval(purgeAds, 350);
    }
    if (!window.__sportsAdPurgeObserver && document.documentElement) {
      window.__sportsAdPurgeObserver = new MutationObserver(purgeAds);
      window.__sportsAdPurgeObserver.observe(document.documentElement, { childList: true, subtree: true });
    }
  })();
  ''';

    String _buildCleanPlayerHtml(String streamUrl) {
    return '''<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>Match Stream</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body { width: 100%; height: 100%; background: #000; overflow: hidden; display: flex; align-items: center; justify-content: center; }
    #player { width: 100%; height: 100%; object-fit: fill; background: #000; }
  </style>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/hls.js/1.5.8/hls.min.js"></script>
</head>
<body>
  <video id="player" autoplay playsinline webkit-playsinline controls></video>
  <script>
    (function() {
      var video = document.getElementById('player');
      var src = "$streamUrl";

      function playVideo() {
        video.play().catch(function() {
          video.muted = true;
          video.play();
        });
      }

      if (window.Hls && Hls.isSupported()) {
        var hls = new Hls({
          enableWorker: true,
          lowLatencyMode: true,
          backBufferLength: 30,
          manifestLoadingMaxRetry: 5,
          levelLoadingMaxRetry: 4
        });
        hls.loadSource(src);
        hls.attachMedia(video);
        hls.on(Hls.Events.MANIFEST_PARSED, function() {
          playVideo();
        });
        hls.on(Hls.Events.ERROR, function(event, data) {
          if (data.fatal) {
            switch (data.type) {
              case Hls.ErrorTypes.NETWORK_ERROR:
                hls.startLoad();
                break;
              case Hls.ErrorTypes.MEDIA_ERROR:
                hls.recoverMediaError();
                break;
              default:
                hls.destroy();
                break;
            }
          }
        });
      } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
        video.src = src;
        video.addEventListener('loadedmetadata', playVideo);
      } else {
        video.src = src;
        playVideo();
      }

      [300, 800, 1500, 3000].forEach(function(ms) {
        setTimeout(playVideo, ms);
      });
    })();
  </script>
</body>
</html>''';
  }

  WebViewController _ensureWebController() {
    if (_webController != null) return _webController!;
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black);

    if (controller.platform is AndroidWebViewController) {
      final androidController = controller.platform as AndroidWebViewController;
      androidController.setMediaPlaybackRequiresUserGesture(false);
    }

    controller.setUserAgent(
      'Mozilla/5.0 (Linux; Android 14; SmartTV; SM-A266B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    );

    controller.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (_) {
          _injectEarly(controller);
        },
        onPageFinished: (_) {
          _injectCleanup(controller);
          if (mounted) setState(() => _isLoadingStream = false);
        },
        onWebResourceError: (error) {
          if (mounted && error.isForMainFrame == true) {
            setState(() {
              _isLoadingStream = false;
              _streamErrorMessage = 'تعذّر تحميل البث';
            });
          }
        },
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (uri == null) return NavigationDecision.prevent;
          final scheme = uri.scheme.toLowerCase();
          if (scheme == 'about' || scheme == 'data') return NavigationDecision.navigate;
          if (scheme != 'http' && scheme != 'https') return NavigationDecision.prevent;

          final host = uri.host.toLowerCase();
          final isAllowed = host.contains('matchlivehd.com') ||
              host.contains('r2.dev') ||
              host.contains('yassirtv.com') ||
              host.contains('siiir.tv') ||
              host.contains('sira.website') ||
              host.contains('koora-l.live') ||
              host.contains('korax90.co') ||
              host.contains('boomstreaming.com') ||
              host.contains('cloudflare.com') ||
              host.contains('cdnjs.cloudflare.com') ||
              host.contains('jsdelivr.net') ||
              host.endsWith('.sbs') ||
              host.endsWith('.cfd') ||
              host.contains('fabor-tv-player.me');

          if (!isAllowed) {
            debugPrint('[SPORTS_WEBVIEW] Blocked unwanted ad navigation: ${request.url}');
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ),
    );

    _webController = controller;
    return controller;
  }

  void _injectEarly(WebViewController controller) {
    const js = """
    (function() {
      window.__isTV = true;
      window.open = function() { return null; };
      window.alert = function() { return true; };
      window.confirm = function() { return true; };
      window.prompt = function() { return null; };
      window.ConsoleBan = { init: function() {} };
      window.aclib = { runPop: function() {}, runAutoTag: function() {} };

      document.addEventListener('click', function(e) {
        var el = e.target;
        while (el && el !== document.documentElement) {
          if (el.id === 'aclib' || 
              (el.className && typeof el.className === 'string' && (el.className.indexOf('pop') !== -1 || el.className.indexOf('ad') !== -1)) ||
              (el.tagName === 'A' && el.target === '_blank' && el.href && !el.href.includes('matchlivehd'))) {
            e.preventDefault();
            e.stopPropagation();
            return false;
          }
          el = el.parentElement;
        }
      }, true);
    })();
    """;
    controller.runJavaScript(js).catchError((_) {});
  }

  void _injectCleanup(WebViewController controller) {
    controller.runJavaScript(_adBlockAndCleanupJs).catchError((_) {});
    const autoPlayJs = """
    (function() {
      var v = document.querySelector('video');
      if (v) {
        v.playsInline = true;
        v.webkitPlaysInline = true;
        v.autoplay = true;
        v.play().catch(function() {
          v.muted = true;
          v.play();
        });
      }
    })();
    """;
    for (final ms in [300, 700, 1500, 3000, 5000]) {
      Future.delayed(Duration(milliseconds: ms), () {
        if (mounted && _webController != null) {
          _webController?.runJavaScript(_adBlockAndCleanupJs).catchError((_) {});
          _webController?.runJavaScript(autoPlayJs).catchError((_) {});
        }
      });
    }
  }

  Future<void> _loadWindowsWebview(String url) async {
    final c = _winWebController ?? win_web.WebviewController();
    if (!_winWebInitialized) {
      await c.initialize();
      await c.setUserAgent(
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0',
      );
      await c.setBackgroundColor(Colors.black);
      await c.setPopupWindowPolicy(win_web.WebviewPopupWindowPolicy.deny);
      _winWebInitialized = true;

      c.loadingState.listen((state) {
        if (state == win_web.LoadingState.navigationCompleted) {
          _winWebController?.executeScript(_adBlockAndCleanupJs).catchError((_) {});
        }
      });

      // Synchronize HTML5 fullscreen events from the web player directly to our app
      _winFullscreenSub?.cancel();
      _winFullscreenSub = c.containsFullScreenElementChanged.listen((isFullScreen) {
        _setFullscreen(isFullScreen);
      });
    }
    _winWebController = c;
    await c.loadUrl(url);

    for (final ms in [400, 1000, 2000, 3500, 5000]) {
      Future.delayed(Duration(milliseconds: ms), () {
        if (mounted && _winWebController != null && _winWebInitialized) {
          _winWebController?.executeScript(_adBlockAndCleanupJs).catchError((_) {});
        }
      });
    }
  }

  Future<void> _togglePlayPause() async {
    final activeCh = _channels.firstWhere(
      (c) => c.id == _activeChannelId,
      orElse: () => _channels.firstOrNull ?? const PlayerChannelItem(id: '', name: ''),
    );
    final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final willPlay = !_isPlaying;

    setState(() => _isPlaying = willPlay);

    if (activeCh.isWebStream) {
      final js = """
      (function() {
        var videos = document.querySelectorAll('video');
        videos.forEach(function(v) {
          if ($willPlay) {
            v.play().catch(function() {});
          } else {
            v.pause();
          }
        });
      })();
      """;
      if (Platform.isWindows && _winWebController != null && _winWebInitialized) {
        try {
          await _winWebController!.executeScript(js);
        } catch (_) {}
      } else if (_webController != null) {
        try {
          await _webController!.runJavaScript(js);
        } catch (_) {}
      }
    } else if (isDesktop && _desktopPlayer != null) {
      try {
        await _desktopPlayer!.playOrPause();
        if (mounted) {
          setState(() => _isPlaying = _desktopPlayer!.state.playing);
        }
      } catch (_) {}
    } else if (_videoController != null && _videoController!.value.isInitialized) {
      try {
        if (_videoController!.value.isPlaying) {
          await _videoController!.pause();
        } else {
          await _videoController!.play();
        }
        if (mounted) {
          setState(() => _isPlaying = _videoController!.value.isPlaying);
        }
      } catch (_) {}
    }

    _scheduleHideControls();
  }

  String _formatKickoffLocal(String raw) {
    if (raw.trim().isEmpty) return '';
    try {
      final dt = DateTime.tryParse(raw.trim());
      if (dt != null) {
        final local = dt.toLocal();
        final h = local.hour;
        final m = local.minute.toString().padLeft(2, '0');
        final period = h >= 12 ? 'م' : 'ص';
        final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
        return '$h12:$m $period';
      }
    } catch (_) {}
    return raw;
  }

  Future<void> _setupChannelsAndStream() async {
    final channelList = <PlayerChannelItem>[];

    // Single Channel Mode (opened directly from Channels tab)
    if (widget.initialSportsChannel != null) {
      final ch = widget.initialSportsChannel!;
      final isYoutube = ch.channelType == 'YOUTUBE_LIVE' || ch.channelUrl.contains('youtube.com');
      channelList.add(
        PlayerChannelItem(
          id: 'single_${ch.channelId}',
          name: ch.channelName,
          logo: ch.channelImage,
          streamUrl: ch.channelUrl,
          subtitle: ch.categoryName.isNotEmpty ? ch.categoryName : 'بث مباشر HD',
          isWebStream: isYoutube,
        ),
      );
      _activeChannelId = channelList.first.id;
      if (mounted) {
        setState(() {
          _channels = channelList;
          _loadingChannels = false;
        });
      }
      _loadChannelStream(channelList.first);
      return;
    }

    // MATCH MODE: Display ONLY channels broadcasting this specific match!
    final match = widget.match;
    final direct = widget.directUrl ?? match.directUrl;
    final sportsService = ref.read(sportsServiceProvider);

    // 1. Direct Broadcasters on the match model (e.g. from SIR TV or merged stream feeds)
    if (match.broadcasters.isNotEmpty) {
      for (final b in match.broadcasters) {
        if (b.streamUrl != null && b.streamUrl!.isNotEmpty) {
          final isHls = b.streamUrl!.contains('.m3u8');
          channelList.add(
            PlayerChannelItem(
              id: 'match_broadcaster_${b.id}',
              name: b.name.isNotEmpty ? b.name : 'قناة البث المباشر HD',
              streamUrl: b.streamUrl,
              isAppSource: true,
              isWebStream: !isHls && (b.streamUrl!.contains('http') && !b.streamUrl!.endsWith('.m3u8')),
              subtitle: isHls ? 'بث HLS مباشر فائق السرعة' : 'مشغل البث المباشر',
            ),
          );
        }
      }
    }

    // 2. Kora x90 Streaming Sources (Authoritative source)
    if (direct != null && (direct.contains('korax90.co') || direct.contains('boomstreaming.com'))) {
      try {
        final koraServers = await sportsService.resolveKoraX90Servers(direct);
        for (int i = 0; i < koraServers.length; i++) {
          final s = koraServers[i];
          final isHls = s.streamUrl.contains('.m3u8');
          channelList.add(
            PlayerChannelItem(
              id: 'korax90_server_$i',
              name: s.name.isNotEmpty ? s.name : 'سيرفر ${i + 1} HD',
              isAppSource: true,
              streamUrl: s.streamUrl,
              subtitle: isHls ? 'بث HLS مباشر فائق السرعة' : 'مشغل البث المباشر',
              isWebStream: !isHls && (s.type == 'iframe' || s.streamUrl.contains('.php')),
              headers: isHls
                  ? const {
                      'User-Agent': 'Mozilla/5.0 (Linux; Android 14; SmartTV; SM-A266B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                      'Referer': 'https://9.boomstreaming.com/',
                    }
                  : null,
            ),
          );
        }
      } catch (e) {
        debugPrint('[SPORTS_PLAYER] Kora x90 servers resolve error: $e');
      }
    }

    // 3. Match against live sports channels in the app (e.g. beIN Sports 1, Alkass, SSC)
    final bName = (match.broadcasterName ?? '').trim();
    if (bName.isNotEmpty && bName != 'غير معروف') {
      final allChannels = ref.read(sportsChannelsProvider).valueOrNull ?? [];
      for (final ch in allChannels) {
        final chName = ch.channelName.toLowerCase();
        final cleanBName = bName.toLowerCase();
        if (chName.contains(cleanBName) || cleanBName.contains(chName)) {
          channelList.add(
            PlayerChannelItem(
              id: 'tv_channel_${ch.channelId}',
              name: ch.channelName,
              logo: ch.channelImage,
              streamUrl: ch.channelUrl,
              subtitle: 'بث القناة الناقلة للمباراة',
              isWebStream: ch.channelType == 'YOUTUBE_LIVE' || ch.channelUrl.contains('youtube.com'),
            ),
          );
        }
      }
    }

    if (channelList.isEmpty) {
      if (mounted) {
        setState(() {
          _channels = [];
          _loadingChannels = false;
          _isLoadingStream = false;
          if (match.isEnded || match.status == 'finished') {
            _streamErrorMessage = 'انتهت هذه المباراة، ولا يتوفر بث مباشر حالياً.';
          } else if (match.isScheduled || match.status == 'scheduled' || match.status.contains('لم تبدأ')) {
            final t = _formatKickoffLocal(match.kickoffAt);
            _streamErrorMessage = t.isNotEmpty
                ? 'لم تبدأ المباراة بعد • موعد انطلاق البث: $t'
                : 'لم تبدأ المباراة بعد. سيبدأ البث المباشر قبل انطلاق المباراة.';
          } else {
            _streamErrorMessage = 'سيرفرات البث المباشر غير متاحة حالياً، يرجى إعادة المحاولة لاحقاً.';
          }
        });
      }
      return;
    }

    final initial = channelList.firstWhere(
      (c) => c.streamUrl != null && c.streamUrl!.isNotEmpty,
      orElse: () => channelList.first,
    );
    _activeChannelId = initial.id;

    if (mounted) {
      setState(() {
        _channels = channelList;
        _loadingChannels = false;
      });
    }

    _loadChannelStream(initial);
  }

  /// Plays the selected channel using native VideoPlayer for HLS and WebViewController for web streams.
  Future<void> _loadChannelStream(PlayerChannelItem channel, {bool forceRefresh = false}) async {
    if (!mounted) return;
    final token = ++_streamLoadToken;
    final oldController = _videoController;
    if (mounted) {
      setState(() {
        _activeChannelId = channel.id;
        _isLoadingStream = true;
        _isStreamBuffering = false;
        _isWebActive = false;
        _isPlaying = true;
        _streamErrorMessage = null;
        _videoController = null;
      });
    }
    await oldController?.dispose();
    if (!mounted || token != _streamLoadToken) return;

    // Clean up desktop player if active
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        await _desktopPlayer?.stop();
      } catch (_) {}
    }

    // Clean up windows webview if switching to a non-web channel
    if (Platform.isWindows && !channel.isWebStream && _winWebController != null && _winWebInitialized) {
      try {
        await _winWebController!.loadUrl('about:blank');
      } catch (_) {}
    }

    final rawUrl = channel.streamUrl ?? '';
    if (rawUrl.isEmpty) {
      if (mounted && token == _streamLoadToken) {
        setState(() {
          _isLoadingStream = false;
          _isStreamBuffering = false;
          _streamErrorMessage = 'بث ${channel.name} غير متاح الآن';
        });
      }
      return;
    }

    if (channel.isWebStream) {
      if (Platform.isWindows) {
        try {
          await _loadWindowsWebview(rawUrl);
          if (mounted && token == _streamLoadToken) {
            setState(() {
              _isWebActive = true;
              _isLoadingStream = false;
              _isStreamBuffering = false;
              _streamErrorMessage = null;
            });
          }
          return;
        } catch (e) {
          debugPrint('[SPORTS_PLAYER] Windows WebView error: $e');
        }
      } else if (!Platform.isLinux && !Platform.isMacOS) {
        try {
          final controller = _ensureWebController();
          await controller.loadRequest(
            Uri.parse(rawUrl),
            headers: channel.headers ?? const {},
          );
          if (mounted && token == _streamLoadToken) {
            setState(() {
              _isWebActive = true;
              _isLoadingStream = false;
              _isStreamBuffering = false;
              _streamErrorMessage = null;
            });
          }
          return;
        } catch (e) {
          debugPrint('[SPORTS_PLAYER] Mobile WebView error: $e');
        }
      }

      if (mounted && token == _streamLoadToken) {
        setState(() {
          _isLoadingStream = false;
          _isStreamBuffering = false;
          _streamErrorMessage = 'تعذّر تشغيل بث القناة المحددة، يُرجى تجربة قناة أخرى من الأسفل.';
        });
      }
      return;
    }

    final sportsService = ref.read(sportsServiceProvider);
    final resolved = await sportsService.resolveLiveStream(rawUrl, forceRefresh: forceRefresh);
    if (!mounted || token != _streamLoadToken) return;

    final streamUrl = resolved?.streamUrl ?? rawUrl;
    final albaplayerUrl = resolved?.albaplayerUrl;
    final Map<String, String> headers = (channel.headers != null && channel.headers!.isNotEmpty)
        ? Map<String, String>.from(channel.headers!)
        : ((resolved != null && resolved.headers.isNotEmpty)
            ? Map<String, String>.from(resolved.headers)
            : (streamUrl.contains('boomstreaming.com') || streamUrl.contains('korax90.co')
                ? const {
                    'User-Agent': 'Mozilla/5.0 (Linux; Android 14; SmartTV; SM-A266B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                    'Referer': 'https://9.boomstreaming.com/',
                  }
                : const {
                    'User-Agent': 'Mozilla/5.0 (Linux; Android 14; SmartTV; SM-A266B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                    'Referer': 'https://pl.matchlivehd.com/',
                  }));

    // If streamUrl is actually a webpage (could not be resolved into HLS/video stream)
    final bool isStreamWebpage = !streamUrl.contains('.m3u8') &&
        !streamUrl.contains('.mp4') &&
        !streamUrl.endsWith('.css') &&
        !streamUrl.contains('/index.css') &&
        !streamUrl.contains('.sss');

    if (isStreamWebpage) {
      if (Platform.isWindows) {
        try {
          await _loadWindowsWebview(streamUrl);
          if (mounted && token == _streamLoadToken) {
            setState(() {
              _isWebActive = true;
              _isLoadingStream = false;
              _isStreamBuffering = false;
              _streamErrorMessage = null;
            });
          }
          return;
        } catch (_) {}
      } else if (!Platform.isLinux && !Platform.isMacOS) {
        try {
          final webCtrl = _ensureWebController();
          final targetWebUrl = (albaplayerUrl != null && albaplayerUrl.isNotEmpty) ? albaplayerUrl : streamUrl;
          await webCtrl.loadRequest(Uri.parse(targetWebUrl), headers: headers);
          if (mounted && token == _streamLoadToken) {
            setState(() {
              _isWebActive = true;
              _isLoadingStream = false;
              _isStreamBuffering = false;
              _streamErrorMessage = null;
            });
          }
          return;
        } catch (_) {}
      }
    }

    // On Desktop (Windows / macOS / Linux), use MediaKit with mpv hardware acceleration
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        _desktopPlayer ??= Player(
          configuration: const PlayerConfiguration(
            bufferSize: 32 * 1024 * 1024,
          ),
        );
        _desktopVideoController ??= VideoController(
          _desktopPlayer!,
          configuration: const VideoControllerConfiguration(
            enableHardwareAcceleration: true,
          ),
        );

        for (final s in _desktopSubscriptions) {
          s.cancel();
        }
        _desktopSubscriptions.clear();

        _desktopSubscriptions.add(_desktopPlayer!.stream.buffering.listen((buffering) {
          if (mounted && token == _streamLoadToken) {
            setState(() => _isStreamBuffering = buffering);
          }
        }));
        _desktopSubscriptions.add(_desktopPlayer!.stream.playing.listen((playing) {
          if (mounted && token == _streamLoadToken) {
            setState(() => _isPlaying = playing);
          }
        }));
        _desktopSubscriptions.add(_desktopPlayer!.stream.error.listen((err) {
          debugPrint('[DESKTOP_SPORTS_PLAYER] error: $err');
          if (mounted && token == _streamLoadToken && !forceRefresh) {
            _loadChannelStream(channel, forceRefresh: true);
          }
        }));

        await _desktopPlayer!.open(
          Media(
            streamUrl,
            httpHeaders: headers,
          ),
          play: true,
        );

        if (!mounted || token != _streamLoadToken) return;
        setState(() {
          _isWebActive = false;
          _isLoadingStream = false;
          _isStreamBuffering = false;
          _isPlaying = true;
          _streamErrorMessage = null;
        });
        _scheduleHideControls();
      } catch (e) {
        debugPrint('[DESKTOP_SPORTS_PLAYER] playback failed: $e');
        if (Platform.isWindows) {
          try {
            await _loadWindowsWebview(albaplayerUrl ?? rawUrl);
            if (mounted && token == _streamLoadToken) {
              setState(() {
                _isWebActive = true;
                _isLoadingStream = false;
                _isStreamBuffering = false;
                _streamErrorMessage = null;
              });
            }
            return;
          } catch (_) {}
        }

        if (!forceRefresh) {
          return _loadChannelStream(channel, forceRefresh: true);
        }
        if (mounted && token == _streamLoadToken) {
          setState(() {
            _isLoadingStream = false;
            _isStreamBuffering = false;
            _streamErrorMessage = 'تعذّر تشغيل البث المباشر';
          });
        }
      }
      return;
    }

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(streamUrl),
      formatHint: VideoFormat.hls,
      httpHeaders: headers,
    );

    try {
      await controller.initialize();
      if (!mounted || token != _streamLoadToken) {
        await controller.dispose();
        return;
      }
      controller.addListener(() => _onVideoEvent(token));
      await controller.play();

      if (mounted) {
        setState(() {
          _videoController = controller;
          _isWebActive = false;
          _isLoadingStream = false;
          _isStreamBuffering = false;
          _isPlaying = true;
        });
      }
      _scheduleHideControls();
    } catch (e) {
      debugPrint('[SPORTS_PLAYER] Native player error: $e');
      await controller.dispose();
      if (!mounted || token != _streamLoadToken) return;

      // Try alternative streams before falling back to clean web player
      if (resolved != null && resolved.alternativeStreamUrls.isNotEmpty) {
        for (final altUrl in resolved.alternativeStreamUrls) {
          try {
            debugPrint('[SPORTS_PLAYER] Trying alternative stream: $altUrl');
            final altController = VideoPlayerController.networkUrl(
              Uri.parse(altUrl),
              formatHint: VideoFormat.hls,
              httpHeaders: headers,
            );
            await altController.initialize();
            if (!mounted || token != _streamLoadToken) {
              await altController.dispose();
              return;
            }
            altController.addListener(() => _onVideoEvent(token));
            await altController.play();

            if (mounted) {
              setState(() {
                _videoController = altController;
                _isWebActive = false;
                _isLoadingStream = false;
                _isStreamBuffering = false;
                _isPlaying = true;
              });
            }
            _scheduleHideControls();
            return;
          } catch (_) {}
        }
      }

      // Fallback to Ad-Free Clean HTML5 Web Player
      try {
        debugPrint('[SPORTS_PLAYER] Fallback to clean web player for ${channel.name}');
        final webCtrl = _ensureWebController();
        if (streamUrl.contains('.m3u8') || streamUrl.contains('.css') || streamUrl.contains('r2.dev')) {
          final isBoom = streamUrl.contains('boomstreaming.com') || streamUrl.contains('korax90');
          final baseUrl = isBoom ? 'https://9.boomstreaming.com/' : 'https://pl.matchlivehd.com/';
          final cleanHtml = _buildCleanPlayerHtml(streamUrl);
          await webCtrl.loadHtmlString(cleanHtml, baseUrl: baseUrl);
        } else {
          final targetWebUrl = (albaplayerUrl != null && albaplayerUrl.isNotEmpty) ? albaplayerUrl : streamUrl;
          await webCtrl.loadRequest(Uri.parse(targetWebUrl), headers: headers);
        }
        if (mounted) {
          setState(() {
            _isWebActive = true;
            _isLoadingStream = false;
            _isStreamBuffering = false;
            _streamErrorMessage = null;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _isLoadingStream = false;
            _isStreamBuffering = false;
            _streamErrorMessage = 'تعذّر تشغيل البث المباشر';
          });
        }
      }
    }
  }

  void _onVideoEvent(int token) {
    final v = _videoController;
    if (v == null || !mounted || token != _streamLoadToken) return;

    if (v.value.hasError) {
      debugPrint('[SPORTS_PLAYER] Video error: ${v.value.errorDescription}, renewing token...');
      final activeCh = _channels.firstWhere(
        (c) => c.id == _activeChannelId,
        orElse: () => _channels.first,
      );
      _loadChannelStream(activeCh, forceRefresh: true);
    } else {
      final buffering = v.value.isBuffering;
      final playing = v.value.isPlaying;
      if (buffering != _isStreamBuffering || playing != _isPlaying) {
        if (mounted) {
          setState(() {
            _isStreamBuffering = buffering;
            _isPlaying = playing;
          });
        }
      }
    }
  }

  Future<void> _switchChannel(PlayerChannelItem channel) async {
    if (_activeChannelId == channel.id && !_isLoadingStream && _streamErrorMessage == null) {
      return;
    }
    await _loadChannelStream(channel);
  }

  Widget _buildPlayerArea({bool fullscreen = false}) {
    final activeCh = _channels.firstWhere(
      (c) => c.id == _activeChannelId,
      orElse: () => _channels.firstOrNull ?? const PlayerChannelItem(id: '', name: ''),
    );
    final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final v = _videoController;
    final buffering = _isLoadingStream || _isStreamBuffering;
    final showWeb = activeCh.isWebStream || _isWebActive;

    final playerWidget = ColoredBox(
      color: Colors.black,
      child: Stack(
        alignment: Alignment.center,
        fit: StackFit.expand,
        children: [
          if (showWeb)
            (Platform.isWindows && _winWebController != null && _winWebInitialized)
                ? win_web.Webview(_winWebController!)
                : (_webController != null
                    ? WebViewWidget(controller: _webController!)
                    : const SizedBox.shrink())
          else if (isDesktop && _desktopVideoController != null)
            SizedBox.expand(
              child: FittedBox(
                fit: _videoFit,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: 16,
                  height: 9,
                  child: Video(
                    controller: _desktopVideoController!,
                    controls: NoVideoControls,
                  ),
                ),
              ),
            )
          else if (v != null && v.value.isInitialized)
            ClipRect(
              child: SizedBox.expand(
                child: FittedBox(
                  fit: _videoFit,
                  clipBehavior: Clip.hardEdge,
                  child: Transform.scale(
                    scaleX: 1.018,
                    scaleY: 1.018,
                    child: SizedBox(
                      width: v.value.size.width > 0 ? v.value.size.width : (v.value.aspectRatio > 0 ? v.value.aspectRatio * 720 : 1280),
                      height: v.value.size.height > 0 ? v.value.size.height : 720,
                      child: VideoPlayer(v),
                    ),
                  ),
                ),
              ),
            ),
          // Watermark Shield: Solid dark frosted badge with App Logo covering the broadcaster logo/ad in top-right
          Positioned(
            top: fullscreen ? 4 : 2,
            right: fullscreen ? 4 : 2,
            child: _buildWatermarkShield(fullscreen),
          ),
          if (_fitToastText != null)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.aspect_ratio_rounded, color: Color(0xFFFF1744), size: 18),
                    const SizedBox(width: 8),
                    Text(
                      _fitToastText!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (buffering && _streamErrorMessage == null)
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const CircularProgressIndicator(
                  color: Color(0xFFFF1744),
                  strokeWidth: 3,
                ),
              ),
            ),
          if (_streamErrorMessage == null)
            _buildControlsOverlay(fullscreen, isWebStream: showWeb),
          if (_streamErrorMessage != null)
            _buildStreamErrorOverlay(),
        ],
      ),
    );

    if (showWeb) {
      return playerWidget;
    }
    // If it's a web stream, do NOT block mouse taps with Flutter gestures:
    // let all clicks pass straight to the HTML5 player controls!
    if (activeCh.isWebStream) {
      return playerWidget;
    }

    return MouseRegion(
      onHover: (_) {
        if (!_controlsVisible) {
          setState(() => _controlsVisible = true);
        }
        _scheduleHideControls();
      },
      child: GestureDetector(
        onTap: _toggleControls,
        onDoubleTap: () => _setFullscreen(!fullscreen),
        behavior: HitTestBehavior.opaque,
        child: playerWidget,
      ),
    );
  }

  Widget _buildWatermarkShield(bool fullscreen) {
    return IgnorePointer(
      child: Container(
        margin: EdgeInsets.only(
          top: fullscreen ? 8 : 4,
          right: fullscreen ? 10 : 5,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: fullscreen ? 10 : 6,
          vertical: fullscreen ? 4 : 2,
        ),
        decoration: BoxDecoration(
          // Smooth feathered vignette that blends completely seamlessly into the video frame
          // without any sharp rectangular borders or card outlines
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.15,
            colors: [
              Colors.black.withOpacity(0.55),
              Colors.black.withOpacity(0.25),
              Colors.transparent,
            ],
            stops: const [0.0, 0.65, 1.0],
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Opacity(
              opacity: 0.94,
              child: Image.asset(
                'assets/images/app_logo.png',
                width: fullscreen ? 22 : 16,
                height: fullscreen ? 22 : 16,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
            const SizedBox(width: 4.5),
            Text(
              'CINEBALL',
              style: TextStyle(
                color: Colors.white.withOpacity(0.94),
                fontSize: fullscreen ? 11 : 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
                shadows: const [
                  Shadow(
                    color: Colors.black,
                    blurRadius: 4,
                    offset: Offset(0, 1.2),
                  ),
                  Shadow(
                    color: Colors.black54,
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsOverlay(bool fullscreen, {required bool isWebStream}) {
    // If it's a web stream, do not overlay controls so native player stays usable
    if (isWebStream) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      ignoring: !_controlsVisible,
      child: AnimatedOpacity(
        opacity: _controlsVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 250),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Click outside buttons toggles controls; double tap toggles fullscreen
            Positioned.fill(
              child: GestureDetector(
                onTap: _toggleControls,
                onDoubleTap: () => _setFullscreen(!fullscreen),
                behavior: HitTestBehavior.translucent,
                child: const SizedBox.expand(),
              ),
            ),

            // Top exit bar when in fullscreen landscape mode
            if (fullscreen)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.85),
                        Colors.black.withOpacity(0.4),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => _setFullscreen(false),
                          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 24),
                          tooltip: 'تصغير الشاشة',
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${widget.match.home.name} vs ${widget.match.away.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => _setFullscreen(false),
                          icon: const Icon(Icons.fullscreen_exit_rounded, color: Colors.white, size: 24),
                          tooltip: 'تصغير',
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Center Play / Pause Button with clean glassmorphic design
            Center(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _togglePlayPause,
                  borderRadius: BorderRadius.circular(32),
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.35), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.4),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 38,
                    ),
                  ),
                ),
              ),
            ),

            // Bottom Footer Bar with smooth upward gradient
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 26, 10, 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.85),
                      Colors.black.withOpacity(0.4),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: _togglePlayPause,
                        icon: Icon(
                          _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                        tooltip: _isPlaying ? 'إيقاف مؤقت' : 'تشغيل',
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _isPlaying ? 'جارٍ البث' : 'متوقف مؤقتاً',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_channels.length > 1) ...[
                        const SizedBox(width: 10),
                        InkWell(
                          onTap: _showChannelSelectionSheet,
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.16),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white24, width: 0.8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 15),
                                const SizedBox(width: 4),
                                Text(
                                  'المصدر (${_channels.length})',
                                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      // Video Fit Toggle Button (ملء العرض / تكبير / أبعاد أصلية)
                      IconButton(
                        onPressed: _cycleVideoFit,
                        icon: Icon(
                          _videoFit == BoxFit.fill
                              ? Icons.fit_screen_rounded
                              : (_videoFit == BoxFit.cover ? Icons.zoom_out_map_rounded : Icons.aspect_ratio_rounded),
                          color: Colors.white,
                          size: 22,
                        ),
                        tooltip: _videoFitTitle,
                      ),
                      const SizedBox(width: 6),
                      // Prominent Fullscreen Pill Button with wide tap target
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _setFullscreen(!fullscreen),
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.22),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: Colors.white38, width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  fullscreen ? 'تصغير' : 'تكبير',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStreamErrorOverlay() {
    return ColoredBox(
      color: Colors.black87,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: 6,
            left: 8,
            child: SafeArea(
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 24),
                tooltip: 'رجوع',
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off_rounded, color: Colors.white54, size: 32),
                  const SizedBox(height: 10),
                  Text(
                    _streamErrorMessage ?? 'تعذّر تشغيل البث المباشر',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          final activeCh = _channels.firstWhere(
                            (c) => c.id == _activeChannelId,
                            orElse: () => _channels.first,
                          );
                          _loadChannelStream(activeCh, forceRefresh: true);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF1744),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text(
                          'إعادة المحاولة',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                      if (_channels.length > 1)
                        OutlinedButton.icon(
                          onPressed: () {
                            final next = _channels.firstWhere(
                              (c) => c.id != _activeChannelId,
                              orElse: () => _channels.first,
                            );
                            _switchChannel(next);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white38),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          ),
                          icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                          label: const Text(
                            'قناة أخرى',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white38),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        ),
                        icon: const Icon(Icons.arrow_back_rounded, size: 16),
                        label: const Text(
                          'رجوع',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showChannelSelectionSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF131826) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(
              color: isDark ? const Color(0xFF1F263A) : AppPalette.of(context).border,
            ),
            boxShadow: isDark ? null : AppPalette.of(context).cardShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.live_tv_rounded, color: Color(0xFFFF1744), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'اختر مصدر البث',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...List.generate(_channels.length, (i) {
                final ch = _channels[i];
                final isSelected = ch.id == _activeChannelId;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFFF1744).withOpacity(isDark ? 0.20 : 0.08)
                        : (isDark ? const Color(0xFF1B2234) : Colors.white),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFFFF1744)
                          : (isDark ? Colors.transparent : AppPalette.of(context).border),
                      width: 1.5,
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF101420) : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: isDark ? null : Border.all(color: AppPalette.of(context).border),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: _channelMark(ch, isSelected, isDark),
                    ),
                    title: Text(
                      ch.name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    subtitle: Text(
                      ch.subtitle ?? (ch.isWebStream ? 'بث الويب' : 'بث مباشر عالي الجودة'),
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle_rounded, color: Color(0xFFFF1744), size: 22)
                        : const Icon(Icons.play_arrow_rounded, color: Colors.grey, size: 20),
                    onTap: () {
                      Navigator.pop(ctx);
                      _switchChannel(ch);
                    },
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  /// Channel branding logo or fallback
  Widget _channelMark(PlayerChannelItem ch, bool isSelected, bool isDark) {
    if (ch.isAppSource) {
      return Image.asset('assets/images/app_logo.png', fit: BoxFit.contain);
    }
    final logo = ch.logo ?? '';
    if (logo.isNotEmpty) {
      return Image.network(
        logo,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _channelFallback(ch, isSelected, isDark),
      );
    }
    final lower = ch.name.toLowerCase();
    if (lower.contains('bein')) {
      return Image.network(
        'https://i.imgur.com/Vtk2cGI.png',
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _channelFallback(ch, isSelected, isDark),
      );
    }
    return _channelFallback(ch, isSelected, isDark);
  }

  Widget _channelFallback(PlayerChannelItem ch, bool isSelected, bool isDark) => Center(
        child: Icon(
          isSelected ? Icons.play_circle_fill_rounded : Icons.live_tv_rounded,
          size: 22,
          color: isSelected ? const Color(0xFFFF1744) : (isDark ? Colors.white60 : Colors.black45),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final match = widget.match;
    final matchDetailsAsync = ref.watch(
      matchDetailsProvider((
        matchId: match.id,
        sourceId: match.sourceId,
        homeName: match.home.name,
        awayName: match.away.name,
      )),
    );

    final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final isDeviceLandscape = !isDesktop && MediaQuery.of(context).orientation == Orientation.landscape;
    final isFullscreen = _isLandscape || isDeviceLandscape;

    final mainScaffold = Scaffold(
      backgroundColor: isFullscreen
          ? Colors.black
          : (isDark ? AppPalette.of(context).bg : AppPalette.of(context).bg),
      body: isFullscreen
          ? _buildPlayerArea(fullscreen: true)
          : SafeArea(
              top: true,
              bottom: false,
              left: false,
              right: false,
              child: _buildBody(context, isDark, match, matchDetailsAsync),
            ),
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (isFullscreen && !isDesktop) {
            _exitFullscreen();
          } else if (isFullscreen && isDesktop) {
            _setFullscreen(false);
          } else {
            Navigator.of(context).maybePop();
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: PopScope(
          canPop: !isFullscreen,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (isFullscreen) {
              _exitFullscreen();
            } else {
              Navigator.of(context).pop();
            }
          },
          child: mainScaffold,
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    bool isDark,
    SportMatchItem match,
    AsyncValue<MatchDetailedInfo?> matchDetailsAsync,
  ) {
    final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final screenH = MediaQuery.of(context).size.height;
    final videoH = isDesktop ? (screenH * 0.38).clamp(220.0, 340.0) : null;

    return Column(
      children: [
        // 1. Video Player Area: constrained height on desktop so tabs & pitch are always visible!
        Container(
          color: Colors.black,
          height: videoH,
          alignment: Alignment.center,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: _buildPlayerArea(fullscreen: false),
          ),
        ),

        // 2. Score & Teams Mini Strip with On-Demand Servers Chip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          color: isDark ? AppPalette.of(context).card : Colors.white,
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    _buildLogo(match.home.logo, 26),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        match.home.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: match.isLive
                      ? const Color(0xFFFF334B).withOpacity(0.12)
                      : (isDark ? const Color(0xFF1E2538) : Colors.white),
                  borderRadius: BorderRadius.circular(8),
                  border: (!isDark && !match.isLive) ? Border.all(color: AppPalette.of(context).border) : null,
                ),
                child: (match.isLive || match.isEnded)
                    ? MatchScoreLine(
                        homeScore: match.homeScore,
                        awayScore: match.awayScore,
                        separator: '-',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: match.isLive ? const Color(0xFFFF334B) : (isDark ? Colors.white : Colors.black87),
                        ),
                      )
                    : Text(
                        match.status,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        match.away.name,
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildLogo(match.away.logo, 26),
                  ],
                ),
              ),
              if (_channels.isNotEmpty) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: _showChannelSelectionSheet,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1F263A) : const Color(0xFFF0F3F8),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDark ? const Color(0xFF2E3852) : const Color(0xFFD6DEEB),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_loadingChannels)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: SizedBox(
                              width: 11,
                              height: 11,
                              child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFFFF1744)),
                            ),
                          )
                        else
                          const Icon(Icons.tune_rounded, size: 14, color: Color(0xFFFF1744)),
                        const SizedBox(width: 4),
                        Text(
                          'السيرفرات (${_channels.length})',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        // 3. Navigation Tab Bar (التشكيلة في المقدمة، ثم الأحداث، الإحصائيات، المعلومات)
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF111622) : Colors.white,
            border: Border(
              top: BorderSide(color: isDark ? const Color(0xFF1C2233) : const Color(0xFFE8EAF0)),
              bottom: BorderSide(color: isDark ? const Color(0xFF1C2233) : const Color(0xFFE8EAF0)),
            ),
          ),
          child: Row(
            children: [
              _buildTabPill('التشكيلة', Icons.people_alt_rounded, 0, isDark),
              _buildTabPill('الأحداث', Icons.sports_soccer_rounded, 1, isDark),
              _buildTabPill('الإحصائيات', Icons.bar_chart_rounded, 2, isDark),
              _buildTabPill('المعلومات', Icons.info_outline_rounded, 3, isDark),
            ],
          ),
        ),

        // 4. Tab Content Body
        Expanded(
          child: matchDetailsAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF1744)),
            ),
            error: (err, _) {
              final synthetic = _createSyntheticMatchDetails(widget.match);
              return _buildSelectedTabContent(synthetic, match, isDark);
            },
            data: (details) {
              final effectiveDetails = (details != null &&
                      details.homeLineup != null &&
                      details.homeLineup!.starters.isNotEmpty)
                  ? details
                  : _createSyntheticMatchDetails(widget.match);

              return _buildSelectedTabContent(effectiveDetails, match, isDark);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSelectedTabContent(MatchDetailedInfo details, SportMatchItem match, bool isDark) {
    switch (_selectedTab) {
      case 0:
        return _buildTacticalPitchLineupView(details, isDark);
      case 1:
        return _buildEventsTimelineView(details, match, isDark);
      case 2:
        return _buildStatsView(details, isDark);
      case 3:
      default:
        return _buildInfoView(details, match, isDark);
    }
  }

  Widget _buildTabPill(String title, IconData icon, int index, bool isDark) {
    final isSelected = _selectedTab == index;
    const accentColor = Color(0xFFFF1744);

    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? accentColor : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? accentColor : (isDark ? Colors.white54 : Colors.black45),
              ),
              const SizedBox(width: 4),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected ? accentColor : (isDark ? Colors.white70 : Colors.black87),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // 1. TACTICAL SOCCER PITCH LINEUP VIEW (الملعب)
  // ==========================================
  Widget _buildTacticalPitchLineupView(MatchDetailedInfo details, bool isDark) {
    final homeLineup = details.homeLineup;
    final awayLineup = details.awayLineup;

    if (homeLineup == null && awayLineup == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.stadium_rounded, size: 48, color: isDark ? Colors.white24 : Colors.black26),
              const SizedBox(height: 12),
              Text(
                'التشكيلة الرسمية لم تُنشر بعد',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'ستظهر هنا على أرضية الملعب فور إعلانها من قبل الفريقين',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white38 : Colors.black45,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final activeLineup = _pitchTeamIndex == 0 ? (homeLineup ?? awayLineup!) : (awayLineup ?? homeLineup!);
    final rawStarters = activeLineup.starters;
    final bool hasCaptain = rawStarters.any((p) => p.isCaptain);
    final startersWithCaptain = rawStarters.asMap().entries.map((entry) {
      final idx = entry.key;
      final p = entry.value;
      if (hasCaptain) return p;
      if (idx == (rawStarters.length > 3 ? 3 : 0)) {
        return PlayerLineupItem(
          id: p.id,
          athleteId: p.athleteId,
          name: p.name,
          shortName: p.shortName,
          jerseyNumber: p.jerseyNumber,
          position: p.position,
          isStarter: p.isStarter,
          line: p.line,
          fieldSide: p.fieldSide,
          rating: p.rating,
          popularityRank: p.popularityRank,
          isCaptain: true,
        );
      }
      return p;
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // Team Selector Switcher
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isDark ? AppPalette.of(context).card : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: isDark ? null : Border.all(color: AppPalette.of(context).border),
          ),
          child: Row(
            children: [
              if (homeLineup != null)
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _pitchTeamIndex = 0),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _pitchTeamIndex == 0 ? const Color(0xFFFF1744) : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            homeLineup.teamName,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: _pitchTeamIndex == 0 ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                            ),
                          ),
                          if (homeLineup.formation != null) ...[
                            const SizedBox(width: 4),
                            Text(
                              '(${homeLineup.formation})',
                              style: TextStyle(
                                fontSize: 11,
                                color: _pitchTeamIndex == 0 ? Colors.white70 : (isDark ? Colors.white38 : Colors.black45),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              if (awayLineup != null)
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _pitchTeamIndex = 1),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _pitchTeamIndex == 1 ? const Color(0xFFFF1744) : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            awayLineup.teamName,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: _pitchTeamIndex == 1 ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                            ),
                          ),
                          if (awayLineup.formation != null) ...[
                            const SizedBox(width: 4),
                            Text(
                              '(${awayLineup.formation})',
                              style: TextStyle(
                                fontSize: 11,
                                color: _pitchTeamIndex == 1 ? Colors.white70 : (isDark ? Colors.white38 : Colors.black45),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // REALISTIC FOOTBALL PITCH (أرضية الملعب)
        Container(
          height: 440,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                // Custom Painted Soccer Pitch
                CustomPaint(
                  size: const Size(double.infinity, 440),
                  painter: _SoccerFieldPainter(),
                ),

                // Tactical Player Formations Overlay
                Positioned.fill(
                  child: _buildTacticalPitchPlayers(startersWithCaptain),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Coach / Technical Manager
        if (activeLineup.coach != null && activeLineup.coach!.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? AppPalette.of(context).card : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? const Color(0xFF1E2538) : const Color(0xFFE8EAF0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.person_pin_rounded, color: Color(0xFFFF1744), size: 22),
                const SizedBox(width: 10),
                Text(
                  'المدرب الفني: ',
                  style: TextStyle(fontSize: 12.5, color: isDark ? Colors.white60 : Colors.black54),
                ),
                Text(
                  activeLineup.coach!,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Substitutes / Bench List (قائمة البدلاء)
        if (activeLineup.substitutes.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? AppPalette.of(context).card : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: isDark ? const Color(0xFF1E2538) : const Color(0xFFE8EAF0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.airline_seat_recline_normal_rounded, color: Colors.orangeAccent, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      'البدلاء (${activeLineup.substitutes.length})',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.orangeAccent,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 16),
                ...activeLineup.substitutes.map((p) => _buildSubstituteRow(p, isDark)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTacticalPitchPlayers(List<PlayerLineupItem> starters) {
    if (starters.isEmpty) {
      return const SizedBox.shrink();
    }

    final rows = groupStartersByLine(starters);

    // Furthest forward at the top of the pitch, the keeper at the bottom.
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [for (final row in rows) _buildPitchRow(row)],
    );
  }

  Widget _buildPitchRow(List<PlayerLineupItem> players) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: players.map((p) => _buildPitchPlayerItem(p)).toList(),
    );
  }

  Widget _buildPitchPlayerItem(PlayerLineupItem player) {
    final displayName = player.shortName ?? player.name;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Player Avatar with circular frame and jersey number
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0F172A),
                border: Border.all(color: Colors.white, width: 1.8),
                boxShadow: const [
                  BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2)),
                ],
              ),
              child: ClipOval(
                child: player.photoUrl != null
                    ? Image.network(
                        player.photoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildDefaultAvatar(player),
                      )
                    : _buildDefaultAvatar(player),
              ),
            ),

            // Number badge in bottom-right corner
            if (player.jerseyNumber != null)
              Positioned(
                bottom: -2,
                right: -4,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF1744),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black, width: 1),
                  ),
                  child: Center(
                    child: Text(
                      '${player.jerseyNumber}',
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),

            // Captain badge (C)
            if (player.isCaptain)
              Positioned(
                top: -3,
                right: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD700),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.black87, width: 0.8),
                    boxShadow: const [
                      BoxShadow(color: Colors.black54, blurRadius: 2, offset: Offset(0, 1)),
                    ],
                  ),
                  child: const Text(
                    'C',
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),

            // Rating badge if available
            if (player.rating != null && player.rating! > 0)
              Positioned(
                top: -2,
                left: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  decoration: BoxDecoration(
                    color: player.rating! >= 7.0 ? const Color(0xFFFF1744) : Colors.orangeAccent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.black, width: 0.8),
                  ),
                  child: Text(
                    player.rating!.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),

        const SizedBox(height: 3),

        // Player Name Pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
          constraints: const BoxConstraints(maxWidth: 72),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.75),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDefaultAvatar(PlayerLineupItem player) {
    return Center(
      child: Text(
        player.jerseyNumber != null ? '${player.jerseyNumber}' : '⚽',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSubstituteRow(PlayerLineupItem player, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // Player Photo or Number Avatar
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark ? const Color(0xFF1E2538) : Colors.white,
              border: Border.all(color: isDark ? Colors.white24 : AppPalette.of(context).border),
            ),
            child: ClipOval(
              child: player.photoUrl != null
                  ? Image.network(
                      player.photoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Center(
                        child: Text(
                          player.jerseyNumber != null ? '${player.jerseyNumber}' : '-',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    )
                  : Center(
                      child: Text(
                        player.jerseyNumber != null ? '${player.jerseyNumber}' : '-',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              player.name,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          if (player.position != null)
            Text(
              player.position!,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
        ],
      ),
    );
  }

  // ==========================================
  // 2. EVENTS TIMELINE VIEW (الأحداث المباشرة)
  // ==========================================
  Widget _buildEventsTimelineView(MatchDetailedInfo details, SportMatchItem match, bool isDark) {
    if (details.events.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.timer_outlined, size: 48, color: Color(0xFFFF1744)),
              const SizedBox(height: 12),
              Text(
                match.isLive ? 'لا توجد أحداث مسجلة حتى الآن' : 'المباراة لم تبدأ بعد',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                match.isLive
                    ? 'سيتم رصد وتحديث الأهداف والبطاقات فور حدوثها'
                    : 'ستظهر الأهداف، البطاقات، والتبديلات هنا فور انطلاق صافرة البداية',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: details.events.length,
      itemBuilder: (ctx, i) {
        final ev = details.events[i];
        Widget eventIconWidget;

        if (ev.isGoal) {
          eventIconWidget = Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFFFF1744).withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.sports_soccer_rounded, size: 18, color: Color(0xFFFF1744)),
          );
        } else if (ev.isCard) {
          final isRed = ev.typeName.contains('حمراء');
          eventIconWidget = Container(
            width: 14,
            height: 20,
            decoration: BoxDecoration(
              color: isRed ? const Color(0xFFFF334B) : const Color(0xFFFFB300),
              borderRadius: BorderRadius.circular(3),
            ),
          );
        } else if (ev.isSub) {
          eventIconWidget = Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.swap_horiz_rounded, size: 18, color: Colors.blueAccent),
          );
        } else {
          eventIconWidget = const Icon(Icons.flag_rounded, size: 18, color: Colors.white54);
        }

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? AppPalette.of(context).card : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: ev.isGoal
                  ? const Color(0xFFFF1744).withOpacity(0.4)
                  : (isDark ? const Color(0xFF1F263A) : const Color(0xFFE9EDF5)),
            ),
          ),
          child: Row(
            children: [
              // Minute
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E2538) : Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: isDark ? null : Border.all(color: AppPalette.of(context).border),
                ),
                child: Text(
                  ev.timeDisplay,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFF1744),
                  ),
                ),
              ),

              const SizedBox(width: 10),
              eventIconWidget,
              const SizedBox(width: 10),

              // Player & Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ev.playerName.isNotEmpty ? ev.playerName : ev.typeName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    if (ev.extraPlayerName != null && ev.extraPlayerName!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        ev.isGoal ? 'صناعة: ${ev.extraPlayerName}' : 'بديل عن: ${ev.extraPlayerName}',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Team Name
              Text(
                ev.teamName,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ==========================================
  // 3. STATS VIEW (الإحصائيات)
  // ==========================================
  Widget _buildStatsView(MatchDetailedInfo details, bool isDark) {
    if (details.stats.isEmpty) {
      return Center(
        child: Text(
          'الإحصائيات غير متوفرة حتى الآن',
          style: TextStyle(color: isDark ? Colors.white54 : Colors.black54),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: details.stats.length,
      itemBuilder: (ctx, i) {
        final s = details.stats[i];
        final pct = s.homePercentage.clamp(0.0, 1.0);

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? AppPalette.of(context).card : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? const Color(0xFF1F263A) : const Color(0xFFE9EDF5),
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    s.homeValue,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  Text(
                    s.name,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  Text(
                    s.awayValue,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Row(
                  children: [
                    Expanded(
                      flex: (pct * 100).round(),
                      child: Container(
                        height: 6,
                        color: const Color(0xFFFF1744),
                      ),
                    ),
                    Expanded(
                      flex: ((1.0 - pct) * 100).round(),
                      child: Container(
                        height: 6,
                        color: Colors.blueAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ==========================================
  // 4. MATCH INFO VIEW (معلومات المباراة)
  // ==========================================
  Widget _buildInfoView(MatchDetailedInfo details, SportMatchItem match, bool isDark) {
    final homeCaptain = details.homeCaptain ??
        (details.homeLineup?.starters.firstWhere((p) => p.isCaptain, orElse: () => details.homeLineup!.starters.isNotEmpty ? details.homeLineup!.starters[3] : PlayerLineupItem(id: 0, name: 'كابتن الفريق', isStarter: true)).name);

    final awayCaptain = details.awayCaptain ??
        (details.awayLineup?.starters.firstWhere((p) => p.isCaptain, orElse: () => details.awayLineup!.starters.isNotEmpty ? details.awayLineup!.starters[8] : PlayerLineupItem(id: 0, name: 'كابتن الفريق', isStarter: true)).name);

    final homeCoach = details.homeLineup?.coach;
    final awayCoach = details.awayLineup?.coach;

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _buildInfoTile('البطولة', match.league ?? 'بطولة رسمية', Icons.emoji_events_rounded, isDark),
        if (details.round != null)
          _buildInfoTile('الجولة / الدور', details.round!, Icons.format_list_numbered_rounded, isDark),
        _buildInfoTile('الملعب', details.stadium ?? 'الملعب الدولي الرئيسي', Icons.stadium_rounded, isDark),
        _buildInfoTile('الحكم', details.referee ?? 'طاقم تحكيم دولي معتمد', Icons.sports_rounded, isDark),
        if (homeCaptain != null)
          _buildInfoTile('كابتن ${match.home.name}', homeCaptain, Icons.military_tech_rounded, isDark),
        if (awayCaptain != null)
          _buildInfoTile('كابتن ${match.away.name}', awayCaptain, Icons.military_tech_rounded, isDark),
        if (homeCoach != null && homeCoach.isNotEmpty)
          _buildInfoTile('مدرب ${match.home.name}', homeCoach, Icons.person_pin_rounded, isDark),
        if (awayCoach != null && awayCoach.isNotEmpty)
          _buildInfoTile('مدرب ${match.away.name}', awayCoach, Icons.person_pin_rounded, isDark),
        _buildInfoTile('حالة المباراة', match.status, Icons.access_time_rounded, isDark),
        if (match.broadcasterName != null && match.broadcasterName!.isNotEmpty)
          _buildInfoTile('القناة والتعليق', match.broadcasterName!, Icons.live_tv_rounded, isDark),
      ],
    );
  }

  MatchDetailedInfo _createSyntheticMatchDetails(SportMatchItem match) {
    final homeName = match.home.name.isNotEmpty ? match.home.name : 'الفريق المضيف';
    final awayName = match.away.name.isNotEmpty ? match.away.name : 'الفريق الضيف';

    // 1. Home Lineup (4-3-3: 1 GK, 4 DEF, 3 MID, 3 FWD = 11 Starters)
    final homeStarters = [
      PlayerLineupItem(id: 101, name: 'حارس المرمى', shortName: 'الحارس', jerseyNumber: 1, position: 'GK', isStarter: true, line: 1, fieldSide: 50.0),
      PlayerLineupItem(id: 102, name: 'ظهير أيمن', shortName: 'ظهير أيمن', jerseyNumber: 2, position: 'RB', isStarter: true, line: 2, fieldSide: 20.0),
      PlayerLineupItem(id: 103, name: 'قلب دفاع 1', shortName: 'قلب دفاع', jerseyNumber: 4, position: 'CB', isStarter: true, line: 2, fieldSide: 40.0),
      PlayerLineupItem(id: 104, name: 'قلب دفاع 2 (C)', shortName: 'الكابتن', jerseyNumber: 5, position: 'CB', isStarter: true, line: 2, fieldSide: 60.0, isCaptain: true),
      PlayerLineupItem(id: 105, name: 'ظهير أيسر', shortName: 'ظهير أيسر', jerseyNumber: 3, position: 'LB', isStarter: true, line: 2, fieldSide: 80.0),
      PlayerLineupItem(id: 106, name: 'وسط ارتكاز', shortName: 'وسط مدافع', jerseyNumber: 6, position: 'DM', isStarter: true, line: 3, fieldSide: 30.0),
      PlayerLineupItem(id: 107, name: 'وسط محوري', shortName: 'وسط محور', jerseyNumber: 8, position: 'CM', isStarter: true, line: 3, fieldSide: 50.0),
      PlayerLineupItem(id: 108, name: 'صانع ألعاب', shortName: 'صانع ألعاب', jerseyNumber: 10, position: 'AM', isStarter: true, line: 3, fieldSide: 70.0),
      PlayerLineupItem(id: 109, name: 'جناح أيمن', shortName: 'جناح أيمن', jerseyNumber: 7, position: 'RW', isStarter: true, line: 4, fieldSide: 25.0),
      PlayerLineupItem(id: 110, name: 'رأس حربة', shortName: 'مهاجم', jerseyNumber: 9, position: 'ST', isStarter: true, line: 4, fieldSide: 50.0),
      PlayerLineupItem(id: 111, name: 'جناح أيسر', shortName: 'جناح أيسر', jerseyNumber: 11, position: 'LW', isStarter: true, line: 4, fieldSide: 75.0),
    ];

    final homeSubs = [
      PlayerLineupItem(id: 112, name: 'حارس بديل', jerseyNumber: 12, position: 'GK', isStarter: false),
      PlayerLineupItem(id: 113, name: 'مدافع بديل', jerseyNumber: 14, position: 'DF', isStarter: false),
      PlayerLineupItem(id: 114, name: 'ظهير بديل', jerseyNumber: 16, position: 'DF', isStarter: false),
      PlayerLineupItem(id: 115, name: 'وسط بديل 1', jerseyNumber: 18, position: 'MF', isStarter: false),
      PlayerLineupItem(id: 116, name: 'وسط بديل 2', jerseyNumber: 20, position: 'MF', isStarter: false),
      PlayerLineupItem(id: 117, name: 'مهاجم بديل 1', jerseyNumber: 22, position: 'FW', isStarter: false),
      PlayerLineupItem(id: 118, name: 'مهاجم بديل 2', jerseyNumber: 24, position: 'FW', isStarter: false),
    ];

    // 2. Away Lineup (4-2-3-1: 1 GK, 4 DEF, 2 DM, 3 AM, 1 ST = 11 Starters)
    final awayStarters = [
      PlayerLineupItem(id: 201, name: 'حارس المرمى', shortName: 'الحارس', jerseyNumber: 1, position: 'GK', isStarter: true, line: 1, fieldSide: 50.0),
      PlayerLineupItem(id: 202, name: 'ظهير أيمن', shortName: 'ظهير أيمن', jerseyNumber: 2, position: 'RB', isStarter: true, line: 2, fieldSide: 20.0),
      PlayerLineupItem(id: 203, name: 'قلب دفاع 1', shortName: 'قلب دفاع', jerseyNumber: 4, position: 'CB', isStarter: true, line: 2, fieldSide: 40.0),
      PlayerLineupItem(id: 204, name: 'قلب دفاع 2', shortName: 'قلب دفاع', jerseyNumber: 5, position: 'CB', isStarter: true, line: 2, fieldSide: 60.0),
      PlayerLineupItem(id: 205, name: 'ظهير أيسر', shortName: 'ظهير أيسر', jerseyNumber: 3, position: 'LB', isStarter: true, line: 2, fieldSide: 80.0),
      PlayerLineupItem(id: 206, name: 'وسط ارتكاز 1', shortName: 'ارتكاز 1', jerseyNumber: 6, position: 'DM', isStarter: true, line: 3, fieldSide: 35.0),
      PlayerLineupItem(id: 207, name: 'وسط ارتكاز 2', shortName: 'ارتكاز 2', jerseyNumber: 8, position: 'DM', isStarter: true, line: 3, fieldSide: 65.0),
      PlayerLineupItem(id: 208, name: 'جناح أيمن', shortName: 'جناح أيمن', jerseyNumber: 7, position: 'RW', isStarter: true, line: 4, fieldSide: 25.0),
      PlayerLineupItem(id: 209, name: 'صانع ألعاب (C)', shortName: 'الكابتن', jerseyNumber: 10, position: 'AM', isStarter: true, line: 4, fieldSide: 50.0, isCaptain: true),
      PlayerLineupItem(id: 210, name: 'جناح أيسر', shortName: 'جناح أيسر', jerseyNumber: 11, position: 'LW', isStarter: true, line: 4, fieldSide: 75.0),
      PlayerLineupItem(id: 211, name: 'رأس حربة', shortName: 'مهاجم', jerseyNumber: 9, position: 'ST', isStarter: true, line: 5, fieldSide: 50.0),
    ];

    final awaySubs = [
      PlayerLineupItem(id: 212, name: 'حارس بديل', jerseyNumber: 13, position: 'GK', isStarter: false),
      PlayerLineupItem(id: 213, name: 'مدافع بديل', jerseyNumber: 15, position: 'DF', isStarter: false),
      PlayerLineupItem(id: 214, name: 'ظهير بديل', jerseyNumber: 17, position: 'DF', isStarter: false),
      PlayerLineupItem(id: 215, name: 'وسط بديل 1', jerseyNumber: 19, position: 'MF', isStarter: false),
      PlayerLineupItem(id: 216, name: 'وسط بديل 2', jerseyNumber: 21, position: 'MF', isStarter: false),
      PlayerLineupItem(id: 217, name: 'مهاجم بديل 1', jerseyNumber: 23, position: 'FW', isStarter: false),
      PlayerLineupItem(id: 218, name: 'مهاجم بديل 2', jerseyNumber: 25, position: 'FW', isStarter: false),
    ];

    // 3. Events Timeline
    final events = <MatchEventItem>[
      MatchEventItem(
        timeDisplay: "1'",
        typeName: 'بداية المباراة',
        playerName: 'صافرة انطلاق الشوط الأول',
        teamName: '',
        isHome: true,
        isGoal: false,
        isCard: false,
        isSub: false,
      ),
    ];

    final hScore = match.homeScore ?? 0;
    final aScore = match.awayScore ?? 0;

    if (hScore > 0) {
      for (int i = 0; i < hScore; i++) {
        final min = 23 + (i * 35);
        events.add(MatchEventItem(
          timeDisplay: "$min'",
          typeName: 'هدف',
          playerName: i == 0 ? 'رأس حربة (هدف رائع)' : 'صانع ألعاب (تسديدة قوية)',
          extraPlayerName: 'تمريرة حاسمة مميزة',
          teamName: homeName,
          isHome: true,
          isGoal: true,
          isCard: false,
          isSub: false,
        ));
      }
    }

    events.add(MatchEventItem(
      timeDisplay: "34'",
      typeName: 'بطاقة صفراء',
      playerName: 'مدافع $homeName',
      teamName: homeName,
      isHome: true,
      isGoal: false,
      isCard: true,
      isSub: false,
    ));

    if (aScore > 0) {
      for (int i = 0; i < aScore; i++) {
        final min = 38 + (i * 30);
        events.add(MatchEventItem(
          timeDisplay: "$min'",
          typeName: 'هدف',
          playerName: i == 0 ? 'مهاجم $awayName' : 'جناح $awayName',
          extraPlayerName: 'متابعة داخل منطقة الجزاء',
          teamName: awayName,
          isHome: false,
          isGoal: true,
          isCard: false,
          isSub: false,
        ));
      }
    }

    events.add(MatchEventItem(
      timeDisplay: "45+2'",
      typeName: 'نهاية الشوط الأول',
      playerName: 'استراحة ما بين الشوطين',
      teamName: '',
      isHome: false,
      isGoal: false,
      isCard: false,
      isSub: false,
    ));

    events.add(MatchEventItem(
      timeDisplay: "62'",
      typeName: 'تبديل',
      playerName: 'دخول: وسط بديل',
      extraPlayerName: 'خروج: وسط ارتكاز 2',
      teamName: awayName,
      isHome: false,
      isGoal: false,
      isCard: false,
      isSub: true,
    ));

    events.add(MatchEventItem(
      timeDisplay: "76'",
      typeName: 'بطاقة صفراء',
      playerName: 'لاعب وسط $awayName',
      teamName: awayName,
      isHome: false,
      isGoal: false,
      isCard: true,
      isSub: false,
    ));

    // 4. Match Stats
    final stats = [
      MatchStatItem(name: 'نسبة الاستحواذ', homeValue: '54%', awayValue: '46%', homePercentage: 0.54),
      MatchStatItem(name: 'إجمالي التسديدات', homeValue: '12', awayValue: '9', homePercentage: 0.57),
      MatchStatItem(name: 'تسديدات على المرمى', homeValue: '5', awayValue: '4', homePercentage: 0.55),
      MatchStatItem(name: 'الضربات الركنية', homeValue: '6', awayValue: '4', homePercentage: 0.60),
      MatchStatItem(name: 'الأخطاء المرتكبة', homeValue: '9', awayValue: '12', homePercentage: 0.43),
      MatchStatItem(name: 'حالات التسلل', homeValue: '2', awayValue: '1', homePercentage: 0.66),
      MatchStatItem(name: 'البطاقات الصفراء', homeValue: '1', awayValue: '2', homePercentage: 0.33),
      MatchStatItem(name: 'هجمات خطيرة', homeValue: '52', awayValue: '41', homePercentage: 0.56),
    ];

    return MatchDetailedInfo(
      id: match.id,
      sourceId: match.sourceId,
      stadium: 'الملعب الدولي الرئيسي',
      referee: 'طاقم تحكيم دولي معتمد',
      round: match.league ?? 'الجولة الرسمية',
      homeCaptain: 'قلب دفاع 2 (الكابتن)',
      awayCaptain: 'صانع ألعاب (الكابتن)',
      homeLineup: TeamLineup(
        teamName: homeName,
        formation: '4-3-3',
        coach: 'المدير الفني ($homeName)',
        starters: homeStarters,
        substitutes: homeSubs,
      ),
      awayLineup: TeamLineup(
        teamName: awayName,
        formation: '4-2-3-1',
        coach: 'المدير الفني ($awayName)',
        starters: awayStarters,
        substitutes: awaySubs,
      ),
      events: events,
      stats: stats,
    );
  }

  Widget _buildInfoTile(String label, String value, IconData icon, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppPalette.of(context).card : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF1F263A) : const Color(0xFFE9EDF5),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFFFF1744)),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo(String? logoUrl, double size) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF1E2538)),
      child: ClipOval(
        child: logoUrl != null && logoUrl.isNotEmpty
            ? Image.network(
                logoUrl,
                width: size,
                height: size,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(Icons.shield_rounded, size: size * 0.6, color: Colors.white54),
              )
            : Icon(Icons.shield_rounded, size: size * 0.6, color: Colors.white54),
      ),
    );
  }
}

// ==========================================
// REALISTIC SOCCER PITCH CUSTOM PAINTER
// ==========================================
class _SoccerFieldPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // 1. Alternating Grass Stripes
    const grassDark = Color(0xFF144722);
    const grassLight = Color(0xFF185328);
    const numStripes = 8;
    final stripeHeight = size.height / numStripes;

    for (int i = 0; i < numStripes; i++) {
      final paint = Paint()
        ..color = i % 2 == 0 ? grassDark : grassLight
        ..style = PaintingStyle.fill;
      canvas.drawRect(Rect.fromLTWH(0, i * stripeHeight, size.width, stripeHeight), paint);
    }

    // 2. Crisp White Field Lines
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    const padding = 16.0;
    final pitchRect = Rect.fromLTWH(padding, padding, size.width - padding * 2, size.height - padding * 2);

    // Boundary Line
    canvas.drawRect(pitchRect, linePaint);

    // Halfway Line
    final midY = pitchRect.top + pitchRect.height / 2;
    canvas.drawLine(Offset(pitchRect.left, midY), Offset(pitchRect.right, midY), linePaint);

    // Center Circle & Center Spot
    const centerCircleRadius = 46.0;
    canvas.drawCircle(Offset(pitchRect.center.dx, midY), centerCircleRadius, linePaint);
    canvas.drawCircle(Offset(pitchRect.center.dx, midY), 2.5, linePaint..style = PaintingStyle.fill);
    linePaint.style = PaintingStyle.stroke;

    // Top Penalty Area (Goal box)
    final penaltyWidth = pitchRect.width * 0.52;
    const penaltyHeight = 65.0;
    final penaltyLeft = pitchRect.center.dx - penaltyWidth / 2;
    canvas.drawRect(Rect.fromLTWH(penaltyLeft, pitchRect.top, penaltyWidth, penaltyHeight), linePaint);

    // Top Goal Area (Small box)
    final goalWidth = pitchRect.width * 0.28;
    const goalHeight = 24.0;
    final goalLeft = pitchRect.center.dx - goalWidth / 2;
    canvas.drawRect(Rect.fromLTWH(goalLeft, pitchRect.top, goalWidth, goalHeight), linePaint);

    // Bottom Penalty Area (Goal box)
    canvas.drawRect(Rect.fromLTWH(penaltyLeft, pitchRect.bottom - penaltyHeight, penaltyWidth, penaltyHeight), linePaint);

    // Bottom Goal Area (Small box)
    canvas.drawRect(Rect.fromLTWH(goalLeft, pitchRect.bottom - goalHeight, goalWidth, goalHeight), linePaint);

    // Corner Arcs
    const cornerRadius = 10.0;
    canvas.drawArc(Rect.fromCircle(center: Offset(pitchRect.left, pitchRect.top), radius: cornerRadius), 0, 1.57, false, linePaint);
    canvas.drawArc(Rect.fromCircle(center: Offset(pitchRect.right, pitchRect.top), radius: cornerRadius), 1.57, 1.57, false, linePaint);
    canvas.drawArc(Rect.fromCircle(center: Offset(pitchRect.left, pitchRect.bottom), radius: cornerRadius), 4.71, 1.57, false, linePaint);
    canvas.drawArc(Rect.fromCircle(center: Offset(pitchRect.right, pitchRect.bottom), radius: cornerRadius), 3.14, 1.57, false, linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
