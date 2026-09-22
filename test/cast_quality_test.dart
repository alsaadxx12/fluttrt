import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/casting/services/cast_media_source.dart';
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';

CinemanaStreamFile file(String resolution, {String name = ''}) =>
    CinemanaStreamFile(
      resolution: resolution,
      name: name.isEmpty ? resolution : name,
      container: 'mp4',
      videoUrl: 'https://cdn.example.com/$resolution.mp4',
    );

void main() {
  group('which stream a far screen is sent', () {
    test('1080p, not the 4K beside it', () {
      // The real listing for one film: the 4K is 16.14 GB against 1.32 for
      // the 1080p. Sending it meant the phone pulling sixteen gigabytes down
      // and pushing them back out over wifi, to a television whose player
      // could not decode them — a black screen at the end of all that.
      final best = CastMediaSource.pickBest([
        file('240p'),
        file('360p'),
        file('480p'),
        file('720p'),
        file('1080p'),
        file('2160p', name: 'mp4-4k'),
      ]);

      expect(best.resolution, '1080p');
    });

    test('the best below the ceiling when there is no 1080p', () {
      final best = CastMediaSource.pickBest([
        file('360p'),
        file('720p'),
        file('2160p'),
      ]);
      expect(best.resolution, '720p');
    });

    test('a lower ceiling is obeyed', () {
      final best = CastMediaSource.pickBest(
        [file('480p'), file('720p'), file('1080p')],
        maxHeight: 720,
      );
      expect(best.resolution, '720p');
    });

    test('nothing under the ceiling means the smallest, not the largest', () {
      // A catalogue that offers 4K and nothing else. Refusing to cast would
      // be worse than trying, and the smallest is the likeliest to arrive.
      final best = CastMediaSource.pickBest([
        file('2160p', name: 'mp4-4k'),
        file('1440p'),
      ]);
      expect(best.resolution, '1440p');
    });

    test('a single stream is the one that is sent', () {
      final best = CastMediaSource.pickBest([file('2160p')]);
      expect(best.resolution, '2160p');
    });

    test('the number is read from the name when the resolution is blank', () {
      final best = CastMediaSource.pickBest([
        file('', name: 'mp4-720'),
        file('', name: 'mp4-4k'),
      ]);
      expect(best.name, 'mp4-720');
    });
  });
}
