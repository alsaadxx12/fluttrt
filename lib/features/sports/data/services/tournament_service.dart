import 'package:dio/dio.dart';

import 'package:youtube_downloader/core/network/http_cache.dart';
import 'league_service.dart';

/// A tournament the app gives a page of its own.
class Tournament {
  const Tournament({
    required this.id,
    required this.name,
    required this.logoUrl,
    required this.accent,
    this.darkBadge = false,
  });

  /// 365Scores competition id.
  final int id;
  final String name;
  final String logoUrl;

  /// The competition's own colour, for its card.
  final int accent;

  /// A logo drawn in white sits on a dark badge, not a white one.
  final bool darkBadge;

  /// Arabian Gulf Cup 27, 2026.
  static const gulfCup = Tournament(
    id: 5452,
    name: 'كأس الخليج العربي 27',
    logoUrl:
        'https://imagecache.365scores.com/image/upload/f_png,w_300,h_300,c_limit,q_auto:best,dpr_2/Competitions/light/5452',
    accent: 0xFF00B1E8,
  );
}

/// One group's table, with what the top of it earns.
class TournamentGroup {
  const TournamentGroup({required this.name, required this.rows});

  final String name;
  final List<TournamentRow> rows;
}

class TournamentRow {
  const TournamentRow({
    required this.position,
    required this.team,
    required this.played,
    required this.won,
    required this.drawn,
    required this.lost,
    required this.goalsFor,
    required this.goalsAgainst,
    required this.points,
    required this.qualifies,
    required this.form,
  });

  final int position;
  final LeagueTeam team;
  final int played, won, drawn, lost, goalsFor, goalsAgainst, points;

  /// Standing where the table says the team goes through.
  final bool qualifies;

  /// Last results, oldest first: 1 won, 2 drawn, 0 lost (365Scores' code).
  final List<int> form;

  int get goalDifference => goalsFor - goalsAgainst;
}

/// The stage the standings say the tournament is at, and where the top of
/// each group goes.
class TournamentStandings {
  const TournamentStandings({required this.groups, required this.stage, required this.destination});

  final List<TournamentGroup> groups;

  /// «المجموعات», «نصف النهائي»…
  final String stage;

  /// «نصف النهائي»: what qualifying earns.
  final String destination;
}

class TopScorer {
  const TopScorer({
    required this.id,
    required this.name,
    required this.teamId,
    required this.teamName,
    required this.goals,
    required this.assists,
  });

  final int id;
  final String name;
  final int teamId;
  final String teamName;
  final int goals;
  final int assists;

  String get photoUrl =>
      'https://imagecache.365scores.com/image/upload/f_png,w_80,h_80,c_limit,q_auto:eco,dpr_2/athletes/$id';
  String get crestUrl =>
      'https://imagecache.365scores.com/image/upload/f_png,w_96,h_96,c_limit,q_auto:eco,dpr_2/Competitors/$teamId';
}

/// Grouped standings, the stage, and the scorers of one tournament, from
/// 365Scores - the source the app already uses for matches and crests.
/// Fixtures come from [LeagueService.fetchFixtures] as for any competition.
class TournamentService {
  final Dio _dio = createDio(
    BaseOptions(
      baseUrl: 'https://webws.365scores.com/web',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: const {'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124.0 Mobile'},
    ),
  );

  static const _base = {'appTypeId': 5, 'langId': 27, 'timezoneName': 'Asia/Baghdad', 'userCountryId': 89};

  static int _int(Object? v) => v is int ? v : (v is num ? v.round() : int.tryParse('$v') ?? 0);

  /// The current stage's tables split by group, as the standings feed
  /// carries them: one table whose rows each name their group.
  Future<TournamentStandings> fetchStandings(int competitionId) async {
    final res = await _dio.get('/standings/', queryParameters: {..._base, 'competitions': competitionId, 'live': true});
    return parseStandings(res.data is Map ? res.data as Map : const {});
  }

