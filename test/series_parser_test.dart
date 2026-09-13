import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/series/domain/series_parser_service.dart';

void main() {
  final parser = SeriesParserService();

  group('SeriesParserService Tests', () {
    test('Extract numeric episodes correctly', () {
      expect(parser.extractEpisodeNumber('مسلسل عمر بن الخطاب الحلقة 15 كاملة HD'), 15);
      expect(parser.extractEpisodeNumber('قيامة عثمان حلقة 04 مترجمة'), 4);
      expect(parser.extractEpisodeNumber('مسلسل جعفر العمدة ح 21'), 21);
      expect(parser.extractEpisodeNumber('Breaking Bad Episode 7 1080p'), 7);
      expect(parser.extractEpisodeNumber('Dark S01 Ep. 09'), 9);
      expect(parser.extractEpisodeNumber('مسلسل الحشاشين - 30'), 30);
    });

    test('Extract Arabic word episodes correctly', () {
      expect(parser.extractEpisodeNumber('مسلسل الاختيار الحلقة الأولى كاملة'), 1);
      expect(parser.extractEpisodeNumber('مسلسل باب الحارة الحلقة العاشرة'), 10);
      expect(parser.extractEpisodeNumber('مسلسل سيلفي الحلقة الخامسة عشرة'), 15);
      expect(parser.extractEpisodeNumber('مسلسل التغريبة الفلسطينية الحلقة الخامسة والعشرون'), 25);
      expect(parser.extractEpisodeNumber('مسلسل المختار الثقفي - الحلقة الثالثة والثلاثون'), 33);
      expect(parser.extractEpisodeNumber('مسلسل المختار الثقفي | الحلقة الأربعون'), 40);
      expect(parser.extractEpisodeNumber(':: مسلسل المختار:: الحلقة الأربعون (الأخيرة) ::'), 40);
      expect(parser.extractEpisodeNumber('مسلسل المختار الثقفي - الحلقة الواحدة والأربعون'), 41);
    });

    test('Extract season numbers correctly', () {
      expect(parser.extractSeasonNumber('مسلسل المؤسس عثمان الموسم الثاني الحلقة 10'), 2);
      expect(parser.extractSeasonNumber('مسلسل الكبير الجزء السادس الحلقة 4'), 6);
      expect(parser.extractSeasonNumber('وادي الذئاب الجزء السابع الحلقة 7 HD'), 7);
      expect(parser.extractSeasonNumber('وادي الذئاب الجزء الثامن الحلقة 15'), 8);
      expect(parser.extractSeasonNumber('وادي الذئاب الجزء التاسع الحلقة 22'), 9);
      expect(parser.extractSeasonNumber('وادي الذئاب الجزء العاشر الحلقة 1'), 10);
      expect(parser.extractSeasonNumber('باب الحارة الجزء الحادي عشر الحلقة 5'), 11);
      expect(parser.extractSeasonNumber('باب الحارة الجزء الثاني عشر الحلقة 18'), 12);
      expect(parser.extractSeasonNumber('باب الحارة الجزء الثالث عشر الحلقة 30'), 13);
      expect(parser.extractSeasonNumber('Vikings Season 4 Episode 12'), 4);
      expect(parser.extractSeasonNumber('Stranger Things S03E01'), 3);
      expect(parser.extractSeasonNumber('Days of Study Series Part 3 Episode 1 Full HD'), 3);
      expect(parser.extractSeasonNumber('School Days Series Part 3 Episode 2 Full HD'), 3);
      expect(parser.extractSeasonNumber('مسلسل ايام الدراسة بارت 3 الحلقة 1'), 3);
      expect(parser.extractSeasonNumber('مسلسل ايام الدراسة 3 الحلقة 1'), 3);
      expect(parser.extractSeasonNumber('ايام الدراسة ج3 الحلقة 5'), 3);
      expect(parser.extractSeasonNumber('مسلسل ايام الدراسة 3 | 1'), 3);
      expect(parser.extractSeasonNumber('مسلسل كذا الحلقة 5'), 1); // default season 1
    });

    test('Extract S01E02 and pipe episodes correctly', () {
      expect(parser.extractEpisodeNumber('Stranger Things S03E01'), 1);
      expect(parser.extractEpisodeNumber('Days of Study Series Part 3 Episode 1 Full HD'), 1);
      expect(parser.extractEpisodeNumber('School Days Series Part 3 Episode 2 Full HD'), 2);
      expect(parser.extractEpisodeNumber('مسلسل ايام الدراسة 3 | 1'), 1);
    });

    test('Filter noise and trailers', () {
      // Create mock video titles testing isNoiseVideo logic
      expect(parser.extractEpisodeNumber('برومو مسلسل الحشاشين رمضان 2024'), null);
    });
  });
}
