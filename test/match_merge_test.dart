import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/sports/data/match_merge.dart';
import 'package:youtube_downloader/features/sports/data/models/sports_models.dart';

SportMatchItem m({
  required int id,
  required String home,
  required String away,
  String? sourceId,
  String status = 'notstarted',
  bool hasWatch = false,
  int? streamId,
  List<BroadcastChannel> channels = const [],
}) =>
    SportMatchItem(
      id: id,
      sourceId: sourceId,
      kickoffAt: '2026-09-12T19:00:00Z',
      status: status,
      home: TeamInfo(name: home),
      away: TeamInfo(name: away),
      hasWatch: hasWatch,
      streamId: streamId,
      broadcasters: channels,
    );

BroadcastChannel ch(int id, String name) => BroadcastChannel(id: id, name: name, image: '');

void main() {
  test('one fixture from two feeds becomes one row', () {
    final merged = MatchMerge.mergeAll([
      [m(id: 1, home: 'الهلال', away: 'النصر', channels: [ch(10, 'قناة أ')])],
      [m(id: 99999, home: 'الهلال', away: 'النصر', channels: [ch(20, 'قناة ب')])],
    ]);

    expect(merged.length, 1, reason: 'different ids for the same fixture is still one match');
    expect(merged.single.broadcasters.length, 2, reason: 'both feeds\' channels survive on the one row');
    expect(merged.single.broadcasters.map((c) => c.name), containsAll(['قناة أ', 'قناة ب']));
  });

  test('two different fixtures stay two rows', () {
    final merged = MatchMerge.mergeAll([
      [m(id: 1, home: 'الهلال', away: 'النصر')],
      [m(id: 2, home: 'الهلال', away: 'الاتحاد')],
    ]);
    expect(merged.length, 2, reason: 'sharing one team does not make it the same match');
  });

  test('a feed that swaps home and away is still the same fixture', () {
    final merged = MatchMerge.mergeAll([
      [m(id: 1, home: 'ريال مدريد', away: 'برشلونة')],
      [m(id: 2, home: 'برشلونة', away: 'ريال مدريد', hasWatch: true, streamId: 55)],
    ]);
    expect(merged.length, 1);
    expect(merged.single.hasWatch, isTrue, reason: 'what the other feed knew is kept');
    expect(merged.single.streamId, 55);
  });

  test('the first list decides how the match is shown', () {
    final merged = MatchMerge.mergeAll([
      [m(id: 1, home: 'Liverpool', away: 'Fulham')],
      [m(id: 2, home: 'liverpool fc', away: 'fulham fc', streamId: 7)],
    ]);
    expect(merged.single.id, 1, reason: 'the primary feed owns the card');
    expect(merged.single.streamId, 7, reason: 'the other feed still fills the gap');
  });

  test('a fixture one feed has live is shown as live', () {
    final merged = MatchMerge.mergeAll([
      [m(id: 1, home: 'الهلال', away: 'النصر', status: 'notstarted')],
      [m(id: 2, home: 'الهلال', away: 'النصر', status: 'live')],
    ]);
    expect(merged.single.isLive, isTrue);
  });

  test('the same channel from both feeds is not listed twice', () {
    final merged = MatchMerge.mergeAll([
      [m(id: 1, home: 'A Team', away: 'B Team', channels: [ch(10, 'قناة أ')])],
      [m(id: 2, home: 'A Team', away: 'B Team', channels: [ch(10, 'قناة أ'), ch(11, 'قناة ب')])],
    ]);
    expect(merged.single.broadcasters.length, 2);
  });

  test('one feed alone is passed through untouched', () {
    final only = [m(id: 1, home: 'A Team', away: 'B Team'), m(id: 2, home: 'C Team', away: 'D Team')];
    expect(MatchMerge.mergeAll([only, const []]).length, 2);
  });

  group('finding the same fixture in another feed', () {
    test('an id that collides across feeds never opens another match', () {
      // Both feeds happen to number a match 77, but they are different games.
      final target = m(id: 77, home: 'الهلال', away: 'النصر');
      final otherFeed = [m(id: 77, home: 'ريال مدريد', away: 'برشلونة', streamId: 900)];

      expect(MatchMerge.findSame(target, otherFeed), isNull,
          reason: 'a missing stream beats the wrong one');
    });

    test('the teams decide, whatever the ids say', () {
      final target = m(id: 5, home: 'الهلال', away: 'النصر');
      final otherFeed = [
        m(id: 1, home: 'ريال مدريد', away: 'برشلونة'),
        m(id: 2, home: 'الهلال', away: 'النصر', streamId: 42),
      ];
      expect(MatchMerge.findSame(target, otherFeed)?.streamId, 42);
    });

    test('with no names to compare, the id is the fallback', () {
      final target = m(id: 9, home: '', away: '');
      final otherFeed = [m(id: 9, home: '', away: '', streamId: 12)];
      expect(MatchMerge.findSame(target, otherFeed)?.streamId, 12);
    });

    test('an empty source id matches nothing', () {
      final target = m(id: 1, home: '', away: '', sourceId: '');
      final otherFeed = [m(id: 2, home: '', away: '', sourceId: '', streamId: 5)];
      expect(MatchMerge.findSame(target, otherFeed), isNull,
          reason: 'two blanks are not the same match');
    });

    test('nothing matching returns nothing', () {
      expect(MatchMerge.findSame(m(id: 1, home: 'A Team', away: 'B Team'), const []), isNull);
    });
  });
}
