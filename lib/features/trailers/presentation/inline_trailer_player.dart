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
  const InlineTrailerPlayer({super.key, required this.videoId});

  @override
  State<InlineTrailerPlayer> createState() => _InlineTrailerPlayerState();
}

class _InlineTrailerPlayerState extends State<InlineTrailerPlayer> {
  VideoPlayerController? _controller;
  bool _failed = false;

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
      await controller.setLooping(true);
      await controller.play();
      setState(() => _controller = controller);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
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
