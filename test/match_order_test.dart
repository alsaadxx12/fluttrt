import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/sports/data/match_order.dart';
import 'package:youtube_downloader/features/sports/data/models/sports_models.dart';

SportMatchItem _m(int id, String status, Duration fromNow) => SportMatchItem(
      id: id,
      kickoffAt: DateTime.now().toUtc().add(fromNow).toIso8601String(),
      status: status,
      home: TeamInfo(name: 'H$id'),
      away: TeamInfo(name: 'A$id'),
    );

/// The home row shows in play first (earliest kick-off first), then upcoming
/// (soonest first) — and drops finished games entirely: nothing to watch,
/// and a tap on one only yields a "match ended" notice.
void main() {
  test('day order: live, then upcoming; finished dropped', () {
    final input = [
      _m(1, 'ended', const Duration(hours: -6)),
      _m(2, 'scheduled', const Duration(hours: 3)),
      _m(3, 'live', const Duration(minutes: -60)),
      _m(4, 'scheduled', const Duration(hours: 1)),
      _m(5, 'ended', const Duration(hours: -2)),
      _m(6, 'live', const Duration(minutes: -20)),
      _m(7, 'postponed', const Duration(hours: 5)), // neither live nor ended: upcoming bucket
    ];
    final out = MatchOrder.dayOrder(input);
    expect(out.map((m) => m.id).toList(), [3, 6, 4, 2, 7]);
    expect(out.any((m) => m.isEnded), isFalse, reason: 'finished games must not be shown');
  });

  test('a day with only finished games shows nothing', () {
    expect(MatchOrder.dayOrder(const []), isEmpty);
    final onlyEnded = [_m(1, 'ended', const Duration(hours: -1)), _m(2, 'ended', const Duration(hours: -3))];
    expect(MatchOrder.dayOrder(onlyEnded), isEmpty);
  });

  test('a game the feed forgot to finish (kick-off 5h ago) is treated as over', () {
    final stale = [_m(1, 'scheduled', const Duration(hours: -5)), _m(2, 'scheduled', const Duration(hours: 2))];
    expect(MatchOrder.dayOrder(stale).map((m) => m.id).toList(), [2]);
  });
}
