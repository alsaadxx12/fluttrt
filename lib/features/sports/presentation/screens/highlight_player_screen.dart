import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../../trailers/data/trailer_stream_resolver.dart';

/// Plays one goals-summary reel full-screen, with a zoom (fit) toggle and
/// rotation to landscape for a true full-screen view.
class HighlightPlayerScreen extends StatefulWidget {
  final String videoId;
  final String title;
  const HighlightPlayerScreen({super.key, required this.videoId, required this.title});

  @override
  State<HighlightPlayerScreen> createState() => _HighlightPlayerScreenState();
}

class _HighlightPlayerScreenState extends State<HighlightPlayerScreen> {
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _controls = true;
  bool _zoom = false; // false: fit inside (contain); true: fill (cover)
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    // Allow landscape here for a proper full-screen highlight.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _start();
    _scheduleHide();
  }

  Future<void> _start() async {
    try {
      final url = await TrailerStreamResolver.instance.resolve(widget.videoId);
      if (url == null) throw StateError('no stream');
      if (!mounted) return;
      final c = VideoPlayerController.networkUrl(url);
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      await c.play();
      setState(() => _controller = c);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.dispose();
    // Restore the app's portrait-only orientation.
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controls = false);
    });
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _scheduleHide();
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null) return;
    setState(() => c.value.isPlaying ? c.pause() : c.play());
    _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (c != null && c.value.isInitialized)
              Center(
                child: _zoom
                    ? SizedBox.expand(
                        child: FittedBox(
                          fit: BoxFit.cover,
                          clipBehavior: Clip.hardEdge,
                          child: SizedBox(
                            width: c.value.size.width,
                            height: c.value.size.height,
                            child: VideoPlayer(c),
                          ),
                        ),
                      )
                    : AspectRatio(
                        aspectRatio: c.value.aspectRatio > 0 ? c.value.aspectRatio : 16 / 9,
                        child: VideoPlayer(c),
                      ),
              )
            else if (_failed)
              const Center(
                child: Text('تعذّر تشغيل هذا الملخّص',
                    style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w700)),
              )
            else
              const Center(child: CircularProgressIndicator(color: Color(0xFF00E0A1))),

            if (_controls) ..._overlay(c),
          ],
        ),
      ),
    );
  }

  List<Widget> _overlay(VideoPlayerController? c) => [
        // Dim so controls read on any frame.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xAA000000), Colors.transparent, Color(0xAA000000)],
              stops: [0.0, 0.5, 1.0],
            ),
          ),
        ),
        // Top bar: back + title + zoom toggle.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    tooltip: _zoom ? 'احتواء' : 'ملء الشاشة',
                    icon: Icon(_zoom ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded, color: Colors.white),
                    onPressed: () {
                      setState(() => _zoom = !_zoom);
                      _scheduleHide();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        // Center play/pause.
        if (c != null && c.value.isInitialized)
          Center(
            child: IconButton(
              iconSize: 62,
              icon: Icon(c.value.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                  color: Colors.white),
              onPressed: _togglePlay,
            ),
          ),
        // Bottom: scrubber + times.
        if (c != null && c.value.isInitialized)
          Positioned(
            left: 12,
            right: 12,
            bottom: 10,
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Text(_fmt(c.value.position), style: const TextStyle(color: Colors.white, fontSize: 12)),
                  Expanded(
                    child: VideoProgressIndicator(
                      c,
                      allowScrubbing: true,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                      colors: const VideoProgressColors(
                        playedColor: Color(0xFF00E0A1),
                        bufferedColor: Colors.white30,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                  ),
                  Text(_fmt(c.value.duration), style: const TextStyle(color: Colors.white, fontSize: 12)),
                ],
              ),
            ),
          ),
      ];

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${two(m)}:${two(s)}';
  }
}
