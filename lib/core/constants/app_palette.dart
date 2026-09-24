import 'package:flutter/material.dart';

/// Surface, text, glass and shadow colours for the current theme, so cards
/// and sections follow day and night mode instead of hard-coding one.
///
/// Night is pitch black with panels of frosted glass: a faint white sheen
/// over a deep blur, under a thin light edge. Day is the same glass on a
/// pale page: panels are milky white, their edge brighter still, and text
/// and icons a deep navy. Every widget asks this class rather than picking
/// a colour, so the two modes stay one design.
class AppPalette {
  final bool isDark;

  const AppPalette._(this.isDark);

  factory AppPalette.of(BuildContext context) => AppPalette._(Theme.of(context).brightness == Brightness.dark);

  const AppPalette.dark() : isDark = true;
  const AppPalette.light() : isDark = false;

  /// Page background: deep pitch black, or a pale cool grey by day.
  Color get bg => isDark ? const Color(0xFF04060A) : const Color(0xFFEEF1F6);

  /// Cards, tiles, sheets.
  Color get card => isDark ? const Color(0xFF0D121D) : Colors.white;

  /// A quieter surface (inputs, chips, secondary panels).
  Color get cardAlt => isDark ? const Color(0xFF131926) : const Color(0xFFF4F6FA);

  /// Loading placeholders.
  Color get skeleton => isDark ? const Color(0xFF1A2232) : const Color(0xFFE2E6EE);

  /// The edge of a surface. Subtle hairline border.
  Color get border => isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08);

  /// A real separator.
  Color get divider => border;

  Color get text => isDark ? Colors.white : const Color(0xFF0F172A);
  Color get textMuted => isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  Color get textFaint => isDark ? Colors.white38 : Colors.black38;

  /// Icons on cards and bars.
  Color get icon => text;

  /// The corner every surface should use, so nothing looks hand-rolled.
  double get radius => 18;

  /// Card elevation: soft deep shadow by night, a whisper of one by day.
  List<BoxShadow> get cardShadow => isDark
      ? [
          BoxShadow(color: Colors.black.withOpacity(0.40), blurRadius: 24, offset: const Offset(0, 8)),
          BoxShadow(color: Colors.black.withOpacity(0.20), blurRadius: 6, offset: const Offset(0, 2)),
        ]
      : [
          BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 24, offset: const Offset(0, 8)),
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2)),
        ];

  // ---------------------------------------------------------------- glass

  /// The sheen of a glass panel where it is brightest (top-left).
  Color get glassTop => Colors.white.withOpacity(isDark ? 0.20 : 0.94);

  /// The sheen of a glass panel where it fades (bottom-right).
  Color get glassBottom => Colors.white.withOpacity(isDark ? 0.06 : 0.72);

  /// The thin edge around a glass panel: a catch of light by night, a
  /// fine slate line by day (white on a white page is no edge at all).
  Color get glassEdge => isDark ? Colors.white.withOpacity(0.30) : const Color(0xFF0F172A).withOpacity(0.11);

  /// The bright line along the top of a pane, where light catches the edge.
  Color get glassHighlight => Colors.white.withOpacity(isDark ? 0.45 : 1.0);

  /// The shadow a pane of glass throws on the page: a close one that
  /// seats it and a soft one that lifts it. By day both are faint, so the
  /// edge stays the pane's own line and not a grey smear under it.
  List<BoxShadow> get glassShadow => isDark
      ? [
          BoxShadow(color: Colors.black.withOpacity(0.45), blurRadius: 18, offset: const Offset(0, 6)),
        ]
      : [
          BoxShadow(color: const Color(0xFF0F172A).withOpacity(0.05), blurRadius: 2, offset: const Offset(0, 1)),
          BoxShadow(color: const Color(0xFF0F172A).withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 8)),
        ];

  /// The panel's sheen as a gradient, ready for a [BoxDecoration].
  LinearGradient get glass => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [glassTop, glassBottom],
      );

  /// A control on the page or on glass - a chip, a tab, a round button;
  /// [selected] is the brighter one by night and the deeper one by day.
  Color glassFill({bool selected = false}) => isDark
      ? Colors.white.withOpacity(selected ? 0.22 : 0.08)
      : (selected ? Colors.black.withOpacity(0.10) : Colors.white.withOpacity(0.62));

  /// The edge of a [glassFill] control.
  Color glassFillEdge({bool selected = false}) =>
      isDark ? Colors.white.withOpacity(selected ? 0.35 : 0.14) : Colors.black.withOpacity(selected ? 0.16 : 0.07);

  /// Secondary words on glass: the unselected tab, a caption.
  Color get onGlassMuted => isDark ? Colors.white70 : const Color(0xFF475569);

  /// A whole sheet of glass (the drawer, the sidebar), top to bottom.
  List<Color> get glassSheet =>
      isDark ? const [Color(0xCC0A0D14), Color(0xE0040609)] : const [Color(0xE6FFFFFF), Color(0xF0F1F4F9)];

  /// The edge of a [glassSheet].
  Color get glassSheetEdge => isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.08);

  /// A panel lying on a [glassSheet]: a lighter sheen by night, a
  /// slightly deeper one by day.
  List<Color> get panel => isDark
      ? [Colors.white.withOpacity(0.12), Colors.white.withOpacity(0.04)]
      : [Colors.black.withOpacity(0.05), Colors.black.withOpacity(0.02)];

  /// The edge of a [panel].
  Color get panelEdge => isDark ? Colors.white.withOpacity(0.16) : Colors.black.withOpacity(0.08);
}
