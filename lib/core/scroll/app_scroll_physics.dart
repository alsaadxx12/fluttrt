import 'dart:ui';
import 'package:flutter/material.dart';

/// Ultra-smooth, responsive scroll physics providing natural momentum and 60fps/120fps fluid scrolling.
class AppScrollPhysics extends ScrollPhysics {
  const AppScrollPhysics({super.parent});

  @override
  AppScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return AppScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  SpringDescription get spring => SpringDescription.withDampingRatio(
        mass: 0.5,
        stiffness: 100.0,
        ratio: 1.1,
      );
}

/// Global standard scroll physics instance with guaranteed refreshability and frictionless fluid gliding.
/// On Android and Desktop, ClampingScrollPhysics ensures zero rubber-band resistance and eliminates gesture hitching.
const ScrollPhysics kAppDefaultScrollPhysics = ClampingScrollPhysics(
  parent: AlwaysScrollableScrollPhysics(),
);

/// Application-wide scroll behavior setting the default physics and input devices.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    switch (getPlatform(context)) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return kAppDefaultScrollPhysics;
    }
  }

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    // Disable unsightly Android glow/stretch effects in favor of clean edge physics
    return child;
  }

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}
