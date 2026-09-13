import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/watch/domain/watch_models.dart';

void main() {
  group('WatchModels Tests', () {
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
