import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/sports/data/models/sports_models.dart';
import 'package:youtube_downloader/features/sports/data/services/sports_service.dart';

void main() {
  group('SportsService.parseTimeToUtcIso', () {
    test('passes through valid ISO-8601 UTC timestamps', () {
      const iso = '2026-09-21T15:00:00.000Z';
      final res = SportsService.parseTimeToUtcIso(iso);
      expect(res, '2026-09-21T15:00:00.000Z');
    });

    test('parses 12-hour PM times from Mecca/Arabic feeds into UTC', () {
      final res = SportsService.parseTimeToUtcIso('6:00 PM', day: 'today');
      final dt = DateTime.parse(res);
      expect(dt.isUtc, isTrue);
      // 6:00 PM Mecca (UTC+3) is 15:00 UTC
      expect(dt.hour, 15);
      expect(dt.minute, 0);
    });

    test('parses 12-hour Arabic text times into UTC', () {
      final res = SportsService.parseTimeToUtcIso('8:15 م', day: 'today');
      final dt = DateTime.parse(res);
      expect(dt.isUtc, isTrue);
      // 8:15 PM Mecca (UTC+3) is 17:15 UTC
      expect(dt.hour, 17);
      expect(dt.minute, 15);
    });

    test('parses 24-hour times into UTC', () {
      final res = SportsService.parseTimeToUtcIso('18:00', day: 'today');
      final dt = DateTime.parse(res);
      expect(dt.isUtc, isTrue);
      // 18:00 Mecca (UTC+3) is 15:00 UTC
      expect(dt.hour, 15);
      expect(dt.minute, 0);
    });

    test('parses tomorrow times with correct date offset', () {
      final res = SportsService.parseTimeToUtcIso('6:00 PM', day: 'tomorrow');
      final dt = DateTime.parse(res);
      final now = DateTime.now();
      final tomorrow = now.add(const Duration(days: 1));
      expect(dt.day, tomorrow.day);
      expect(dt.hour, 15);
    });

    test('parses yesterday times with correct date offset', () {
      final res = SportsService.parseTimeToUtcIso('6:00 PM', day: 'yesterday');
      final dt = DateTime.parse(res);
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));
      expect(dt.day, yesterday.day);
      expect(dt.hour, 15);
    });

    test('handles empty or blank string gracefully', () {
      expect(SportsService.parseTimeToUtcIso(''), '');
      expect(SportsService.parseTimeToUtcIso('   '), '');
    });
  });

  group('SportMatchItem lifecycle with parsed kickoff times', () {
    test('match with future kickoff is scheduled', () {
      final futureKo = DateTime.now().toUtc().add(const Duration(hours: 2)).toIso8601String();
      final m = SportMatchItem(
        id: 1,
        kickoffAt: futureKo,
        status: 'scheduled',
        home: TeamInfo(name: 'Team A'),
        away: TeamInfo(name: 'Team B'),
      );
      expect(m.isLive, isFalse);
      expect(m.isEnded, isFalse);
      expect(m.isScheduled, isTrue);
    });

    test('match with past kickoff (> 3h) is ended', () {
      final pastKo = DateTime.now().toUtc().subtract(const Duration(hours: 4)).toIso8601String();
      final m = SportMatchItem(
        id: 2,
        kickoffAt: pastKo,
        status: 'scheduled',
        home: TeamInfo(name: 'Team A'),
        away: TeamInfo(name: 'Team B'),
      );
      expect(m.isEnded, isTrue);
      expect(m.isLive, isFalse);
    });
  });
}
