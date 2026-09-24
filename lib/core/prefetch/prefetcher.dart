import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/core/network/image_cache.dart';
import 'package:youtube_downloader/features/asia2tv/presentation/providers/asia2tv_providers.dart';
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';
import 'package:youtube_downloader/features/cinemana/presentation/providers/cinemana_provider.dart';
import 'package:youtube_downloader/features/home/presentation/widgets/franchise_spotlight.dart';
import 'package:youtube_downloader/features/sports/presentation/providers/alkass_provider.dart';
import 'package:youtube_downloader/features/sports/presentation/providers/sports_provider.dart';
import 'package:youtube_downloader/features/viu/data/viu_models.dart';
import 'package:youtube_downloader/features/viu/presentation/viu_providers.dart';

/// Fetches, while the logo is still on screen, everything the viewer is
/// about to look at: every feed on the home page and the pictures on it,
/// the crests and channel marks, the first films of every series in the
/// spotlight, the Viu rows, and the first page of each catalogue.
///
/// The feeds land in the HTTP cache and the pictures in the image store on
/// disk, so a row scrolled to, or a page opened, draws from disk in a few
/// milliseconds instead of waiting on the network - as if it had all been
/// fetched long before. Four pictures are in flight at a time, so the
/// hero and the first rows, which the splash asked for first, are never
/// crowded out.
class Prefetcher {
  Prefetcher._();

  static bool _started = false;

  /// The pictures still to fetch, and how many are being fetched now.
  static final List<String> _queue = [];
  static final Set<String> _seen = {};
  static int _inFlight = 0;
  static const int _parallel = 4;

  /// How many pictures of a row are worth having before the row is seen.
  static const int _perRow = 24;

  /// Starts once per launch; later calls are no-ops.
  static Future<void> start(ProviderContainer container) async {
    if (_started) return;
    _started = true;
    try {
      await _run(container);
    } catch (e) {
      debugPrint('[prefetch] $e');
    }
  }

  static void _enqueue(Iterable<String?> urls) {
    for (final u in urls) {
      if (u == null || u.isEmpty) continue;
      if (_seen.add(u)) _queue.add(u);
    }
    _pump();
  }

  static void _pump() {
    while (_inFlight < _parallel && _queue.isNotEmpty) {
      final url = _queue.removeAt(0);
      _inFlight++;
      appImageCache.getSingleFile(url).then<void>((_) {}, onError: (_) {}).whenComplete(() {
        _inFlight--;
        _pump();
      });
    }
  }

  static Future<void> _run(ProviderContainer c) async {
    Future<void> posters(ProviderListenable<Future<List<CinemanaItem>>> feed, {int take = _perRow}) async {
      try {
        final items = await c.read(feed);
        _enqueue(items.take(take).map((i) => i.cardImageUrl));
      } catch (_) {}
    }

    // The hero first: the big posters, then everything under them in the
    // order the page shows it.
    try {
      final hero = await c.read(heroBannerMoviesProvider.future);
      _enqueue(hero.take(12).map((m) => m.imgUrl ?? m.bestPosterUrl));
    } catch (_) {}

    // The matches and the channels sit right under the hero.
    try {
      final sports = c.read(sportsNotifierProvider('today'));
      _enqueue([
        for (final m in sports.liveMatches) ...[m.home.logo, m.away.logo, m.leagueLogo],
        for (final g in sports.groups)
          for (final m in g.matches) ...[m.home.logo, m.away.logo, m.leagueLogo],
      ]);
    } catch (_) {}
    try {
      final channels = await c.read(alkassChannelsProvider.future);
      _enqueue(channels.map((ch) => ch.logo));
    } catch (_) {}

    await Future.wait([
      posters(homeRecentlyAddedProvider.future),
      posters(homeLatestMoviesProvider.future),
      posters(homeLatestSeriesProvider.future),
      posters(homeMostViewedProvider.future),
    ]);
    await Future.wait([
      posters(homeAnimeProvider.future),
      posters(homeArabicMoviesProvider.future),
      posters(homeArabicSeriesProvider.future),
      posters(asianSeriesMergedProvider.future),
      posters(homeFeaturedProvider.future),
      posters(homeTopRatedProvider.future),
    ]);

    // The spotlight: the first films of the first series on show.
    for (final id in FranchiseSpotlight.defaultIds.take(8)) {
      await posters(franchiseFilmsProvider(id).future, take: 8);
    }

    // The Viu rows.
    for (final category in ViuCategory.home) {
      try {
        final shows = await c.read(viuHomeRowProvider(category).future);
        _enqueue(shows.take(_perRow).map((s) => s.portraitUrl ?? s.landscapeUrl));
      } catch (_) {}
    }

    // The first page of each catalogue, so the tabs open filled.
    for (final kind in const ['movies', 'series', 'anime']) {
      c.read(cinemanaSectionProvider(kind));
    }
    await Future<void>.delayed(const Duration(seconds: 3));
    for (final kind in const ['movies', 'series', 'anime']) {
      try {
        _enqueue(c.read(cinemanaSectionProvider(kind)).items.take(30).map((i) => i.cardImageUrl));
      } catch (_) {}
    }
    debugPrint('[prefetch] queued ${_seen.length} pictures');
  }
}
