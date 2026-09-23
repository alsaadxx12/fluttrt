import 'dart:async';

import 'package:flutter/material.dart';
import 'package:youtube_downloader/presentation/widgets/pinch_zoom.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../../data/cinemana_subtitles.dart';
import '../../data/models/cinemana_models.dart';
import 'package:youtube_downloader/core/video/desktop_video.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';

/// How the viewer wants subtitles: on/off, text size and height on screen.
class SubtitleSettings {
  final bool on;

  /// Index into [scales].
  final int size;

  /// How far above the bottom the subtitles sit, as a share of the video
  /// height (0 = just above the bottom edge).
  final double lift;

  const SubtitleSettings({this.on = true, this.size = 2, this.lift = 0});

  /// Text height as a share of the video height.
  static const scales = [0.048, 0.056, 0.064, 0.074, 0.086, 0.1];
  static const maxLift = 0.75;
  static const liftStep = 0.05;

  bool get canShrink => size > 0;
  bool get canGrow => size < scales.length - 1;
  bool get canRaise => lift < maxLift - 0.001;
  bool get canLower => lift > 0.001;

  static const _kOn = 'cinemana_subs_on';
  static const _kSize = 'cinemana_sub_size';
  static const _kLift = 'cinemana_sub_lift';

  /// The viewer's saved choice (shared by every player in the app).
  static Future<SubtitleSettings> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      return SubtitleSettings(
        on: p.getBool(_kOn) ?? true,
        size: p.getInt(_kSize) ?? 2,
        lift: p.getDouble(_kLift) ?? 0,
      ).copyWith(); // clamps stored values
    } catch (_) {
      return const SubtitleSettings();
    }
  }

  Future<void> save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kOn, on);
      await p.setInt(_kSize, size);
      await p.setDouble(_kLift, lift);
    } catch (_) {}
  }

  SubtitleSettings copyWith({bool? on, int? size, double? lift}) => SubtitleSettings(
        on: on ?? this.on,
        size: (size ?? this.size).clamp(0, scales.length - 1),
        lift: (lift ?? this.lift).clamp(0.0, maxLift),
      );
}

/// The Cinemana video with its own controls, drawn by the app over the
/// native player: play/pause, ±10 s, seek bar, fullscreen, quality, and
/// Arabic subtitles the viewer can switch off, resize and move up or down.
/// The controls fade out a few seconds after the last touch.
class CinemanaPlayerView extends StatefulWidget {
  final VideoPlayerController? controller;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  final bool fullscreen;
  final VoidCallback onToggleFullscreen;
  final String title;

  final List<SubtitleCue>? cues;
  final SubtitleSettings subtitles;
  final ValueChanged<SubtitleSettings> onSubtitlesChanged;

  final List<CinemanaStreamFile> streams;
  final CinemanaStreamFile? selectedStream;
  final ValueChanged<CinemanaStreamFile> onQuality;
  final VoidCallback? onBack;

  const CinemanaPlayerView({
    super.key,
    required this.controller,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.fullscreen,
    required this.onToggleFullscreen,
    required this.title,
    required this.cues,
    required this.subtitles,
    required this.onSubtitlesChanged,
    required this.streams,
    required this.selectedStream,
    required this.onQuality,
    this.onBack,
  });

  @override
  State<CinemanaPlayerView> createState() => _CinemanaPlayerViewState();
}

class _CinemanaPlayerViewState extends State<CinemanaPlayerView> {
  static const _hideAfter = Duration(seconds: 3);
  static const _barHeight = 46.0;

  bool _controlsVisible = true;

  /// The whole picture at 1; a pinch on it zooms in, a button jumps to
  /// the zoom that fills the screen and back.
  final ZoomController _zoom = ZoomController();
  BoxConstraints? _lastBox;
  double _lastAr = 16 / 9;
  Timer? _hideTimer;
  double? _dragMs; // seek bar position while dragging
  bool _preview = false; // sample subtitle line after a settings change
  Timer? _previewTimer;
  Offset? _doubleTapAt;
  int _seekFlash = 0; // -1 / +1 briefly after a double-tap seek
  Timer? _seekFlashTimer;

  @override
  void initState() {
    super.initState();
    _zoom.addListener(_onZoom);
    widget.controller?.addListener(_onVideo);
    _scheduleHide();
  }

