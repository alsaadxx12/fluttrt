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

  /// Page background — deep pitch black everywhere.
  Color get bg => const Color(0xFF04060A);

  /// Cards, tiles, sheets — sleek cinematic dark surface.
  Color get card => const Color(0xFF0D121D);

  /// A quieter surface (inputs, chips, secondary panels).
  Color get cardAlt => const Color(0xFF131926);

  /// Loading placeholders.
  Color get skeleton => const Color(0xFF1A2232);

  /// The edge of a surface. Subtle hairline border.
  Color get border => Colors.white.withOpacity(0.08);

  /// A real separator.
  Color get divider => Colors.white.withOpacity(0.08);

  Color get text => Colors.white;
  Color get textMuted => const Color(0xFF94A3B8);
  Color get textFaint => Colors.white38;

  /// Icons on cards and bars.
  Color get icon => Colors.white;

  /// The corner every surface should use, so nothing looks hand-rolled.
  double get radius => 18;

  /// Card elevation: soft deep shadow.
  List<BoxShadow> get cardShadow => [
        BoxShadow(color: Colors.black.withOpacity(0.40), blurRadius: 24, offset: const Offset(0, 8)),
        BoxShadow(color: Colors.black.withOpacity(0.20), blurRadius: 6, offset: const Offset(0, 2)),
      ];
}
