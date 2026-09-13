import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/sports/data/models/sports_models.dart';
import 'package:youtube_downloader/features/sports/presentation/important_match.dart';
import 'package:youtube_downloader/features/sports/presentation/widgets/match_deck.dart';

SportMatchItem m({
  int id = 1,
  String home = 'الهلال',
  String away = 'النصر',
  String status = 'live',
  int? minute,
  int? homeScore,
  int? awayScore,
  bool hasWatch = false,
  String? league,
}) =>
    SportMatchItem(
      id: id,
      kickoffAt: '2026-09-13T19:00:00Z',
      status: status,
      minute: minute,
      home: TeamInfo(name: home, logo: ''),
      away: TeamInfo(name: away, logo: ''),
      homeScore: homeScore,
      awayScore: awayScore,
      hasWatch: hasWatch,
      league: league,
    );

void main() {
  group('choosing the match', () {
    test('only a match being played right now qualifies', () {
      expect(ImportantMatch.pick([m(status: 'scheduled', hasWatch: true)]), isNull);
      expect(ImportantMatch.pick([m(status: 'ended', hasWatch: true)]), isNull);
      expect(ImportantMatch.pick(const []), isNull);
      expect(ImportantMatch.pick([m(hasWatch: true)]), isNotNull);
    });

    test('a match that can be watched beats one that cannot', () {
      final pick = ImportantMatch.pick([
        m(id: 1, league: 'دوري أبطال أوروبا', minute: 80),
        m(id: 2, hasWatch: true, league: 'دوري محلي', minute: 5),
      ]);
      expect(pick?.id, 2, reason: 'no use announcing a match the viewer cannot open');
    });

    test('among watchable matches, the bigger competition wins', () {
      final pick = ImportantMatch.pick([
        m(id: 1, hasWatch: true, league: 'دوري الدرجة الثالثة', minute: 20),
        m(id: 2, hasWatch: true, league: 'دوري أبطال أوروبا', minute: 20),
      ]);
      expect(pick?.id, 2);
    });

    test('all else equal, the match nearer its end wins', () {
      final pick = ImportantMatch.pick([
        m(id: 1, hasWatch: true, league: 'الدوري الإنجليزي', minute: 10),
        m(id: 2, hasWatch: true, league: 'الدوري الإنجليزي', minute: 85),
      ]);
      expect(pick?.id, 2, reason: 'a game in its closing minutes is the one you would regret missing');
    });

    test('major competitions are recognised in both languages', () {
      expect(ImportantMatch.isMajor('دوري أبطال أوروبا'), isTrue);
      expect(ImportantMatch.isMajor('UEFA Champions League'), isTrue);
      expect(ImportantMatch.isMajor('Premier League'), isTrue);
      expect(ImportantMatch.isMajor('دوري الهواة'), isFalse);
      expect(ImportantMatch.isMajor(null), isFalse);
    });

    test('labels read properly before and during play', () {
      expect(ImportantMatch.minuteLabel(m(minute: 63)), 'الدقيقة 63');
      expect(ImportantMatch.minuteLabel(m(minute: null)), 'مباشر الآن');
      expect(ImportantMatch.scoreLabel(m(homeScore: 2, awayScore: 1)), '2 - 1');
      expect(ImportantMatch.scoreLabel(m()), '0 - 0', reason: 'goalless is a score, not a blank');
    });
  });

  group('the deck on the rail', () {
    testWidgets('shows the crests, the score and the minute, and can be put away', (tester) async {
      final matches = [
        m(home: 'ريال مدريد', away: 'برشلونة', minute: 63, homeScore: 2, awayScore: 1, league: 'الدوري الإسباني'),
        m(id: 2, home: 'الهلال', away: 'النصر', minute: 10),
      ];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Stack(children: [MatchDeck(matches: matches)])),
      ));
      await tester.pump();

      // Nothing is thrown in front of the viewer: only the tab is showing.
      expect(find.text('2 - 1'), findsNothing);
      expect(find.text('2'), findsOneWidget, reason: 'the tab says how many are waiting');

      await tester.tap(find.text('2'));
      await tester.pumpAndSettle();

      expect(find.text('ريال مدريد'), findsOneWidget);
      expect(find.text('برشلونة'), findsOneWidget);
      expect(find.text('2 - 1'), findsOneWidget);
      expect(find.text('الدقيقة 63'), findsOneWidget);
      expect(find.text('الدوري الإسباني'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await tester.pumpAndSettle();
      expect(find.text('2 - 1'), findsNothing, reason: 'the hand goes back off the edge');
    });

    testWidgets('no live matches means no tab at all', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Stack(children: [MatchDeck(matches: [])])),
      ));
      await tester.pump();
      expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
    });
  });
}
