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
  });
}