  @override
  void didUpdateWidget(CinemanaPlayerView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.removeListener(_onVideo);
      widget.controller?.addListener(_onVideo);
      _showControls();
    }
    final a = old.subtitles, b = widget.subtitles;
    if (b.on && (a.size != b.size || a.lift != b.lift || !a.on)) _flashPreview();
  }

  @override
  void dispose() {
    _zoom.removeListener(_onZoom);
    _zoom.dispose();
    widget.controller?.removeListener(_onVideo);
    _hideTimer?.cancel();
    _previewTimer?.cancel();
    _seekFlashTimer?.cancel();
    super.dispose();
  }

  bool _wasPlaying = false;

  void _onVideo() {
    final playing = widget.controller?.value.isPlaying ?? false;
    if (playing == _wasPlaying) return;
    _wasPlaying = playing;
    // Paused: keep the controls up. Playing again: let them fade.
    if (!mounted) return;
    setState(() {});
    if (playing) {
      _scheduleHide();
    } else {
      _hideTimer?.cancel();
      setState(() => _controlsVisible = true);
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideAfter, () {
      final playing = widget.controller?.value.isPlaying ?? false;
      if (mounted && playing && _dragMs == null) setState(() => _controlsVisible = false);
    });
  }

  void _showControls() {
    if (!mounted) return;
    setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  void _toggleControls() {
    if (_controlsVisible) {
      _hideTimer?.cancel();
      setState(() => _controlsVisible = false);
    } else {
      _showControls();
    }
  }

  /// Any press on a control keeps the controls up a little longer.
  void _act(VoidCallback action) {
    action();
    _showControls();
  }

  void _flashPreview() {
    setState(() => _preview = true);
    _previewTimer?.cancel();
    _previewTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _preview = false);
    });
  }

  void _setSubs(SubtitleSettings s) => _act(() => widget.onSubtitlesChanged(s));

  void _seekBy(int seconds) {
    final c = widget.controller;
    if (c == null || !c.value.isInitialized) return;
    final target = c.value.position + Duration(seconds: seconds);
    final max = c.value.duration;
    c.seekTo(target < Duration.zero ? Duration.zero : (target > max ? max : target));
  }

  void _onDoubleTap(double width) {
    final at = _doubleTapAt;
    if (at == null) return;
    final forward = at.dx > width / 2;
    _seekBy(forward ? 10 : -10);
    setState(() => _seekFlash = forward ? 1 : -1);
    _seekFlashTimer?.cancel();
    _seekFlashTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _seekFlash = 0);
    });
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final ready = c != null && c.value.isInitialized;
    // On a desktop the picture must be on screen while the stream opens, or
    // it never opens at all. The screen keeps redrawing it meanwhile, which is
    // when VideoPlayer picks up its texture (see desktop_video.dart).
    final showView = ready || (c != null && isDesktopVideo);
    return ColoredBox(
      color: Colors.black,
      child: LayoutBuilder(builder: (context, box) {
        _lastBox = box;
        if (c != null && c.value.aspectRatio > 0) _lastAr = c.value.aspectRatio;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (showView)
              Zoomed(
                zoom: _zoom,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: c.value.aspectRatio > 0 ? c.value.aspectRatio : 16 / 9,
                    child: VideoPlayer(c),
                  ),
                ),
              ),
            // Tap: show/hide controls. Double-tap a side: ±10 s.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleControls,
              onScaleStart: (_) => _zoom.begin(),
              onScaleUpdate: (d) => _zoom.update(d.scale),
              onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
              onDoubleTap: () => _onDoubleTap(box.maxWidth),
            ),
            if (_seekFlash != 0) _seekFlashBadge(box),
            if (ready) _subtitleLayer(c, box),
            if (widget.error != null)
              _errorView(widget.error!)
            else if (widget.loading || !ready)
              const Center(child: CircularProgressIndicator(color: Color(0xFFE50914)))
            else
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: c,
                builder: (_, v, __) {
                  if (v.hasError) return _errorView('انقطع الفيديو، اضغط لإعادة المحاولة');
                  return v.isBuffering && v.isPlaying
                      ? const Center(child: CircularProgressIndicator(color: Colors.white70))
                      : const SizedBox.shrink();
                },
              ),
            _controlsLayer(box, ready),
          ],
        );
      }),
    );
  }

  void _onZoom() {
    if (mounted) setState(() {});
  }

  void _toggleZoom() {
    final box = _lastBox;
    if (box == null) return;
    _zoom.toggle(boxW: box.maxWidth, boxH: box.maxHeight, aspect: _lastAr);
    _scheduleHide();
  }

  Widget _errorView(String message) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white70, size: 38),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 12.5),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: widget.onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE50914),
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );

  Widget _seekFlashBadge(BoxConstraints box) {
    final forward = _seekFlash > 0;
    return Positioned(
      top: 0,
      bottom: 0,
      left: forward ? null : box.maxWidth * 0.12,
      right: forward ? box.maxWidth * 0.12 : null,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
          child: Icon(
            forward ? Icons.forward_10_rounded : Icons.replay_10_rounded,
            color: Colors.white,
            size: 30,
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------- subtitles

  /// Lines on screen at [ms] (cues may overlap).
  String _cueAt(List<SubtitleCue> cues, int ms) {
    var lo = 0, hi = cues.length - 1, last = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (cues[mid].startMs <= ms) {
        last = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    final lines = <String>[];
    for (var i = last; i >= 0 && i > last - 4; i--) {
      if (cues[i].endMs > ms) lines.insert(0, cues[i].text);
    }
    return lines.join('\n');
  }

  Widget _subtitleLayer(VideoPlayerController c, BoxConstraints box) {
    final cues = widget.cues;
    final s = widget.subtitles;
    if (cues == null || !s.on) return const SizedBox.shrink();

    // The picture's own box inside the player (letterboxing aside), so the
    // subtitles sit on the video rather than on the black bars.
    final ar = c.value.aspectRatio > 0 ? c.value.aspectRatio : 16 / 9;
    // The picture's own box, as zoomed, so the subtitles sit on the video
    // rather than on the black bars (which shrink as the zoom grows).
    final videoH = ((box.maxWidth / ar).clamp(0.0, box.maxHeight) * _zoom.value).clamp(0.0, box.maxHeight);
    final barsH = (box.maxHeight - videoH) / 2;
    final fontSize = (videoH * SubtitleSettings.scales[s.size]).clamp(11.0, 46.0);
    var bottom = barsH + videoH * (0.045 + s.lift);
    // Out of the way of the seek bar while it is showing.
    if (_controlsVisible && bottom < _barHeight + 8) bottom = _barHeight + 8;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      left: box.maxWidth * 0.06,
      right: box.maxWidth * 0.06,
      bottom: bottom,
      child: ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: c,
        builder: (_, v, __) {
          var text = _cueAt(cues, v.position.inMilliseconds);
          if (text.isEmpty && _preview) text = 'هذا هو حجم ومكان الترجمة';
          if (text.isEmpty) return const SizedBox.shrink();
          // Drag the line itself up or down to move it.
          return GestureDetector(
            onTap: _toggleControls,
            onVerticalDragStart: (_) => _flashPreview(),
            onVerticalDragUpdate: (d) => widget.onSubtitlesChanged(
              widget.subtitles.copyWith(lift: widget.subtitles.lift - d.delta.dy / videoH),
            ),
            child: Center(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: fontSize * 0.5, vertical: fontSize * 0.14),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(fontSize * 0.3),
                ),
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                    shadows: const [Shadow(color: Colors.black, blurRadius: 3, offset: Offset(0, 1))],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // --------------------------------------------------------------- controls

  Widget _controlsLayer(BoxConstraints box, bool ready) {
    final c = widget.controller;
    return IgnorePointer(
      ignoring: !_controlsVisible,
      child: AnimatedOpacity(
        opacity: _controlsVisible ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Soft shade behind the top and bottom rows only.
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 64,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black54, Colors.transparent],
                    ),
                  ),
                ),
              ),
            ),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 72,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black54, Colors.transparent],
                    ),
                  ),
                ),
              ),
            ),
            _topRow(),
            if (ready && widget.error == null) _centerRow(c!),
            if (ready) Positioned(left: 0, right: 0, bottom: 0, child: _bottomRow(c!)),
          ],
        ),
      ),
    );
  }

  Widget _roundButton(IconData icon, VoidCallback? onTap, {double size = 22, String? tip}) {
    return IconButton(
      tooltip: tip,
      onPressed: onTap == null ? null : () => _act(onTap),
      icon: Icon(icon, size: size),
      color: Colors.white,
      disabledColor: Colors.white30,
      padding: const EdgeInsets.all(7),
      constraints: const BoxConstraints(),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _topRow() {
    final s = widget.subtitles;
    final hasSubs = widget.cues != null;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
          child: Row(
            children: [
              _roundButton(
                Icons.arrow_back_rounded,
                widget.onBack ?? () => Navigator.of(context).maybePop(),
                size: 24,
                tip: 'رجوع',
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
              if (hasSubs) ...[
                _roundButton(
                  s.on ? Icons.closed_caption_rounded : Icons.closed_caption_disabled_rounded,
                  () => widget.onSubtitlesChanged(s.copyWith(on: !s.on)),
                  tip: s.on ? 'إخفاء الترجمة' : 'إظهار الترجمة',
                ),
                if (s.on) ...[
                  _roundButton(
                      Icons.text_decrease_rounded, s.canShrink ? () => _setSubs(s.copyWith(size: s.size - 1)) : null,
                      tip: 'تصغير الخط'),
                  _roundButton(
                      Icons.text_increase_rounded, s.canGrow ? () => _setSubs(s.copyWith(size: s.size + 1)) : null,
                      tip: 'تكبير الخط'),
                  _roundButton(Icons.keyboard_arrow_down_rounded,
                      s.canLower ? () => _setSubs(s.copyWith(lift: s.lift - SubtitleSettings.liftStep)) : null,
                      tip: 'إنزال الترجمة'),
                  _roundButton(Icons.keyboard_arrow_up_rounded,
                      s.canRaise ? () => _setSubs(s.copyWith(lift: s.lift + SubtitleSettings.liftStep)) : null,
                      tip: 'رفع الترجمة'),
                ],
              ],
              if (widget.streams.length > 1) _qualityMenu(),
              if (widget.fullscreen)
                _roundButton(
                  _zoom.isWhole ? Icons.fit_screen_rounded : Icons.crop_free_rounded,
                  _toggleZoom,
                  size: 22,
                  tip: _zoom.isWhole ? 'ملء الشاشة' : 'الأبعاد الأصلية',
                ),
              _roundButton(
                widget.fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                widget.onToggleFullscreen,
                size: 24,
                tip: widget.fullscreen ? 'خروج من ملء الشاشة' : 'ملء الشاشة',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _qualityMenu() {
    return PopupMenuButton<CinemanaStreamFile>(
      tooltip: 'الجودة',
      icon: const Icon(Icons.high_quality_rounded, color: Colors.white, size: 24),
      onOpened: () => _hideTimer?.cancel(),
      onCanceled: _scheduleHide,
      onSelected: (q) => _act(() => widget.onQuality(q)),
      itemBuilder: (_) => [
        for (final q in widget.streams)
          CheckedPopupMenuItem(
            value: q,
            checked: q.resolution == widget.selectedStream?.resolution,
            child: Text(q.resolution),
          ),
      ],
    );
  }

  Widget _centerRow(VideoPlayerController c) {
    return Center(
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _roundButton(Icons.replay_10_rounded, () => _seekBy(-10), size: 36, tip: 'رجوع 10 ثوانٍ'),
            const SizedBox(width: 26),
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: c,
              builder: (_, v, __) {
                final isPlaying = v.isPlaying;
                return Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => _act(() {
                      if (isPlaying) {
                        c.pause();
                      } else {
                        c.play();
                      }
                    }),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Icon(
                        isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        size: 44,
                        color: Colors.white,
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 26),
            _roundButton(Icons.forward_10_rounded, () => _seekBy(10), size: 36, tip: 'تقديم 10 ثوانٍ'),
          ],
        ),
      ),
    );
  }

  static String _clock(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  Widget _bottomRow(VideoPlayerController c) {
    // Time runs left to right, as in every video player.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: _barHeight,
          child: ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: c,
            builder: (_, v, __) {
              final total = v.duration.inMilliseconds.toDouble();
              final pos = (_dragMs ?? v.position.inMilliseconds.toDouble()).clamp(0.0, total > 0 ? total : 0.0);
              final buffered = v.buffered.isEmpty ? 0.0 : v.buffered.last.end.inMilliseconds.toDouble();
              const timeStyle = TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600);
              return Row(
                children: [
                  const SizedBox(width: 6),
                  _roundButton(
                    v.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    () => _act(() {
                      if (v.isPlaying) {
                        c.pause();
                      } else {
                        c.play();
                      }
                    }),
                    size: 24,
                    tip: v.isPlaying ? 'إيقاف مؤقت' : 'تشغيل',
                  ),
                  const SizedBox(width: 4),
                  Text(_clock(Duration(milliseconds: pos.round())), style: timeStyle),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                        activeTrackColor: const Color(0xFFE50914),
                        inactiveTrackColor: Colors.white24,
                        secondaryActiveTrackColor: Colors.white54,
                        thumbColor: const Color(0xFFE50914),
                      ),
                      child: Slider(
                        min: 0,
                        max: total > 0 ? total : 1,
                        value: total > 0 ? pos : 0,
                        secondaryTrackValue: total > 0 ? buffered.clamp(0.0, total) : null,
                        onChangeStart: (x) {
                          _hideTimer?.cancel();
                          setState(() => _dragMs = x);
                        },
                        onChanged: (x) => setState(() => _dragMs = x),
                        onChangeEnd: (x) async {
                          await c.seekTo(Duration(milliseconds: x.round()));
                          if (mounted) setState(() => _dragMs = null);
                          _scheduleHide();
                        },
                      ),
                    ),
                  ),
                  Text(_clock(v.duration), style: timeStyle),
                  const SizedBox(width: 4),
                  if (widget.fullscreen)
                    _roundButton(
                      _zoom.isWhole ? Icons.fit_screen_rounded : Icons.crop_free_rounded,
                      _toggleZoom,
                      size: 24,
                      tip: _zoom.isWhole ? 'ملء الشاشة' : 'الأبعاد الأصلية',
                    ),
                  _roundButton(
                    widget.fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                    widget.onToggleFullscreen,
                    size: 26,
                    tip: widget.fullscreen ? 'خروج من ملء الشاشة' : 'ملء الشاشة',
                  ),
                  const SizedBox(width: 6),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Under the video: subtitles on/off, text size, and moving them up/down.
class SubtitleSettingsBar extends StatelessWidget {
  final SubtitleSettings settings;
  final ValueChanged<SubtitleSettings> onChanged;

  const SubtitleSettingsBar({super.key, required this.settings, required this.onChanged});

  Widget _button(IconData icon, String tip, VoidCallback? onTap, Color color) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      color: color,
      disabledColor: color.withOpacity(0.3),
      tooltip: tip,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(),
      visualDensity: VisualDensity.compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Colors.white : Colors.black87;
    final s = settings;
    const red = Color(0xFFE50914);
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF16161D) : Colors.white,
        border: isDark ? null : Border(bottom: BorderSide(color: AppPalette.of(context).border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(Icons.closed_caption_rounded, size: 16, color: red),
          const SizedBox(width: 6),
          const Text('الترجمة', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
          Transform.scale(
            scale: 0.72,
            child: Switch(
              value: s.on,
              onChanged: (v) => onChanged(s.copyWith(on: v)),
              activeColor: Colors.white,
              activeTrackColor: red,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const Spacer(),
          _button(Icons.text_decrease_rounded, 'تصغير الخط',
              s.on && s.canShrink ? () => onChanged(s.copyWith(size: s.size - 1)) : null, fg),
          _button(Icons.text_increase_rounded, 'تكبير الخط',
              s.on && s.canGrow ? () => onChanged(s.copyWith(size: s.size + 1)) : null, fg),
          Container(
            width: 1,
            height: 18,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            color: fg.withOpacity(0.15),
          ),
          _button(Icons.keyboard_arrow_down_rounded, 'إنزال الترجمة',
              s.on && s.canLower ? () => onChanged(s.copyWith(lift: s.lift - SubtitleSettings.liftStep)) : null, fg),
          _button(Icons.keyboard_arrow_up_rounded, 'رفع الترجمة',
              s.on && s.canRaise ? () => onChanged(s.copyWith(lift: s.lift + SubtitleSettings.liftStep)) : null, fg),
        ],
      ),
    );
  }
}
