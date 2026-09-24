import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';

/// A pane of frosted glass.
///
/// A sheen that brightens towards the top-left, inside a thin light edge,
/// with a brighter line along the top where the light catches the pane,
/// and a soft shadow on the page. Every panel that is not a picture - a
/// settings card, the story on a profile, a sheet - is one of these, so
/// the whole app is cut from the same glass.
///
/// No blur unless asked for with [blur]: the renderer runs a blur again on
/// every frame, and a pane that scrolls with its page would cost a blur of
/// the page per frame. The sheen, edge and light are what read as glass.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = 12,
    this.padding,
    this.margin,
    this.blur = 0,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  /// A backdrop blur, for a pane that sits still over something moving.
  final double blur;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final pane = Stack(
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
    );
    return Container(
      margin: margin,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(radius), boxShadow: p.glassShadow),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: blur > 0 ? BackdropFilter(filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur), child: pane) : pane,
      ),
    );
  }
}

/// A bottom sheet of the same glass: the deep tint the drawer uses, with a
/// bright line along its rounded top. No blur, for the reason above: what
/// scrolls inside it would cost a blur of the page on every frame.
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
      clipBehavior: Clip.antiAlias,
      child: Container(
        height: height,
        padding: padding,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.alphaBlend(p.glassSheet.first, p.bg),
              Color.alphaBlend(p.glassSheet.last, p.bg),
            ],
          ),
          border: Border(top: BorderSide(color: p.glassHighlight, width: 0.8)),
        ),
        child: child,
      ),
    );
  }
}
