import 'package:dio/dio.dart';

import 'package:youtube_downloader/core/network/http_cache.dart';
/// One fixture of a competition as 365Scores lists it.
class LeagueFixture {
  final int id; // 365Scores game id (= the app's match `sourceId`)
  final DateTime startTime;
  final String statusText;
  final bool isLive;
  final bool isEnded;
  final String roundName;
  final LeagueTeam home;
  final LeagueTeam away;
  final int? homeScore;
  final int? awayScore;

  const LeagueFixture({
    required this.id,
    required this.startTime,
    required this.statusText,
    required this.isLive,
    required this.isEnded,
    required this.roundName,
    required this.home,
    required this.away,
    this.homeScore,
    this.awayScore,
  });
}

class LeagueTeam {
  final int id;
  final String name;
  const LeagueTeam({required this.id, required this.name});

  String get crestUrl =>
      'https://imagecache.365scores.com/image/upload/f_png,w_96,h_96,c_limit,q_auto:eco,dpr_2/Competitors/$id';
}

/// A standings table (a league has one; a cup may have one per group).
class LeagueTable {
  final String name;
  final List<LeagueRow> rows;
  const LeagueTable({required this.name, required this.rows});
}

class LeagueRow {
  final int position;
  final LeagueTeam team;
  final int played, won, drawn, lost, goalsFor, goalsAgainst;
  final int points;

  const LeagueRow({
    required this.position,
    required this.team,
    required this.played,
    required this.won,
    required this.drawn,
    required this.lost,
    required this.goalsFor,
    required this.goalsAgainst,
    required this.points,
  });

  int get goalDifference => goalsFor - goalsAgainst;
}

/// Fixtures and standings of one competition, from 365Scores (the source
/// the app already uses for match data and crests).
class LeagueService {
  final Dio _dio = createDio(
    BaseOptions(
      baseUrl: 'https://webws.365scores.com/web',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: const {'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124.0 Mobile'},
    ),
  );

  static const _base = {
    'appTypeId': 5,
    'langId': 27, // Arabic
    'timezoneName': 'Asia/Baghdad',
    'userCountryId': 89,
  };

  static int _int(Object? v) => v is int ? v : (v is num ? v.round() : int.tryParse('$v') ?? 0);

  /// "الجولة 4": 365Scores keeps the word and the number apart.
  static String _round(Map g) {
    final name = '${g['roundName'] ?? g['stageName'] ?? ''}'.trim();
    final num = _int(g['roundNum']);
    if (name.isEmpty) return num > 0 ? 'الجولة $num' : '';
    return (num > 0 && !RegExp(r'\d').hasMatch(name)) ? '$name $num' : name;
  }

  static LeagueTeam _team(Map c) => LeagueTeam(id: _int(c['id']), name: '${c['name'] ?? ''}');

  /// The competition's latest results followed by its upcoming fixtures
  /// (the next round or two), by kick-off. Between matchdays the "current"
  /// list is empty, so both ends are asked for.
  Future<List<LeagueFixture>> fetchFixtures(int competitionId) async {
    final query = {..._base, 'competitions': competitionId, 'showOdds': false};
    final pages = await Future.wait([
      _dio.get('/games/results/', queryParameters: query).catchError((_) => Response(requestOptions: RequestOptions())),
      _dio.get('/games/fixtures/', queryParameters: query).catchError((_) => Response(requestOptions: RequestOptions())),
    ]);
    final seen = <int>{};
    final games = <Map>[];
    for (final res in pages) {
      for (final g in ((res.data is Map ? res.data['games'] : null) as List? ?? const []).whereType<Map>()) {
        if (seen.add(_int(g['id']))) games.add(g);
      }
    }
    final out = <LeagueFixture>[];
    for (final g in games) {
      final home = g['homeCompetitor'], away = g['awayCompetitor'];
      if (home is! Map || away is! Map) continue;
      final start = DateTime.tryParse('${g['startTime'] ?? ''}');
      if (start == null) continue;
      // statusGroup (365Scores): 2 = not started, 3 = in play, 4 = ended;
      // scores are -1 before kick-off.
      final group = _int(g['statusGroup']);
      final hs = (home['score'] as num?) ?? -1, as_ = (away['score'] as num?) ?? -1;
      out.add(LeagueFixture(
        id: _int(g['id']),
        startTime: start.toLocal(),
        statusText: '${g['statusText'] ?? ''}',
        isLive: group == 3,
        isEnded: group == 4 || g['justEnded'] == true,
        roundName: _round(g),
        home: _team(home),
        away: _team(away),
        homeScore: hs >= 0 ? hs.round() : null,
        awayScore: as_ >= 0 ? as_.round() : null,
      ));
    }
    out.sort((a, b) => a.startTime.compareTo(b.startTime));
    // Keep it readable: the last dozen results and the next thirty fixtures.
    final now = DateTime.now();
    final past = out.where((f) => f.isEnded || f.startTime.isBefore(now.subtract(const Duration(hours: 3)))).toList();
    final coming = out.where((f) => !past.contains(f)).toList();
    return [...past.length > 12 ? past.sublist(past.length - 12) : past, ...coming.take(30)];
  }

  /// The competition's tables (empty for a cup without a group stage).
  Future<List<LeagueTable>> fetchStandings(int competitionId) async {
    final res = await _dio.get('/standings/', queryParameters: {..._base, 'competitions': competitionId, 'live': true});
    final tables = (res.data is Map ? res.data['standings'] : null) as List? ?? const [];
    return [
      for (final t in tables.whereType<Map>())
        LeagueTable(
          name: '${t['name'] ?? t['displayName'] ?? ''}',
          rows: [
            for (final r in (t['rows'] as List? ?? const []).whereType<Map>())
              if (r['competitor'] is Map)
                LeagueRow(
                  position: _int(r['position']),
                  team: _team(r['competitor'] as Map),
                  played: _int(r['gamePlayed']),
                  won: _int(r['gamesWon']),
                  drawn: _int(r['gamesEven']),
                  lost: _int(r['gamesLost']),
                  goalsFor: _int(r['for']),
                  goalsAgainst: _int(r['against']),
                  points: _int(r['points']),
                ),
          ]..sort((a, b) => a.position.compareTo(b.position)),
        ),
    ].where((t) => t.rows.isNotEmpty).toList();
  }
}
