import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/sports/data/models/sports_models.dart';
import 'package:youtube_downloader/features/sports/data/services/sports_service.dart';

/// Once a match is under way the Kora x90 page shows the score where the
/// time was. The app used to put noon UTC there, so Iraq v Oman, which
/// kicked off at half past five, was shown as a three o'clock game. Now a
/// missing time is taken from 365scores' record of the same fixture.
void main() {
  SportMatchItem match(String home, String away, {String kickoff = '', int? minute}) => SportMatchItem(
        id: home.hashCode,
        kickoffAt: kickoff,
        status: 'live',
        minute: minute,
        home: TeamInfo(name: home),
        away: TeamInfo(name: away),
      );

  final agree = SportsService().matchesTeams;

  test('a match without a time takes it, and the minute, from the same fixture', () {
    final fixed = SportsService.fillKickoff(
      match('العراق', 'عُمان'),
      [
        match('السعودية', 'قطر', kickoff: '2026-09-23T20:00:00+03:00'),
        match('العراق', 'عمان', kickoff: '2026-09-23T17:30:00+03:00', minute: 28)
      ],
      agree: agree,
    );
    expect(fixed.kickoffAt, '2026-09-23T17:30:00+03:00');
    expect(fixed.minute, 28);
  });

  test('a match that has its time keeps it', () {
    final fixed = SportsService.fillKickoff(
      match('العراق', 'عُمان', kickoff: '2026-09-23T14:30:00.000Z'),
      [match('العراق', 'عمان', kickoff: '2026-09-23T17:30:00+03:00')],
      agree: agree,
    );
    expect(fixed.kickoffAt, '2026-09-23T14:30:00.000Z');
  });

  test('no record for the fixture: the time stays empty, never noon', () {
    final fixed = SportsService.fillKickoff(
      match('العراق', 'عُمان'),
      [match('السنغال', 'الكاميرون', kickoff: '2026-09-23T17:30:00+03:00')],
      agree: agree,
    );
    expect(fixed.kickoffAt, isEmpty);
  });
}
