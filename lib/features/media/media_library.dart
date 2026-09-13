import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cinemana/data/services/cinemana_service.dart';
import 'domain/media_item.dart';
import 'domain/media_merger.dart';
import 'domain/media_provider.dart';
import 'providers/cinemana/cinemana_media_provider.dart';
import 'providers/filmrise/filmrise_media_provider.dart';

/// The library the UI asks, instead of asking any single source.
///
/// It queries every provider, in priority order, and merges the answers so a
/// work carried by more than one source appears once. A provider that fails
/// contributes nothing and never breaks the others.
class MediaLibrary {
  final List<MediaProvider> providers;

  MediaLibrary(this.providers) {
    providers.sort((a, b) => a.priority.compareTo(b.priority));
  }

  Future<List<MediaItem>> getMovies({int page = 0}) => _gather((p) => p.getMovies(page: page));
  Future<List<MediaItem>> getSeries({int page = 0}) => _gather((p) => p.getSeries(page: page));
  Future<List<MediaItem>> getHome() => _gather((p) => p.getHome());
  Future<List<MediaItem>> search(String query) => _gather((p) => p.search(query));

  Future<List<MediaItem>> _gather(Future<List<MediaItem>> Function(MediaProvider) call) async {
    final lists = await Future.wait([
      for (final p in providers)
        call(p).then<List<MediaItem>>((v) => v).catchError((_) => const <MediaItem>[]),
    ]);
    return MediaMerger.merge(lists);
  }

  /// The provider that should serve this work, and the one to fall back to
  /// when it fails. Playback never switches source on its own otherwise.
  MediaSource? sourceFor(MediaItem item, {String? failedProvider}) {
    if (failedProvider == null) return item.primarySource;
    for (final s in item.sources) {
      if (s.provider != failedProvider) return s;
    }
    return null;
  }
}

/// FilmRise is built and tested but NOT merged into the library.
///
/// Every endpoint reachable on the Future Today backend under the supplied
/// appId/siteId serves the Fawesome/iFood food-and-kids network, not a film
/// catalogue: no title carries a year, a duration, a description, a season
/// or an episode, and `shows.php` answers "no enough data" for every id.
/// Merging that into the film library would fill it with cooking clips, so
/// the provider stays off until a catalogue endpoint is confirmed. Flip this
/// to true once FilmRiseConfig points at one.
const bool kFilmRiseEnabled = false;

/// Cinemana stays exactly as it is and keeps priority 0.
final mediaLibraryProvider = Provider<MediaLibrary>((ref) {
  return MediaLibrary([
    CinemanaMediaProvider(CinemanaService()),
    if (kFilmRiseEnabled) FilmRiseMediaProvider(),
  ]);
});
