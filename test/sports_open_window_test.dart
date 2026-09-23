import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/sports/data/models/sports_models.dart';

/// A match still to come can be opened only from a quarter of an hour
/// before kick-off; one in play or over, always.
void main() {
  SportMatchItem at(DateTime kickoff, {String status = 'scheduled'}) => SportMatchItem(
        id: 1,
        kickoffAt: kickoff.toUtc().toIso8601String(),
        status: status,
        home: TeamInfo(name: 'العراق'),
        away: TeamInfo(name: 'عمان'),
      );

  test('an hour before kick-off the match is closed', () {
    expect(at(DateTime.now().add(const Duration(hours: 1))).canOpen, isFalse);
  });

  test('ten minutes before kick-off it is open', () {
    expect(at(DateTime.now().add(const Duration(minutes: 10))).canOpen, isTrue);
  });

  test('a match in play is open whatever the clock says', () {
    expect(at(DateTime.now().add(const Duration(hours: 1)), status: 'live').canOpen, isTrue);
  });

  test('a match with no kick-off time is not kept out', () {
    final m = SportMatchItem(id: 1, kickoffAt: '', status: 'scheduled', home: TeamInfo(name: 'a'), away: TeamInfo(name: 'b'));
    expect(m.canOpen, isTrue);
  });

  test('it opens exactly a quarter of an hour before', () {
    final ko = DateTime(2026, 9, 23, 17, 30);
    expect(at(ko).opensAt, DateTime(2026, 9, 23, 17, 15));
  });
}
