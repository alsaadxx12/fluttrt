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
import '../../data/match_merge.dart';
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
  String? _streamErrorMessage;
  bool _isLandscape = false;
  bool _controlsVisible = true;
  bool _isPlaying = true;
  Timer? _hideControlsTimer;
  int _streamLoadToken = 0;

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

  /// True while the button is forcing an orientation, so the device's own
  /// reading is ignored until it has caught up.
  bool _forcing = false;

  /// Follows the device: landscape means fullscreen, upright means not.
  /// Only the view state and the system bars change here; the orientation
  /// itself is left to the phone.
  void _syncToDevice(bool landscape) {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) return;
    if (_isLandscape == landscape || !mounted) return;
    setState(() => _isLandscape = landscape);
    SystemChrome.setEnabledSystemUIMode(
      landscape ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  /// Some phones bring the navigation bar back on their own: after the
  /// rotation into landscape settles, or when the page's own fullscreen view
  /// closes. immersiveSticky is asked for once and then quietly undone, which
  /// is why a side bar appears on other devices but not here. So every time
  /// the window changes while fullscreen, ask for the bars to be hidden again.
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (_isLandscape && mounted) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  /// Coming back from the background in fullscreen leaves the bars showing
  /// too.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && _isLandscape && mounted) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideControlsTimer?.cancel();
    _winFullscreenSub?.cancel();
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
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  void _setFullscreen(bool fullscreen) async {
    final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    _forcing = true;
    setState(() => _isLandscape = fullscreen);
    if (isDesktop) {
      _forcing = false;
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
      SystemChrome.setPreferredOrientations(
        fullscreen
            ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
            : [DeviceOrientation.portraitUp],
      );
      Future.delayed(const Duration(milliseconds: 700), () {
        if (!mounted) return;
        _forcing = false;
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      });
    }
  }

  void _exitFullscreen() => _setFullscreen(false);

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    if (!_isPlaying) return;
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
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
          final u = request.url.toLowerCase();
          if (u.contains('play.google.com') ||
              u.contains('market:') ||
              u.contains('intent:') ||
              u.contains('1xbet') ||
              u.contains('betting') ||
              u.contains('whatsapp') ||
              u.contains('t.me') ||
              u.contains('telegram.me') ||
              u.contains('.apk') ||
              (!u.startsWith('http://') && !u.startsWith('https://'))) {
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
    })();
    """;
    controller.runJavaScript(js).catchError((_) {});
  }

  void _injectCleanup(WebViewController controller) {
    controller.runJavaScript(_adBlockAndCleanupJs).catchError((_) {});
    for (final ms in [500, 1200, 2500, 4000, 6500]) {
      Future.delayed(Duration(milliseconds: ms), () {
        if (mounted && _webController != null) {
          _webController?.runJavaScript(_adBlockAndCleanupJs).catchError((_) {});
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
    final sportsService = ref.read(sportsServiceProvider);

    // 1. Source 1 (The App's Original Source): streamId resolver
    int? streamId = match.streamId;
    if (streamId == null && (widget.directUrl == null || widget.directUrl!.isEmpty)) {
      try {
        final liveMatches = await sportsService.fetchLiveMatches();
        final found = MatchMerge.findSame(match, liveMatches);
        if (found != null && found.streamId != null) {
          streamId = found.streamId;
        }
      } catch (_) {}
    }

    if (streamId != null && streamId > 0) {
      try {
        final streamInfo = await sportsService.fetchStream(streamId);
        if (streamInfo != null && streamInfo.ok && streamInfo.url.isNotEmpty) {
          final isWeb = streamInfo.play == 'webview' ||
              (!streamInfo.url.contains('.m3u8') && !streamInfo.url.contains('albaplayer'));
          channelList.add(
            PlayerChannelItem(
              id: 'source_orig_$streamId',
              name: 'البث المباشر (المصدر 1)',
              isAppSource: true,
              streamUrl: streamInfo.url,
              subtitle: 'بث عالي الدقة HD',
              headers: streamInfo.headers,
              isWebStream: isWeb,
            ),
          );
        }
      } catch (e) {
        debugPrint('[SPORTS_PLAYER] Error loading Source 1: $e');
      }
    }

    // 2. Source 2 (The App's New Source): directUrl / broadcasters from Cinamana / Koralive
    final direct = widget.directUrl ?? match.directUrl;
    if (direct != null && direct.isNotEmpty && !channelList.any((c) => c.streamUrl == direct)) {
      final name = (match.broadcasterName != null &&
              match.broadcasterName!.isNotEmpty &&
              match.broadcasterName != 'غير معروف')
          ? match.broadcasterName!
          : (channelList.isNotEmpty ? 'البث المباشر (المصدر 2)' : 'البث المباشر HD');
      channelList.add(
        PlayerChannelItem(
          id: 'source_new_direct',
          name: name,
          streamUrl: direct,
          subtitle: 'بث مباشر سريع HD',
          isWebStream: false,
        ),
      );
    }

    if (match.broadcasters.isNotEmpty) {
      for (int i = 0; i < match.broadcasters.length; i++) {
        final bc = match.broadcasters[i];
        final stream = bc.streamUrl;
        if (stream != null && stream.isNotEmpty && !channelList.any((c) => c.streamUrl == stream)) {
          channelList.add(
            PlayerChannelItem(
              id: 'source_new_bc_${bc.id}_$i',
              name: bc.name.isNotEmpty ? bc.name : 'قناة بديلة',
              logo: bc.image.isNotEmpty ? bc.image : null,
              streamUrl: stream,
              subtitle: 'بث ${bc.name}',
              isWebStream: false,
            ),
          );
        }
      }
    }

    if (channelList.isEmpty) {
      channelList.add(
        PlayerChannelItem(
          id: 'ch_empty',
          name: match.displayBroadcaster.isNotEmpty ? match.displayBroadcaster : 'البث المباشر',
          streamUrl: direct,
          subtitle: 'بث مباشر',
          isWebStream: false,
        ),
      );
    }

    // On a desktop a web-based stream cannot render, so start on the first
    // channel that can actually play here (a direct one), falling back to the
    // first channel when the match has only web streams.
    final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final initial = isDesktop
        ? channelList.firstWhere((c) => !c.isWebStream, orElse: () => channelList.first)
        : channelList.first;
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
    final token = ++_streamLoadToken;
    final oldController = _videoController;
    setState(() {
      _activeChannelId = channel.id;
      _isLoadingStream = true;
      _isStreamBuffering = false;
      _isPlaying = true;
      _streamErrorMessage = null;
      _videoController = null;
    });
    await oldController?.dispose();

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
    final headers = (resolved != null && resolved.headers.isNotEmpty)
        ? resolved.headers
        : const {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 14; SmartTV; SM-A266B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Referer': 'https://pl.matchlivehd.com/',
          };

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
          await webCtrl.loadRequest(Uri.parse(streamUrl), headers: headers);
          if (mounted && token == _streamLoadToken) {
            setState(() {
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
          _isLoadingStream = false;
          _isStreamBuffering = false;
          _isPlaying = true;
          _streamErrorMessage = null;
        });
        _scheduleHideControls();
      } catch (e) {
        debugPrint('[DESKTOP_SPORTS_PLAYER] playback failed: $e');
        // Fallback to WebView on Desktop if native player cannot open
        if (Platform.isWindows) {
          try {
            await _loadWindowsWebview(rawUrl);
            if (mounted && token == _streamLoadToken) {
              setState(() {
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

      setState(() {
        _videoController = controller;
        _isLoadingStream = false;
        _isStreamBuffering = false;
        _isPlaying = true;
      });
      _scheduleHideControls();
    } catch (e) {
      await controller.dispose();
      if (!mounted || token != _streamLoadToken) return;

      // Auto-renew token if initial playback failed
      if (!forceRefresh) {
        debugPrint('[SPORTS_PLAYER] Playback error, renewing token dynamically for ${channel.name}...');
        return _loadChannelStream(channel, forceRefresh: true);
      }

      // Fallback to Web Player if native player cannot load
      try {
        debugPrint('[SPORTS_PLAYER] Fallback to web controller for ${channel.name}');
        final webCtrl = _ensureWebController();
        await webCtrl.loadRequest(Uri.parse(rawUrl), headers: headers);
        setState(() {
          _isLoadingStream = false;
          _isStreamBuffering = false;
          _streamErrorMessage = null;
        });
      } catch (_) {
        setState(() {
          _isLoadingStream = false;
          _isStreamBuffering = false;
          _streamErrorMessage = 'تعذّر تشغيل البث المباشر';
        });
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
        setState(() {
          _isStreamBuffering = buffering;
          _isPlaying = playing;
        });
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

    final playerWidget = ColoredBox(
      color: Colors.black,
      child: Stack(
        alignment: Alignment.center,
        fit: StackFit.expand,
        children: [
          if (activeCh.isWebStream)
            (Platform.isWindows && _winWebController != null && _winWebInitialized)
                ? win_web.Webview(_winWebController!)
                : (_webController != null
                    ? WebViewWidget(controller: _webController!)
                    : const SizedBox.shrink())
          else if (isDesktop && _desktopVideoController != null)
            Center(
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Video(
                  controller: _desktopVideoController!,
                  controls: NoVideoControls,
                ),
              ),
            )
          else if (v != null && v.value.isInitialized)
            Center(
              child: AspectRatio(
                aspectRatio: v.value.aspectRatio > 0 ? v.value.aspectRatio : 16 / 9,
                child: VideoPlayer(v),
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
            _buildControlsOverlay(fullscreen, isWebStream: activeCh.isWebStream),
          if (_streamErrorMessage != null)
            _buildStreamErrorOverlay(),
        ],
      ),
    );

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
        behavior: HitTestBehavior.opaque,
        child: playerWidget,
      ),
    );
  }

  Widget _buildControlsOverlay(bool fullscreen, {required bool isWebStream}) {
    final activeCh = _channels.firstWhere(
      (c) => c.id == _activeChannelId,
      orElse: () => _channels.firstOrNull ?? const PlayerChannelItem(id: '', name: ''),
    );
    final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    // Top Header Bar
    final topBar = Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.8),
              Colors.black.withOpacity(0.25),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Row(
            children: [
              IconButton(
                onPressed: () {
                  if (fullscreen && isDesktop) {
                    _setFullscreen(false);
                  } else {
                    Navigator.of(context).maybePop();
                  }
                },
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 24),
                tooltip: 'رجوع',
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF1744),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.fiber_manual_record_rounded, color: Colors.white, size: 9),
                    SizedBox(width: 4),
                    Text(
                      'مباشر',
                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  activeCh.name.isNotEmpty ? activeCh.name : '${widget.match.home.name} × ${widget.match.away.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
              if (_channels.length > 1) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: _showChannelSelectionSheet,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white38, width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          'تغيير المصدر (${_channels.length})',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    // If it's a web stream, show ONLY the slim top header bar.
    // Do NOT add a center pause button or bottom bar so the match player's
    // native HTML5 controls remain unobstructed and fully clickable!
    if (isWebStream) {
      return topBar;
    }

    return IgnorePointer(
      ignoring: !_controlsVisible,
      child: AnimatedOpacity(
        opacity: _controlsVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 250),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Click outside buttons toggles controls without dimming the screen
            Positioned.fill(
              child: GestureDetector(
                onTap: _toggleControls,
                behavior: HitTestBehavior.translucent,
                child: const SizedBox.expand(),
              ),
            ),

            topBar,

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
                padding: const EdgeInsets.fromLTRB(10, 26, 10, 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.8),
                      Colors.black.withOpacity(0.35),
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
                      const Spacer(),
                      IconButton(
                        onPressed: () => _setFullscreen(!fullscreen),
                        icon: Icon(
                          fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                        tooltip: fullscreen ? 'إلغاء ملء الشاشة' : 'ملء الشاشة',
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
                onPressed: () => Navigator.of(context).maybePop(),
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
                        onPressed: () => Navigator.of(context).maybePop(),
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
              color: isDark ? const Color(0xFF1F263A) : const Color(0xFFE5E7EB),
            ),
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
                        : (isDark ? const Color(0xFF1B2234) : const Color(0xFFF3F4F6)),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? const Color(0xFFFF1744) : Colors.transparent,
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

  Widget _buildChannelSwitcherBar(bool isDark) {
    if (_channels.isEmpty && !_loadingChannels) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF101420) : const Color(0xFFF0F3F8),
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF1D2436) : AppPalette.of(context).border,
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF1744).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.live_tv_rounded,
                    color: Color(0xFFFF1744),
                    size: 15,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'القنوات الناقلة للمباراة (${_channels.length})',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : const Color(0xFF111827),
                  ),
                ),
                const Spacer(),
                if (_loadingChannels)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF1744)),
                  )
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 60,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: _channels.length,
              itemBuilder: (ctx, i) {
                final ch = _channels[i];
                final isSelected = ch.id == _activeChannelId;

                return MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _switchChannel(ch),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 175,
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFFF1744).withOpacity(isDark ? 0.22 : 0.12)
                            : (isDark ? AppPalette.of(context).card : Colors.white),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFFFF1744)
                              : (isDark ? const Color(0xFF1F263A) : const Color(0xFFE2E8F0)),
                          width: isSelected ? 2.0 : 1.0,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: const Color(0xFFFF1744).withOpacity(0.25),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                )
                              ]
                            : null,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF0F1420) : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.all(4),
                            child: _channelMark(ch, isSelected, isDark),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        ch.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                          color: isSelected
                                              ? const Color(0xFFFF1744)
                                              : (isDark ? Colors.white : const Color(0xFF111827)),
                                        ),
                                      ),
                                    ),
                                    if (isSelected)
                                      Container(
                                        width: 6,
                                        height: 6,
                                        margin: const EdgeInsets.only(right: 4),
                                        decoration: const BoxDecoration(
                                          color: Color(0xFFFF1744),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  ch.subtitle ?? (ch.isWebStream ? 'بث الويب' : 'بث مباشر HD'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isDark ? Colors.white54 : Colors.black45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final match = widget.match;
    final matchDetailsAsync = ref.watch(
      matchDetailsProvider((matchId: match.id, sourceId: match.sourceId)),
    );

    // Turning the phone is what drives fullscreen ONLY on mobile devices.
    final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final deviceLandscape = !isDesktop && MediaQuery.of(context).orientation == Orientation.landscape;
    if (!_forcing && !isDesktop && deviceLandscape != _isLandscape) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncToDevice(deviceLandscape));
    }

    final mainScaffold = Scaffold(
      backgroundColor: _isLandscape
          ? Colors.black
          : (isDark ? AppPalette.of(context).bg : AppPalette.of(context).bg),
      body: SafeArea(
        top: !_isLandscape,
        bottom: false,
        child: _buildBody(context, isDark, match, matchDetailsAsync),
      ),
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_isLandscape && !isDesktop) {
            _exitFullscreen();
          } else if (_isLandscape && isDesktop) {
            _setFullscreen(false);
          } else {
            Navigator.of(context).maybePop();
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: PopScope(
          canPop: isDesktop || !_isLandscape,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (_isLandscape && !isDesktop) {
              _exitFullscreen();
            } else if (_isLandscape && isDesktop) {
              _setFullscreen(false);
            } else {
              Navigator.of(context).maybePop();
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
    if (_isLandscape) {
      return _buildPlayerArea(fullscreen: true);
    }

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

        // Channel Switcher Strip directly below Video Player
        _buildChannelSwitcherBar(isDark),

          // 2. Score & Teams Mini Strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                        : (isDark ? const Color(0xFF1E2538) : const Color(0xFFEEF2F8)),
                    borderRadius: BorderRadius.circular(8),
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
              error: (err, _) => Center(
                child: Text(
                  'التفاصيل غير متوفرة حالياً لهذه المباراة',
                  style: TextStyle(color: isDark ? Colors.white54 : Colors.black54),
                ),
              ),
              data: (details) {
                if (details == null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.sports_soccer_rounded, size: 48, color: isDark ? Colors.white24 : Colors.black26),
                          const SizedBox(height: 12),
                          Text(
                            'التفاصيل والتشكيلة لم تُنشر بعد',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'يتم الإعلان عن التشكيلة الرسمية قبل موعد المباراة بساعة',
                            textAlign: TextAlign.center,
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
              },
            ),
          ),
        ],
      );
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

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // Team Selector Switcher
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isDark ? AppPalette.of(context).card : const Color(0xFFECEFF5),
            borderRadius: BorderRadius.circular(12),
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
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
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
                  child: _buildTacticalPitchPlayers(activeLineup.starters),
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
              color: isDark ? const Color(0xFF1E2538) : const Color(0xFFEEF1F6),
              border: Border.all(color: isDark ? Colors.white24 : Colors.black12),
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
                  color: isDark ? const Color(0xFF1E2538) : const Color(0xFFEEF1F6),
                  borderRadius: BorderRadius.circular(6),
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
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _buildInfoTile('البطولة', match.league ?? 'غير محدد', Icons.emoji_events_rounded, isDark),
        if (details.round != null)
          _buildInfoTile('الجولة / الدور', details.round!, Icons.format_list_numbered_rounded, isDark),
        if (details.stadium != null)
          _buildInfoTile('الملعب', details.stadium!, Icons.stadium_rounded, isDark),
        if (details.referee != null)
          _buildInfoTile('الحكم', details.referee!, Icons.sports_rounded, isDark),
        _buildInfoTile('حالة المباراة', match.status, Icons.access_time_rounded, isDark),
      ],
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