  static TournamentStandings parseStandings(Map data) {
    final tables = (data['standings'] as List? ?? const []).whereType<Map>().toList();
    if (tables.isEmpty) return const TournamentStandings(groups: [], stage: '', destination: '');
    final t = tables.firstWhere((x) => x['isCurrentStage'] == true, orElse: () => tables.first);
    final groupNames = <int, String>{
      for (final g in (t['groups'] as List? ?? const []).whereType<Map>()) _int(g['num']): '${g['name'] ?? ''}',
    };
    final destinations = (t['destinations'] as List? ?? const []).whereType<Map>().toList();
    final qualifyingNums = {for (final d in destinations) _int(d['num'])};
    final destination = destinations.isEmpty ? '' : '${destinations.first['name'] ?? ''}';
    final byGroup = <int, List<TournamentRow>>{};
    for (final r in (t['rows'] as List? ?? const []).whereType<Map>()) {
      final c = r['competitor'];
      if (c is! Map) continue;
      final dest = r['destinationNum'];
      byGroup.putIfAbsent(_int(r['groupNum']), () => []).add(TournamentRow(
            position: _int(r['position']),
            team: LeagueTeam(id: _int(c['id']), name: '${c['name'] ?? ''}'),
            played: _int(r['gamePlayed']),
            won: _int(r['gamesWon']),
            drawn: _int(r['gamesEven']),
            lost: _int(r['gamesLost']),
            goalsFor: _int(r['for']),
            goalsAgainst: _int(r['against']),
            points: _int(r['points']),
            qualifies: dest != null && qualifyingNums.contains(_int(dest)),
            form: [for (final f in (r['recentForm'] as List? ?? const [])) _int(f)],
          ));
    }
    final nums = byGroup.keys.toList()..sort();
    final groups = [
      for (final n in nums)
        TournamentGroup(
          name: groupNames[n] ?? (nums.length > 1 ? 'المجموعة $n' : ''),
          rows: byGroup[n]!..sort((a, b) => a.position.compareTo(b.position)),
        ),
    ];
    // The stage's own name, from the season's list of stages.
    var stage = '';
    final comps = (data['competitions'] as List? ?? const []).whereType<Map>();
    for (final c in comps) {
      final stageNum = _int(t['stageNum']);
      for (final s in (c['seasons'] as List? ?? const []).whereType<Map>()) {
        for (final st in (s['stages'] as List? ?? const []).whereType<Map>()) {
          if (_int(st['num']) == stageNum) stage = '${st['name'] ?? ''}';
        }
      }
    }
    if (stage.isEmpty && groups.length > 1) stage = 'المجموعات';
    return TournamentStandings(groups: groups, stage: stage, destination: destination);
  }

  /// The tournament's scorers, most goals first; assists ride along.
  Future<List<TopScorer>> fetchTopScorers(int competitionId) async {
    final res = await _dio.get('/stats/', queryParameters: {..._base, 'competitions': competitionId});
    return parseTopScorers(res.data is Map ? res.data as Map : const {});
  }

  static List<TopScorer> parseTopScorers(Map data) {
    final stats = data['stats'];
    if (stats is! Map) return const [];
    final cats = (stats['athletesStats'] as List? ?? const []).whereType<Map>().toList();
    Map? cat(int id) => cats.cast<Map?>().firstWhere((c) => _int(c!['id']) == id, orElse: () => null);
    final teams = <int, String>{
      for (final c in (data['competitors'] as List? ?? const []).whereType<Map>()) _int(c['id']): '${c['name'] ?? ''}',
    };
    final assists = <int, int>{};
    for (final r in ((cat(2)?['rows']) as List? ?? const []).whereType<Map>()) {
      final e = r['entity'];
      if (e is Map) assists[_int(e['id'])] = _value(r);
    }
    final out = <TopScorer>[];
    for (final r in ((cat(1)?['rows']) as List? ?? const []).whereType<Map>()) {
      final e = r['entity'];
      if (e is! Map) continue;
      final id = _int(e['id']);
      final teamId = _int(e['competitorId']);
      out.add(TopScorer(
        id: id,
        name: '${e['name'] ?? ''}',
        teamId: teamId,
        teamName: teams[teamId] ?? '',
        goals: _value(r),
        assists: assists[id] ?? 0,
      ));
    }
    out.sort((a, b) => b.goals != a.goals ? b.goals.compareTo(a.goals) : b.assists.compareTo(a.assists));
    return out;
  }

  /// The row's first figure: «1», «0.75»…
  static int _value(Map r) {
    final stats = (r['stats'] as List? ?? const []).whereType<Map>();
    for (final s in stats) {
      return (double.tryParse('${s['value']}') ?? 0).round();
    }
    return 0;
  }
}
