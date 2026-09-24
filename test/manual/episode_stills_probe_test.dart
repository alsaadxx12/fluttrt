@Tags(['manual'])
library;

// Live: does TMDB hand back a still for each episode of the kinds of series
// the Asian-drama catalogue lists? Run by hand:
//   flutter test test/manual/episode_stills_probe_test.dart --tags manual
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/trailers/data/tmdb_service.dart';

void main() {
  test('stills for a few series, by Arabic name with an original-name hint', () async {
    final tmdb = TmdbService();
    final cases = <(String, String?, String?)>[
      ('مسلسل الحب الحقيقي', 'True Beauty', '2020'),
      ('مسلسل لعبة الحبار', 'Squid Game', '2021'),
      ('مسلسل الملكة الأخيرة', 'The Last Empress', null),
      ('مسلسل وادي الذئاب', null, null),
    ];
    for (final (title, hint, year) in cases) {
      final stills = await tmdb.episodeStills(title, hint: hint, year: year);
      final sample = stills.entries.take(2).map((e) => '${e.key}: ${e.value}').join(', ');
      // ignore: avoid_print
      print('$title -> ${stills.length} stills; $sample');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
