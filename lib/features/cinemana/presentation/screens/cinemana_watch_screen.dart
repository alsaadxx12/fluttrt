import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';
import 'package:youtube_downloader/features/history/presentation/providers/watch_history_provider.dart';
import '../../data/cinemana_subtitles.dart';
import '../../data/models/cinemana_models.dart';
import '../providers/cinemana_provider.dart';
import '../widgets/cinemana_player_view.dart';
import 'package:youtube_downloader/core/video/desktop_video.dart';
import 'package:window_manager/window_manager.dart';
import 'package:youtube_downloader/features/casting/services/resume_store.dart';

class CinemanaWatchScreen extends ConsumerStatefulWidget {
  final CinemanaItem item;
  final List<CinemanaEpisode> episodes;
  final CinemanaEpisode? initialEpisode;
  final String? initialSeason;

  const CinemanaWatchScreen({
    super.key,
    required this.item,
    this.episodes = const [],
    this.initialEpisode,
    this.initialSeason,
  });

  @override
  ConsumerState<CinemanaWatchScreen> createState() =>
      _CinemanaWatchScreenState();
}

class _CinemanaWatchScreenState extends ConsumerState<CinemanaWatchScreen> {
  late CinemanaEpisode? _currentEpisode;
  Map<String, List<CinemanaEpisode>> _seasons = {};
  String? _selectedSeason;
  List<CinemanaStreamFile> _streams = [];
  CinemanaStreamFile? _selectedStream;
  bool _isLoadingStreams = true;
  String? _errorMessage;
  bool _isFullscreen = false;

  // Native player (ExoPlayer): the picture resizes cleanly on rotation and
  // fullscreen, and the app draws the controls and subtitles itself.
  VideoPlayerController? _video;
  String? _playerError;
  int _videoToken = 0;
  bool _wakeLocked = false;
  final _playerKey = GlobalKey();

  // Arabic subtitles; on/off, size and height are remembered.
  SubtitleSettings _subs = const SubtitleSettings();
  bool _hasSubs = false; // this video has Arabic subtitles, loaded
  List<SubtitleCue>? _subCues;
  int _loadToken = 0;
  Timer? _savePrefsTimer;

