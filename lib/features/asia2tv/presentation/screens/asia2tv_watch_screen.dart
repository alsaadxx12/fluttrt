import 'dart:async';
import 'package:flutter/material.dart';
import 'package:youtube_downloader/presentation/widgets/episode_row.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_palette.dart';
import '../../../../core/video/desktop_video.dart';
import '../../../cinemana/data/cinemana_subtitles.dart';
import '../../../cinemana/data/models/cinemana_models.dart';
import '../../../cinemana/presentation/widgets/cinemana_player_view.dart';
import '../../data/models/asia2tv_models.dart';
import '../providers/asia2tv_providers.dart';

class Asia2TvWatchScreen extends ConsumerStatefulWidget {
  final Asia2TvItem? item;
  final String initialWatchUrl;
  final String title;
  final List<Asia2TvEpisode>? allEpisodes;
  final int? currentEpisodeNumber;

  /// A picture for each episode number, when the details page found some.
  final Map<int, String>? stills;

  const Asia2TvWatchScreen({
    super.key,
    this.item,
    required this.initialWatchUrl,
    required this.title,
    this.allEpisodes,
    this.currentEpisodeNumber,
    this.stills,
  });

  @override
  ConsumerState<Asia2TvWatchScreen> createState() => _Asia2TvWatchScreenState();
}

class _Asia2TvWatchScreenState extends ConsumerState<Asia2TvWatchScreen> {
  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  late String _currentWatchUrl;
  late String _currentTitle;
  int? _currentEpNumber;

  VideoPlayerController? _controller;
  bool _isLoading = true;
  String? _errorMessage;

  List<CinemanaStreamFile> _streams = const [];
  CinemanaStreamFile? _selectedStream;
  List<Asia2TvServer> _servers = const [];
  String _activeServer = 'Vidmoly';

  bool _isFullscreen = false;
  int _streamToken = 0;

  SubtitleSettings _subs = const SubtitleSettings();
  List<SubtitleCue>? _cues;

  @override
  void initState() {
    super.initState();
    _currentWatchUrl = widget.initialWatchUrl;
    _currentTitle = widget.title;
    _currentEpNumber = widget.currentEpisodeNumber;

    SubtitleSettings.load().then((s) {
      if (mounted) setState(() => _subs = s);
    });

    _loadAndPlayStream(_currentWatchUrl);
  }

  @override
  void dispose() {
    _streamToken++;
    _closeController();
    WakelockPlus.disable().catchError((_) {});
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _closeController() {
    final c = _controller;
    _controller = null;
    c?.pause().catchError((_) {});
    c?.dispose().catchError((_) {});
  }

  /// Resolves the watch page servers, automatically selects the highest resolution (1080p),
  /// and streams directly without any ads.
  Future<void> _loadAndPlayStream(String watchUrl) async {
    final token = ++_streamToken;
    _closeController();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _streams = const [];
      _selectedStream = null;
    });

