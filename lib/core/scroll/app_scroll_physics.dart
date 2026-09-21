import 'dart:ui';
import 'package:flutter/material.dart';

/// Unified ultra-smooth scroll physics modeled after modern fluid feeds (TikTok, Facebook, Instagram).
///
/// Features:
/// 1. Natural momentum: Smooth gliding velocity that continues naturally after lifting the finger.
/// 2. Controlled subtle boundary spring: Elegant, tight edge behavior without exaggerated bouncy snaps.
/// 3. Cross-platform consistency: Identical silky feel across Android, iOS, Windows, and Web.
class AppScrollPhysics extends BouncingScrollPhysics {
  const AppScrollPhysics({
    super.parent,
    super.decelerationRate = ScrollDecelerationRate.normal,
  });

  @override
  AppScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return AppScrollPhysics(
      parent: buildParent(ancestor),
      decelerationRate: decelerationRate,
    );
  }

  /// Refined spring description for fluid, responsive, silky-smooth scrolling without lag or heavy drag
  @override
  SpringDescription get spring => const SpringDescription(
        mass: 0.8,
        stiffness: 100.0,
        damping: 1.1,
      );
}

/// Global standard scroll physics instance with guaranteed refreshability
const ScrollPhysics kAppDefaultScrollPhysics = AppScrollPhysics(
  parent: AlwaysScrollableScrollPhysics(),
);

/// Application-wide scroll behavior setting the default physics and input devices.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return kAppDefaultScrollPhysics;
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
