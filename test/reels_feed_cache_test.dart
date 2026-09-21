import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';
import 'package:youtube_downloader/features/reels/data/reels_service.dart';
import 'package:youtube_downloader/features/reels/presentation/providers/reels_feed_provider.dart';

/// The scenes feed is kept on the device between launches, so a reel must
/// survive the trip through JSON unchanged — its catalogue entry with it,
/// so the «مشاهدة الفيلم» link is still there on the next launch.
void main() {
  const item = CinemanaItem(
    id: '4321',
    arTitle: 'نهاية شارع أوك',
    enTitle: 'The End of Oak Street',
    stars: '7.1',
    year: '2026',
    kind: '1',
    arContent: 'وصف',
    enContent: 'desc',
    imgUrl: 'https://cnth2.shabakaty.com/p/full.jpg',
    imgThumbUrl: 'https://cnth2.shabakaty.com/p/thumb.jpg',
    imgMediumUrl: 'https://cnth2.shabakaty.com/p/medium.jpg',
    categories: ['دراما'],
    categoriesEn: ['Drama'],
    trailerUrl: 'https://youtu.be/t',
    duration: '98',
  );

  Reel reel({CinemanaItem? catalogItem}) => Reel(
        id: 'abc12345678',
        title: 'نهاية شارع أوك (2026)',
        author: 'إعلان رسمي',
        channelId: 'UC123',
        description: 'desc',
        duration: const Duration(seconds: 42),
        viewCount: 1234,
        likeCount: 56,
        uploadDate: DateTime.utc(2026, 9, 1),
        thumbnail: 'https://cnth2.shabakaty.com/p/full.jpg',
        catalogItem: catalogItem,
      );

  test('a reel round-trips through the on-device cache', () {
    final r = reel();
    final back = reelFromJson(reelToJson(r));
    expect(back.id, r.id);
    expect(back.title, r.title);
    expect(back.author, r.author);
    expect(back.channelId, r.channelId);
    expect(back.description, r.description);
    expect(back.duration, r.duration);
    expect(back.viewCount, r.viewCount);
    expect(back.likeCount, r.likeCount);
    expect(back.uploadDate, r.uploadDate);
    expect(back.kind, Reel.kindTrailer);
    expect(back.thumbnail, r.thumbnail);
    expect(back.thumbnailUrl, r.thumbnailUrl);
    expect(back.catalogItem, isNull);
    expect(back.isSeries, isFalse);
  });

  test('the catalogue entry goes with it, through real JSON text, and comes back as the same film', () {
    final r = reel(catalogItem: item);
    final json = reelToJson(r);
    expect(json['catalogItem'], isA<Map<String, dynamic>>());
    final back = reelFromJson(jsonDecode(jsonEncode(json)) as Map<String, dynamic>);
    final got = back.catalogItem;
    expect(got, isNotNull);
    expect(got!.id, item.id);
    expect(got.arTitle, item.arTitle);
    expect(got.enTitle, item.enTitle);
    expect(got.year, item.year);
    expect(got.kind, item.kind);
    expect(got.isSeries, isFalse);
    expect(got.stars, item.stars);
    expect(got.arContent, item.arContent);
    expect(got.enContent, item.enContent);
    expect(got.imgUrl, item.imgUrl);
    expect(got.imgMediumUrl, item.imgMediumUrl);
    expect(got.imgThumbUrl, item.imgThumbUrl);
    expect(got.categories, item.categories);
    expect(got.categoriesEn, item.categoriesEn);
    expect(got.trailerUrl, item.trailerUrl);
    expect(got.duration, item.duration);
    expect(back.isSeries, isFalse);
  });

  test('a series comes back as a series', () {
    final back = reelFromJson(reelToJson(reel(catalogItem: item.copyWith(kind: '2'))));
    expect(back.catalogItem?.isSeries, isTrue);
    expect(back.isSeries, isTrue);
  });

  test('missing optional fields come back as null, not as a crash', () {
    final back = reelFromJson({'id': 'x'});
    expect(back.id, 'x');
    expect(back.title, '');
    expect(back.duration, isNull);
    expect(back.viewCount, isNull);
    expect(back.uploadDate, isNull);
    expect(back.thumbnail, isNull);
    expect(back.thumbnailUrl, contains('oardefault'));
    expect(back.catalogItem, isNull);
    expect(reelFromJson({'id': 'x', 'catalogItem': null}).catalogItem, isNull);
    expect(reelFromJson({'id': 'x', 'catalogItem': 'junk'}).catalogItem, isNull, reason: 'not a map: no entry');
  });
}
