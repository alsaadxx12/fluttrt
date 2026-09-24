import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// One of everything the app draws, drawn once behind the splash logo.
///
/// The renderer compiles a program for each kind of drawing the first time
/// it meets it - a blur, a gradient inside a rounded clip, a shadow, a
/// scaled picture - and that compile lands in the middle of whatever frame
/// asked for it: the first swipe of the home page used to pay for all of
/// them at once. Here they are paid for while the logo animates, where a
/// late frame is invisible. Almost transparent, so nothing shows, but not
/// invisible: an [Offstage] widget is never painted and compiles nothing.
class ShaderPrimer extends StatelessWidget {
  const ShaderPrimer({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: 0.01,
        child: Stack(
          children: [
            // A gradient under a blur, inside a rounded clip: the glass.
            Positioned(
              left: 10,
              top: 10,
              width: 140,
              height: 90,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Colors.white30, Colors.white10]),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white38, width: 0.8),
                      boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 18, offset: Offset(0, 6))],
                    ),
                  ),
                ),
              ),
            ),
            // A blurred picture-like box, and a scaled one: the wide cards
            // and the zoomed players.
            Positioned(
              left: 10,
              top: 120,
              width: 100,
              height: 60,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 22, sigmaY: 22, tileMode: TileMode.mirror),
                child: const ColoredBox(color: Colors.red),
              ),
            ),
            Positioned(
              left: 130,
              top: 120,
              width: 60,
              height: 60,
              child: Transform.scale(
                scale: 1.3,
                child: const DecoratedBox(
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.red),
                ),
              ),
            ),
            // Text with a shadow, a red pill, a spinner.
            const Positioned(
              left: 10,
              top: 200,
              child: Text(
                'CINEBALL',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                ),
              ),
            ),
            Positioned(
              left: 10,
              top: 240,
              child: Material(
                color: Colors.red,
                shape: const StadiumBorder(),
                elevation: 4,
                child: const SizedBox(width: 80, height: 32),
              ),
            ),
            const Positioned(
              left: 120,
              top: 240,
              child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
            ),
          ],
        ),
      ),
    );
  }
}
