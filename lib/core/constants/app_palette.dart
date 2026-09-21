import 'package:flutter/material.dart';

/// Surface, text and shadow colours for the current theme, so cards and
/// sections follow light and dark mode instead of hard-coding dark colours.
///
/// Light mode is the app's look: a pure white page everywhere — top bar,
/// drawer, every screen — with white containers set apart by soft shadows
/// rather than by gray fills, deep navy text and the brand red for accents.
class AppPalette {
  final bool isDark;

  const AppPalette._(this.isDark);

  factory AppPalette.of(BuildContext context) => AppPalette._(Theme.of(context).brightness == Brightness.dark);

  /// Page background.
  Color get bg => isDark ? const Color(0xFF06080E) : Colors.white;

  /// Cards, tiles, sheets.
  ///
  /// A card is meant to read as the screen catching a little more light, not
  /// as a panel laid on top of it. So the separation comes from tone and a
  /// soft lift rather than from an outline: the border below is barely there,
  /// and the card sits only a step away from the page.
  Color get card => isDark ? const Color(0xFF111823) : Colors.white;

  /// A quieter surface (inputs, chips, secondary panels).
  Color get cardAlt => isDark ? const Color(0xFF0D131C) : Colors.white;

  /// Loading placeholders.
  Color get skeleton => isDark ? const Color(0xFF121927) : const Color(0xFFF1F3F6);

  /// The edge of a surface. Deliberately faint: at full strength it frames
  /// the card and breaks the illusion that it belongs to the screen.
  Color get border => isDark ? Colors.white.withOpacity(0.045) : const Color(0xFFE8ECF2);

  /// A real separator, for when two things genuinely need dividing.
  Color get divider => isDark ? Colors.white.withOpacity(0.07) : const Color(0xFFE3E9F3);

  Color get text => isDark ? Colors.white : const Color(0xFF0F172A);
  Color get textMuted => isDark ? Colors.white70 : const Color(0xFF475569);
  Color get textFaint => isDark ? Colors.white38 : const Color(0xFF94A3B8);

  /// Icons on cards and bars.
  Color get icon => isDark ? Colors.white : const Color(0xFF1E293B);

  /// The corner every surface should use, so nothing looks hand-rolled.
  double get radius => 18;

  /// Card elevation: light falling on a raised surface rather than a drop
  /// shadow behind a sticker. Wide and faint in both themes, with a close
  /// contact shadow in light mode to keep white cards from floating.
  List<BoxShadow> get cardShadow => isDark
      ? [
          BoxShadow(color: Colors.black.withOpacity(0.30), blurRadius: 24, offset: const Offset(0, 8)),
          BoxShadow(color: Colors.black.withOpacity(0.16), blurRadius: 6, offset: const Offset(0, 2)),
        ]
      // On a pure white page the shadow is what separates a container from
      // the page, so it is a little firmer than a mere lift.
      : const [
          BoxShadow(color: Color(0x140F172A), blurRadius: 4, offset: Offset(0, 1)),
          BoxShadow(color: Color(0x1F101828), blurRadius: 22, offset: Offset(0, 8)),
        ];
}
