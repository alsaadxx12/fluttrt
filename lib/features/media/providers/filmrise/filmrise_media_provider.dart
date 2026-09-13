import '../../domain/media_item.dart';
import '../../domain/media_key.dart';
import '../../domain/media_provider.dart';
import 'filmrise_api.dart';

/// FilmRise / Future Today as a second, independent source.
///
/// Everything the API returns passes through [FilmRiseApi.looksLikeFilm]
/// first: the same endpoint also serves cooking and kids clips, and those
/// must never reach the film library.
class FilmRiseMediaProvider implements MediaProvider {
  final FilmRiseApi api;
  FilmRiseMediaProvider({FilmRiseApi? api}) : api = api ?? FilmRiseApi();

  static const providerId = 'filmrise';

  @override
  String get id => providerId;

  /// Secondary: it fills gaps and stands in when Cinemana fails, but never
  /// takes over how a shared work is shown.
  @override
  int get priority => 1;

  @override
  Future<List<MediaItem>> getHome() => safely(() async => _map(await api.fetch()));

  @override
  Future<List<MediaItem>> getMovies({int page = 0}) =>
      safely(() async => _map(await api.fetch(page: page), only: MediaKind.movie));

  @override
  Future<List<MediaItem>> getSeries({int page = 0}) =>
      safely(() async => _map(await api.fetch(page: page), only: MediaKind.series));

  @override
  Future<List<MediaItem>> search(String query) =>
      safely(() async => _map(await api.fetch(searchType: 'search', query: query)));

  @override
  Future<MediaItem?> getDetails(String externalId) async {
    try {
      final rows = await api.fetch();
      for (final r in rows) {
        if (r.id == externalId && FilmRiseApi.looksLikeFilm(r)) return toMedia(r);
      }
    } catch (_) {}
    return null;
  }

  /// The backend exposes no per-series episode listing, so a series from
  /// here carries no episodes of its own; Cinemana supplies them when it
  /// has the same series.
  @override
  Future<List<MediaItem>> getEpisodes(String seriesExternalId) async => const [];

  List<MediaItem> _map(List<FilmRiseRow> rows, {MediaKind? only}) {
    final out = <MediaItem>[];
    for (final r in rows) {
      if (!FilmRiseApi.looksLikeFilm(r)) continue;
      final item = toMedia(r);
      if (only != null && item.kind != only) continue;
      out.add(item);
    }
    return out;
  }

  /// A raw row turned into the shared model.
  static MediaItem toMedia(FilmRiseRow r) {
    final (season, episode) = MediaKey.extractEpisode(r.title);
    final kind = episode != null
        ? MediaKind.episode
        : (r.feedType.toLowerCase() == 'series' || r.section == 'series' || r.section == 'shows'
            ? MediaKind.series
            : MediaKind.movie);
    final year = r.year ?? MediaKey.extractYear(r.title);
    final base = MediaItem(
      contentId: '',
      title: r.title,
      originalTitle: r.title,
      kind: kind,
      year: year,
      overview: r.description,
      duration: r.durationSeconds == null ? null : (r.durationSeconds! / 60).round(),
      genres: r.section.isEmpty ? const [] : [r.section],
      seriesTitle: episode == null ? null : r.title.split(RegExp(r'[sS]\d{1,2}[eE]\d{1,3}')).first.trim(),
      seasonNumber: season,
      episodeNumber: episode,
      sources: [
        MediaSource(
          provider: providerId,
          externalId: r.id,
          streamUrl: r.videoUrl,
          posterUrl: r.mainPicture ?? r.picture,
          backdropUrl: r.mainPicture,
          hasSubtitles: (r.captionsUrl ?? '').isNotEmpty,
        ),
      ],
    );
    return MediaItem(
      contentId: MediaKey.of(base),
      title: base.title,
      originalTitle: base.originalTitle,
      kind: base.kind,
      year: base.year,
      overview: base.overview,
      duration: base.duration,
      genres: base.genres,
      seriesTitle: base.seriesTitle,
      seasonNumber: base.seasonNumber,
      episodeNumber: base.episodeNumber,
      sources: base.sources,
    );
  }
}
