import 'dart:math' as math;

import 'package:flutter/material.dart';

/// How far the picture is zoomed: 1 is the whole picture in its own shape
/// (bars and all), larger is closer in, cropped evenly all round.
///
/// Every player keeps one and wires its own tap layer to it: a pinch on
/// the picture zooms, a button jumps between the whole picture and one
/// that fills the screen.
class ZoomController extends ValueNotifier<double> {
  ZoomController() : super(1.0);

  static const double maxZoom = 3.0;

  double _start = 1.0;

  /// A pinch is beginning: remember where it starts from.
  void begin() => _start = value;

  /// A pinch has moved: [scale] is relative to where it began.
  void update(double scale) => value = (_start * scale).clamp(1.0, maxZoom);

  /// The zoom that makes a [aspect]-shaped picture fill a [boxW] by [boxH]
  /// box: the picture is first laid whole in the box, then grown until the
  /// box has no bars left.
  static double coverFor({required double boxW, required double boxH, required double aspect}) {
    if (boxW <= 0 || boxH <= 0 || aspect <= 0) return 1.0;
    final w = math.min(boxW, boxH * aspect);
    final h = w / aspect;
    return math.max(boxW / w, boxH / h).clamp(1.0, maxZoom);
  }

  /// Between the whole picture and one that fills the box.
  void toggle({required double boxW, required double boxH, required double aspect}) {
    final cover = coverFor(boxW: boxW, boxH: boxH, aspect: aspect);
    value = (value - 1.0).abs() < 0.02 ? cover : 1.0;
  }

  bool get isWhole => (value - 1.0).abs() < 0.02;
}

/// [child], zoomed as [zoom] says, about its middle, cut at the edges.
class Zoomed extends StatelessWidget {
  const Zoomed({super.key, required this.zoom, required this.child});

  final ZoomController zoom;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: ValueListenableBuilder<double>(
        valueListenable: zoom,
        builder: (_, value, child) => Transform.scale(scale: value, child: child),
        child: child,
      ),
    );
  }
}
