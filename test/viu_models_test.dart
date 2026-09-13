import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/viu/data/viu_models.dart';

void main() {
  test('series entry: names, dubbing, trailers, images', () {
    final s = ViuShow.fromSeries({
      'series_id': '107446',
      'name': 'بنات الشمس - مدبلج',
      'is_movie': '0',
      'user_level': 2,
      'cover_portrait_image_url': 'https://prod-images.viu.com/1/p',
      'cover_landscape_image_url': 'https://prod-images.viu.com/1/l',
      'category_name': 'مسلسلات تركية',
    });
    expect(s.displayName, 'بنات الشمس');
    expect(s.isDubbed, isTrue);
    expect(s.isMovie, isFalse);
    expect(s.userLevel, 2);
    expect(s.portraitUrl, endsWith('/p'));
    expect(ViuShow.fromSeries({'series_id': '1', 'name': 'أرواح مسروقة (مدبلج)'}).displayName, 'أرواح مسروقة');
    expect(ViuShow.fromSeries({'series_id': '1', 'name': 'سائق سيارة أجرة - الموسم 3 - إعلان'}).isTrailer, isTrue);
    expect(ViuShow.fromSeries({'series_id': '1', 'name': 'x', 'cover_portrait_image_url': ''}).portraitUrl, isNull);
  });

  test('episode: free flag, number and duration', () {
    final e = ViuEpisode.fromJson({
      'product_id': '3250335',
      'ccs_product_id': '1166310278',
      'number': '12',
      'user_level': 0,
      'time_duration': '2750',
    });
    expect(e.isFree, isTrue);
    expect(e.number, 12);
    expect(e.durationLabel, '46 د');
    expect(ViuEpisode.fromJson({'product_id': '1', 'ccs_product_id': '2', 'user_level': 2}).isFree, isFalse);
    expect(ViuEpisode.fromJson({'product_id': '1', 'ccs_product_id': '2', 'time_duration': 5460}).durationLabel,
        '1 س 31 د');
  });

  test('home shows the four requested categories in order', () {
    expect(ViuCategory.home.map((c) => c.title),
        ['مسلسلات عربية', 'مسلسلات كورية', 'مسلسلات تركية', 'أفلام أخرى']);
    expect(ViuCategory.home.last.isMovies, isTrue);
  });

  test('original and dubbed versions share one card', () {
    ViuShow show(String id, String name) => ViuShow(seriesId: id, name: name, categoryName: 'مسلسلات تركية');
    final merged = ViuShow.mergeVersions([
      show('1', 'بنات الشمس'),
      show('2', 'بنات الشمس - مدبلج'),
      show('3', 'ارواح مسروقة'),
      show('4', 'أرواح مسروقة (مدبلج)'),
      show('5', 'معجزة القرن - مدبلج'),
      show('6', 'معجزة القرن 1'),
      show('7', 'خير، شر وشهرة - مدبلج'),
      show('8', 'خير, شر وشهرة'),
      show('9', 'الفقيرة والأمير- مدبلج'),
      show('10', 'الفقيرة والأمير'),
      show('11', 'سائق سيارة أجرة - الموسم 3'),
      show('12', 'سائق سيارة أجرة - الموسم 2'), // another season: its own card
      show('13', 'صفحة بيضا'),
      show('14', 'صفحة بيضا - يعرض الآن'),
      show('1', 'بنات الشمس'), // the same entry twice
    ]);
    expect(merged.map((m) => m.displayName), [
      'بنات الشمس',
      'ارواح مسروقة',
      'معجزة القرن',
      'خير، شر وشهرة',
      'الفقيرة والأمير',
      'سائق سيارة أجرة - الموسم 3',
      'سائق سيارة أجرة - الموسم 2',
      'صفحة بيضا',
    ]);
    expect(merged.first.versions.map((v) => v.seriesId), ['1', '2']);
    expect(merged.first.versions.map((v) => v.versionLabel), ['مترجم', 'مدبلج']);
    expect(merged.first.hasDubbedVersion && merged.first.hasOriginalVersion, isTrue);
    expect(merged.last.versions.map((v) => v.versionLabel), ['مترجم', 'يعرض الآن']);
    expect(const ViuShow(seriesId: 'a', name: 'عيلة الملك', categoryName: 'مسلسلات عربية').versionLabel, 'الأصلي');
  });
}
