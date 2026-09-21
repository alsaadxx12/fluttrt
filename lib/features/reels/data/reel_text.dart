/// Small pure helpers for the reels pages: counts the TikTok way and the
/// direction a line of text should run in. No Flutter imports, so they can
/// be unit-tested without a widget binding.
library;

/// `1.2K`, `3.4M`, `1.1B` — the compact count TikTok prints under its
/// buttons. Below a thousand the plain number; a trailing `.0` is dropped
/// (`12K`, not `12.0K`). Negative numbers are clamped to `0`.
String formatReelCount(int count) {
  if (count < 0) count = 0;
  if (count < 1000) return '$count';
  String scaled(double v, String suffix) {
    // One decimal below 10 (1.2K), none above (12K, 340K).
    final s = v < 10 ? v.toStringAsFixed(1) : v.round().toString();
    return '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s}$suffix';
  }

  if (count < 1000000) return scaled(count / 1000, 'K');
  if (count < 1000000000) return scaled(count / 1000000, 'M');
  return scaled(count / 1000000000, 'B');
}

/// True when the first strong (directional) character of [text] is a Latin
/// letter — such a title should run left-to-right even inside the RTL app.
/// Digits, punctuation, emoji and spaces are skipped over; a text with no
/// letters at all is not Latin.
bool reelStartsLatin(String text) {
  for (final rune in text.runes) {
    if (_isArabicOrHebrew(rune)) return false;
    if (_isLatinLetter(rune)) return true;
  }
  return false;
}

bool _isLatinLetter(int r) =>
    (r >= 0x41 && r <= 0x5A) ||
    (r >= 0x61 && r <= 0x7A) ||
    (r >= 0xC0 && r <= 0x24F && r != 0xD7 && r != 0xF7);

bool _isArabicOrHebrew(int r) =>
    (r >= 0x0590 && r <= 0x08FF) || // Hebrew, Arabic, Syriac, Thaana, Arabic supplement
    (r >= 0xFB1D && r <= 0xFDFF) || // presentation forms A
    (r >= 0xFE70 && r <= 0xFEFF); // presentation forms B

/// The first letter of [name] for an avatar circle; `?` when there is none.
String reelInitial(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '?';
  // Skip a leading '@' or other punctuation so «@channel» shows «C».
  for (final rune in trimmed.runes) {
    final ch = String.fromCharCode(rune);
    if (RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(ch)) return ch.toUpperCase();
  }
  return trimmed.substring(0, 1).toUpperCase();
}
