import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_downloader/presentation/widgets/app_search_field.dart';

import '../../casting/controllers/cast_controller.dart';
import '../../casting/services/cast_media_source.dart';
import '../../casting/services/cast_service.dart';
import '../../casting/widgets/cast_device_sheet.dart';
import '../../sports/presentation/providers/alkass_provider.dart';
import '../data/shahid_models.dart';
import 'shahid_providers.dart';

/// Native live-channel player. Plays the channel's HLS stream directly
/// (MediaKit on desktop, VideoPlayer on mobile).
class ShahidPlayerScreen extends ConsumerStatefulWidget {
  final ShahidItem channel;

  /// Other channels shown under the player for one-tap switching.
  final List<ShahidItem> channels;

  const ShahidPlayerScreen({
    super.key,
    required this.channel,
    this.channels = const [],
  });

  @override
  ConsumerState<ShahidPlayerScreen> createState() => _ShahidPlayerScreenState();
}

class _ShahidPlayerScreenState extends ConsumerState<ShahidPlayerScreen> {
  late ShahidItem _current;
  VideoPlayerController? _video;
  Player? _desktopPlayer;
  VideoController? _desktopVideoController;
  final List<StreamSubscription> _desktopSubs = [];
  bool _loading = true;
  String? _error;
  bool _controlsVisible = true;
  bool _fullscreen = false;
  Timer? _hideControls;
  int _openToken = 0;
  final _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _current = widget.channel;
    _open(_current);
  }

  /// The channel's address right now: fetched afresh each time (playlists
  /// can rotate, and an Alkass address carries a token that runs out), with
  /// the one checked when the list loaded as the fallback.
  Future<String?> _freshUrl(ShahidItem channel) async {
    final fromShahid = channel.pageUrl.contains('shahid.mbc.net');
    final fromAlkass = channel.pageUrl.contains('alkass.net');
    return (fromShahid
            ? await ref.read(shahidServiceProvider).fetchStreamUrl(channel.id)
            : fromAlkass
                ? await ref.read(alkassServiceProvider).streamFor(channel.id)
                : null) ??
        channel.streamUrl;
  }

  /// Sends the channel to the television, the way a match is sent: pairs
  /// a set first when none is, then hands it a fresh address. The phone's
  /// own player is paused - on a live channel it would be a second full
  /// download for nothing.
  Future<void> _castCurrent() async {
    final cast = ref.read(castControllerProvider);
    if (!cast.isConnected) {
      await showCastDeviceSheet(context);
      if (!mounted || !ref.read(castControllerProvider).isConnected) return;
    }
    final channel = _current;
    final url = await _freshUrl(channel);
    if (!mounted) return;
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('البث غير متاح لهذه القناة الآن')));
      return;
    }
    try {
      await ref.read(castControllerProvider.notifier).cast(
            CastMediaSource.forLive(
              id: 'channel_${channel.id}',
              title: channel.title,
              streamUrl: url,
              posterUrl: channel.logoUrl(480) ?? '',
            ),
          );
      await _video?.pause();
      await _desktopPlayer?.pause();
    } on CastException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _open(ShahidItem channel) async {
    final token = ++_openToken;
    final old = _video;
    setState(() {
      _current = channel;
      _video = null;
      _loading = true;
      _error = null;
    });
    await old?.dispose();

    final url = await _freshUrl(channel);
    if (!mounted || token != _openToken) return;
    if (url == null) {
      setState(() {
        _loading = false;
        _error = 'البث غير متاح لهذه القناة الآن';
      });
      return;
    }

    final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    if (isDesktop) {
      _desktopPlayer?.stop();
      try {
        _desktopPlayer ??= Player(
          configuration: const PlayerConfiguration(bufferSize: 32 * 1024 * 1024),
        );
        _desktopVideoController ??= VideoController(
          _desktopPlayer!,
          configuration: const VideoControllerConfiguration(enableHardwareAcceleration: true),
        );
        for (final s in _desktopSubs) {
          s.cancel();
        }
        _desktopSubs.clear();

        _desktopSubs.add(_desktopPlayer!.stream.buffering.listen((buffering) {
          if (mounted && token == _openToken) {
            setState(() {});
          }
        }));
        _desktopSubs.add(_desktopPlayer!.stream.error.listen((err) {
          if (mounted && token == _openToken) {
            setState(() => _error = 'انقطع البث');
          }
        }));

        await _desktopPlayer!.open(
          Media(
            url,
            httpHeaders: const {
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
            },
          ),
          play: true,
        );
        if (!mounted || token != _openToken) return;
        setState(() {
          _loading = false;
        });
        _scheduleHide();
      } catch (e) {
        if (!mounted || token != _openToken) return;
        setState(() {
          _loading = false;
          _error = 'تعذّر تشغيل البث';
        });
      }
      return;
    }

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(url),
      formatHint: VideoFormat.hls,
      httpHeaders: const {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
      },
    );
    try {
      await controller.initialize();
      if (!mounted || token != _openToken) {
        await controller.dispose();
        return;
      }
      controller.addListener(_onVideoEvent);
      await controller.play();
      setState(() {
        _video = controller;
        _loading = false;
      });
      _scheduleHide();
    } catch (e) {
      await controller.dispose();
      if (!mounted || token != _openToken) return;
      setState(() {
        _loading = false;
        _error = 'تعذّر تشغيل البث';
      });
    }
  }

  void _onVideoEvent() {
    final v = _video;
    if (v == null || !mounted) return;
    if (v.value.hasError && _error == null) {
      setState(() => _error = 'انقطع البث');
    } else {
      setState(() {}); // buffering / play state
    }
  }

  void _scheduleHide() {
    _hideControls?.cancel();
    _hideControls = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  void _setFullscreen(bool on) {
    setState(() => _fullscreen = on);
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      if (on) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _hideControls?.cancel();
    _video?.removeListener(_onVideoEvent);
    _video?.dispose();
    for (final s in _desktopSubs) {
      s.cancel();
    }
    _desktopPlayer?.stop();
    _desktopPlayer?.dispose();
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  // ---------------------------------------------------------------- UI

  Widget _playerArea() {
    final v = _video;
    final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final buffering =
        isDesktop ? (_loading || (_desktopPlayer?.state.buffering ?? false)) : (v != null && v.value.isBuffering);

    return MouseRegion(
      onHover: (_) {
        if (!_controlsVisible) {
          setState(() => _controlsVisible = true);
        }
        _scheduleHide();
      },
      child: GestureDetector(
        onTap: _toggleControls,
        child: ColoredBox(
          color: Colors.black,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (isDesktop && _desktopVideoController != null)
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
                    aspectRatio: v.value.aspectRatio == 0 ? 16 / 9 : v.value.aspectRatio,
                    child: VideoPlayer(v),
                  ),
                ),
              if (_loading || (buffering && _error == null)) const CircularProgressIndicator(color: Color(0xFFE50914)),
              if (_error != null)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off_rounded, color: Colors.white54, size: 34),
                    const SizedBox(height: 8),
                    Text(_error!, style: const TextStyle(color: Colors.white, fontSize: 13)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _open(_current),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE50914),
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('إعادة المحاولة'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).maybePop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white38),
                          ),
                          icon: const Icon(Icons.arrow_back_rounded, size: 18),
                          label: const Text('رجوع'),
                        ),
                      ],
                    ),
                  ],
                ),
              if (_controlsVisible && (_video != null || _desktopVideoController != null) && _error == null) ...[
                // Back button on fullscreen
                if (_fullscreen)
                  PositionedDirectional(
                    top: 10,
                    start: 10,
                    child: SafeArea(
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 24),
                        onPressed: () => _setFullscreen(false),
                        tooltip: 'رجوع',
                      ),
                    ),
                  ),
                // LIVE
                PositionedDirectional(
                  top: 10,
                  end: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE50914),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'LIVE',
                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                // fullscreen toggle
                PositionedDirectional(
                  bottom: 8,
                  end: 8,
                  child: IconButton(
                    onPressed: () => _setFullscreen(!_fullscreen),
                    icon: Icon(
                      _fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                    tooltip: _fullscreen ? 'إلغاء ملء الشاشة' : 'ملء الشاشة',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp('[أإآ]'), 'ا').replaceAll('ة', 'ه').replaceAll('ى', 'ي').trim();

  /// Two big tiles per row. Shahid's own 16:9 tiles fill the card; other
  /// channels' logos are shown whole. Channels sharing a logo get their name.
  Widget _otherChannelsGrid(List<ShahidItem> others) {
    final q = _norm(_query);
    final shown = q.isEmpty ? others : others.where((c) => _norm(c.title).contains(q)).toList();
    if (shown.isEmpty) {
      return const Center(
        child: Text('لا توجد قناة بهذا الاسم', style: TextStyle(color: Colors.black45, fontSize: 13.5)),
      );
    }
    final logoCount = <String, int>{};
    for (final c in widget.channels) {
      final l = c.logoTemplate;
      if (l != null) logoCount[l] = (logoCount[l] ?? 0) + 1;
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 16 / 9,
      ),
      itemCount: shown.length,
      itemBuilder: (_, i) {
        final c = shown[i];
        final isShahidTile = c.pageUrl.contains('shahid.mbc.net');
        final l = c.logoUrl(480);
        final caption = (logoCount[c.logoTemplate] ?? 0) > 1 ? c.title : null;
        final image = l == null
            ? const Center(child: Icon(Icons.live_tv_rounded, color: Colors.white24))
            : CachedNetworkImage(
                imageUrl: l,
                fit: isShahidTile ? BoxFit.cover : BoxFit.contain,
                // Same decode size as the channels page, so it comes from memory.
                memCacheWidth: 480,
                fadeInDuration: const Duration(milliseconds: 100),
                placeholder: (_, __) => const SizedBox.shrink(),
                errorWidget: (_, __, ___) => const Icon(Icons.live_tv_rounded, color: Colors.white24),
              );
        return InkWell(
          onTap: () => _open(c),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF121724),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: c.id == _current.id ? const Color(0xFFE50914) : Colors.white.withOpacity(0.08),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (isShahidTile)
                  image
                else
                  Padding(padding: EdgeInsets.fromLTRB(16, 14, 16, caption == null ? 14 : 28), child: image),
                if (caption != null)
                  PositionedDirectional(
                    start: 8,
                    end: 8,
                    bottom: 7,
                    child: Text(
                      caption,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (_fullscreen) {
      content = PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _setFullscreen(false);
        },
        child: Scaffold(backgroundColor: Colors.black, body: _playerArea()),
      );
    } else {
      final dpr = MediaQuery.of(context).devicePixelRatio;
      final logo = _current.logoUrl((160 * dpr).round());
      final others = widget.channels.where((c) => c.id != _current.id).toList();

      content = Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              // top bar: back + channel logo
              SizedBox(
                height: 54,
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.black87),
                      onPressed: () => Navigator.of(context).maybePop(),
                      tooltip: 'رجوع',
                    ),
                    if (logo != null)
                      SizedBox(
                        height: 30,
                        width: 110,
                        child: CachedNetworkImage(
                          imageUrl: logo,
                          fit: BoxFit.contain,
                          // RTL page: the logo sits at the start, i.e. the right.
                          alignment: Alignment.centerRight,
                        ),
                      ),
                    const Spacer(),
                    // To the television, as a match goes; coloured once a
                    // set is on.
                    Consumer(
                      builder: (context, ref, _) {
                        final casting = ref.watch(isCastingProvider);
                        return IconButton(
                          onPressed: _castCurrent,
                          tooltip: 'البث على التلفاز',
                          icon: Icon(
                            casting ? Icons.cast_connected_rounded : Icons.cast_rounded,
                            color: casting ? const Color(0xFFE50914) : Colors.black87,
                            size: 22,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              AspectRatio(aspectRatio: 16 / 9, child: _playerArea()),
              if (others.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Row(
                    children: [
                      const Text(
                        'قنوات أخرى',
                        style: TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(width: 12),
                      // Search the channels by name - the shared flat pill.
                      Expanded(
                        child: AppSearchField(
                          controller: _search,
                          hintText: 'ابحث عن قناة',
                          onChanged: (v) => setState(() => _query = v),
                          onClear: () => setState(() => _query = ''),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: _otherChannelsGrid(others)),
              ],
            ],
          ),
        ),
      );
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_fullscreen) {
            _setFullscreen(false);
          } else {
            Navigator.of(context).maybePop();
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: content,
      ),
    );
  }
}
