import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/sports/data/models/sports_models.dart';
import 'package:youtube_downloader/features/sports/data/services/sports_service.dart';

/// The Kora x90 page is behind on a game in play: once a match is under
/// way it shows the score where the time was, and the score it shows lags
/// (0-0 through the first half of Iraq v Oman, which stood at 1-0). So a
/// game in play is corrected from 365scores' record of the same fixture:
/// its kick-off time, its minute and its score.
void main() {
  SportMatchItem match(
    String home,
    String away, {
    String kickoff = '',
    int? minute,
    String status = 'live',
    int? homeScore,
    int? awayScore,
  }) =>
      SportMatchItem(
        id: home.hashCode,
        kickoffAt: kickoff,
        status: status,
        minute: minute,
        home: TeamInfo(name: home),
        away: TeamInfo(name: away),
        homeScore: homeScore,
        awayScore: awayScore,
      );

  final agree = SportsService().matchesTeams;

  test('a match without a time takes it, and the minute, from the same fixture', () {
    final fixed = SportsService.fillFrom365(
      match('العراق', 'عُمان'),
      [
        match('السعودية', 'قطر', kickoff: '2026-09-23T20:00:00+03:00'),
        match('العراق', 'عمان', kickoff: '2026-09-23T17:30:00+03:00', minute: 28),
      ],
      agree: agree,
    );
    expect(fixed.kickoffAt, '2026-09-23T17:30:00+03:00');
    expect(fixed.minute, 28);
  });

  test('a game in play shows the live score, not the page\'s stale one', () {
    final fixed = SportsService.fillFrom365(
      match('العراق', 'عُمان', kickoff: '2026-09-23T14:30:00.000Z', homeScore: 0, awayScore: 0),
      [match('العراق', 'عمان', kickoff: '2026-09-23T17:30:00+03:00', minute: 44, homeScore: 1, awayScore: 0)],
      agree: agree,
    );
    expect(fixed.homeScore, 1);
    expect(fixed.awayScore, 0);
    expect(fixed.minute, 44);
    expect(fixed.kickoffAt, '2026-09-23T14:30:00.000Z', reason: 'a time the page gave is kept');
  });

  test('the record\'s final whistle beats the page\'s «live»', () {
    final fixed = SportsService.fillFrom365(
      match('العراق', 'عُمان', kickoff: '2026-09-23T14:30:00.000Z', homeScore: 1, awayScore: 0),
      [match('العراق', 'عمان', kickoff: '2026-09-23T17:30:00+03:00', status: 'finished', homeScore: 2, awayScore: 0)],
      agree: agree,
    );
    expect(fixed.status, 'finished');
    expect(fixed.homeScore, 2);
  });

  test('a scheduled match with its time is left exactly as it is', () {
    final item = match('العراق', 'عُمان', kickoff: '2026-09-23T14:30:00.000Z', status: 'scheduled');
    final fixed = SportsService.fillFrom365(
      item,
      [match('العراق', 'عمان', kickoff: '2026-09-23T17:30:00+03:00', status: 'scheduled')],
      agree: agree,
    );
    expect(identical(fixed, item), isTrue);
  });

  test('no record for the fixture: nothing changes, and the time stays empty, never noon', () {
    final item = match('العراق', 'عُمان');
    final fixed = SportsService.fillFrom365(
      item,
      [match('السنغال', 'الكاميرون', kickoff: '2026-09-23T17:30:00+03:00')],
      agree: agree,
    );
    expect(identical(fixed, item), isTrue);
    expect(fixed.kickoffAt, isEmpty);
  });
}
