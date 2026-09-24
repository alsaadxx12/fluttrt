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

/// The app's red, caught in the glass: a soft bloom in the top corner of
/// a pane and a faint halo round it. [strong] for what is live now.
///
/// Wraps the pane's own clip, so the pane stays what it was; the bloom is
/// laid over it and lets every touch through.
class GlassGlow extends StatelessWidget {
  const GlassGlow({super.key, required this.child, required this.radius, this.strong = false});

  final Widget child;
  final double radius;
  final bool strong;

  static const Color _red = Color(0xFFE50914);

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: _red.withOpacity(strong ? 0.38 : 0.16),
            blurRadius: strong ? 22 : 16,
            spreadRadius: -2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const AlignmentDirectional(1.0, -1.0),
                      radius: strong ? 1.15 : 0.95,
                      colors: [
                        _red.withOpacity(strong ? 0.42 : 0.24),
                        _red.withOpacity(strong ? 0.12 : 0.06),
                        _red.withOpacity(0.0),
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
