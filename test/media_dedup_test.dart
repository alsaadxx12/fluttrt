import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/media/domain/media_item.dart';
import 'package:youtube_downloader/features/media/domain/media_key.dart';
import 'package:youtube_downloader/features/media/domain/media_merger.dart';
import 'package:youtube_downloader/features/media/providers/filmrise/filmrise_api.dart';
import 'package:youtube_downloader/features/media/providers/filmrise/filmrise_media_provider.dart';

MediaItem movie(String title, {int? year, required String provider, String id = 'x', String? poster}) {
  final base = MediaItem(
    contentId: '',
    title: title,
    originalTitle: title,
    kind: MediaKind.movie,
    year: year,
    sources: [MediaSource(provider: provider, externalId: id, posterUrl: poster)],
  );
  return MediaItem(
    contentId: MediaKey.of(base),
    title: base.title,
    originalTitle: base.originalTitle,
    kind: base.kind,
    year: base.year,
    sources: base.sources,
  );
}

MediaItem series(String title, {required String provider, String id = 'x'}) {
  final base = MediaItem(
    contentId: '',
    title: title,
    originalTitle: title,
    kind: MediaKind.series,
    sources: [MediaSource(provider: provider, externalId: id)],
  );
  return MediaItem(
    contentId: MediaKey.of(base),
    title: title,
    originalTitle: title,
    kind: MediaKind.series,
    sources: base.sources,
  );
}

MediaItem episode(String show, int s, int e, {required String provider}) {
  final base = MediaItem(
    contentId: '',
    title: '$show S${s}E$e',
    originalTitle: '$show S${s}E$e',
    kind: MediaKind.episode,
    seriesTitle: show,
    seasonNumber: s,
    episodeNumber: e,
    sources: [MediaSource(provider: provider, externalId: '$show-$s-$e')],
  );
  return MediaItem(
    contentId: MediaKey.of(base),
    title: base.title,
    originalTitle: base.originalTitle,
    kind: MediaKind.episode,
    seriesTitle: show,
    seasonNumber: s,
    episodeNumber: e,
    sources: base.sources,
  );
}

