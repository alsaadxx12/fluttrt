import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';
import 'package:youtube_downloader/features/cinemana/data/services/cinemana_service.dart';

CinemanaItem series(String lang, {List<String> cats = const ['Drama']}) =>
    CinemanaItem.fromJson({
      'nb': 'x',
      'en_title': 'Show',
      'ar_title': 'مسلسل',
      'year': '2026',
      'kind': '2',
      'language_lighttigerNb': lang,
      'categories': [for (final c in cats) {'en_title': c, 'ar_title': c}],
    });

void main() {
  test('the language id is read off the catalogue entry', () {
    // It is the only handle Cinemana gives on where a series is from.
    expect(series('23').languageId, '23');
    expect(CinemanaItem.fromJson({'nb': '1'}).languageId, '');
  });

  group('what counts as an Asian series', () {
    test('Korean, Japanese and Chinese belong', () {
      for (final lang in ['23', '22', '21', '47', '80']) {
        expect(CinemanaService.isAsianSeries(series(lang)), isTrue, reason: lang);
      }
    });

    test('Turkish, Arabic, Indian and English do not', () {
      // Turkish and Indian drama are their own thing, not what the row means.
      for (final lang in ['25', '9', '10', '7']) {
        expect(CinemanaService.isAsianSeries(series(lang)), isFalse, reason: lang);
      }
    });

    test('a Japanese animated series is anime, and the page already has it', () {
      expect(
        CinemanaService.isAsianSeries(series('22', cats: ['Animation', 'Action'])),
        isFalse,
      );
    });

    test('a series with no language is left out rather than guessed at', () {
      expect(CinemanaService.isAsianSeries(series('')), isFalse);
    });
  });
}
