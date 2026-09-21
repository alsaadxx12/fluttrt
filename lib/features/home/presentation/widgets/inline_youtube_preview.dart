import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_downloader/core/network/image_cache.dart';
import 'package:youtube_downloader/features/trailers/data/trailer_stream_resolver.dart';

/// The YouTube card's own preview player.
///
/// No iframe, so none of YouTube's chrome: no giant play triangle over the
/// poster, no logo, no ad-hoc buttons. The video's direct stream is resolved
/// (and usually already prewarmed), then played by the platform player. The
/// poster stays under it until the first frame is ready, with a thin red
/// line at the foot while it loads. A tap pauses or resumes; a thin red
/// progress line sits at the bottom, with the time and a mute switch that
/// appear briefly after a tap.
class InlineYouTubePreview extends StatefulWidget {
  const InlineYouTubePreview({
    super.key,
    required this.videoId,
    required this.thumbnailUrl,
    this.onFailed,
  });

  final String videoId;
  final String thumbnailUrl;

  /// Called when no direct stream could be played, so the card can fall
  /// back to the embedded player.
  final VoidCallback? onFailed;

  @override
  State<InlineYouTubePreview> createState() => _InlineYouTubePreviewState();
}

class _InlineYouTubePreviewState extends State<InlineYouTubePreview> {
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _ended = false;
  bool _muted = false;
  bool _chromeVisible = false;
  Timer? _chromeTimer;
  IconData? _flashIcon;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final url = await TrailerStreamResolver.instance.resolve(widget.videoId);
      if (url == null) throw StateError('no stream');
      if (!mounted) return;
      final controller = VideoPlayerController.networkUrl(url);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      controller.addListener(_onTick);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
      widget.onFailed?.call();
    }
  }

  void _onTick() {
    final c = _controller;
    if (c == null || !mounted) return;
    final v = c.value;
    final ended = v.isInitialized && v.duration > Duration.zero && v.position >= v.duration && !v.isPlaying;
    if (ended != _ended) setState(() => _ended = ended);
  }

  void _showChrome() {
    _chromeTimer?.cancel();
    setState(() => _chromeVisible = true);
    _chromeTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _chromeVisible = false);
    });
  }

  void _flash(IconData icon) {
    _flashTimer?.cancel();
    setState(() => _flashIcon = icon);
    _flashTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _flashIcon = null);
    });
  }

  Future<void> _togglePlay() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    _showChrome();
    if (_ended) {
      await c.seekTo(Duration.zero);
      await c.play();
      _flash(Icons.play_arrow_rounded);
      return;
    }
    if (c.value.isPlaying) {
      await c.pause();
      _flash(Icons.pause_rounded);
    } else {
      await c.play();
      _flash(Icons.play_arrow_rounded);
    }
  }

  Future<void> _toggleMute() async {
    final c = _controller;
    if (c == null) return;
    _showChrome();
    _muted = !_muted;
    await c.setVolume(_muted ? 0 : 1);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _chromeTimer?.cancel();
    _flashTimer?.cancel();
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ready = c != null && c.value.isInitialized;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: ready ? _togglePlay : null,
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The poster stays until the first frame, and shows again at the end.
            if (!ready || _ended)
              CachedNetworkImage(
                imageUrl: widget.thumbnailUrl,
                cacheManager: appImageCache,
                fit: BoxFit.cover,
                memCacheWidth: 480,
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                placeholderFadeInDuration: Duration.zero,
                useOldImageOnUrlChange: true,
                placeholder: (_, __) => const SizedBox.shrink(),
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),
            if (ready && !_ended)
              FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: c.value.size.width,
                  height: c.value.size.height,
                  child: VideoPlayer(c),
                ),
              ),

            // While the stream is being fetched: only a thin red line.
            if (!ready && !_failed)
              const Align(
                alignment: Alignment.bottomCenter,
                child: LinearProgressIndicator(
                  minHeight: 3,
                  backgroundColor: Colors.white10,
                  valueColor: AlwaysStoppedAnimation(Color(0xFFE50914)),
                ),
              ),

            // At the end: a small replay hint, nothing else.
            if (_ended)
              Center(
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.replay_rounded, color: Colors.white, size: 24),
                ),
              ),

            // Brief feedback for a tap.
            if (_flashIcon != null)
              Center(
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_flashIcon, color: Colors.white, size: 28),
                ),
              ),

            if (ready) ...[
              // Time and mute, shown for a moment after a tap.
              if (_chromeVisible) ...[
                Positioned(
                  left: 8,
                  bottom: 10,
                  child: GestureDetector(
                    onTap: _toggleMute,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  bottom: 10,
                  child: ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: c,
                    builder: (_, v, __) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${_fmt(v.position)} / ${_fmt(v.duration)}',
                        // Times read left-to-right whatever the page direction.
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ],
              // The thin progress line at the very bottom, always.
              Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  height: 3,
                  child: VideoProgressIndicator(
                    c,
                    allowScrubbing: false,
                    padding: EdgeInsets.zero,
                    colors: const VideoProgressColors(
                      playedColor: Color(0xFFE50914),
                      bufferedColor: Colors.white30,
                      backgroundColor: Colors.white10,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
