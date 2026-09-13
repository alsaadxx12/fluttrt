import '../data/models/sports_models.dart';

/// Picks the one match worth interrupting the viewer for when the app opens.
///
/// Only a match being played right now qualifies: a fixture hours away is
/// news, not an event. Among those, the ones that can actually be watched
/// come first, then the ones in a competition most people follow, and
/// finally the one furthest along, because a game in its closing stages is
/// the one you would regret missing.
class ImportantMatch {
  ImportantMatch._();

  /// Competitions worth a prompt. Matched loosely against the league name
  /// the feed supplies, in either language.
  static const majorLeagues = [
    'أبطال أوروبا', 'champions league',
    'الدوري الأوروبي', 'europa league',
    'الإنجليزي', 'premier league',
    'الإسباني', 'laliga', 'la liga',
    'الإيطالي', 'serie a',
    'الألماني', 'bundesliga',
    'الفرنسي', 'ligue 1',
    'كأس العالم', 'world cup',
    'أبطال آسيا', 'asian champions',
    'السعودي', 'saudi pro',
    'نجوم العراق', 'iraq stars',
    'أمم', 'nations', 'قارات', 'ديربي',
  ];

  static bool isMajor(String? league) {
    final l = (league ?? '').toLowerCase();
    if (l.isEmpty) return false;
    return majorLeagues.any((k) => l.contains(k.toLowerCase()));
  }

  static bool _watchable(SportMatchItem m) => m.hasWatch || m.streamId != null || (m.directUrl ?? '').isNotEmpty;

  /// How strongly this match deserves the prompt. Higher wins.
  static int score(SportMatchItem m) {
    if (!m.isLive) return -1;
    var s = 0;
    if (_watchable(m)) s += 100;
    if (isMajor(m.league)) s += 50;
    // Later in the game is more urgent, but never enough to beat a match
    // that can actually be watched.
    s += ((m.minute ?? 0).clamp(0, 120) ~/ 10);
    return s;
  }

  /// The match to announce, or null when nothing is worth interrupting for.
  static SportMatchItem? pick(List<SportMatchItem> matches) {
    SportMatchItem? best;
    var bestScore = 0;
    for (final m in matches) {
      final s = score(m);
      if (s > bestScore) {
        bestScore = s;
        best = m;
      }
    }
    return best;
  }

  /// The most important matches, best first, for the deck on the edge of
  /// the screen. Only matches being played right now are ever included.
  static List<SportMatchItem> pickTop(List<SportMatchItem> matches, {int limit = 6}) {
    final scored = <(int, SportMatchItem)>[];
    for (final m in matches) {
      final s = score(m);
      if (s > 0) scored.add((s, m));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final e in scored.take(limit)) e.$2];
  }

  /// The minute to show, e.g. "الدقيقة 63".
  static String minuteLabel(SportMatchItem m) {
    final min = m.minute;
    if (min == null || min <= 0) return 'مباشر الآن';
    return 'الدقيقة $min';
  }

  /// The score line, or a dash before anyone has scored.
  static String scoreLabel(SportMatchItem m) => '${m.homeScore ?? 0} - ${m.awayScore ?? 0}';
}
