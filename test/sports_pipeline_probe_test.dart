import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/sports/data/match_merge.dart';
import 'package:youtube_downloader/features/sports/data/models/sports_models.dart';
import 'package:youtube_downloader/features/sports/data/services/sports_service.dart';

/// Live probe (network): what the home "live matches" row actually receives.
/// Prints raw → merged → live-now counts so a shortfall can be placed: the
/// feed, the fuzzy de-duplication in the merge, or genuinely few games in play.
/// (No TestWidgetsFlutterBinding: it would mock HttpClient and fail requests.)
void main() {
  test('home row pipeline counts', () async {
    final s = SportsService();
    final groups = await s.fetchMatches(day: 'today');
    final live = await s.fetchLiveMatches(day: 'today');
    final raw = <SportMatchItem>[for (final g in groups) ...g.matches];
    final merged = MatchMerge.mergeAll([raw, live]);
    final liveNow = merged.where((m) => m.isLive).toList();
    final ended = merged.where((m) => m.isEnded).length;
    final scheduled = merged.where((m) => m.isScheduled).length;
    // ignore: avoid_print
    print('groups=${groups.length} raw=${raw.length} channelFeed=${live.length} '
        'merged=${merged.length} liveNow=${liveNow.length} ended=$ended scheduled=$scheduled');
    // ignore: avoid_print
    print('live now: ${liveNow.map((m) => '${m.home.name} v ${m.away.name} (${m.status}, ${m.minute}\')').join(' | ')}');
    // The merge must not swallow matches: it may only remove true duplicates
    // of the channel feed, never rows of the raw table.
    expect(merged.length, greaterThanOrEqualTo(raw.length * 0.9),
        reason: 'merge collapsed distinct matches (fuzzy team match too loose)');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