    try {
      final service = ref.read(asia2tvServiceProvider);
      final playback = await service.resolveEpisodePlayback(watchUrl);

      if (!mounted || token != _streamToken) return;

      if (playback.streams.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'لم يتم العثور على سيرفر مباشر متاح لهذه الحلقة حالياً.';
          _servers = playback.servers;
        });
        return;
      }

      // Streams are sorted descending by resolution: 1080p > 720p > 480p > 360p
      // Automatically pick the highest resolution available!
      final highestStream = playback.streams.first;

      setState(() {
        _streams = playback.streams;
        _selectedStream = highestStream;
        _servers = playback.servers;
        _activeServer = playback.activeServerName;
      });

      await _startPlayback(highestStream.videoUrl, token: token);
    } catch (e) {
      if (!mounted || token != _streamToken) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'حدث خطأ أثناء تحميل السيرفرات. يرجى المحاولة مرة أخرى.';
      });
    }
  }

  Future<void> _startPlayback(String streamUrl, {required int token, Duration? startAt}) async {
    _closeController();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final isHls = streamUrl.contains('.m3u8');
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(streamUrl),
      formatHint: isHls ? VideoFormat.hls : VideoFormat.other,
      httpHeaders: const {
        'User-Agent': _ua,
        'Referer': 'https://ww1.asia2tv.pw/',
      },
    );

    try {
      if (isDesktopVideo) {
        setState(() => _controller = controller);
        await openWhileRedrawing(controller, () {
          if (mounted) setState(() {});
        });
      } else {
        await controller.initialize();
      }

      if (!mounted || token != _streamToken) {
        controller.dispose().catchError((_) {});
        return;
      }

      if (startAt != null) {
        await controller.seekTo(startAt);
      }

      await controller.play();
      WakelockPlus.enable().catchError((_) {});

      setState(() {
        _controller = controller;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted || token != _streamToken) return;
      controller.dispose().catchError((_) {});
      setState(() {
        _isLoading = false;
        _errorMessage = 'تعذّر تشغيل الفيديو، جرب دقة أخرى أو سيرفر بديل.';
      });
    }
  }

  void _onQualityChanged(CinemanaStreamFile stream) {
    if (stream.videoUrl == _selectedStream?.videoUrl) return;
    final pos = _controller?.value.position ?? Duration.zero;
    setState(() => _selectedStream = stream);
    _startPlayback(stream.videoUrl, token: _streamToken, startAt: pos);
  }

  void _toggleFullscreen() {
    setState(() => _isFullscreen = !_isFullscreen);
    if (_isFullscreen) {
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

  void _playNextEpisode() {
    final episodes = widget.allEpisodes;
    if (episodes == null || episodes.isEmpty || _currentEpNumber == null) return;
    final nextIdx = episodes.indexWhere((e) => e.number == _currentEpNumber! + 1);
    if (nextIdx != -1) {
      final nextEp = episodes[nextIdx];
      setState(() {
        _currentWatchUrl = nextEp.url;
        _currentTitle = nextEp.title;
        _currentEpNumber = nextEp.number;
      });
      _loadAndPlayStream(nextEp.url);
    }
  }

  void _playPreviousEpisode() {
    final episodes = widget.allEpisodes;
    if (episodes == null || episodes.isEmpty || _currentEpNumber == null) return;
    final prevIdx = episodes.indexWhere((e) => e.number == _currentEpNumber! - 1);
    if (prevIdx != -1) {
      final prevEp = episodes[prevIdx];
      setState(() {
        _currentWatchUrl = prevEp.url;
        _currentTitle = prevEp.title;
        _currentEpNumber = prevEp.number;
      });
      _loadAndPlayStream(prevEp.url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final episodes = widget.allEpisodes ?? const [];
    final hasPrev = _currentEpNumber != null && episodes.any((e) => e.number == _currentEpNumber! - 1);
    final hasNext = _currentEpNumber != null && episodes.any((e) => e.number == _currentEpNumber! + 1);

    if (_isFullscreen) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: CinemanaPlayerView(
          controller: _controller,
          loading: _isLoading,
          error: _errorMessage,
          onRetry: () => _loadAndPlayStream(_currentWatchUrl),
          fullscreen: true,
          onToggleFullscreen: _toggleFullscreen,
          title: _currentTitle,
          cues: _cues,
          subtitles: _subs,
          onSubtitlesChanged: (s) => setState(() => _subs = s),
          streams: _streams,
          selectedStream: _selectedStream,
          onQuality: _onQualityChanged,
          onBack: _toggleFullscreen,
        ),
      );
    }

    return Scaffold(
      backgroundColor: palette.bg,
      // No app bar: the player draws its own back, title and fullscreen;
      // a bar above it with the same things was those things twice.
      body: SafeArea(
        child: Column(
          children: [
            // Video Player Container
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                color: Colors.black,
                child: CinemanaPlayerView(
                  controller: _controller,
                  loading: _isLoading,
                  error: _errorMessage,
                  onRetry: () => _loadAndPlayStream(_currentWatchUrl),
                  fullscreen: false,
                  onToggleFullscreen: _toggleFullscreen,
                  title: _currentTitle,
                  cues: _cues,
                  subtitles: _subs,
                  onSubtitlesChanged: (s) => setState(() => _subs = s),
                  streams: _streams,
                  selectedStream: _selectedStream,
                  onQuality: _onQualityChanged,
                ),
              ),
            ),

            // Content below player
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Title and Quality badge
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          _currentTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (_selectedStream != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white24, width: 0.8),
                          ),
                          child: Text(
                            'سيرفر $_activeServer',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.primary, width: 1),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.hd_rounded, color: AppColors.primary, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                _selectedStream!.resolution,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Ad-Free & Highest Quality status indicator
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E1A14),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4), width: 1),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.verified_user_rounded, color: Color(0xFF10B981), size: 16),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'بث مباشر أصلي وبدون إعلانات نهائياً • تحويل تلقائي لأعلى دقة متوفرة',
                            style: TextStyle(color: Color(0xFF10B981), fontSize: 11.5, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (_servers.length > 1) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.dns_rounded, color: Colors.white54, size: 14),
                        const SizedBox(width: 6),
                        const Text('السيرفرات:',
                            style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (final s in _servers)
                                  Padding(
                                    padding: const EdgeInsetsDirectional.only(end: 6),
                                    child: ChoiceChip(
                                      label: Text(s.name, style: const TextStyle(fontSize: 11)),
                                      selected: _activeServer.toLowerCase().contains(s.name.toLowerCase()) ||
                                          s.name.toLowerCase().contains(_activeServer.toLowerCase()),
                                      selectedColor: AppColors.primary.withOpacity(0.25),
                                      backgroundColor: const Color(0xFF141A26),
                                      labelStyle: TextStyle(
                                        color: _activeServer.toLowerCase().contains(s.name.toLowerCase())
                                            ? Colors.white
                                            : Colors.white60,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                      side: BorderSide(
                                        color: _activeServer.toLowerCase().contains(s.name.toLowerCase())
                                            ? AppColors.primary
                                            : Colors.white12,
                                      ),
                                      onSelected: (_) {
                                        setState(() => _activeServer = s.name);
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Next / Previous Episode Bar
                  if (episodes.isNotEmpty)
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: hasPrev ? _playPreviousEpisode : null,
                            icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 18),
                            label: const Text('الحلقة السابقة'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF141A26),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.white.withOpacity(0.04),
                              disabledForegroundColor: Colors.white24,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: hasNext ? _playNextEpisode : null,
                            icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 18),
                            label: const Text('الحلقة التالية'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.white.withOpacity(0.04),
                              disabledForegroundColor: Colors.white24,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      ],
                    ),

                  const SizedBox(height: 20),

                  // Episode list if series: every source's episodes in one
                  // row, the one playing ringed in red.
                  if (episodes.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'جميع الحلقات',
                          style: TextStyle(
                            color: palette.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '${episodes.length} حلقة',
                          style: TextStyle(color: palette.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    EpisodeRow(
                      tiles: [
                        for (final ep in episodes)
                          EpisodeTile(
                            label: 'الحلقة ${ep.number}',
                            image: widget.stills?[ep.number],
                          ),
                      ],
                      fallbackImage: widget.item?.posterUrl ?? '',
                      currentIndex: episodes.indexWhere((e) => e.number == _currentEpNumber),
                      onTap: (i) {
                        final ep = episodes[i];
                        if (ep.number == _currentEpNumber) return;
                        setState(() {
                          _currentWatchUrl = ep.url;
                          _currentTitle = ep.title;
                          _currentEpNumber = ep.number;
                        });
                        _loadAndPlayStream(ep.url);
                      },
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
