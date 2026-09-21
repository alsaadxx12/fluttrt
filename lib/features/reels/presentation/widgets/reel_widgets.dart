import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:youtube_downloader/core/network/image_cache.dart';
import 'package:youtube_downloader/features/reels/data/reel_text.dart';
import 'package:youtube_downloader/features/reels/data/reels_service.dart';

/// The direction a reel's title should run in: left-to-right when it opens
/// with Latin letters, otherwise whatever the page uses.
TextDirection? reelTextDirection(String text) => reelStartsLatin(text) ? TextDirection.ltr : null;

/// A clock for the scrubber's chip: «m:ss» (`0:12`, `1:45`), and «h:mm:ss»
/// once past an hour. Never negative.
String reelClock(Duration d) {
  if (d < Duration.zero) d = Duration.zero;
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

/// [to] held within the clip: never before the start, and never past
/// [total] once the length is known (zero means it is not yet).
Duration reelClampSeek(Duration to, Duration total) {
  if (to < Duration.zero) return Duration.zero;
  if (total > Duration.zero && to > total) return total;
  return to;
}

/// Which third of a frame [width] wide a double tap at [dx] landed in:
/// -1 the left third (back), 1 the right third (forward), 0 the middle
/// (the like) — and 0 whenever the width is unknown.
int reelSeekZone(double dx, double width) {
  if (width <= 0) return 0;
  if (dx < width / 3) return -1;
  if (dx > width * 2 / 3) return 1;
  return 0;
}

/// The quality chip's text for a picture of [quality] — its shorter side as
/// YouTube labels it, 1080 for a vertical 1080×1920 clip: «1080p», «1440p»
/// — and null while the quality is unknown (null or not positive), when no
/// chip shows.
String? reelQualityLabel(int? quality) => quality == null || quality <= 0 ? null : '${quality}p';

/// How tall the seek bar's touch strip is: a finger's width above the foot
/// of the page, all of it taking touches for the line through its middle.
const double kReelSeekBarHeight = 44;

/// The seek bar's measures, and where its parts sit in a strip [width]
/// wide: the touch strip is [stripHeight] tall with the line through its
/// middle, [line] thick at rest and [lineTouched] while touched, when the
/// [thumb] shows on it and the time chip above.
///
/// Positions run left to right whatever the page's direction: the clip
/// starts at the left. Pure, for the tests.
class ReelSeekBarGeometry {
  const ReelSeekBarGeometry(this.width);

  /// The strip's width; zero or less while unknown, when everything sits at
  /// the start.
  final double width;

  static const double stripHeight = kReelSeekBarHeight;
  static const double line = 3;
  static const double lineTouched = 8;
  static const double thumb = 16;

  /// The share of the clip a touch [dx] from the strip's left edge means,
  /// 0..1 — clamped, so a finger past either end holds the end.
  double fractionAt(double dx) => width <= 0 ? 0 : (dx / width).clamp(0.0, 1.0);

  /// The thumb's left edge for [fraction] of the clip: centred on the point,
  /// but never over either end of the strip.
  double thumbLeft(double fraction) {
    final f = fraction.clamp(0.0, 1.0);
    final maxLeft = (width - thumb).clamp(0.0, double.infinity);
    return (f * width - thumb / 2).clamp(0.0, maxLeft);
  }

  /// Where the thumb's centre sits for [fraction].
  double thumbCentre(double fraction) => thumbLeft(fraction) + thumb / 2;

  /// The left edge of a [chipWidth]-wide slot centred over the thumb, held
  /// inside the strip.
  double chipLeft(double fraction, double chipWidth) {
    final maxLeft = (width - chipWidth).clamp(0.0, double.infinity);
    return (thumbCentre(fraction) - chipWidth / 2).clamp(0.0, maxLeft);
  }
}

/// The tiny quality chip beside the kind pill: «1080p» (the picture's
/// actual quality, see [reelQualityLabel]) on a faint outlined box; nothing
/// at all while the quality is unknown.
class ReelQualityChip extends StatelessWidget {
  const ReelQualityChip({super.key, required this.quality});

  final int? quality;

  @override
  Widget build(BuildContext context) {
    final label = reelQualityLabel(quality);
    if (label == null) return const SizedBox.shrink();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x2EFFFFFF),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: Colors.white60, width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Text(
          label,
          textDirection: TextDirection.ltr,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            height: 1.2,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// The seek bar at the foot of a reel.
///
/// A [kReelSeekBarHeight]-tall touch strip with a line through its middle
/// — always there, 3 px: the played share in white, the buffered share in
/// faint white over a fainter track, filling from the left whatever the
/// page's direction. A touch anywhere in the strip grows the line to 8 px,
/// puts a 16 px white thumb where the finger is and the time («0:12 /
/// 0:58», always left-to-right) in a chip centred above it; the finger
/// moving scrubs, lifting seeks there, and a tap seeks to its point.
///
/// The page owns the touch: [touched] is the fraction under the finger
/// (null the rest of the time), which it sets from [onTouchDown] and
/// [onTouchMove] — pausing the clip meanwhile — and clears from [onTouchUp]
/// (the seek, then play) and [onTouchCancel]. The strip claims every drag
/// that starts in it, sideways or not, so a scrub never turns into a page
/// swipe.
class ReelSeekBar extends StatefulWidget {
  const ReelSeekBar({
    super.key,
    required this.played,
    required this.buffered,
    required this.duration,
    required this.touched,
    required this.onTouchDown,
    required this.onTouchMove,
    required this.onTouchUp,
    required this.onTouchCancel,
  });

  /// How much of the clip has played, 0..1.
  final ValueListenable<double> played;

  /// How much of the clip is buffered, 0..1.
  final ValueListenable<double> buffered;

  /// The clip's length; zero while unknown.
  final ValueListenable<Duration> duration;

  /// The fraction under the finger while the strip is touched; null the
  /// rest of the time.
  final ValueListenable<double?> touched;

  final ValueChanged<double> onTouchDown;
  final ValueChanged<double> onTouchMove;
  final ValueChanged<double> onTouchUp;
  final VoidCallback onTouchCancel;

  /// The slot the time chip is centred in.
  static const double chipSlot = 112;

  @override
  State<ReelSeekBar> createState() => _ReelSeekBarState();
}

class _ReelSeekBarState extends State<ReelSeekBar> {
  /// True from a drag's start to its end or cancel.
  bool _dragging = false;

  ReelSeekBarGeometry get _geometry {
    final box = context.findRenderObject() as RenderBox?;
    return ReelSeekBarGeometry(box != null && box.hasSize ? box.size.width : 0);
  }

  double _fractionAtGlobal(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return 0;
    return _geometry.fractionAt(box.globalToLocal(global).dx);
  }

  void _onTapDown(TapDownDetails d) => widget.onTouchDown(_geometry.fractionAt(d.localPosition.dx));

  void _onTapUp(TapUpDetails d) => widget.onTouchUp(_geometry.fractionAt(d.localPosition.dx));

  /// The tap gave way — to this strip's own drag, which starts in the same
  /// event and keeps the touch, or to something else, which ends it. Told
  /// apart a microtask later, once the drag has had its chance to start.
  void _onTapCancel() {
    Future.microtask(() {
      if (mounted && !_dragging) widget.onTouchCancel();
    });
  }

  /// One finger scrubs; a second landing in the strip meanwhile is let go
  /// (null: the recognizer drops that pointer), so the two never fight over
  /// the thumb or end the scrub twice.
  Drag? _onDragStart(Offset global) {
    if (_dragging) return null;
    _dragging = true;
    widget.onTouchDown(_fractionAtGlobal(global));
    return _SeekDrag(
      from: global,
      onMove: (at) => widget.onTouchMove(_fractionAtGlobal(at)),
      onEnd: (at) {
        _dragging = false;
        widget.onTouchUp(_fractionAtGlobal(at));
      },
      onCancel: () {
        _dragging = false;
        widget.onTouchCancel();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: <Type, GestureRecognizerFactory>{
        // The tap first: it is what wins a touch that never moved.
        TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
          () => TapGestureRecognizer(debugOwner: this),
          (r) => r
            ..onTapDown = _onTapDown
            ..onTapUp = _onTapUp
            ..onTapCancel = _onTapCancel,
        ),
        ImmediateMultiDragGestureRecognizer: GestureRecognizerFactoryWithHandlers<ImmediateMultiDragGestureRecognizer>(
          () => ImmediateMultiDragGestureRecognizer(debugOwner: this),
          (r) => r.onStart = _onDragStart,
        ),
      },
      child: SizedBox(
        height: ReelSeekBarGeometry.stripHeight,
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) => ListenableBuilder(
            listenable: Listenable.merge([widget.played, widget.buffered, widget.duration, widget.touched]),
            builder: (_, __) => _SeekBarPaint(
              geometry: ReelSeekBarGeometry(constraints.maxWidth.isFinite ? constraints.maxWidth : 0),
              played: widget.played.value,
              buffered: widget.buffered.value,
              duration: widget.duration.value,
              touched: widget.touched.value,
            ),
          ),
        ),
      ),
    );
  }
}

/// One finger's drag along the strip: where it is, from the start plus
/// every delta since (the recognizer's first report carries the touch-down
/// point, not the finger's).
class _SeekDrag extends Drag {
  _SeekDrag({required Offset from, required this.onMove, required this.onEnd, required this.onCancel}) : _at = from;

  final ValueChanged<Offset> onMove;
  final ValueChanged<Offset> onEnd;
  final VoidCallback onCancel;
  Offset _at;

  @override
  void update(DragUpdateDetails details) {
    _at += details.delta;
    onMove(_at);
  }

  @override
  void end(DragEndDetails details) => onEnd(_at);

  @override
  void cancel() => onCancel();
}

/// The seek bar's picture: the line, and while touched the thumb and the
/// chip.
class _SeekBarPaint extends StatelessWidget {
  const _SeekBarPaint({
    required this.geometry,
    required this.played,
    required this.buffered,
    required this.duration,
    required this.touched,
  });

  final ReelSeekBarGeometry geometry;
  final double played;
  final double buffered;
  final Duration duration;
  final double? touched;

  @override
  Widget build(BuildContext context) {
    final f = (touched ?? played).clamp(0.0, 1.0);
    final isTouched = touched != null;
    final lineHeight = isTouched ? ReelSeekBarGeometry.lineTouched : ReelSeekBarGeometry.line;
    const thumb = ReelSeekBarGeometry.thumb;
    const strip = ReelSeekBarGeometry.stripHeight;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              height: lineHeight,
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(ReelSeekBarGeometry.lineTouched / 2),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: buffered.clamp(0.0, 1.0),
                      heightFactor: 1,
                      child: const ColoredBox(color: Colors.white38),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: f,
                      heightFactor: 1,
                      child: const ColoredBox(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: geometry.thumbLeft(f),
          top: (strip - thumb) / 2,
          child: AnimatedScale(
            scale: isTouched ? 1 : 0,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: const SizedBox(
              width: thumb,
              height: thumb,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 4)],
                ),
              ),
            ),
          ),
        ),
        if (isTouched)
          Positioned(
            left: geometry.chipLeft(f, ReelSeekBar.chipSlot),
            width: ReelSeekBar.chipSlot,
            bottom: strip / 2 + thumb / 2 + 6,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xB3000000),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    '${reelClock(duration * f)} / ${reelClock(duration)}',
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A reel's vertical thumbnail; when YouTube has no vertical frame for it
/// the ordinary 16:9 one is drawn instead. Zero fades, decoded at [width]
/// logical pixels, from the shared image cache. Drawn [fit] — the player
/// asks for `contain`, whole like the clip over it, so nothing jumps when
/// the first frame arrives; a grid cell keeps `cover`.
class ReelPoster extends StatelessWidget {
  const ReelPoster({
    super.key,
    required this.reel,
    required this.width,
    this.fit = BoxFit.cover,
    this.placeholderColor = Colors.black,
  });

  final Reel reel;
  final double width;
  final BoxFit fit;

  /// What shows before the picture arrives (and if it never does): black on
  /// the player, the page's skeleton tone in a grid.
  final Color placeholderColor;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final memWidth = (width * dpr).round().clamp(64, 2160);
    final blank = ColoredBox(color: placeholderColor);
    Widget image(String url, {Widget Function(BuildContext, String, Object)? errorWidget}) => CachedNetworkImage(
          imageUrl: url,
          cacheManager: appImageCache,
          fit: fit,
          memCacheWidth: memWidth,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          placeholderFadeInDuration: Duration.zero,
          useOldImageOnUrlChange: true,
          placeholder: (_, __) => blank,
          errorWidget: errorWidget ?? (_, __, ___) => blank,
        );
    return image(
      reel.thumbnailUrl,
      errorWidget: (_, __, ___) => image(reel.fallbackThumbnailUrl),
    );
  }
}
