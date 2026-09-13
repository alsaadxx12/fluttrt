import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';

CinemanaItem _item({required String kind, List<String> categoriesEn = const []}) {
  return CinemanaItem.fromJson({
    'nb': '1',
    'ar_title': 'عنوان',
    'en_title': 'Title',
    'kind': kind,
    'stars': '7.0',
    'year': '2026',
    'ar_content': '',
    'en_content': '',
    'categories': [
      for (final c in categoriesEn) {'en_title': c, 'ar_title': 'ترجمة'},
    ],
  });
}

void main() {
  group('CinemanaItem category matching', () {
    test('keeps the English category titles alongside the Arabic ones', () {
      final item = _item(kind: '2', categoriesEn: ['Animation', 'Action']);
      expect(item.categoriesEn, ['Animation', 'Action']);
      expect(item.categories, ['ترجمة', 'ترجمة']);
    });

    test('hasCategoryEn matches regardless of case and padding', () {
      final item = _item(kind: '2', categoriesEn: ['Animation']);
      expect(item.hasCategoryEn('Animation'), true);
      expect(item.hasCategoryEn(' animation '), true);
      expect(item.hasCategoryEn('Action'), false);
      expect(item.hasCategoryEn(''), false);
    });

    test('an item without categories never matches a genre', () {
      expect(_item(kind: '1').hasCategoryEn('Animation'), false);
    });

    test('survives a favorites round-trip through toJson', () {
      final item = _item(kind: '2', categoriesEn: ['Animation', 'Comedy']);
      final restored = CinemanaItem.fromJson(item.toJson());
      expect(restored.hasCategoryEn('Animation'), true);
      expect(restored.hasCategoryEn('Comedy'), true);
    });
  });
}
