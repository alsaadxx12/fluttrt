import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../data/trailer_stream_resolver.dart';

/// Our own trailer player: no YouTube iframe, so no embed error 152.
///
/// Official studio trailers routinely restrict embedding to their own domains,
/// which is what made the iframe player return 4-152 for every trailer. This
/// instead resolves the trailer's actual muxed stream (video + audio) and
/// plays it through the platform player (ExoPlayer on Android). The stream URL
/// comes from a shared cache, so a trailer that was prewarmed starts at once.
/// The video fills its card (BoxFit.cover). Phone only, matching the showcase.
class InlineTrailerPlayer extends StatefulWidget {
  final String videoId;

  /// Whether the video runs. Flipping it pauses or resumes the player in
  /// place; the stream stays resolved and buffered, so resuming is instant.
  final bool playing;

  /// Called when this trailer cannot be played (no stream, or init failed),
  /// so a feed can skip past it.
  final VoidCallback? onFailed;

  /// Called when this trailer finishes playback, allowing the feed to
  /// automatically advance to the next trailer card.
  final VoidCallback? onEnded;

  const InlineTrailerPlayer({
    super.key,
    required this.videoId,
    this.playing = true,
    this.onFailed,
    this.onEnded,
  });

  @override
  State<InlineTrailerPlayer> createState() => _InlineTrailerPlayerState();
}

class _InlineTrailerPlayerState extends State<InlineTrailerPlayer> {
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _endedFired = false;

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
      // If onEnded is configured, do not loop so we can detect completion
      final shouldLoop = widget.onEnded == null;
      await controller.setLooping(shouldLoop);
      controller.addListener(_onVideoChanged);

      // `widget` is read after the awaits, so a flip during init is honoured.
      if (widget.playing) await controller.play();
      if (!mounted) {
        controller.removeListener(_onVideoChanged);
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (_) {
      // A card that is already gone (scrolled past, or the row rebuilt) must
      // not report a failure: the feed would skip whatever is fronted now.
      if (!mounted) return;
      setState(() => _failed = true);
      widget.onFailed?.call();
    }
  }

  void _onVideoChanged() {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _endedFired || widget.onEnded == null) return;
    final duration = c.value.duration;
    final position = c.value.position;
    if (duration > Duration.zero) {
      final nearEnd = position >= duration - const Duration(milliseconds: 250);
      final stoppedAtEnd = !c.value.isPlaying &&
          position >= duration - const Duration(milliseconds: 600) &&
          position > Duration.zero;
      if (nearEnd || stoppedAtEnd) {
        _endedFired = true;
        widget.onEnded?.call();
      }
    }
  }

  @override
  void didUpdateWidget(InlineTrailerPlayer old) {
    super.didUpdateWidget(old);
    if (old.videoId != widget.videoId) {
      _endedFired = false;
    }
    if (old.playing == widget.playing) return;
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (widget.playing) {
      c.play();
    } else {
      c.pause();
    }
  }

  @override
  void dispose() {
    final c = _controller;
    c?.removeListener(_onVideoChanged);
    c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (c != null && c.value.isInitialized)
            // Fill the card completely, cropping the edges rather than
            // letterboxing.
            FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: c.value.size.width,
                height: c.value.size.height,
                child: VideoPlayer(c),
              ),
            )
          else if (_failed)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'تعذّر تشغيل هذا الإعلان',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            )
          else
            const Align(
              alignment: Alignment.bottomCenter,
              child: LinearProgressIndicator(
                minHeight: 3,
                backgroundColor: Colors.white10,
                valueColor: AlwaysStoppedAnimation(Color(0xFFE50914)),
              ),
            ),
        ],
      ),
    );
  }
}
