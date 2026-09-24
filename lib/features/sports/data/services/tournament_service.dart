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
    this.accent2,
    this.darkBadge = false,
  });

  /// 365Scores competition id.
  final int id;
  final String name;
  final String logoUrl;

  /// The competition's own colours: its banner runs from the second,
  /// dark one to the first.
  final int accent;
  final int? accent2;

  /// A logo drawn in white sits on a dark badge, not a white one.
  final bool darkBadge;

  /// Arabian Gulf Cup 27, 2026.
  static const gulfCup = Tournament(
    id: 5452,
    name: 'كأس الخليج العربي 27',
    logoUrl:
        'https://imagecache.365scores.com/image/upload/f_png,w_300,h_300,c_limit,q_auto:best,dpr_2/Competitions/light/5452',
    accent: 0xFF00B1E8,
    accent2: 0xFF06304A,
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
    this.imageVersion,
    this.live = false,
  });

  final int id;
  final String name;
  final int teamId;
  final String teamName;
  final int goals;
  final int assists;

  /// 365Scores' photo version: with it the newest photo comes, without it
  /// whatever the cache holds.
  final int? imageVersion;

  /// Some of these goals were scored in a match still being played.
  final bool live;

  TopScorer copyWith({int? goals, int? assists, int? imageVersion, bool? live}) => TopScorer(
        id: id,
        name: name,
        teamId: teamId,
        teamName: teamName,
        goals: goals ?? this.goals,
        assists: assists ?? this.assists,
        imageVersion: imageVersion ?? this.imageVersion,
        live: live ?? this.live,
      );

  /// The player's newest photo, cropped to his face; a silhouette when
  /// 365Scores has none.
  String get photoUrl => 'https://imagecache.365scores.com/image/upload/'
      'f_png,w_200,h_200,c_limit,q_auto:eco,dpr_2,d_Athletes:default.png,r_max,c_thumb,g_face,z_0.65/'
      '${imageVersion == null ? '' : 'v$imageVersion/'}Athletes/$id';
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
  /// 365Scores' table counts a match only once it is over, so the goals
  /// of the matches being played right now are read from those matches'
  /// events and added on top.
  Future<List<TopScorer>> fetchTopScorers(int competitionId) async {
    final results = await Future.wait([
      _dio.get('/stats/', queryParameters: {..._base, 'competitions': competitionId}),
      fetchLiveGoals(competitionId).catchError((_) => <TopScorer>[]),
    ]);
    final res = results[0] as Response;
    final table = parseTopScorers(res.data is Map ? res.data as Map : const {});
    return mergeLive(table, results[1] as List<TopScorer>);
  }

  /// The goals and assists of the competition's matches being played now.
  Future<List<TopScorer>> fetchLiveGoals(int competitionId) async {
    final res = await _dio.get('/games/current/', queryParameters: {..._base, 'competitions': competitionId});
    final data = res.data;
    final games = data is Map ? (data['games'] as List? ?? const []).whereType<Map>() : const <Map>[];
    final live = [
      for (final g in games)
        if (_int(g['statusGroup']) == 3) _int(g['id']),
    ];
    if (live.isEmpty) return const [];
    final details = await Future.wait([
      for (final id in live)
        _dio.get('/game/', queryParameters: {..._base, 'gameId': id}).then<Map>((r) {
          final d = r.data;
          return d is Map && d['game'] is Map ? d['game'] as Map : const {};
        }).catchError((_) => <dynamic, dynamic>{}),
    ]);
    return mergeLive(const [], [for (final g in details) ...parseGameGoals(g)]);
  }

  /// The scorers of one match from its events: a goal for the player who
  /// scored it, an assist for the player named beside him; an own goal
  /// is nobody's. The match's members carry the players' athlete ids,
  /// names and photo versions. Every scorer is marked [TopScorer.live].
  static List<TopScorer> parseGameGoals(Map game) {
    final teams = <int, String>{
      for (final c in [game['homeCompetitor'], game['awayCompetitor']])
        if (c is Map) _int(c['id']): '${c['name'] ?? ''}',
    };
    final members = <int, Map>{
      for (final m in (game['members'] as List? ?? const []).whereType<Map>()) _int(m['id']): m,
    };
    final goals = <int, int>{}, assists = <int, int>{};
    for (final e in (game['events'] as List? ?? const []).whereType<Map>()) {
      final type = e['eventType'];
      if (type is! Map || _int(type['id']) != 1) continue;
      if (_int(type['subTypeId']) == 2) continue; // an own goal
      goals.update(_int(e['playerId']), (v) => v + 1, ifAbsent: () => 1);
      final extra = e['extraPlayers'];
      if (extra is List && extra.isNotEmpty) {
        assists.update(_int(extra.first), (v) => v + 1, ifAbsent: () => 1);
      }
    }
    final out = <TopScorer>[];
    for (final memberId in {...goals.keys, ...assists.keys}) {
      final m = members[memberId];
      if (m == null) continue;
      final teamId = _int(m['competitorId']);
      out.add(TopScorer(
        id: _int(m['athleteId']),
        name: '${m['name'] ?? ''}',
        teamId: teamId,
        teamName: teams[teamId] ?? '',
        goals: goals[memberId] ?? 0,
        assists: assists[memberId] ?? 0,
        imageVersion: m['imageVersion'] is num ? _int(m['imageVersion']) : null,
        live: true,
      ));
    }
    return out;
  }

  /// [table] with [live] goals and assists added on, by player; players
  /// the table has not seen yet join it. Most goals first.
  static List<TopScorer> mergeLive(List<TopScorer> table, List<TopScorer> live) {
    if (live.isEmpty) return table;
    final byId = <int, TopScorer>{for (final s in table) s.id: s};
    for (final l in live) {
      final was = byId[l.id];
      byId[l.id] = was == null
          ? l
          : was.copyWith(
              goals: was.goals + l.goals,
              assists: was.assists + l.assists,
              imageVersion: was.imageVersion ?? l.imageVersion,
              live: true,
            );
    }
    // A scorer is one with a goal; an assist alone does not put him here.
    final out = byId.values.where((s) => s.goals > 0).toList();
    out.sort((a, b) => b.goals != a.goals ? b.goals.compareTo(a.goals) : b.assists.compareTo(a.assists));
    return out;
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
        imageVersion: e['imageVersion'] is num ? _int(e['imageVersion']) : null,
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
