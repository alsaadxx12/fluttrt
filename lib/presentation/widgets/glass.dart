import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';

/// A pane of frosted glass.
///
/// The page shows through a deep blur, under a sheen that brightens
/// towards the top-left, inside a thin light edge, with a brighter line
/// along the top where the light catches the pane. Every panel that is
/// not a picture - a settings card, the story on a profile, a sheet - is
/// one of these, so the whole app is cut from the same glass.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = 12,
    this.padding,
    this.margin,
    this.blur = 24,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      margin: margin,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(radius), boxShadow: p.glassShadow),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAliasWithSaveLayer,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Stack(
            children: [
              Container(
                width: double.infinity,
                padding: padding,
                decoration: BoxDecoration(
                  gradient: p.glass,
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(color: p.glassEdge, width: 0.8),
                ),
                child: child,
              ),
              // The catch of light along the top edge.
              Positioned(
                top: 0,
                left: radius,
                right: radius,
                height: 1,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.transparent, p.glassHighlight, Colors.transparent],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A bottom sheet of the same glass: the page shows through it, under the
/// deep tint the drawer uses, with a bright line along its rounded top.
class GlassSheet extends StatelessWidget {
  const GlassSheet({super.key, required this.child, this.height, this.padding});

  final Widget child;
  final double? height;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAliasWithSaveLayer,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: p.glassSheet,
            ),
            border: Border(top: BorderSide(color: p.glassHighlight, width: 0.8)),
          ),
          child: child,
        ),
      ),
    );
  }
}
