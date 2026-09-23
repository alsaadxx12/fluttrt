import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/sports/data/services/sports_service.dart';

void main() {
  test('iraq match times by source', () async {
    final s = SportsService();
    // ignore: avoid_print
    print('now local=${DateTime.now()} utc=${DateTime.now().toUtc()} offset=${DateTime.now().timeZoneOffset}');
    Future<void> show(String name, Future<dynamic> Function() go) async {
      try {
        final result = await go();
        final items = result is List ? result : [];
        for (final x in items) {
          final matches = x.runtimeType.toString().contains('LeagueGroup') ? (x as dynamic).matches : [x];
          for (final m in matches) {
            final text = '${m.home.name} ${m.away.name}';
            if (text.contains('العراق') ||
                text.toLowerCase().contains('iraq') ||
                text.contains('عمان') ||
                text.toLowerCase().contains('oman')) {
              // ignore: avoid_print
              print(
                  '$name: ${m.home.name} v ${m.away.name} kickoffAt=${m.kickoffAt} status=${m.status} minute=${m.minute} league=${m.league} id=${m.id}');
            }
          }
        }
        // ignore: avoid_print
        print('$name: ${items.length} groups/items');
      } catch (e) {
        // ignore: avoid_print
        print('$name failed: $e');
      }
    }

    await show('fetchMatches', () => s.fetchMatches(day: 'today'));
    await show('365', () => s.fetch365Matches(day: 'today'));
    await show('koraX90', () => s.fetchKoraX90Matches(day: 'today'));
    await show('cinamana', () => s.fetchCinamanaMatches());
    await show('fetchLiveMatches', () => s.fetchLiveMatches(day: 'today'));
  }, timeout: const Timeout(Duration(minutes: 4)));
}