  @override
  void initState() {
    super.initState();
    _currentEpisode = widget.initialEpisode;
    // «سجل المشاهدة»: the title goes in once, when its player opens. For a
    // series or anime [widget.item] is the show, so the history lists it
    // once however many episodes are watched.
    ref
        .read(watchHistoryProvider.notifier)
        .record(widget.item, episode: _currentEpisode);
    _loadSubtitlePrefs();
    _allowRotation();
    _initSeasons();
    _loadStreamFiles();
    _resumeTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _rememberPosition());
  }

  Timer? _resumeTimer;

  void _initSeasons() {
    final Map<String, List<CinemanaEpisode>> map = {};
    for (final ep in widget.episodes) {
      final s = ep.seasonNumber.isNotEmpty ? ep.seasonNumber : '1';
      map.putIfAbsent(s, () => []).add(ep);
    }
    for (final s in map.keys) {
      map[s]!.sort((a, b) => a.intEpisodeNumber.compareTo(b.intEpisodeNumber));
    }
    final sortedKeys = map.keys.toList()
      ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));

    final Map<String, List<CinemanaEpisode>> sorted = {};
    for (final k in sortedKeys) {
      sorted[k] = map[k]!;
    }
    _seasons = sorted;

    if (widget.initialEpisode != null &&
        widget.initialEpisode!.seasonNumber.isNotEmpty) {
      _selectedSeason = widget.initialEpisode!.seasonNumber;
    } else if (widget.initialSeason != null &&
        _seasons.containsKey(widget.initialSeason)) {
      _selectedSeason = widget.initialSeason;
    } else if (sortedKeys.isNotEmpty) {
      _selectedSeason = sortedKeys.first;
    }
  }

  String get _currentVideoId =>
      _currentEpisode != null ? _currentEpisode!.id : widget.item.id;

  String get _currentTitle => _currentEpisode != null
      ? '${widget.item.displayTitle} - الحلقة ${_currentEpisode!.episodeNumber}'
      : widget.item.displayTitle;

  Future<void> _loadStreamFiles() async {
    final token = ++_loadToken;
    setState(() {
      _isLoadingStreams = true;
      _errorMessage = null;
      _hasSubs = false;
      _subCues = null;
      _playerError = null;
    });
    _closeVideo();

    final service = ref.read(cinemanaServiceProvider);
    // Subtitles download alongside the stream list and join the player
    // whenever they arrive.
    _loadSubtitles(_currentVideoId, token);
    final streams = await service.fetchStreamFiles(_currentVideoId);

    if (!mounted || token != _loadToken) return;

    if (streams.isEmpty) {
      setState(() {
        _isLoadingStreams = false;
        _errorMessage = 'لا تتوفر روابط تشغيل مباشرة لهذا المحتوى حالياً';
      });
      return;
    }

    // Prefer 720p or 1080p
    CinemanaStreamFile selected = streams.first;
    for (final s in streams) {
      if (s.resolution.contains('720') || s.name.contains('720')) {
        selected = s;
        break;
      }
    }

    setState(() {
      _streams = streams;
      _selectedStream = selected;
      _isLoadingStreams = false;
    });

    // From where it was left — here, or on a television.
    final resumeAt = await ResumeStore.read(_currentVideoId);
    if (!mounted || token != _loadToken) return;
    _openStream(selected.videoUrl, startAt: resumeAt);
  }

  /// Writes down where the film is, every few seconds while it plays, so
  /// the next opening - on the phone or a screen - starts there.
  void _rememberPosition({bool now = false}) {
    final video = _video;
    if (video == null || !video.value.isInitialized) return;
    final position = video.value.position;
    final duration = video.value.duration;
    ResumeStore.save(_currentVideoId, position, duration: duration);
    // And in the history, where the page shows «وصلت إلى 42:10».
    ref.read(watchHistoryProvider.notifier).updatePosition(
          _currentVideoId,
          position,
          duration: duration,
          now: now,
        );
  }

  Future<void> _loadSubtitlePrefs() async {
    final saved = await SubtitleSettings.load();
    if (mounted) setState(() => _subs = saved);
  }

  void _onSubtitlesChanged(SubtitleSettings s) {
    setState(() => _subs = s);
    // Dragging the line fires many changes; save once it settles.
    _savePrefsTimer?.cancel();
    _savePrefsTimer =
        Timer(const Duration(milliseconds: 500), () => _subs.save());
  }

  /// Arabic only - that is what the viewer reads.
  Future<void> _loadSubtitles(String videoId, int token) async {
    if (videoId.startsWith('krmzi_') || videoId.startsWith('ts_')) return;
    final service = ref.read(cinemanaServiceProvider);
    final sources = await service.fetchSubtitleSources(videoId);
    final url = sources.ar;
    if (url == null || !mounted || token != _loadToken) return;
    final cues = await service.fetchSubtitleCues(url);
    if (cues.isEmpty || !mounted || token != _loadToken) return;
    setState(() {
      _hasSubs = true;
      _subCues = cues;
    });
  }

  /// Starts [url] in the native player, optionally from [startAt] (used when
  /// switching quality).
  Future<void> _openStream(String url, {Duration? startAt}) async {
    final token = ++_videoToken;
    _closeVideo();
    setState(() => _playerError = null);

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(url),
      httpHeaders: const {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
      },
    );
    try {
      if (isDesktopVideo) {
        // On a desktop the view has to be rendering while the stream opens,
        // or initialize() never returns. Put it on screen now and keep
        // redrawing it until the stream has opened.
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
      controller.addListener(_syncWakelock);
      await controller.play();
      setState(() => _video = controller);
    } catch (_) {
      if (identical(_video, controller)) _video = null;
      await disposeQuietly(controller);
      if (!mounted || token != _videoToken) return;
      setState(() => _playerError =
          'تعذّر تشغيل الفيديو، حاول مرة أخرى أو اختر جودة أخرى');
    }
  }

  void _closeVideo() {
    final old = _video;
    if (old == null) return;
    old.removeListener(_syncWakelock);
    _video = null;
    old.dispose();
    _syncWakelock();
  }

  /// Screen stays on while a video plays, and only then.
  void _syncWakelock() {
    final playing = _video?.value.isPlaying ?? false;
    if (playing == _wakeLocked) return;
    _wakeLocked = playing;
    WakelockPlus.toggle(enable: playing).catchError((_) {});
  }

  void _retryPlayback() {
    final stream = _selectedStream;
    if (stream == null) {
      _loadStreamFiles();
    } else {
      // Pick up where it stopped (a dropped connection mid-film).
      final at = _video?.value.position;
      _openStream(stream.videoUrl, startAt: at);
    }
  }

  @override
  void dispose() {
    _resumeTimer?.cancel();
    _rememberPosition(now: true);
    _savePrefsTimer?.cancel();
    _videoToken++;
    _closeVideo();
    WakelockPlus.disable().catchError((_) {});
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
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
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
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

  void _switchQuality(CinemanaStreamFile stream) {
    if (stream.videoUrl == _selectedStream?.videoUrl && _video != null) return;
    final at = _video?.value.position;
    setState(() => _selectedStream = stream);
    _openStream(stream.videoUrl, startAt: at);
  }

  void _selectEpisode(CinemanaEpisode ep) {
    if (_currentEpisode?.id == ep.id) return;
    _rememberPosition(now: true);
    setState(() {
      _currentEpisode = ep;
    });
    // The history follows the episode: one entry for the show, on the
    // episode being watched.
    ref.read(watchHistoryProvider.notifier).record(widget.item, episode: ep);
    _loadStreamFiles();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobile = !isDesktopVideo;
    final isLandscapeMobile =
        isMobile && MediaQuery.of(context).orientation == Orientation.landscape;

    // Fullscreen: only when explicitly toggled on desktop, or rotated on mobile
    if (_isFullscreen || isLandscapeMobile) {
      return PopScope(
        canPop: !_isFullscreen,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _setFullscreen(false);
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: _player(fullscreen: true),
        ),
      );
    }

    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0F0F13) : Colors.white,
        // No app bar: the player draws its own top row - back, the title,
        // fullscreen - and a second row of the same three above it was
        // exactly that, the same three twice.
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // 1. Video player (16:9)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: _player(fullscreen: false),
              ),

              // 2. Stream Quality Selector Chips
              if (_streams.length > 1)
                Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF16161D) : Colors.white,
                    border: isDark
                        ? null
                        : Border(
                            bottom: BorderSide(
                                color: AppPalette.of(context).border)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      const Icon(Icons.high_quality_rounded,
                          size: 16, color: AppColors.primary),
                      const SizedBox(width: 8),
                      const Text('الجودة: ',
                          style: TextStyle(
                              fontSize: 11.5, fontWeight: FontWeight.bold)),
                      Expanded(
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _streams.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 6),
                          itemBuilder: (context, index) {
                            final s = _streams[index];
                            final isSelected =
                                _selectedStream?.resolution == s.resolution;
                            return ChoiceChip(
                              label: Text(s.resolution,
                                  style: const TextStyle(fontSize: 11)),
                              selected: isSelected,
                              selectedColor: AppColors.primary,
                              onSelected: (_) => _switchQuality(s),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 0),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),

              // 2b. Subtitle language
              if (_hasSubs)
                SubtitleSettingsBar(
                    settings: _subs, onChanged: _onSubtitlesChanged),

              // 3. Details & Episodes Section (Matching Image 5)
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    // Title and Stars
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _currentTitle,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.item.categories.join(' • '),
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.darkTextSecondary),
                              ),
                            ],
                          ),
                        ),
                        if (widget.item.stars.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.amber.withOpacity(0.16),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.star_rounded,
                                    size: 16, color: Colors.amber),
                                const SizedBox(width: 4),
                                Text(
                                  widget.item.stars,
                                  style: const TextStyle(
                                      color: Colors.amber,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Series Episodes Carousel with Season Tabs & RTL Flow
                    if (widget.episodes.isNotEmpty) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.movie_filter_rounded,
                                  color: AppColors.primary, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                _selectedSeason != null
                                    ? 'حلقات الموسم $_selectedSeason'
                                    : 'الحلقات (${widget.episodes.length})',
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          if (_selectedSeason != null &&
                              _seasons.containsKey(_selectedSeason))
                            Text(
                              '${_seasons[_selectedSeason]!.length} حلقة',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.darkTextSecondary),
                            ),
                        ],
                      ),

                      // Season Selection Chips (RTL)
                      if (_seasons.keys.length > 1) ...[
                        const SizedBox(height: 8),
                        Directionality(
                          textDirection: TextDirection.rtl,
                          child: SizedBox(
                            height: 34,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: _seasons.keys.map((sNum) {
                                final isSelected = _selectedSeason == sNum;
                                final count = _seasons[sNum]?.length ?? 0;
                                return Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: ChoiceChip(
                                    label: Text('الموسم $sNum ($count)',
                                        style: const TextStyle(fontSize: 11)),
                                    selected: isSelected,
                                    selectedColor: AppColors.primary,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 0),
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    onSelected: (_) {
                                      setState(() {
                                        _selectedSeason = sNum;
                                      });
                                    },
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 10),

                      // Episodes Carousel scrolling RTL (From Right to Left)
                      Builder(
                        builder: (context) {
                          final currentSeasonEpisodes =
                              (_selectedSeason != null &&
                                      _seasons.containsKey(_selectedSeason))
                                  ? _seasons[_selectedSeason]!
                                  : widget.episodes;

                          return SizedBox(
                            height: 120,
                            child: Directionality(
                              textDirection: TextDirection.rtl,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: currentSeasonEpisodes.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 10),
                                itemBuilder: (context, index) {
                                  final ep = currentSeasonEpisodes[index];
                                  final isCurrent =
                                      _currentEpisode?.id == ep.id;

                                  return InkWell(
                                    onTap: () => _selectEpisode(ep),
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      width: 140,
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? const Color(0xFF1E1E26)
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: isCurrent
                                              ? AppColors.primary
                                              : (isDark
                                                  ? Colors.transparent
                                                  : AppPalette.of(context)
                                                      .border),
                                          width: 2,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Stack(
                                              fit: StackFit.expand,
                                              children: [
                                                ClipRRect(
                                                  borderRadius:
                                                      const BorderRadius
                                                          .vertical(
                                                          top: Radius.circular(
                                                              8)),
                                                  child: ep.imgUrl != null &&
                                                          ep.imgUrl!.isNotEmpty
                                                      ? Image.network(
                                                          ep.imgUrl!,
                                                          fit: BoxFit.cover,
                                                          cacheWidth: 320,
                                                          errorBuilder: (_, __,
                                                                  ___) =>
                                                              Container(
                                                                  color: isDark
                                                                      ? Colors
                                                                          .black26
                                                                      : AppPalette.of(
                                                                              context)
                                                                          .skeleton),
                                                        )
                                                      : Container(
                                                          color: isDark
                                                              ? Colors.black26
                                                              : AppPalette.of(
                                                                      context)
                                                                  .skeleton),
                                                ),
                                                if (isCurrent)
                                                  Container(
                                                    decoration: BoxDecoration(
                                                      color: AppColors.primary
                                                          .withOpacity(0.35),
                                                      borderRadius:
                                                          const BorderRadius
                                                              .vertical(
                                                              top: Radius
                                                                  .circular(8)),
                                                    ),
                                                    child: const Center(
                                                      child: Icon(
                                                          Icons
                                                              .play_arrow_rounded,
                                                          color: Colors.white,
                                                          size: 32),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 6),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  'الحلقة ${ep.episodeNumber}',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: isCurrent
                                                        ? FontWeight.bold
                                                        : FontWeight.w600,
                                                    color: isCurrent
                                                        ? AppColors.primary
                                                        : (isDark
                                                            ? Colors.white
                                                            : Colors.black87),
                                                  ),
                                                ),
                                                if (ep.duration.isNotEmpty)
                                                  Text(
                                                    ep.duration,
                                                    style: const TextStyle(
                                                        fontSize: 10,
                                                        color: AppColors
                                                            .darkTextSecondary),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    ],

                    const SizedBox(height: 20),

                    // Description
                    const Text(
                      'نبذة عن العمل',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.item.arContent.isNotEmpty
                          ? widget.item.arContent
                          : (widget.item.enContent.isNotEmpty
                              ? widget.item.enContent
                              : 'لا يوجد وصف متاح.'),
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: isDark
                            ? const Color(0xFFC8C8D0)
                            : const Color(0xFF484850),
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
  }

  /// The one player, moved (not rebuilt) between the page and fullscreen.
  Widget _player({required bool fullscreen}) {
    return CinemanaPlayerView(
      key: _playerKey,
      controller: _video,
      // On a desktop the controller is on screen before it has opened, so
      // "no controller yet" is no longer the only waiting state.
      loading: _isLoadingStreams ||
          (_video == null && _playerError == null && _errorMessage == null) ||
          (_video != null && !_video!.value.isInitialized),
      error: _errorMessage ?? _playerError,
      onRetry: _errorMessage != null ? _loadStreamFiles : _retryPlayback,
      fullscreen: fullscreen,
      onToggleFullscreen: () => _setFullscreen(!fullscreen),
      onBack: () {
        if (_isFullscreen) {
          _setFullscreen(false);
        } else {
          Navigator.of(context).maybePop();
        }
      },
      title: _currentTitle,
      cues: _hasSubs ? _subCues : null,
      subtitles: _subs,
      onSubtitlesChanged: _onSubtitlesChanged,
      streams: _streams,
      selectedStream: _selectedStream,
      onQuality: _switchQuality,
    );
  }
}
