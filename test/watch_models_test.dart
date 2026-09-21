import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/core/utils/formatters.dart';
import 'package:youtube_downloader/features/watch/domain/watch_models.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  group('WatchModels Tests', () {
    test('PlayableItem.fromVideo carries the video metadata across', () {
      final uploaded = DateTime(2024, 3, 15);
      final video = Video(
        VideoId('dQw4w9WgXcQ'),
        'Some Video',
        'Some Channel',
        ChannelId('UCuAXFkgsw1L7xaCfnd5JJOw'),
        uploaded,
        '2024-03-15',
        null,
        '  A description with spaces around it.  ',
        const Duration(minutes: 3, seconds: 33),
        const ThumbnailSet('dQw4w9WgXcQ'),
        const ['a', 'b'],
        const Engagement(1234567, 100, null),
        false,
      );

      final item = PlayableItem.fromVideo(video);

      expect(item.id, equals('dQw4w9WgXcQ'));
      expect(item.title, equals('Some Video'));
      expect(item.author, equals('Some Channel'));
      expect(item.duration, equals(const Duration(minutes: 3, seconds: 33)));
      expect(item.thumbnailUrl, isNotEmpty);
      expect(item.viewCount, equals(1234567));
      expect(item.uploadDate, equals(uploaded));
      expect(item.description, equals('A description with spaces around it.'));
      expect(item.channelId, equals('UCuAXFkgsw1L7xaCfnd5JJOw'));
      expect(item.episodeNumber, isNull);
    });

    test('PlayableItem.fromVideo falls back to publishDate and drops an empty description', () {
      final published = DateTime(2023, 1, 1);
      final video = Video(
        VideoId('dQw4w9WgXcQ'),
        'Untitled',
        'Channel',
        ChannelId('UCuAXFkgsw1L7xaCfnd5JJOw'),
        null,
        null,
        published,
        '   ',
        null,
        const ThumbnailSet('dQw4w9WgXcQ'),
        null,
        const Engagement(0, null, null),
        false,
      );

      final item = PlayableItem.fromVideo(video);

      expect(item.uploadDate, equals(published));
      expect(item.description, isNull);
      expect(item.viewCount, equals(0));
    });

    test('Formatters.formatViews compacts counts the way YouTube does', () {
      expect(Formatters.formatViews(null), equals(''));
      expect(Formatters.formatViews(850), equals('850 مشاهدة'));
      expect(Formatters.formatViews(1234), equals('1.2 ألف مشاهدة'));
      expect(Formatters.formatViews(12000), equals('12 ألف مشاهدة'));
      expect(Formatters.formatViews(3400000), equals('3.4 مليون مشاهدة'));
      expect(Formatters.formatViews(2000000000), equals('2 مليار مشاهدة'));
      // Rounding steps up a unit instead of printing '1000 ألف'.
      expect(Formatters.formatViews(999999), equals('1 مليون مشاهدة'));
      expect(Formatters.compactCount(999499), equals('999 ألف'));
    });

    test('Formatters.timeAgo speaks Arabic relative time', () {
      final now = DateTime(2024, 6, 1, 12);
      expect(Formatters.timeAgo(null, now: now), equals(''));
      expect(Formatters.timeAgo(now.subtract(const Duration(days: 3)), now: now), equals('قبل 3 أيام'));
      expect(Formatters.timeAgo(now.subtract(const Duration(days: 14)), now: now), equals('قبل أسبوعين'));
      expect(Formatters.timeAgo(now.subtract(const Duration(days: 150)), now: now), equals('قبل 5 أشهر'));
      expect(Formatters.timeAgo(now.subtract(const Duration(days: 400)), now: now), equals('قبل سنة'));
      expect(Formatters.timeAgo(now.subtract(const Duration(hours: 2)), now: now), equals('قبل ساعتين'));
    });

    test('PlayableItem creates properly with episode information', () {
      const item = PlayableItem(
        id: 'test_id',
        title: 'Test Episode 1',
        author: 'Test Channel',
        thumbnailUrl: 'https://example.com/thumb.jpg',
        episodeNumber: 1,
        seasonNumber: 1,
        seriesName: 'Test Series',
      );

      expect(item.id, equals('test_id'));
      expect(item.title, equals('Test Episode 1'));
      expect(item.episodeNumber, equals(1));
      expect(item.seriesName, equals('Test Series'));
    });

    test('WatchPlaylistContext navigates through playlist correctly', () {
      final items = [
        const PlayableItem(
          id: 'id_1',
          title: 'Ep 1',
          author: 'Channel',
          thumbnailUrl: 'thumb1',
          episodeNumber: 1,
        ),
        const PlayableItem(
          id: 'id_2',
          title: 'Ep 2',
          author: 'Channel',
          thumbnailUrl: 'thumb2',
          episodeNumber: 2,
        ),
        const PlayableItem(
          id: 'id_3',
          title: 'Ep 3',
          author: 'Channel',
          thumbnailUrl: 'thumb3',
          episodeNumber: 3,
        ),
      ];

      final playlist = WatchPlaylistContext(
        title: 'قائمة الحلقات',
        items: items,
        currentIndex: 0,
      );

      expect(playlist.currentItem?.id, equals('id_1'));
      expect(playlist.hasNext, isTrue);
      expect(playlist.hasPrevious, isFalse);
      expect(playlist.nextItem?.id, equals('id_2'));
      expect(playlist.previousItem, isNull);

      final nextPlaylist = playlist.copyWith(currentIndex: 1);
      expect(nextPlaylist.currentItem?.id, equals('id_2'));
      expect(nextPlaylist.hasNext, isTrue);
      expect(nextPlaylist.hasPrevious, isTrue);
      expect(nextPlaylist.nextItem?.id, equals('id_3'));
      expect(nextPlaylist.previousItem?.id, equals('id_1'));

      final lastPlaylist = playlist.copyWith(currentIndex: 2);
      expect(lastPlaylist.currentItem?.id, equals('id_3'));
      expect(lastPlaylist.hasNext, isFalse);
      expect(lastPlaylist.hasPrevious, isTrue);
    });

    test('StreamQualityOption formats correctly', () {
      const option720 = StreamQualityOption(label: '720p', streamUrl: 'https://stream.url/720.mp4');
      const option1080 = StreamQualityOption(label: '1080p', streamUrl: 'https://stream.url/1080.mp4');

      expect(option720.label, equals('720p'));
      expect(option1080.label, equals('1080p'));
      expect(option720.isMuxed, isTrue);
    });
  });
}
