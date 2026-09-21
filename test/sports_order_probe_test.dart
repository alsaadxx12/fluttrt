import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/sports/data/match_merge.dart';
import 'package:youtube_downloader/features/sports/data/match_order.dart';
import 'package:youtube_downloader/features/sports/data/models/sports_models.dart';
import 'package:youtube_downloader/features/sports/data/services/sports_service.dart';

/// Live probe (network): the exact list the home row renders right now, in
/// order — so a mismatch with what the phone shows can be placed. No
/// TestWidgetsFlutterBinding (it mocks HttpClient).
void main() {
  test('home row order right now', () async {
    final s = SportsService();
    final groups = await s.fetchMatches(day: 'today');
    final live = await s.fetchLiveMatches(day: 'today');
    final raw = <SportMatchItem>[for (final g in groups) ...g.matches];
    final merged = MatchMerge.mergeAll([raw, live]);
    final ordered = MatchOrder.dayOrder(merged);
    final liveCount = merged.where((m) => m.isLive).length;
    // ignore: avoid_print
    print('now(utc)=${DateTime.now().toUtc()} merged=${merged.length} live=$liveCount');
    for (var i = 0; i < ordered.length && i < 15; i++) {
      final m = ordered[i];
      // ignore: avoid_print
      print('  [$i] ${m.status.padRight(9)} kick=${m.kickoffAt}  ${m.home.name} v ${m.away.name}'
          '${m.isLive ? "  <LIVE>" : m.isEnded ? "  <ended>" : ""}');
    }
    expect(ordered.length, merged.length);
    if (liveCount > 0) {
      expect(ordered.first.isLive, isTrue, reason: 'live matches must come first');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
