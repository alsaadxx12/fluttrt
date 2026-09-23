import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/cinemana/data/services/cinemana_service.dart';
import 'package:youtube_downloader/features/trailers/data/tmdb_service.dart';

/// Live probe (network): does the wide-still lookup find a TMDB backdrop
/// for each series in the home page's Arabic row? Prints the cleaned name,
/// the hint taken from the poster's file name, and what came back.
void main() {
  test('stills for the arabic series row', () async {
    final items = await CinemanaService().fetchArabicSeries(page: 0, itemsPerPage: 24);
    final tmdb = TmdbService();
    var found = 0;
    for (final it in items) {
      final hint = TmdbService.hintFromImageName(it.imgUrl ?? it.imgThumbUrl);
      final still = await tmdb.backdropForTitle(it.arTitle, year: it.year, series: it.isSeries, hint: hint);
      if (still != null) found++;
      // ignore: avoid_print
      print('${still == null ? "MISS" : "ok  "} "${TmdbService.cleanTitle(it.arTitle)}" hint="$hint" -> ${still?.split('/').last ?? '-'}');
    }
    // ignore: avoid_print
    print('found $found of ${items.length}');
  }, timeout: const Timeout(Duration(minutes: 4)));
}