void main() {
  group('title normalisation', () {
    test('strips case, punctuation, noise words and a leading article', () {
      expect(MediaKey.normalizeTitle('The Dark Knight'), 'dark knight');
      expect(MediaKey.normalizeTitle('the dark knight (2008)'), 'dark knight');
      expect(MediaKey.normalizeTitle('The Dark Knight - Full Movie HD'), 'dark knight');
      expect(MediaKey.normalizeTitle('  The   Dark  Knight!!  '), 'dark knight');
      expect(MediaKey.normalizeTitle('The Dark Knight [Official] 1080p'), 'dark knight');
    });

    test('a sequel number is identity, not noise', () {
      expect(MediaKey.normalizeTitle('Rocky II') == MediaKey.normalizeTitle('Rocky'), isFalse);
      expect(MediaKey.normalizeTitle('Toy Story 3') == MediaKey.normalizeTitle('Toy Story'), isFalse);
    });

    test('reads a year out of a title', () {
      expect(MediaKey.extractYear('The Dark Knight (2008)'), 2008);
      expect(MediaKey.extractYear('The Dark Knight - 2008'), 2008);
      expect(MediaKey.extractYear('The Dark Knight'), isNull);
    });

    test('reads season and episode out of a title', () {
      expect(MediaKey.extractEpisode('Breaking Bad S02E05'), (2, 5));
      expect(MediaKey.extractEpisode('Breaking Bad 2x05'), (2, 5));
      expect(MediaKey.extractEpisode('Breaking Bad'), (null, null));
    });
  });

  group('deduplication', () {
    test('the same film from both providers shows once, with both sources', () {
      final merged = MediaMerger.merge([
        [movie('The Dark Knight - 2008', year: 2008, provider: 'cinemana', id: 'c1')],
        [movie('The Dark Knight (2008)', year: 2008, provider: 'filmrise', id: 'f1')],
      ]);

      expect(merged.length, 1);
      expect(merged.first.sources.length, 2);
      expect(merged.first.sources.first.provider, 'cinemana', reason: 'Cinemana stays the primary source');
      expect(merged.first.sources[1].provider, 'filmrise');
      expect(merged.first.fallbackSource?.externalId, 'f1');
    });

    test('a film only FilmRise has is added', () {
      final merged = MediaMerger.merge([
        [movie('The Dark Knight', year: 2008, provider: 'cinemana')],
        [movie('Night of the Living Dead', year: 1968, provider: 'filmrise', id: 'f9')],
      ]);
      expect(merged.length, 2);
      expect(merged.last.hasProvider('filmrise'), isTrue);
      expect(merged.last.hasProvider('cinemana'), isFalse);
    });

    test('the same title with a different year is a different work', () {
      final merged = MediaMerger.merge([
        [movie('The Lion King', year: 1994, provider: 'cinemana')],
        [movie('The Lion King', year: 2019, provider: 'filmrise', id: 'f2')],
      ]);
      expect(merged.length, 2, reason: 'a remake is its own film');
    });

    test('a series in both providers shows once', () {
      final merged = MediaMerger.merge([
        [series('Breaking Bad', provider: 'cinemana', id: 'c5')],
        [series('breaking bad', provider: 'filmrise', id: 'f5')],
      ]);
      expect(merged.length, 1);
      expect(merged.first.sources.length, 2);
    });

    test('different episodes of one series are never folded together', () {
      final merged = MediaMerger.merge([
        [episode('Breaking Bad', 1, 1, provider: 'cinemana'), episode('Breaking Bad', 1, 2, provider: 'cinemana')],
        [episode('Breaking Bad', 1, 2, provider: 'filmrise'), episode('Breaking Bad', 2, 1, provider: 'filmrise')],
      ]);
      expect(merged.length, 3, reason: 'S1E1, S1E2 and S2E1');
      final shared = merged.firstWhere((m) => m.seasonNumber == 1 && m.episodeNumber == 2);
      expect(shared.sources.length, 2, reason: 'the same episode from both providers merges');
    });

    test('a missing year falls back to title similarity', () {
      final merged = MediaMerger.merge([
        [movie('Casablanca', year: 1942, provider: 'cinemana')],
        [movie('Casablanca', provider: 'filmrise', id: 'f3')],
      ]);
      expect(merged.length, 1);
      expect(merged.first.sources.length, 2);
      expect(merged.first.year, 1942, reason: 'the known year survives');
    });

    test('similar but different titles are not merged', () {
      final merged = MediaMerger.merge([
        [movie('Spider-Man', provider: 'cinemana')],
        [movie('Spider-Man 2', provider: 'filmrise', id: 'f4')],
      ]);
      expect(merged.length, 2);
    });

    test('a different picture never makes a second card', () {
      final merged = MediaMerger.merge([
        [movie('Fight Club', year: 1999, provider: 'cinemana', id: 'c7', poster: '')],
        [movie('Fight Club', year: 1999, provider: 'filmrise', id: 'f7', poster: 'https://f/img.jpg')],
      ]);
      expect(merged.length, 1);
      expect(merged.first.posterUrl, 'https://f/img.jpg', reason: 'the gap is filled from the other source');
    });

    test('a provider that returns nothing leaves the rest untouched', () {
      final merged = MediaMerger.merge([
        [movie('Heat', year: 1995, provider: 'cinemana')],
        <MediaItem>[],
      ]);
      expect(merged.length, 1);
      expect(merged.first.hasProvider('cinemana'), isTrue);
    });
  });

  group('FilmRise content filter', () {
    FilmRiseRow row(Map<String, dynamic> j) => FilmRiseRow.fromJson({
          'id': '1',
          'title': 'x',
          'type': 'post',
          'feed_type': 'video',
          'video_url': 'https://v/x.mp4',
          ...j,
        });

    test('short clips from the same endpoint are refused', () {
      expect(
        FilmRiseApi.looksLikeFilm(row({
          'title': 'We Only Ate Red Foods for 24 Hours Challenge',
          'path_alias': 'kids-edutainment/123-red-foods',
        })),
        isFalse,
      );
      expect(FilmRiseApi.looksLikeFilm(row({'title': 'How To Make Pasta', 'path_alias': 'dish/1-pasta'})), isFalse);
    });

    test('a row with no playable url is refused', () {
      expect(FilmRiseApi.looksLikeFilm(row({'video_url': '', 'path_alias': 'movies/1-x'})), isFalse);
    });

    test('a film section, a film feed type or a feature length is accepted', () {
      expect(FilmRiseApi.looksLikeFilm(row({'title': 'Night of the Living Dead', 'path_alias': 'movies/1-notld'})), isTrue);
      expect(FilmRiseApi.looksLikeFilm(row({'title': 'Some Show', 'feed_type': 'series'})), isTrue);
      expect(FilmRiseApi.looksLikeFilm(row({'title': 'Long Feature', 'duration': 5400})), isTrue);
    });

    test('an accepted row becomes a usable media item', () {
      final item = FilmRiseMediaProvider.toMedia(row({
        'title': 'Night of the Living Dead (1968)',
        'path_alias': 'movies/1-notld',
        'main_picture': 'https://img/hd.jpg',
        'duration': 5760,
      }));
      expect(item.kind, MediaKind.movie);
      expect(item.year, 1968);
      expect(item.duration, 96);
      expect(item.primarySource?.provider, 'filmrise');
      expect(item.primarySource?.streamUrl, 'https://v/x.mp4');
      expect(item.posterUrl, 'https://img/hd.jpg');
    });
  });
}
