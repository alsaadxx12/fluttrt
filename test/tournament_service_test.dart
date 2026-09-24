import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/sports/data/services/tournament_service.dart';

Map _load(String name) => jsonDecode(File('test/fixtures/$name').readAsStringSync()) as Map;

void main() {
  test('the Gulf Cup standings split into their two groups, top two marked as going through', () {
    final s = TournamentService.parseStandings(_load('gulf_cup_standings.json'));
    expect(s.groups.map((g) => g.name), ['المجموعة أ', 'المجموعة ب']);
    expect(s.groups.first.rows.length, 4);
    expect(s.stage, 'المجموعات');
    expect(s.destination, 'نصف النهائي');
    final a = s.groups.first.rows;
    expect(a.first.team.name, 'السعودية');
    expect(a.first.points, 3);
    expect(a.first.qualifies, isTrue);
    expect(a[1].qualifies, isTrue);
    expect(a[2].qualifies, isFalse);
    expect(a.first.form, [1]);
  });

  test('scorers come with their goals, assists and team', () {
    final scorers = TournamentService.parseTopScorers(_load('gulf_cup_stats.json'));
    expect(scorers, isNotEmpty);
    expect(scorers.first.goals, greaterThanOrEqualTo(scorers.last.goals));
    expect(scorers.first.teamName, isNotEmpty);
    expect(scorers.first.live, isFalse);
  });

  test('the newest photo, cropped to the face, carries the photo version', () {
    const s = TopScorer(id: 72150, name: 'x', teamId: 1, teamName: 't', goals: 1, assists: 0, imageVersion: 27);
    expect(s.photoUrl, contains('/v27/Athletes/72150'));
    expect(s.photoUrl, contains('g_face'));
    const bare = TopScorer(id: 72150, name: 'x', teamId: 1, teamName: 't', goals: 1, assists: 0);
    expect(bare.photoUrl, contains('/Athletes/72150'));
    expect(bare.photoUrl, isNot(contains('/v27/')));
  });

  test("a live match's goals go to their scorers by athlete id; an own goal is nobody's", () {
    // UAE 3-0 Yemen at half time: two goals with assists, one own goal.
    final game = _load('gulf_cup_game_live.json')['game'] as Map;
    final live = TournamentService.parseGameGoals(game);
    final byName = {for (final s in live) s.name: s};
    expect(byName['نيكولاس خيمينيز']!.goals, 1);
    expect(byName['نيكولاس خيمينيز']!.id, 15447);
    expect(byName['نيكولاس خيمينيز']!.teamName, 'الإمارات');
    expect(byName['نيكولاس خيمينيز']!.imageVersion, 23);
    expect(byName['نيكولاس خيمينيز']!.shortName, 'خيمينيز');
    expect(byName['لوان بيريرا']!.goals, 1);
    expect(byName['برونو دى اوليفيرا']!.assists, 1);
    expect(byName['برونو دى اوليفيرا']!.goals, 0);
    expect(byName.containsKey('نادر سهل'), isFalse, reason: 'the own goal credits no scorer');
    expect(live.every((s) => s.live), isTrue);
  });

  test('live goals add to the table, new scorers join it, most goals first', () {
    const table = [
      TopScorer(id: 1, name: 'a', teamId: 1, teamName: 't', goals: 2, assists: 0),
      TopScorer(id: 2, name: 'b', teamId: 1, teamName: 't', goals: 1, assists: 1),
    ];
    const live = [
      TopScorer(id: 2, name: 'b', teamId: 1, teamName: 't', goals: 2, assists: 0, imageVersion: 5, live: true),
      TopScorer(id: 3, name: 'c', teamId: 2, teamName: 'u', goals: 1, assists: 0, live: true),
      TopScorer(id: 4, name: 'd', teamId: 2, teamName: 'u', goals: 0, assists: 1, live: true),
    ];
    final merged = TournamentService.mergeLive(table, live);
    expect(merged.map((s) => s.id).toList(), [2, 1, 3], reason: 'an assist alone is not a scorer');
    expect(merged.first.goals, 3);
    expect(merged.first.live, isTrue);
    expect(merged.first.imageVersion, 5);
    expect(merged[1].live, isFalse);
    expect(TournamentService.mergeLive(table, const []), same(table));
  });
}
