import 'media_item.dart';

/// What every content source must offer. The UI talks to this, never to a
/// provider's own API shape: each provider has an adapter that turns its
/// response into [MediaItem]s before anything else sees them.
abstract class MediaProvider {
  /// Stable internal name ('cinemana', 'filmrise'). Used for tracking and
  /// for picking a stream; never shown to the user outside developer tools.
  String get id;

  /// Lower runs first and owns how a shared work is shown.
  int get priority;

  Future<List<MediaItem>> getHome();
  Future<List<MediaItem>> getMovies({int page});
  Future<List<MediaItem>> getSeries({int page});
  Future<List<MediaItem>> search(String query);

  /// Full details for one work of this provider, including a playable url.
  Future<MediaItem?> getDetails(String externalId);

  /// Episodes of a series, when the provider has them.
  Future<List<MediaItem>> getEpisodes(String seriesExternalId) async => const [];
}

/// A provider that answers with nothing instead of throwing, so one source
/// being down never takes the library with it.
extension SafeMediaProvider on MediaProvider {
  Future<List<MediaItem>> safely(Future<List<MediaItem>> Function() call) async {
    try {
      return await call();
    } catch (_) {
      return const [];
    }
  }
}
