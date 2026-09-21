import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/asia2tv/data/models/asia2tv_models.dart';
import 'package:youtube_downloader/features/asia2tv/data/services/asia2tv_service.dart';
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';

Asia2TvItem entry({
  String id = '1',
  String title = 'دراما',
  String url = 'https://example.test/drama/',
  String poster = 'https://example.test/p.jpg',
  bool isMovie = false,
}) =>
    Asia2TvItem(id: id, title: title, url: url, posterUrl: poster, isMovie: isMovie, year: '2026');

void main() {
  group('only what can be shown and opened is kept', () {
    test('a complete entry is kept', () {
      expect(Asia2TvService.isPlayable(entry()), isTrue);
    });

    test('an entry with no poster is dropped', () {
      // It draws as an empty grey card; the listing pages are full of them.
      expect(Asia2TvService.isPlayable(entry(poster: '')), isFalse);
      expect(Asia2TvService.isPlayable(entry(poster: '   ')), isFalse);
    });

    test('an entry with nothing to open is dropped', () {
      expect(Asia2TvService.isPlayable(entry(url: '')), isFalse);
    });

    test('an entry with no title is dropped', () {
      expect(Asia2TvService.isPlayable(entry(title: '  ')), isFalse);
    });
  });

  group('a title folded into one of the app\'s own rows', () {
    test('a drama reads as a series, a film as a film', () {
      // The converter used to write 'series'/'movies' into `kind`, which
      // `isSeries` does not read, so every drama showed up as a film.
      expect(entry().toCinemanaItem().isSeries, isTrue);
      expect(entry(isMovie: true).toCinemanaItem().isSeries, isFalse);
    });

    test('it is marked as coming from elsewhere', () {
      expect(entry().toCinemanaItem().externalSource, Asia2TvItem.externalSourceKey);
    });

    test('the app\'s own titles carry no such mark', () {
      // Otherwise every card would be routed away from the Cinemana page.
      final own = CinemanaItem.fromJson({'nb': '99', 'en_title': 'Film', 'kind': '1'});
      expect(own.externalSource, isNull);
    });

    test('the entry behind a converted title can be found again', () {
      // A card keeps only the id; opening it needs the original back.
      final original = entry(id: 'abc123');
      final converted = original.toCinemanaItem();
      expect(Asia2TvItem.byId(converted.id), same(original));
    });

    test('an id never seen returns nothing rather than a wrong title', () {
      expect(Asia2TvItem.byId('never-listed'), isNull);
    });
  });
}
