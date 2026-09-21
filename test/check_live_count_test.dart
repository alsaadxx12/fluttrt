import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/sports/data/services/sports_service.dart';

void main() {
  test('inspect live matches ids and links', () async {
    final service = SportsService();
    final groups = await service.fetchKoraX90Matches(day: 'today');
    final all = groups.expand((g) => g.matches).where((m) => m.isLive || m.status == 'live').toList();
    expect(groups, isNotEmpty);
    expect(all, isNotEmpty);
  });
}
