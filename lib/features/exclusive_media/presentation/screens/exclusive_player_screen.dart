import 'dart:async';
import 'package:flutter/material.dart';
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
import '../../data/models/exclusive_media_models.dart';
import '../providers/exclusive_media_providers.dart';

class ExclusivePlayerScreen extends ConsumerStatefulWidget {
  final ExclusiveMediaItem? item;
  final String initialWatchUrl;
  final String title;
  final List<ExclusiveEpisode>? allEpisodes;
  final int? currentEpisodeNumber;

  const ExclusivePlayerScreen({
    super.key,
    this.item,
    required this.initialWatchUrl,
    required this.title,
    this.allEpisodes,
    this.currentEpisodeNumber,
  });

  @override
  ConsumerState<ExclusivePlayerScreen> createState() => _ExclusivePlayerScreenState();
}

class _ExclusivePlayerScreenState extends ConsumerState<ExclusivePlayerScreen> {
  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

  late String _currentWatchUrl;
  late String _currentTitle;
  int? _currentEpNumber;

  VideoPlayerController? _controller;
  bool _isLoading = true;
  String? _errorMessage;

  List<CinemanaStreamFile> _streams = const [];
  CinemanaStreamFile? _selectedStream;

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

  /// Resolves the watch page and automatically selects the highest resolution (1080p/720p),
  /// playing directly with zero ads and zero external server pickers.
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
      final service = ref.read(exclusiveServiceProvider);
      final streams = await service.resolveDirectStreams(watchUrl);

      if (!mounted || token != _streamToken) return;

      if (streams.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'لم يتم العثور على رابط مباشر متاح حالياً.';
        });
        return;
      }

      // Convert to CinemanaStreamFile format for player
      final cinemanaStreams = streams.map((s) {
        return CinemanaStreamFile(
          name: s.quality,
          resolution: s.quality,
          container: s.url.contains('.m3u8') ? 'hls' : 'mp4',
          videoUrl: s.url,
        );
      }).toList();

      final highestStream = cinemanaStreams.first;

      setState(() {
        _streams = cinemanaStreams;
        _selectedStream = highestStream;
      });

      await _startPlayback(highestStream.videoUrl, token: token);
    } catch (e) {
      if (!mounted || token != _streamToken) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'تعذر تحميل البث المباشر. يرجى المحاولة مرة أخرى.';
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
        'Referer': 'https://akwam.ss/',
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
        _errorMessage = 'تعذر تشغيل هذا المسار. يرجى إعادة المحاولة.';
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
      backgroundColor: const Color(0xFF04060A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF04060A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _currentTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.18),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4), width: 0.8),
                  ),
                  child: const Text(
                    'بدون إعلانات',
                    style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
                if (_selectedStream != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.primary.withOpacity(0.4), width: 0.8),
                    ),
                    child: Text(
                      _selectedStream!.resolution,
                      style: const TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
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
                  onBack: () => Navigator.of(context).pop(),
                ),
              ),
            ),

            // Episode navigation & details below player in portrait mode
            Expanded(
              child: Container(
                color: palette.bg,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    // Episode navigation bar
                    if (widget.allEpisodes != null && widget.allEpisodes!.isNotEmpty) ...[
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: hasPrev ? _playPreviousEpisode : null,
                              icon: const Icon(Icons.skip_previous_rounded, size: 18),
                              label: const Text('الحلقة السابقة'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(
                                  color: hasPrev ? Colors.white24 : Colors.white10,
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: hasNext ? _playNextEpisode : null,
                              icon: const Icon(Icons.skip_next_rounded, size: 18),
                              label: const Text('الحلقة التالية'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: hasNext ? AppColors.primary : Colors.white10,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Episodes quick list
                      Text(
                        'كافة الحلقات (${widget.allEpisodes!.length})',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 48,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: widget.allEpisodes!.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, idx) {
                            final ep = widget.allEpisodes![idx];
                            final isCurrent = ep.number == _currentEpNumber;
                            return ActionChip(
                              label: Text('حلقة ${ep.number}'),
                              labelStyle: TextStyle(
                                color: isCurrent ? Colors.white : Colors.white70,
                                fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w600,
                                fontSize: 12.5,
                              ),
                              backgroundColor: isCurrent ? AppColors.primary : const Color(0xFF141926),
                              side: BorderSide(
                                color: isCurrent ? AppColors.primary : Colors.white12,
                                width: 1,
                              ),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              onPressed: () {
                                if (isCurrent) return;
                                setState(() {
                                  _currentWatchUrl = ep.url;
                                  _currentTitle = ep.title;
                                  _currentEpNumber = ep.number;
                                });
                                _loadAndPlayStream(ep.url);
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
