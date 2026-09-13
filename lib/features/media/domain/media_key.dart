import 'media_item.dart';

/// Turns provider titles into one comparable identity, so the same work
/// coming from two providers is recognised as one.
///
/// Ids are useless for this: every provider numbers its own catalogue.
class MediaKey {
  MediaKey._();

  /// Words providers bolt onto titles that say nothing about the work.
  static const _noise = {
    'hd', 'fhd', 'uhd', '4k', '1080p', '720p', '480p',
    'full', 'movie', 'film', 'fullmovie', 'official', 'trailer', 'teaser',
    'watch', 'online', 'free', 'stream', 'streaming',
    'remastered', 'uncut', 'extended', 'unrated', 'edition', 'version',
    'subtitled', 'subbed', 'dubbed', 'dub', 'sub',
    'مترجم', 'مدبلج', 'كامل', 'فيلم', 'مشاهدة', 'اونلاين', 'بجودة', 'عالية',
  };

  /// A leading article carries no identity: "The Dark Knight" and
  /// "Dark Knight" are the same film.
  static const _articles = {'the', 'a', 'an', 'el', 'la', 'le', 'les'};

  /// lowercase, no punctuation, no noise words, single spaces.
  static String normalizeTitle(String raw) {
    var s = raw.toLowerCase();
    // Arabic presentation forms and diacritics carry no identity.
    s = s.replaceAll(RegExp('[ً-ٰٟ]'), '');
    s = s.replaceAll(RegExp('[أإآٱ]'), 'ا').replaceAll('ى', 'ي').replaceAll('ة', 'ه');
    // A year attached as metadata is handled by extractYear, not the title:
    // bracketed anywhere, or trailing after a separator. A year that is part
    // of the name ("2012", "Blade Runner 2049") has neither and survives.
    s = s.replaceAll(RegExp(r'[\(\[]\s*(19|20)\d{2}\s*[\)\]]'), ' ');
    s = s.replaceAll(RegExp(r'[-–—|:]\s*(19|20)\d{2}\s*$'), ' ');
    // Anything that is not a letter or a digit separates words.
    s = s.replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ');
    var words = s.split(' ').where((w) => w.isNotEmpty).toList();
    // Roman-numeral and digit sequels stay: they tell works apart.
    words = words.where((w) => !_noise.contains(w)).toList();
    while (words.isNotEmpty && _articles.contains(words.first)) {
      words.removeAt(0);
    }
    return words.join(' ').trim();
  }

  /// A year written in the title, e.g. "The Dark Knight (2008)".
  static int? extractYear(String raw) {
    final m = RegExp(r'[\(\[\-\s](19|20)\d{2}[\)\]\s]?').firstMatch(' $raw ');
    if (m == null) return null;
    final y = int.tryParse(m.group(0)!.replaceAll(RegExp(r'[^\d]'), ''));
    return (y != null && y >= 1900 && y <= 2100) ? y : null;
  }

  /// Season/episode written into a title: S02E05, 2x05, "Season 2 Episode 5".
  static (int?, int?) extractEpisode(String raw) {
    final s = raw.toLowerCase();
    var m = RegExp(r's(\d{1,2})\s*e(\d{1,3})').firstMatch(s);
    m ??= RegExp(r'(\d{1,2})\s*x\s*(\d{1,3})').firstMatch(s);
    m ??= RegExp(r'season\s*(\d{1,2}).*?episode\s*(\d{1,3})').firstMatch(s);
    if (m == null) return (null, null);
    return (int.tryParse(m.group(1)!), int.tryParse(m.group(2)!));
  }

  /// The identity a work is filed under.
  ///
  /// A movie is its normalised title plus its year, so a remake is its own
  /// work. A series is its title alone, so both providers' copies meet. An
  /// episode adds season and number, so episodes never collapse together.
  static String of(MediaItem item) {
    final t = normalizeTitle(item.originalTitle.isNotEmpty ? item.originalTitle : item.title);
    switch (item.kind) {
      case MediaKind.movie:
        return 'movie:$t:${item.year ?? ''}';
      case MediaKind.series:
        return 'series:$t';
      case MediaKind.episode:
        final series = normalizeTitle(item.seriesTitle ?? item.originalTitle);
        return 'episode:$series:s${item.seasonNumber ?? 0}:e${item.episodeNumber ?? 0}';
    }
  }

  /// 0..1. Used only when a year is missing on one side, where an exact key
  /// cannot be formed.
  static double similarity(String a, String b) {
    final x = normalizeTitle(a), y = normalizeTitle(b);
    if (x.isEmpty || y.isEmpty) return 0;
    if (x == y) return 1;
    final distance = _levenshtein(x, y);
    final longest = x.length > y.length ? x.length : y.length;
    return 1 - distance / longest;
  }

  /// Two titles name the same work even though a year is missing.
  /// Deliberately strict: a wrong merge hides a film from the user.
  static bool sameTitle(String a, String b) => similarity(a, b) >= 0.92;

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    final cur = List<int>.filled(b.length + 1, 0);
    for (var i = 0; i < a.length; i++) {
      cur[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
        var best = cur[j] + 1;
        if (prev[j + 1] + 1 < best) best = prev[j + 1] + 1;
        if (prev[j] + cost < best) best = prev[j] + cost;
        cur[j + 1] = best;
      }
      prev = List<int>.from(cur);
    }
    return prev[b.length];
  }
}
