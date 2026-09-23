import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../cinemana/data/cinemana_subtitles.dart';
import '../../cinemana/data/models/cinemana_models.dart';
import '../../cinemana/presentation/widgets/cinemana_player_view.dart';
import '../data/viu_models.dart';
import 'viu_providers.dart';
import '../../../core/video/desktop_video.dart';
import '../../../core/constants/app_palette.dart';
import 'package:window_manager/window_manager.dart';

/// A Viu series (or film): the player on top, its free episodes below.
/// Plays in the app's own native player - no web page, no ads.
class ViuWatchScreen extends ConsumerStatefulWidget {
  final ViuShow show;

  const ViuWatchScreen({super.key, required this.show});

  @override
  ConsumerState<ViuWatchScreen> createState() => _ViuWatchScreenState();
}

class _ViuWatchScreenState extends ConsumerState<ViuWatchScreen> {
  static const _ua =
      'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  /// The version being watched (original / dubbed) of [ViuWatchScreen.show].
  late ViuShow _show;
  static const _prefDubbed = 'viu_prefer_dubbed';

  List<ViuEpisode>? _episodes;
  bool _episodesFailed = false;
  ViuEpisode? _current;

  VideoPlayerController? _video;
  bool _preparing = false;
  String? _playerError;
  int _episodeToken = 0;
  int _videoToken = 0;
  Duration _lastPosition = Duration.zero;
  bool _wakeLocked = false;
  bool _advancing = false;

  List<CinemanaStreamFile> _streams = const [];
  CinemanaStreamFile? _selected;
  List<SubtitleCue>? _cues;
  SubtitleSettings _subs = const SubtitleSettings();
  Timer? _saveSubsTimer;

