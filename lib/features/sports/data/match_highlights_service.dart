import 'dart:async';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'models/sports_models.dart';
import 'services/sports_service.dart';

/// One finished match whose goals we can show a highlights reel for.
class MatchHighlight {
  final String home;
  final String away;
  final String? homeLogo;
  final String? awayLogo;
  final String? league;
  final String? leagueLogo;
  final int homeScore;
  final int awayScore;
  final String kickoffAt;

  /// Yesterday's match, as opposed to today's.
  final bool yesterday;

  const MatchHighlight({
    required this.home,
    required this.away,
    this.homeLogo,
    this.awayLogo,
    this.league,
    this.leagueLogo,
    required this.homeScore,
    required this.awayScore,
    required this.kickoffAt,
    required this.yesterday,
  });

  String get key => '${home}__${away}__$kickoffAt';
  String get score => '$homeScore - $awayScore';

  /// What to search YouTube for: an Arabic goals-summary query.
  String get searchQuery => '$home vs $away ملخص اهداف';
  String get searchQueryEn => '$home vs $away highlights';
}

/// A resolved highlights reel: the YouTube video and its still.
class HighlightVideo {
  final String videoId;
  final String? thumbUrl;
  const HighlightVideo(this.videoId, this.thumbUrl);
}

/// A YouTube search hit for the in-section search field.
class HighlightHit {
  final String videoId;
  final String title;
  final String? thumbUrl;
  final String? author;
  const HighlightHit(this.videoId, this.title, this.thumbUrl, this.author);
}

/// Reads yesterday's and today's finished matches, and finds each one's goals
/// summary on YouTube (official highlights, like the trailers — not a live
/// rebroadcast of the match).
class MatchHighlightsService {
  MatchHighlightsService({SportsService? sports}) : _sports = sports ?? SportsService();
  final SportsService _sports;

  /// Finished matches from yesterday and today, most recent first.
  Future<List<MatchHighlight>> recent({int limit = 40}) async {
    final res = await Future.wait([
      _sports.fetchMatches(day: 'yesterday').catchError((_) => <LeagueGroup>[]),
      _sports.fetchMatches(day: 'today').catchError((_) => <LeagueGroup>[]),
    ]);

    final out = <MatchHighlight>[];
    final seen = <String>{};
    for (var d = 0; d < res.length; d++) {
      for (final g in res[d]) {
        for (final m in g.matches) {
          if (!m.isEnded || m.homeScore == null || m.awayScore == null) continue;
          final h = MatchHighlight(
            home: m.home.name,
            away: m.away.name,
            homeLogo: m.home.logo,
            awayLogo: m.away.logo,
            league: m.league,
            leagueLogo: m.leagueLogo,
            homeScore: m.homeScore!,
            awayScore: m.awayScore!,
            kickoffAt: m.kickoffAt,
            yesterday: d == 0,
          );
          if (h.home.isEmpty || h.away.isEmpty) continue;
          if (seen.add(h.key)) out.add(h);
        }
      }
    }
    // Most recent kick-off first.
    out.sort((a, b) => b.kickoffAt.compareTo(a.kickoffAt));
    return out.take(limit).toList();
  }
}

/// Finds and caches a match's highlights video on YouTube.
class HighlightResolver {
  HighlightResolver._();
  static final HighlightResolver instance = HighlightResolver._();

  final Map<String, HighlightVideo?> _cache = {};
  final Map<String, Future<HighlightVideo?>> _inflight = {};

  HighlightVideo? cached(String key) => _cache[key];

  /// Free-text search for a match's goals summary on YouTube (e.g. the user
  /// types "برشلونة"). Biases the query toward goal-summary results.
  Future<List<HighlightHit>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final lower = q.toLowerCase();
    final biased = (lower.contains('ملخص') || lower.contains('اهداف') || lower.contains('أهداف') || lower.contains('highlight'))
        ? q
        : '$q ملخص اهداف';
    final yt = YoutubeExplode();
    try {
      // Prefer recent uploads; if that is empty, search without the date bound.
      var list = await yt.search.search(biased, filter: UploadDateFilter.lastMonth).timeout(const Duration(seconds: 15));
      if (list.isEmpty) {
        list = await yt.search.search(biased).timeout(const Duration(seconds: 15));
      }
      return list
          .take(24)
          .map((v) => HighlightHit(v.id.value, v.title, v.thumbnails.highResUrl, v.author))
          .toList();
    } catch (_) {
      return const [];
    } finally {
      yt.close();
    }
  }

  Future<HighlightVideo?> find(MatchHighlight m) {
    if (_cache.containsKey(m.key)) return Future.value(_cache[m.key]);
    return _inflight.putIfAbsent(m.key, () => _find(m))
      ..whenComplete(() => _inflight.remove(m.key));
  }

  Future<HighlightVideo?> _find(MatchHighlight m) async {
    final yt = YoutubeExplode();
    try {
      HighlightVideo? pick;
      // Recent uploads first, so a fixture's old highlights don't win. Fall
      // back to an unfiltered search only if the recent one finds nothing.
      final attempts = <MapEntry<String, SearchFilter?>>[
        MapEntry(m.searchQuery, UploadDateFilter.lastWeek),
        MapEntry(m.searchQueryEn, UploadDateFilter.lastWeek),
        MapEntry(m.searchQuery, null),
      ];
      for (final a in attempts) {
        try {
          final list = a.value == null
              ? await yt.search.search(a.key).timeout(const Duration(seconds: 12))
              : await yt.search.search(a.key, filter: a.value!).timeout(const Duration(seconds: 12));
          final v = _bestResult(list, m);
          if (v != null) {
            pick = HighlightVideo(v.id.value, v.thumbnails.highResUrl);
            break;
          }
        } catch (_) {
          // try the next attempt
        }
      }
      _cache[m.key] = pick;
      return pick;
    } catch (_) {
      _cache[m.key] = null;
      return null;
    } finally {
      yt.close();
    }
  }

  /// The first result that reads like a goals summary, else the first result.
  Video? _bestResult(List<Video> list, MatchHighlight m) {
    if (list.isEmpty) return null;
    bool looksLikeHighlight(Video v) {
      final t = v.title.toLowerCase();
      return t.contains('ملخص') ||
          t.contains('highlight') ||
          t.contains('اهداف') ||
          t.contains('أهداف') ||
          t.contains('goals');
    }

    for (final v in list.take(6)) {
      if (looksLikeHighlight(v)) return v;
    }
    return list.first;
  }
}
