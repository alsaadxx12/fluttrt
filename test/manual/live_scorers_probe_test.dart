@Tags(['manual'])
library;

// Live: the Gulf Cup scorers with the goals of the matches being played
// now added on. Run by hand:
//   flutter test test/manual/live_scorers_probe_test.dart --tags manual
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/sports/data/services/tournament_service.dart';

void main() {
  test('scorers, live goals included', () async {
    final service = TournamentService();
    final scorers = await service.fetchTopScorers(Tournament.gulfCup.id);
    for (final s in scorers) {
      // ignore: avoid_print
      print('${s.goals} ${s.assists}  ${s.live ? "LIVE " : "     "}${s.name} (${s.teamName}) v${s.imageVersion}');
    }
    expect(scorers, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