  bool _isFullscreen = false;
  final _playerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    SubtitleSettings.load().then((s) {
      if (mounted) setState(() => _subs = s);
    });
    _show = widget.show;
    _pickVersionThenLoad();
    _allowRotation();
  }

  /// Several versions: start with the kind (dubbed or not) chosen last time.
  Future<void> _pickVersionThenLoad() async {
    final versions = widget.show.versions;
    if (versions.length > 1) {
      var preferDubbed = true;
      try {
        preferDubbed =
            (await SharedPreferences.getInstance()).getBool(_prefDubbed) ??
                true;
      } catch (_) {}
      final pick = versions.firstWhere((v) => v.isDubbed == preferDubbed,
          orElse: () => versions.first);
      if (mounted) setState(() => _show = pick);
    }
    await _loadEpisodes();
  }

  Future<void> _loadEpisodes() async {
    final seriesId = _show.seriesId;
    setState(() => _episodesFailed = false);
    try {
      final eps =
          await ref.read(viuServiceProvider).fetchFreeEpisodes(seriesId);
      if (mounted && seriesId == _show.seriesId)
        setState(() => _episodes = eps);
    } catch (_) {
      if (mounted && seriesId == _show.seriesId)
        setState(() => _episodesFailed = true);
    }
  }

  /// Switch original <-> dubbed; if an episode was playing, carry on with
  /// the same episode number in the other version.
  Future<void> _switchVersion(ViuShow version) async {
    if (version.seriesId == _show.seriesId) return;
    final playingNumber = _current?.number;
    _episodeToken++;
    _videoToken++;
    _closeVideo();
    setState(() {
      _show = version;
      _episodes = null;
      _current = null;
      _streams = const [];
      _cues = null;
      _playerError = null;
      _preparing = false;
    });
    if (widget.show.hasDubbedVersion && widget.show.hasOriginalVersion) {
      SharedPreferences.getInstance()
          .then((p) => p.setBool(_prefDubbed, version.isDubbed))
          .catchError((_) => false);
    }
    await _loadEpisodes();
    final eps = _episodes;
    if (!mounted || playingNumber == null || eps == null || eps.isEmpty) return;
    _playEpisode(eps.firstWhere((e) => e.number == playingNumber,
        orElse: () => eps.first));
  }

  @override
  void dispose() {
    _saveSubsTimer?.cancel();
    _episodeToken++;
    _videoToken++;
    _closeVideo();
    WakelockPlus.disable().catchError((_) {});
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ------------------------------------------------------------ playback

  static int _px(CinemanaStreamFile s) =>
      int.tryParse(s.resolution.replaceAll(RegExp(r'\D'), '')) ?? 0;

  Future<void> _playEpisode(ViuEpisode ep, {Duration? startAt}) async {
    final token = ++_episodeToken;
    _videoToken++;
    _closeVideo();
    setState(() {
      _current = ep;
      _preparing = true;
      _playerError = null;
      _cues = null;
    });
    final service = ref.read(viuServiceProvider);
    try {
      final pb = await service.fetchPlayback(ep);
      if (!mounted || token != _episodeToken) return;
      final streams = [
        for (final q in pb.qualities)
          CinemanaStreamFile(
              name: q.label,
              resolution: q.label,
              container: 'hls',
              videoUrl: q.url),
      ];
      // Keep the viewer's quality; otherwise 720p (or the best below it).
      final wanted = _selected?.resolution ?? '720p';
      final pick = streams.firstWhere(
        (s) => s.resolution == wanted,
        orElse: () =>
            streams.lastWhere((s) => _px(s) <= 720, orElse: () => streams.last),
      );
      setState(() {
        _streams = streams;
        _selected = pick;
      });
      final subsUrl = pb.arabicSubtitleUrl;
      if (subsUrl != null) {
        service.fetchSubtitleCues(subsUrl).then((cues) {
          if (mounted && token == _episodeToken && cues.isNotEmpty)
            setState(() => _cues = cues);
        });
      }
      await _openStream(pick.videoUrl, startAt: startAt);
    } catch (e) {
      if (!mounted || token != _episodeToken) return;
      setState(() {
        _preparing = false;
        _playerError =
            e is ViuException ? e.message : 'تعذّر تشغيل الحلقة، حاول مرة أخرى';
      });
    }
  }

  Future<void> _openStream(String url, {Duration? startAt}) async {
    final token = ++_videoToken;
    _closeVideo();
    setState(() {
      _preparing = true;
      _playerError = null;
    });
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(url),
      formatHint: VideoFormat.hls,
      httpHeaders: const {'User-Agent': _ua},
    );
    try {
      if (isDesktopVideo) {
        // On a desktop the view has to be rendering while the stream opens,
        // or initialize() never returns (see desktop_video.dart).
        setState(() => _video = controller);
        await openWhileRedrawing(controller, () {
          if (mounted && token == _videoToken) setState(() {});
        });
      } else {
        await controller.initialize();
      }
      if (!mounted || token != _videoToken) {
        await disposeQuietly(controller);
        return;
      }
      if (startAt != null && startAt > Duration.zero)
        await controller.seekTo(startAt);
      controller.addListener(_onVideoTick);
      await controller.play();
      _advancing = false;
      setState(() {
        _video = controller;
        _preparing = false;
      });
    } catch (_) {
      if (identical(_video, controller)) _video = null;
      await disposeQuietly(controller);
      if (!mounted || token != _videoToken) return;
      setState(() {
        _preparing = false;
        _playerError = 'تعذّر تشغيل الحلقة، حاول مرة أخرى أو اختر جودة أخرى';
      });
    }
  }

  void _closeVideo() {
    final old = _video;
    if (old == null) return;
    old.removeListener(_onVideoTick);
    _video = null;
    old.dispose();
    _onVideoTick();
  }

  void _onVideoTick() {
    final v = _video?.value;
    final playing = v?.isPlaying ?? false;
    if (playing != _wakeLocked) {
      _wakeLocked = playing;
      WakelockPlus.toggle(enable: playing).catchError((_) {});
    }
    if (v == null) return;
    if (v.position > Duration.zero) _lastPosition = v.position;
    // Episode over: on to the next free one.
    if (v.isCompleted && !_advancing) {
      _advancing = true;
      final next = _nextEpisode;
      if (next != null) _playEpisode(next);
    }
  }

  ViuEpisode? get _nextEpisode {
    final eps = _episodes, cur = _current;
    if (eps == null || cur == null) return null;
    final i = eps.indexWhere((e) => e.productId == cur.productId);
    return i >= 0 && i + 1 < eps.length ? eps[i + 1] : null;
  }

  void _retry() {
    final cur = _current;
    // Fresh stream addresses (they expire), from where it stopped.
    if (cur != null) _playEpisode(cur, startAt: _lastPosition);
  }

  void _switchQuality(CinemanaStreamFile s) {
    if (s.videoUrl == _selected?.videoUrl && _video != null) return;
    final at = _video?.value.position ?? _lastPosition;
    setState(() => _selected = s);
    _openStream(s.videoUrl, startAt: at);
  }

  void _onSubtitlesChanged(SubtitleSettings s) {
    setState(() => _subs = s);
    _saveSubsTimer?.cancel();
    _saveSubsTimer =
        Timer(const Duration(milliseconds: 500), () => _subs.save());
  }

  void _setFullscreen(bool fs) async {
    setState(() => _isFullscreen = fs);
    if (isDesktopVideo) {
      try {
        await windowManager.setFullScreen(fs);
      } catch (_) {}
    }
    if (fs) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations(
          [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      _allowRotation();
    }
  }

  /// While this player is open the phone may be turned: landscape is
  /// fullscreen. Everywhere else the app is locked upright (see main).
  void _allowRotation() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  String get _title {
    final cur = _current;
    if (cur == null || _show.isMovie || (_episodes?.length ?? 0) <= 1)
      return _show.displayName;
    return '${_show.displayName} - الحلقة ${cur.number}';
  }

  // --------------------------------------------------------------- build

  Widget _player({required bool fullscreen}) {
    return CinemanaPlayerView(
      key: _playerKey,
      controller: _video,
      loading: _preparing,
      error: _playerError,
      onRetry: _retry,
      fullscreen: fullscreen,
      onToggleFullscreen: () => _setFullscreen(!fullscreen),
      onBack: () {
        if (_isFullscreen) {
          _setFullscreen(false);
        } else {
          Navigator.of(context).maybePop();
        }
      },
      title: _title,
      cues: _cues,
      subtitles: _subs,
      onSubtitlesChanged: _onSubtitlesChanged,
      streams: _streams,
      selectedStream: _selected,
      onQuality: _switchQuality,
    );
  }

  /// Before anything plays: the show's artwork and a big play button.
  Widget _cover() {
    final eps = _episodes;
    final first = (eps == null || eps.isEmpty) ? null : eps.first;
    final image =
        _show.landscapeUrl ?? _show.portraitUrl ?? widget.show.landscapeUrl;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return GestureDetector(
      onTap: first == null ? null : () => _playEpisode(first),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          if (image != null)
            CachedNetworkImage(
              imageUrl: image,
              fit: BoxFit.cover,
              memCacheWidth: (MediaQuery.of(context).size.width * dpr).round(),
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            ),
          const ColoredBox(color: Color(0x59000000)),
          Center(
            child: eps == null && !_episodesFailed
                ? const CircularProgressIndicator(color: Color(0xFFE50914))
                : first == null
                    ? Text(
                        _episodesFailed
                            ? 'تعذّر تحميل الحلقات'
                            : 'لا توجد حلقات مجانية حالياً',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: const BoxDecoration(
                                color: Color(0xFFE50914),
                                shape: BoxShape.circle),
                            child: const Icon(Icons.play_arrow_rounded,
                                color: Colors.white, size: 40),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _show.isMovie || eps!.length == 1
                                ? 'شاهد الآن'
                                : 'شاهد الحلقة ${first.number}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobile = !isDesktopVideo;
    final isLandscapeMobile =
        isMobile && MediaQuery.of(context).orientation == Orientation.landscape;
    final started = _current != null;

    if (started && (_isFullscreen || isLandscapeMobile)) {
      return PopScope(
        canPop: !_isFullscreen,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _setFullscreen(false);
        },
        child: Scaffold(
            backgroundColor: Colors.black, body: _player(fullscreen: true)),
      );
    }

    final eps = _episodes;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F13) : Colors.white,
      // No app bar: the player draws its own back, title and fullscreen;
      // a bar above it with the same things was those things twice.
      body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: started ? _player(fullscreen: false) : _cover(),
              ),
              if (started && _streams.length > 1) _qualityBar(isDark),
              if (started && _cues != null)
                SubtitleSettingsBar(
                    settings: _subs, onChanged: _onSubtitlesChanged),
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _details(isDark)),
                    if (eps != null && eps.length > 1)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                        sliver: SliverList.separated(
                          itemCount: eps.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) => _episodeTile(eps[i], isDark),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          )),
    );
  }

  Widget _qualityBar(bool isDark) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF16161D) : Colors.white,
        border: isDark
            ? null
            : Border(bottom: BorderSide(color: AppPalette.of(context).border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          const Icon(Icons.high_quality_rounded,
              size: 16, color: Color(0xFFE50914)),
          const SizedBox(width: 8),
          const Text('الجودة: ',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _streams.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final s = _streams[i];
                return ChoiceChip(
                  label:
                      Text(s.resolution, style: const TextStyle(fontSize: 11)),
                  selected: _selected?.resolution == s.resolution,
                  selectedColor: const Color(0xFFE50914),
                  onSelected: (_) => _switchQuality(s),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _details(bool isDark) {
    final show = _show;
    final versions = widget.show.versions;
    final eps = _episodes;
    final fg = isDark ? Colors.white : Colors.black87;
    final sub = isDark ? const Color(0xFFA8A8B3) : const Color(0xFF55555F);
    final description = show.description.isNotEmpty
        ? show.description
        : (_current?.description ?? '');
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(show.displayName,
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w900, color: fg)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (show.categoryName.isNotEmpty)
                _chip(show.categoryName, isDark),
              if (show.isDubbed && versions.length == 1)
                _chip('مدبلج', isDark, red: true),
              if (eps != null && eps.length > 1)
                _chip('${eps.length} حلقة مجانية', isDark),
            ],
          ),
          if (versions.length > 1) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Text('النسخة: ',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: fg)),
                const SizedBox(width: 4),
                for (final v in versions) ...[
                  ChoiceChip(
                    label: Text(v.versionLabel,
                        style: const TextStyle(fontSize: 12)),
                    selected: v.seriesId == show.seriesId,
                    selectedColor: const Color(0xFFE50914),
                    labelStyle: TextStyle(
                      color: v.seriesId == show.seriesId ? Colors.white : fg,
                      fontWeight: FontWeight.w700,
                    ),
                    onSelected: (_) => _switchVersion(v),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ],
          if (description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(description,
                style: TextStyle(fontSize: 12.5, height: 1.5, color: sub)),
          ],
          if (eps != null && eps.length > 1) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.video_library_rounded,
                    color: Color(0xFFE50914), size: 18),
                const SizedBox(width: 8),
                Text('الحلقات',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold, color: fg)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String text, bool isDark, {bool red = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: red
              ? const Color(0xFFE50914)
              : (isDark ? const Color(0xFF1E1E26) : Colors.white),
          borderRadius: BorderRadius.circular(6),
          border: (red || isDark)
              ? null
              : Border.all(color: AppPalette.of(context).border),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color:
                red ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
          ),
        ),
      );

  Widget _episodeTile(ViuEpisode ep, bool isDark) {
    final isCurrent = _current?.productId == ep.productId;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return InkWell(
      onTap: () => _playEpisode(ep),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF17171F) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isCurrent
                ? const Color(0xFFE50914)
                : (isDark ? Colors.transparent : AppPalette.of(context).border),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 128,
                height: 72,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: Color(0xFF22222C)),
                    if (ep.coverUrl != null)
                      CachedNetworkImage(
                        imageUrl: ep.coverUrl!,
                        fit: BoxFit.cover,
                        memCacheWidth: (128 * dpr).round(),
                        errorWidget: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    Center(
                      child: Icon(
                        isCurrent
                            ? Icons.equalizer_rounded
                            : Icons.play_circle_fill_rounded,
                        color: Colors.white.withOpacity(0.9),
                        size: 28,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'الحلقة ${ep.number}',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: isCurrent
                          ? const Color(0xFFE50914)
                          : (isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                  if (ep.durationLabel.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      ep.durationLabel,
                      style: TextStyle(
                          fontSize: 11.5,
                          color: isDark ? Colors.white54 : Colors.black45),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
