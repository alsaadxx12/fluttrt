@Tags(['manual'])
library;

// Live: what the «الأكثر مشاهدة» row now holds - this year's and last
// year's films, the ones the world watches most first. Run by hand:
//   flutter test test/manual/recent_top_rated_probe_test.dart --tags manual
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/cinemana/data/services/cinemana_service.dart';
import 'package:youtube_downloader/features/trailers/data/tmdb_service.dart';

void main() {
  test('the newest films, most watched first', () async {
    final service = CinemanaService();
    final tmdb = TmdbService();
    final year = DateTime.now().year;
    final films = [
      ...await service.fetchFilmsOfYear(year, pages: 12),
      ...await service.fetchFilmsOfYear(year - 1, pages: 6),
    ];
    final popular = [
      ...await tmdb.popularFilmTitles(year: year, pages: 4),
      ...await tmdb.popularFilmTitles(year: year - 1, pages: 2),
    ];
    // ignore: avoid_print
    print('films: ${films.length}  popular titles: ${popular.length}');
    final ranked = CinemanaService.rankByPopularity(films, popular).take(24).toList();
    for (final it in ranked) {
      // ignore: avoid_print
      print('${it.year}  ${it.stars.padLeft(4)}  ${it.enTitle}');
    }
    expect(ranked, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
