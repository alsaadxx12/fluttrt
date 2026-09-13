import '../../../cinemana/data/models/cinemana_models.dart';
import '../../../cinemana/data/services/cinemana_service.dart';
import '../../domain/media_item.dart';
import '../../domain/media_key.dart';
import '../../domain/media_provider.dart';

/// Cinemana behind the shared interface.
///
/// This is an adapter only: it calls the existing [CinemanaService] and
/// changes nothing about it, so every screen that already uses Cinemana
/// keeps working exactly as before.
class CinemanaMediaProvider implements MediaProvider {
  final CinemanaService _service;
  CinemanaMediaProvider(this._service);

  static const providerId = 'cinemana';

  @override
  String get id => providerId;

  /// The primary source: it owns how a shared work is shown.
  @override
  int get priority => 0;

  @override
  Future<List<MediaItem>> getHome() async => toMediaList(await _service.fetchRecentlyAdded());

  @override
  Future<List<MediaItem>> getMovies({int page = 0}) async => toMediaList(await _service.fetchMovies(page: page));

  @override
  Future<List<MediaItem>> getSeries({int page = 0}) async => toMediaList(await _service.fetchSeries(page: page));

  @override
  Future<List<MediaItem>> search(String query) async => toMediaList(await _service.search(query));

  @override
  Future<MediaItem?> getDetails(String externalId) async {
    final item = await _service.fetchItemDetails(externalId);
    return item == null ? null : toMedia(item);
  }

  @override
  Future<List<MediaItem>> getEpisodes(String seriesExternalId) async {
    final episodes = await _service.fetchEpisodes(seriesExternalId);
    return [
      for (final e in episodes)
        () {
          final name = e.arTitle.trim().isNotEmpty ? e.arTitle.trim() : e.enTitle.trim();
          final latin = e.enTitle.trim().isNotEmpty ? e.enTitle.trim() : e.arTitle.trim();
          return MediaItem(
            contentId: 'episode:${MediaKey.normalizeTitle(latin)}:s${e.intSeasonNumber}:e${e.intEpisodeNumber}',
            title: name,
            originalTitle: latin,
            kind: MediaKind.episode,
            duration: int.tryParse(e.duration.trim()),
            seriesTitle: latin,
            seasonNumber: e.intSeasonNumber,
            episodeNumber: e.intEpisodeNumber,
            sources: [
              MediaSource(
                provider: providerId,
                externalId: e.id,
                posterUrl: e.imgUrl,
                // Cinemana ships Arabic subtitles across its catalogue.
                hasSubtitles: true,
              ),
            ],
          );
        }(),
    ];
  }

  static List<MediaItem> toMediaList(List<CinemanaItem> items) => [for (final i in items) toMedia(i)];

  /// Cinemana's own shape turned into the shared model.
  static MediaItem toMedia(CinemanaItem i) {
    final isSeries = i.kind == '2';
    final english = i.enTitle.trim();
    final arabic = i.arTitle.trim();
    final year = int.tryParse(i.year.trim()) ?? MediaKey.extractYear(english.isNotEmpty ? english : arabic);
    final item = MediaItem(
      contentId: '',
      title: arabic.isNotEmpty ? arabic : english,
      originalTitle: english.isNotEmpty ? english : arabic,
      kind: isSeries ? MediaKind.series : MediaKind.movie,
      year: year,
      overview: i.arContent.trim().isNotEmpty ? i.arContent.trim() : i.enContent.trim(),
      duration: int.tryParse(i.duration.trim()),
      genres: i.categories.isNotEmpty ? i.categories : i.categoriesEn,
      seasonNumber: int.tryParse(i.season.trim()),
      episodeNumber: int.tryParse(i.episodeNummer.trim()),
      sources: [
        MediaSource(
          provider: providerId,
          externalId: i.id,
          posterUrl: i.imgMediumUrl ?? i.imgUrl ?? i.imgThumbUrl,
          backdropUrl: i.backdropUrl,
          hasSubtitles: true,
        ),
      ],
    );
    // The identity is derived, never stored by a provider.
    return MediaItem(
      contentId: MediaKey.of(item),
      title: item.title,
      originalTitle: item.originalTitle,
      kind: item.kind,
      year: item.year,
      overview: item.overview,
      duration: item.duration,
      genres: item.genres,
      seriesTitle: item.seriesTitle,
      seasonNumber: item.seasonNumber,
      episodeNumber: item.episodeNumber,
      sources: item.sources,
    );
  }
}
