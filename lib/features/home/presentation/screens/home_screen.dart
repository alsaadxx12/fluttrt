import 'dart:ui' show ImageFilter;
import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';
import '../../../../presentation/widgets/window_caption_buttons.dart';
import 'package:youtube_downloader/features/casting/controllers/cast_controller.dart';
import 'package:youtube_downloader/features/casting/widgets/cast_device_sheet.dart';
import 'package:youtube_downloader/features/casting/widgets/cast_diagnostics_page.dart';
import 'package:youtube_downloader/features/search/presentation/screens/search_screen.dart';
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';
import 'package:youtube_downloader/features/cinemana/presentation/providers/cinemana_provider.dart';
import 'package:youtube_downloader/features/cinemana/presentation/screens/cinemana_catalog_screen.dart';
import 'package:youtube_downloader/features/cinemana/presentation/screens/cinemana_detail_screen.dart';
import 'package:youtube_downloader/features/sports/data/models/sports_models.dart';
import 'package:youtube_downloader/features/sports/presentation/providers/sports_provider.dart';
import 'package:youtube_downloader/features/sports/presentation/screens/sports_player_screen.dart';
import 'package:youtube_downloader/features/sports/presentation/widgets/match_score_line.dart';
import 'package:youtube_downloader/presentation/screens/main_scaffold.dart';
import 'package:youtube_downloader/features/viu/data/viu_models.dart';
import 'package:youtube_downloader/features/viu/presentation/viu_widgets.dart';
import 'package:youtube_downloader/features/viu/presentation/other_films.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';
import 'package:youtube_downloader/core/network/http_cache.dart';
import 'package:youtube_downloader/core/network/image_cache.dart';
import '../widgets/subscription_plans_showcase.dart';
import 'package:youtube_downloader/features/home/presentation/widgets/franchise_showcase.dart';
import 'package:youtube_downloader/features/home/presentation/widgets/franchise_spotlight.dart';
import '../widgets/dynamic_franchises_showcase.dart';
import 'package:youtube_downloader/features/cinemana/data/cinemana_franchises.dart';
import 'package:youtube_downloader/features/sports/presentation/widgets/glowing_crest.dart';
import '../../../../presentation/widgets/card_motion.dart';
import '../widgets/alkass_channels_row.dart';
import '../../../../presentation/widgets/reveal.dart';
import '../../../sports/data/match_merge.dart';
import '../../../sports/data/match_order.dart';
import '../../../../core/video/desktop_video.dart';
import 'package:youtube_downloader/core/scroll/app_scroll_physics.dart';
import 'package:youtube_downloader/features/update/presentation/update_controller.dart';
import 'package:youtube_downloader/features/subscription/presentation/providers/subscription_provider.dart';
import 'package:youtube_downloader/features/asia2tv/presentation/providers/asia2tv_providers.dart';
import 'package:youtube_downloader/features/asia2tv/presentation/open_catalogue_item.dart';
import 'package:youtube_downloader/presentation/widgets/house_notice.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final PageController _heroPageController;
  // The slide on screen. A notifier rather than setState: only the dots and
  // the details listen, so a slide change never rebuilds the whole page.
  final ValueNotifier<int> _heroPage = ValueNotifier<int>(0);
  // What the last precache covered, so a rebuild alone never re-warms it.
  int _precachedPage = -1;
  List<CinemanaItem>? _precachedList;
  // Holds the warm-up off the first frames; see _precacheNextHeroSlides.
  Timer? _heroPrecacheTimer;
  // Starts the lower rows' feeds once the top of the page has settled.
  Timer? _prefetchTimer;

  Timer? _heroAutoSlideTimer;

  @override
  void initState() {
    super.initState();
    _heroPageController = PageController();

    _startAutoSlideTimer();
    _prefetchTimer = Timer(const Duration(milliseconds: 900), _prefetchRows);
    WidgetsBinding.instance.addPostFrameCallback((_) => _welcome());
  }

  /// Whether this launch has had its word from the house.
  static bool _welcomed = false;

  /// The night-of-it notice, once per launch: over the whole app, bottom
  /// bar and all, until the viewer sends it away.
  void _welcome() {
    if (_welcomed || !mounted) return;
    _welcomed = true;
    HouseNotice.show(context, const HouseNotice.welcome());
  }

  /// Starts the feeds for the rows further down, without subscribing this
  /// page to any of them.
  ///
  /// Each row watches its own provider and is now built only once it scrolls
  /// near, so without this its request would not leave until the viewer got
  /// there. Reading them here keeps the data ready - but after a pause, so
  /// the banners and the matches, which are what is actually on screen, get
  /// the connection and the decoder to themselves first.
  void _prefetchRows() {
    if (!mounted) return;
    for (final feed in <ProviderListenable<Object?>>[
      homeRecentlyAddedProvider,
      homeLatestMoviesProvider,
      franchiseFilmsProvider('spider-man'),
      franchiseFilmsProvider('batman'),
      franchiseFilmsProvider('james-bond'),
      homeLatestSeriesProvider,
      homeAsianSeriesProvider,
      asianSeriesMergedProvider,
      homeAnimeProvider,
      homeMostViewedProvider,
      homeArabicMoviesProvider,
      homeArabicSeriesProvider,
    ]) {
      ref.read(feed);
    }
  }

  /// The wide cover art for [m], or '' when Cinemana has none.
  static String _heroWideCover(CinemanaItem m) => (m.backdropUrl != null &&
          m.backdropUrl!.isNotEmpty &&
          m.backdropUrl!.contains('cover'))
      ? m.backdropUrl!
      : '';

  /// The artwork a hero slide draws for [m]. The slide and the precache both
  /// ask here, so they always name the same file.
  static String _heroImageUrl(CinemanaItem m, bool isDesktop) {
    final wideCover = _heroWideCover(m);
    final highResPoster = (m.imgUrl != null && m.imgUrl!.isNotEmpty)
        ? m.imgUrl!
        : m.bestPosterUrl;
    return isDesktop
        ? (wideCover.isNotEmpty
            ? wideCover
            : (m.bestBackdropUrl.isNotEmpty
                ? m.bestBackdropUrl
                : highResPoster))
        : (highResPoster.isNotEmpty ? highResPoster : m.bestBackdropUrl);
  }

  /// Warm the disk/memory cache for the slides right after the current one,
  /// so a swipe (or the auto-advance) never waits on the network.
  ///
  /// Runs once per (page, list): a rebuild with the same slide showing and
  /// the same titles is a no-op.
  void _precacheNextHeroSlides(List<CinemanaItem> movies, double width) {
    if (!mounted || movies.isEmpty) return;
    final page = _heroPage.value;
    if (page == _precachedPage && listEquals(movies, _precachedList)) return;
    _precachedPage = page;
    _precachedList = movies;
    // Warming the next two banners means two more full-width decodes and two
    // more downloads. Fired straight after the first frame they competed with
    // the posters the viewer is actually looking at, and the page filled in
    // in fits. The slides are not needed for eight seconds, so they wait.
    _heroPrecacheTimer?.cancel();
    _heroPrecacheTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) _warmHeroSlides(movies, width, page);
    });
  }

  void _warmHeroSlides(List<CinemanaItem> movies, double width, int page) {
    if (!mounted || movies.isEmpty) return;
    final isDesktop = width >= 700;
    for (var i = 1; i <= 2; i++) {
      final m = movies[(page + i) % movies.length];
      final url = _heroImageUrl(m, isDesktop);
      if (url.isEmpty) continue;
      // Exactly the provider the slide decodes with - same url, same resize
      // width, same cache - so the swipe is served from the memory cache.
      // CachedNetworkImage wraps its provider in ResizeImage(width:
      // memCacheWidth); mobile slides decode at the screen's own width, the
      // desktop slide at native size.
      final base = CachedNetworkImageProvider(url, cacheManager: appImageCache);
      if (isDesktop) {
        precacheImage(base, context).catchError((_) {});
        if (_heroWideCover(m).isEmpty) {
          // The poster's blurred backdrop is a 400px decode of the same file.
          precacheImage(ResizeImage(base, width: 400), context)
              .catchError((_) {});
        }
      } else {
        precacheImage(ResizeImage(base, width: _decodeWidthFor(width)), context)
            .catchError((_) {});
      }
    }
  }

  /// How many pictures the hero has to move between; set as it is built.
  int _heroCount = 0;

  /// The hero moves on to the next picture every six seconds, on its own
  /// and without pause: a finger on it swipes, and nothing else.
  void _startAutoSlideTimer() {
    _heroAutoSlideTimer?.cancel();
    _heroAutoSlideTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || _heroCount < 2 || !_heroPageController.hasClients) return;
      final next = (_heroPage.value + 1) % _heroCount;
      _heroPageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _barScrolled.dispose();
    _heroAutoSlideTimer?.cancel();
    _heroPrecacheTimer?.cancel();
    _prefetchTimer?.cancel();
    _heroPageController.dispose();
    _heroPage.dispose();
    super.dispose();
  }

  /// Pull-to-refresh: every request bypasses the fresh window once, then all
  /// the page's providers reload together. The indicator stays until each
  /// has answered; a failing one is swallowed so it never throws out of the
  /// indicator.
  Future<void> _refreshHome() async {
    HttpCache.instance.markStale();
    Future<void> quiet(Future<Object?> f) =>
        f.then<void>((_) {}, onError: (_, __) {});
    await Future.wait<void>([
      quiet(ref.refresh(heroBannerMoviesProvider.future)),
      quiet(ref.refresh(homeFeaturedProvider.future)),
      quiet(ref.refresh(homeRecentlyAddedProvider.future)),
      quiet(ref.refresh(homeLatestMoviesProvider.future)),
      quiet(ref.refresh(homeLatestSeriesProvider.future)),
      quiet(ref.refresh(homeAsianSeriesProvider.future)),
      quiet(ref.refresh(asianSeriesMergedProvider.future)),
      quiet(ref.refresh(homeAnimeProvider.future)),
      quiet(ref.refresh(sportsChannelsProvider.future)),
      quiet(ref.refresh(homeMostViewedProvider.future)),
      quiet(ref.refresh(homeArabicMoviesProvider.future)),
      quiet(ref.refresh(homeArabicSeriesProvider.future)),
      quiet(ref.read(sportsNotifierProvider('today').notifier).refresh()),
      quiet(ref.read(updateControllerProvider.notifier).checkForUpdate()),
    ]);
  }

  void _openCatalog({required String kind, String? order, int? categoryId}) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => CinemanaCatalogScreen(
          kind: kind,
          initialOrder: order,
          initialCategoryId: categoryId,
        ),
      ),
    );
  }

  void _openFranchiseById(String id) {
    final franchise = FilmFranchise.all.firstWhere(
      (f) => f.id == id,
      orElse: () => FilmFranchise.all.first,
    );
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => FranchiseScreen(franchise: franchise),
      ),
    );
  }

  // Format kickoff ISO timestamp into clean local time (e.g. 7:45 م) and small date (e.g. 09/09)
  Map<String, String> _formatMatchTimeAndDate(String rawKickoff) {
    if (rawKickoff.trim().isEmpty) {
      return {'time': 'VS', 'date': ''};
    }
    final raw = rawKickoff.trim();
    DateTime? dt = DateTime.tryParse(raw);
    if (dt == null) {
      final match = RegExp(r'(\d{1,2}):(\d{2})\s*([a-zA-Z\u0600-\u06FF]+)?')
          .firstMatch(raw);
      if (match != null) {
        int h = int.tryParse(match.group(1) ?? '') ?? 0;
        final m = int.tryParse(match.group(2) ?? '') ?? 0;
        final period = (match.group(3) ?? '').toLowerCase().trim();
        if (period.contains('p') || period.contains('م')) {
          if (h < 12) h += 12;
        } else if (period.contains('a') || period.contains('ص')) {
          if (h == 12) h = 0;
        }
        final now = DateTime.now();
        dt = DateTime.utc(now.year, now.month, now.day, h, m)
            .subtract(const Duration(hours: 3));
      }
    }
    if (dt == null) {
      return {'time': raw, 'date': ''};
    }
    final local = dt.toLocal();
    final h = local.hour;
    final min = local.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'م' : 'ص';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final timeStr = '$h12:$min $period';
    final dateStr =
        '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}';
    return {'time': timeStr, 'date': dateStr};
  }

  // The merged list, kept until one of the two feeds actually changes.
  List<SportMatchItem>? _mergedMatches;
  // The same list in the order the row draws it. The sort used to run on
  // every rebuild of the page; it now runs only when a feed hands over
  // something new.
  List<SportMatchItem>? _orderedMatches;
  List<SportMatchItem>? _mergedFromLive;
  List<LeagueGroup>? _mergedFromGroups;

  /// Folds the feeds' matches into one list, recomputing only when a feed
  /// hands over new data. Riverpod replaces these lists on change, so
  /// identity is the whole test.
  List<SportMatchItem> _mergedTodayMatches(dynamic sportsState) {
    final live = sportsState.liveMatches as List<SportMatchItem>;
    final groups = sportsState.groups as List<LeagueGroup>;
    if (_mergedMatches != null &&
        identical(live, _mergedFromLive) &&
        identical(groups, _mergedFromGroups)) {
      return _mergedMatches!;
    }
    // The day's table owns each fixture (its real status and score); the
    // channel feed only adds streams. Merged the other way round, a channel
    // copy stamped `مباشر` decided the status and finished games looked live.
    final merged = MatchMerge.mergeAll([
      [for (final g in groups) ...g.matches],
      live,
    ]);
    _mergedFromLive = live;
    _mergedFromGroups = groups;
    _mergedMatches = merged;
    // In play first, then upcoming, then finished - sorted here, with the
    // merge, so the row never re-sorts just because the page rebuilt.
    _orderedMatches = MatchOrder.dayOrder(merged);
    return merged;
  }

  /// The day's matches in the order the row shows them.
  List<SportMatchItem> _orderedTodayMatches(dynamic sportsState) {
    _mergedTodayMatches(sportsState);
    return _orderedMatches!;
  }

  /// One poster row fed by [provider].
  ///
  /// The row watches its own feed inside its own [Consumer], so it appears
  /// the moment that one request lands and nothing else on the page is
  /// rebuilt with it.
  Widget _posterRowSection({
    required ProviderListenable<AsyncValue<List<CinemanaItem>>> provider,
    required String title,
    VoidCallback? onViewAll,
  }) {
    return RepaintBoundary(
      child: Consumer(
        builder: (context, ref, _) => ref.watch(provider).when(
              data: (items) {
                if (items.isEmpty) return const SizedBox.shrink();
                return _buildHorizontalCategorySection(
                  title: title,
                  items: items,
                  isLoading: false,
                  onViewAll: onViewAll,
                );
              },
              loading: () => _buildHorizontalCategorySection(
                title: title,
                items: const [],
                isLoading: true,
              ),
              error: (_, __) => const SizedBox.shrink(),
            ),
      ),
    );
  }

  /// One wide-card series row fed by [provider]; see [_posterRowSection].
  Widget _wideSeriesRowSection({
    required ProviderListenable<AsyncValue<List<CinemanaItem>>> provider,
    required String title,
    required String badge,
    VoidCallback? onViewAll,
  }) {
    return RepaintBoundary(
      child: Consumer(
        builder: (context, ref, _) => ref.watch(provider).when(
              data: (items) => _buildWideSeriesSection(
                title: title,
                badge: badge,
                items: items,
                isLoading: false,
                onViewAll: onViewAll,
              ),
              loading: () => _buildWideSeriesSection(
                title: title,
                items: const [],
                isLoading: true,
              ),
              error: (_, __) => const SizedBox.shrink(),
            ),
      ),
    );
  }

  /// Everything under the hero, in order, each entry built only once it
  /// scrolls near. Built once for the life of the page: no entry closes over
  /// anything from [build], so a rebuild never has to make this list again.
  late final List<WidgetBuilder> _sections = <WidgetBuilder>[
    // Sports Section: Real Matches (Dynamic title, increased card height,
    // clean time/date, team logos)
    (_) => RepaintBoundary(
          child: Consumer(
            builder: (context, ref, __) {
              final sportsState = ref.watch(sportsNotifierProvider('today'));
              // Collect all real matches for today.
              //
              // The two feeds number their matches differently, so comparing
              // ids let the same fixture through twice and it sat twice in the
              // row. Identity is the two teams, and the surviving card keeps
              // every channel either feed knew about, so the source is chosen
              // inside the match.
              final allTodayMatches = _mergedTodayMatches(sportsState);
              // Dynamic title: the live count when something is in play,
              // otherwise just the day. "Live" means actually in play right
              // now - judged by each match's real status, not by the channel
              // feed's `live_now`, whose entries are mostly still *scheduled*
              // (it lists matches that have a stream today, not ones that have
              // kicked off). Using it flipped the row to "live" and then
              // showed the whole day, finished games included.
              final liveNow = allTodayMatches.where((m) => m.isLive).toList();
              final hasLiveMatches = liveNow.isNotEmpty;
              // The row shows the whole day (live first), so it is titled as
              // such; the live count and the red dot still flag what is in
              // play right now.
              return _buildSportsSection(
                title: hasLiveMatches
                    ? 'مباريات اليوم · ${liveNow.length} مباشرة'
                    : 'مباريات اليوم',
                isLiveMode: hasLiveMatches,
                matches: _orderedTodayMatches(sportsState),
                isLoading: sportsState.isLoading,
              );
            },
          ),
        ),

    (_) => const SizedBox(height: 10),

    // Alkass's free channels: the marks in a row, a tap plays the channel.
    (_) => const RepaintBoundary(child: AlkassChannelsRow()),
    (_) => const SizedBox(height: 24),

    // Subscription plans.
    (_) => const RepaintBoundary(child: SubscriptionPlansShowcase()),

    (_) => const SizedBox(height: 24),

    // 2. Recently added.
    (_) => _posterRowSection(
          provider: homeRecentlyAddedProvider,
          title: 'أضيف حديثًا',
          onViewAll: () => _openCatalog(kind: 'movies', order: 'desc'),
        ),

    (_) => const SizedBox(height: 24),

    // 3. Latest movies.
    (_) => _posterRowSection(
          provider: homeLatestMoviesProvider,
          title: 'أحدث الأفلام',
          onViewAll: () => _openCatalog(kind: 'movies', order: 'release'),
        ),

    (_) => const SizedBox(height: 24),

    // 4. Latest series - wide card layout.
    (_) => _wideSeriesRowSection(
          provider: homeLatestSeriesProvider,
          title: 'أحدث المسلسلات',
          badge: 'جديد',
          onViewAll: () => _openCatalog(kind: 'series', order: 'release'),
        ),

    (_) => const SizedBox(height: 24),

    // The big film series, each complete and in order.
    // Live, endless film franchises (seeded with the curated ones).
    (_) => const RepaintBoundary(
        child: DynamicFranchisesShowcase(section: FranchiseSection.films)),
    (_) => const SizedBox(height: 24),

    // أحدث المسلسلات الآسيوية (كورية، يابانية، صينية…)
    (_) => _wideSeriesRowSection(
          provider: asianSeriesMergedProvider,
          title: 'أحدث المسلسلات الآسيوية',
          badge: 'آسيوي',
        ),

    (_) => const SizedBox(height: 24),

    // One film series staged big: a backdrop the width of the page with
    // every part of the series under it. The chips swap in another.
    (_) => const RepaintBoundary(child: FranchiseSpotlight()),
    (_) => const SizedBox(height: 24),

    // 5. Anime.
    (_) => _posterRowSection(
          provider: homeAnimeProvider,
          title: 'الأنمي',
          onViewAll: () => _openCatalog(kind: 'anime', order: 'release'),
        ),

    (_) => const SizedBox(height: 24),

    // Anime franchises: each franchise's series and films together.
    (_) => const RepaintBoundary(
        child: DynamicFranchisesShowcase(section: FranchiseSection.anime)),
    (_) => const SizedBox(height: 12),

    // 6. Most viewed.
    (_) => _posterRowSection(
          provider: homeMostViewedProvider,
          title: 'الأكثر مشاهدة',
          onViewAll: () => _openCatalog(kind: 'movies', order: 'views'),
        ),

    (_) => const SizedBox(height: 24),

    // 7. Arabic movies.
    (_) => _posterRowSection(
          provider: homeArabicMoviesProvider,
          title: 'الأفلام العربية',
          onViewAll: () => _openCatalog(kind: 'movies', categoryId: 130),
        ),

    (_) => const SizedBox(height: 24),

    // 8. Arabic series - wide card layout.
    (_) => _wideSeriesRowSection(
          provider: homeArabicSeriesProvider,
          title: 'المسلسلات العربية',
          badge: 'عربي',
          onViewAll: () => _openCatalog(kind: 'series', categoryId: 130),
        ),

    (_) => const SizedBox(height: 24),

    // TV-series universes (spin-offs and sequels together).
    (_) => const RepaintBoundary(
        child: FranchisesShowcase(section: FranchiseSection.series)),
    (_) => const SizedBox(height: 12),

    // 9. Viu: Arabic / Korean / Turkish series and free films, played in the
    // app's own player. Each row loads when it scrolls near and hides itself
    // if it has nothing.
    for (final category in ViuCategory.home.where((c) => !c.isMovies))
      (_) => RepaintBoundary(child: ViuHomeSection(category: category)),

    // Viu's free films plus varied films by genre.
    (_) => const RepaintBoundary(child: OtherFilmsSection()),
    (_) => const SizedBox(height: 24),
  ];

  @override
  Widget build(BuildContext context) {
    // Nothing is watched at this level any more. The hero and every row
    // below watch their own feed inside their own Consumer, so one feed
    // landing rebuilds one row — not the hero, the matches and all twenty
    // sections at once, which is what made the cards stutter into place
    // while the ten home feeds arrived one after another.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = _p.bg;
    // The floating top bar: status bar + 4px padding + 40px row + 4px padding.
    final topBarHeight = MediaQuery.of(context).padding.top + 52.0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(statusBarColor: Colors.transparent),
      child: ColoredBox(
        color: bgColor,
        child: Stack(
          children: [
            // Main Scrollable Content
            RefreshIndicator(
              color: const Color(0xFFE50914),
              backgroundColor: _p.card,
              strokeWidth: 2.4,
              displacement: 48,
              // The spinner drops in below the floating bar, never under it.
              edgeOffset: topBarHeight,
              triggerMode: RefreshIndicatorTriggerMode.anywhere,
              onRefresh: _refreshHome,
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n.depth == 0) _barScrolled.value = n.metrics.pixels > 6;
                  return false;
                },
                child: CustomScrollView(
                  key: const PageStorageKey('home'),
                  physics: kAppDefaultScrollPhysics,
                  cacheExtent: 600,
                  slivers: [
                    // 1. Full-Bleed Hero Movie Section (Screen-filling, Crystal
                    // Clear, Latest 20, Interactive & Pausable). Its own Consumer:
                    // the banner feed landing repaints the hero and nothing else.
                    SliverToBoxAdapter(
                      child: RepaintBoundary(
                        child: Consumer(
                          builder: (context, ref, _) {
                            final bannerAsync =
                                ref.watch(heroBannerMoviesProvider);
                            final featuredAsync =
                                ref.watch(homeFeaturedProvider);
                            // Hero Section: Strictly official Cinemana banners
                            // ("الإصدارات الجديدة"). The banner feed alone: while it
                            // loads the hero keeps its skeleton rather than showing
                            // the featured titles and then swapping them out.
                            final heroMovies = bannerAsync.when(
                              data: (b) => b.take(20).toList(),
                              loading: () => const <CinemanaItem>[],
                              error: (_, __) => (featuredAsync.valueOrNull ??
                                      const <CinemanaItem>[])
                                  .take(20)
                                  .toList(),
                            );
                            // The flat skeleton stays until there is something to
                            // show - also while the featured fallback is still on
                            // its way after the banner feed failed - so nothing
                            // flashes.
                            return _buildHeroSection(
                              heroMovies,
                              heroMovies.isEmpty &&
                                  (bannerAsync.isLoading ||
                                      (bannerAsync.hasError &&
                                          featuredAsync.isLoading)),
                            );
                          },
                        ),
                      ),
                    ),

                    // Everything under the hero is one lazy list. The children are
                    // *builders*, not a ready-made list of widgets: with a child
                    // list every section's tree was constructed on every rebuild of
                    // this page, however far off screen it sat. Now a row is built
                    // only once it comes within cacheExtent of the viewport, so the
                    // first frame is the hero and the matches, nothing more.
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _sections[index](context),
                        childCount: _sections.length,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Pinned top bar: white and flat while the page is at rest; once
            // the page has moved, the content shows through a soft blur and a
            // faint shadow separates the bar from what scrolls under it.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ValueListenableBuilder<bool>(
                valueListenable: _barScrolled,
                // Glass, the way iOS draws its bars: what scrolls under shows
                // through a blur and a tint of the page colour.
                builder: (context, scrolled, child) => ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _p.bg.withOpacity(scrolled ? 0.72 : 0.0),
                        border: scrolled
                            ? Border(
                                bottom: BorderSide(
                                    color: Colors.white.withOpacity(0.08),
                                    width: 0.6))
                            : null,
                      ),
                      child: child,
                    ),
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: _buildFloatingTopBar(),
                  ),
                ),
              ),
            ),

          ],
        ),
      ),
    );
  }

  // ==========================================
  // 1. HERO MOVIE SECTION (Screen-Filling, Crystal Clear, Pausable on Tap)
  // ==========================================
  /// The hero runs on each title's portrait poster, which Cinemana serves at a
  /// flat 2:3. The artwork box uses that exact ratio, so the picture fills it
  /// edge to edge with nothing cropped and no letterbox bars - and at full
  /// width that is four times the height the old 27:10 cover art gave.
  ///
  /// Slightly wider than the poster's own 2:3 (0.667): the box is ~7% shorter,
  /// and with the artwork anchored to the top only the bottom strip is trimmed
  /// - the strip the title, plot and play button already cover.
  static const double _heroArtworkAspect = 0.72;

  /// The top bar keeps one colour whatever banner is showing, and the banner
  /// is rounded at the top; the bar's colour fills in behind those corners,
  /// so bar and picture read as one moulded piece.

  AppPalette get _p => AppPalette.of(context);

  /// True once the page has scrolled past the top; the bar blurs and lifts.
  final ValueNotifier<bool> _barScrolled = ValueNotifier<bool>(false);

  Widget _buildHeroSection(List<CinemanaItem> movies, bool isLoading) {
    return LayoutBuilder(
      builder: (context, constraints) =>
          _buildHeroContent(movies, isLoading, constraints.maxWidth),
    );
  }

  Widget _buildHeroContent(
    List<CinemanaItem> movies,
    bool isLoading,
    double availableWidth,
  ) {
    final media = MediaQuery.of(context);
    final isDesktop = availableWidth > 680;
    _heroCount = movies.length;
    // Pinned top bar: compact vertical padding
    final topBarHeight = media.padding.top + 52.0;
    // Sleek minimal separation gap between top bar and hero artwork:
    final artworkTop = topBarHeight + 4.0;
    // On Windows/Desktop, provide a generous, well-proportioned height (420-520px)
    // so the hero artwork has ample space, clear visibility, and doesn't get squeezed.
    final artworkHeight = isDesktop
        ? (availableWidth * 0.35).clamp(420.0, 520.0)
        : availableWidth / _heroArtworkAspect;

    // Warm the next slides once the list is on screen; the guard inside makes
    // this free on a rebuild that changed neither the page nor the list.
    if (movies.length > 1) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _precacheNextHeroSlides(movies, availableWidth),
      );
    }

    return Stack(
      children: [
        // The Column is the only unpositioned child, so it sizes the Stack:
        // the hero is exactly as tall as the artwork plus its details.
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: artworkTop),

            // Artwork carousel, square-cornered: the picture runs edge to
            // edge, the way a poster on a wall does.
            SizedBox(
              height: artworkHeight,
              width: double.infinity,
              child: ClipRRect(
                borderRadius: BorderRadius.zero,
                child: movies.isNotEmpty
                    ? PageView.builder(
                        controller: _heroPageController,
                        physics: const ClampingScrollPhysics(),
                        onPageChanged: (index) {
                          // Dots and details listen to the notifier; the
                          // page itself is left alone.
                          _heroPage.value = index;
                          _precacheNextHeroSlides(movies, availableWidth);
                        },
                        itemCount: movies.length,
                        itemBuilder: (context, index) {
                          return _buildHeroFullPoster(
                              movies[index], availableWidth);
                        },
                      )
                    : (isLoading
                        ? _buildHeroLoadingSkeleton()
                        : _buildHeroEmptyPlaceholder()),
              ),
            ),

            // Only the dots sit below the picture; everything else is on it.
            SizedBox(
              height: 18,
              child: movies.length > 1
                  ? Center(
                      child: ValueListenableBuilder<int>(
                        valueListenable: _heroPage,
                        builder: (_, page, __) =>
                            _buildHeroDots(movies.length, page),
                      ),
                    )
                  : null,
            ),
          ],
        ),

        // A light fog of the page's own colour over the bottom of the artwork,
        // thickening to the edge, so the picture melts into the app.
        Positioned(
          left: 0,
          right: 0,
          top: artworkTop + artworkHeight * 0.58,
          height: artworkHeight * 0.42 + 1,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _homeBg.withOpacity(0),
                    _homeBg.withOpacity(0.35),
                    _homeBg.withOpacity(0.75),
                    _homeBg,
                  ],
                  stops: const [0, 0.45, 0.8, 1],
                ),
              ),
            ),
          ),
        ),

        // Title, rating, plot and the play button, laid over the lower part of
        // the artwork rather than on a panel beneath it.
        if (movies.isNotEmpty)
          Positioned(
            left: 20,
            right: 20,
            top: artworkTop,
            height: artworkHeight,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ValueListenableBuilder<int>(
                  valueListenable: _heroPage,
                  builder: (_, page, __) => _buildHeroRealMovieDetails(
                      movies[page.clamp(0, movies.length - 1)]),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// The home page's background - the colour the hero's fog fades into.
  Color get _homeBg => _p.bg;

  // One hero slide: the complete artwork, uncropped, edge to edge.
  Widget _buildHeroFullPoster(CinemanaItem movie, double availableWidth) {
    final isDesktop = availableWidth >= 700;
    final wideCover = _heroWideCover(movie);

    // On mobile phone portrait, always prioritize the official high-resolution
    // portrait poster (1280x1920) rather than the low-res 2.7:1 horizontal strip!
    // `_precacheNextHeroSlides` resolves the very same URL and decode width,
    // so a warmed slide is a memory-cache hit, not a second decode.
    final imageUrl = _heroImageUrl(movie, isDesktop);

    if (imageUrl.isEmpty) return _buildHeroEmptyPlaceholder();

    if (isDesktop) {
      if (wideCover.isNotEmpty) {
        return Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: wideCover,
              cacheManager: appImageCache,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              filterQuality: FilterQuality.high,
              memCacheWidth: null, // Full native razor-sharp resolution
              memCacheHeight: null,
              fadeInDuration: Duration.zero,
              fadeOutDuration: Duration.zero,
              placeholderFadeInDuration: Duration.zero,
              useOldImageOnUrlChange: true,
              placeholder: (_, __) => _buildHeroLoadingSkeleton(),
              errorWidget: (_, __, ___) => _buildHeroEmptyPlaceholder(),
            ),
          ],
        );
      }

      return Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 45, sigmaY: 45),
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              cacheManager: appImageCache,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              memCacheWidth: 400, // a blur needs no detail
              fadeInDuration: Duration.zero,
              fadeOutDuration: Duration.zero,
              placeholderFadeInDuration: Duration.zero,
              useOldImageOnUrlChange: true,
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
          const ColoredBox(color: Color(0x45000000)),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 20),
              child: ClipRRect(
                borderRadius: BorderRadius.zero,
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  cacheManager: appImageCache,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  memCacheWidth:
                      null, // Native full resolution without downsampling
                  memCacheHeight: null,
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  placeholderFadeInDuration: Duration.zero,
                  useOldImageOnUrlChange: true,
                  placeholder: (_, __) => _buildHeroLoadingSkeleton(),
                  errorWidget: (_, __, ___) => _buildHeroEmptyPlaceholder(),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Mobile: decode at the screen's own pixel width, not the poster's full
    // 1280x1920. A phone screen cannot show more pixels than it has, so this is
    // visually identical yet decodes far faster and uses a fraction of the
    // memory — which is what made the top images slow to appear.
    return CachedNetworkImage(
      imageUrl: imageUrl,
      cacheManager: appImageCache,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      filterQuality: FilterQuality.medium,
      memCacheWidth: _decodeWidthFor(availableWidth),
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholderFadeInDuration: Duration.zero,
      useOldImageOnUrlChange: true,
      placeholder: (_, __) => _buildHeroLoadingSkeleton(),
      errorWidget: (_, __, ___) => _buildHeroEmptyPlaceholder(),
    );
  }

  /// A flat block in the skeleton colour: no spinner, nothing to flash.
  Widget _buildHeroLoadingSkeleton() {
    return ColoredBox(color: _p.skeleton);
  }

  Widget _buildHeroEmptyPlaceholder() {
    return Container(
      color: _p.skeleton,
      child: Center(
        child: Icon(Icons.movie_filter_rounded, size: 64, color: _p.textFaint),
      ),
    );
  }

  // ==========================================
  // FLOATING TOP BAR (Large Professional Logo, Direct Drawer Trigger, Live Search)
  // ==========================================
  Widget _buildFloatingTopBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    // One plain row: the account button with search and cast beside it, and
    // the app's name at the far end.
    final topBarContent = SizedBox(
      height: 48,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Account / menu
          _buildTranslucentIconButton(
            icon: Icons.person_rounded,
            onTap: () => mainScaffoldKey.currentState?.openDrawer(),
          ),
          const SizedBox(width: 8),

          _buildTranslucentIconButton(
            icon: Icons.search_rounded,
            onTap: () => Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
          const SizedBox(width: 8),

          // Cast to a screen. The icon fills in and turns the brand red while
          // a device is connected, so the bar says at a glance that
          // something is playing elsewhere.
          Consumer(
            builder: (context, ref, _) {
              final casting = ref.watch(isCastingProvider);
              return _buildTranslucentIconButton(
                icon:
                    casting ? Icons.cast_connected_rounded : Icons.cast_rounded,
                color: casting ? const Color(0xFFE50914) : null,
                ring: casting ? const Color(0x66E50914) : null,
                onTap: () => showCastDeviceSheet(context),
                // Hidden on purpose: the diagnostics are for the evening
                // something does not play.
                onLongPress: () => CastDiagnosticsPage.open(context),
              );
            },
          ),

          const Spacer(),

          // On desktop: integrated window controls (frameless, seamless)
          if (isDesktop) ...[
            const WindowCaptionButtons(),
            Container(
              height: 18,
              width: 1,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              color: isDark ? Colors.white12 : _p.border,
            ),
            const SizedBox(width: 6),
          ],

          _buildAppNameMark(),
        ],
      ),
    );

    if (isDesktop) {
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onDoubleTap: () async {
          try {
            final isMax = await windowManager.isMaximized();
            if (isMax) {
              await windowManager.unmaximize();
            } else {
              await windowManager.maximize();
            }
          } catch (_) {}
        },
        child: DragToMoveArea(child: topBarContent),
      );
    }
    return topBarContent;
  }

  Widget _buildTranslucentIconButton({
    required IconData icon,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    Color? color,
    Color? ring,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF141926),
            border: Border.all(
                color: ring ?? Colors.white.withOpacity(0.12), width: 1),
          ),
          child: Icon(
            icon,
            color: color ?? Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }

  /// The app's name, in place of its icon mark.
  ///
  /// "BALL" carries the brand red so the word is read as two halves at a
  /// glance, the way the logo did.
  Widget _buildAppNameMark() {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: 'CINE', style: TextStyle(color: _p.text)),
          const TextSpan(
              text: 'BALL', style: TextStyle(color: Color(0xFFE50914))),
        ],
      ),
      style: const TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.4,
        height: 1,
      ),
    );
  }

  // ==========================================
  // REAL HERO DETAILS (Crisp Title Without Muddy Shadows, Compact Play Button)
  // ==========================================
  Widget _buildHeroRealMovieDetails(CinemanaItem movie) {
    final genreText = movie.categories.isNotEmpty
        ? movie.categories.take(2).join(' • ')
        : (movie.isSeries ? 'مسلسل' : 'فيلم');
    final yearText = movie.year.isNotEmpty ? movie.year : '2026';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Metadata: ⭐ Stars • Genre • Year
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.star_rounded, color: Color(0xFFFFB800), size: 15),
            const SizedBox(width: 4),
            Text(
              movie.stars.isNotEmpty ? movie.stars : '8.5',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                shadows: [
                  Shadow(color: Colors.black, blurRadius: 3),
                  Shadow(color: Colors.black87, blurRadius: 10),
                ],
              ),
            ),
            _buildMetaSeparator(),
            Text(
              genreText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                shadows: [
                  Shadow(color: Colors.black, blurRadius: 3),
                  Shadow(color: Colors.black87, blurRadius: 10),
                ],
              ),
            ),
            _buildMetaSeparator(),
            Text(
              yearText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                shadows: [
                  Shadow(color: Colors.black, blurRadius: 3),
                  Shadow(color: Colors.black87, blurRadius: 10),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        // «+» for the list, «شاهد» for the film: the two things to do
        // with a picture, and nothing to read.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Consumer(
              builder: (context, ref, _) {
                final saved = ref.watch(cinemanaFavoritesProvider).any((it) => it.id == movie.id);
                return Tooltip(
                  message: saved ? 'في قائمتي' : 'أضف إلى قائمتي',
                  child: Material(
                    color: Colors.white.withOpacity(saved ? 0.28 : 0.16),
                    shape: const CircleBorder(side: BorderSide(color: Colors.white54, width: 0.8)),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => ref.read(cinemanaFavoritesProvider.notifier).toggleFavorite(movie),
                      child: SizedBox(
                        width: 36,
                        height: 36,
                        child: Icon(
                          saved ? Icons.check_rounded : Icons.add_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute(
                    builder: (_) => CinemanaDetailScreen(item: movie),
                  ),
                );
              },
              icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
              label: const Text(
                'شاهد',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE50914),
                foregroundColor: Colors.white,
                elevation: 4,
                shadowColor: const Color(0xFFE50914).withOpacity(0.45),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 6),
      ],
    );
  }

  Widget _buildHeroDots(int totalSlides, int currentPage) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        totalSlides,
        (dotIndex) {
          final isCurrent = dotIndex == currentPage;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 2.5),
            width: isCurrent ? 18 : 6,
            height: 5.5,
            decoration: BoxDecoration(
              color: isCurrent
                  ? const Color(0xFFE50914)
                  : (_p.isDark ? Colors.white24 : const Color(0x330F172A)),
              borderRadius: BorderRadius.circular(3),
            ),
          );
        },
      ),
    );
  }

  /// Device pixels needed to draw something [logicalWidth] wide. Passed to
  /// Image.network as cacheWidth so a 1280x1920 poster is decoded at card size
  /// instead of full size - the difference is ~9.8MB vs ~0.2MB per card, and
  /// with a dozen rows on screen that was exhausting the GPU budget.
  int _decodeWidthFor(double logicalWidth) {
    return (logicalWidth * MediaQuery.of(context).devicePixelRatio).round();
  }

  /// The decode width for a card [logicalWidth] wide: its own pixels, no
  /// more, kept between 200 and 720 so a poster is decoded once at draw size
  /// and a large one never decodes more than it can show.
  ///
  /// The ceiling used to be 480, which a 4x screen's card passes - the poster
  /// was then decoded smaller than the card it fills and drawn soft. 720
  /// covers every phone card at its real pixel width, and since the decode is
  /// never larger than the source file it costs nothing where the artwork is
  /// smaller than that.
  int _hiResDecodeWidth(double logicalWidth) {
    return (logicalWidth * MediaQuery.of(context).devicePixelRatio)
        .clamp(200, 720)
        .round();
  }

  Widget _buildMetaSeparator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        '•',
        style: TextStyle(
          color: Colors.white.withOpacity(0.6),
          fontSize: 12,
          shadows: const [Shadow(color: Colors.black54, blurRadius: 3)],
        ),
      ),
    );
  }

  Widget _buildSportsSection({
    required String title,
    required bool isLiveMode,
    required List<SportMatchItem> matches,
    required bool isLoading,
  }) {
    // A day with nothing to watch has no matches section at all — no header,
    // no "no matches" box, no gap. (The section is a Column, so its spacer
    // below is folded in here to vanish with it.)
    if (!isLoading && matches.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header Row (NO "عرض الكل")
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              if (isLiveMode) ...[
                Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFFF2A4A),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0xFFFF2A4A),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ] else ...[
                const Icon(Icons.sports_soccer_rounded,
                    color: Colors.white, size: 19),
                const SizedBox(width: 8),
              ],

              // Dynamic Title: "المباريات المباشرة" or "مباريات اليوم"
              Text(
                title,
                style: TextStyle(
                  color: _p.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () {
                  final isUnlocked = ref.read(isSportsUnlockedProvider);
                  context.push(isUnlocked ? '/sports' : '/sports-activation');
                },
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    children: [
                      Text(
                        'عرض الكل',
                        style: TextStyle(
                          color: Color(0xFFFF1744),
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: Color(0xFFFF1744),
                        size: 11,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Horizontal List of Real Match Cards
        if (matches.isNotEmpty)
          SizedBox(
            height: 180,
            child: ListView.separated(
              key: const PageStorageKey('row-sports'),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              itemCount: matches.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final match = matches[index];
                return _buildRealMatchCard(match);
              },
            ),
          )
        else if (isLoading)
          SizedBox(
            height: 180,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Color(0xFFE50914), strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'جاري تحميل المباريات...',
                    style: TextStyle(color: _p.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
          )
        else
          Container(
            height: 90,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: _p.cardAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _p.border),
            ),
            child: Center(
              child: Text(
                'لا توجد مباريات مجدولة حالياً',
                style: TextStyle(color: _p.textMuted, fontSize: 13),
              ),
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  // Real Match Card with increased height & clean local time + small date
  Widget _buildRealMatchCard(SportMatchItem match) {
    final leagueName = (match.league != null && match.league!.isNotEmpty)
        ? match.league!
        : 'مباراة';

    final timeData = _formatMatchTimeAndDate(match.kickoffAt);
    final matchTime = timeData['time'] ?? 'VS';
    final matchDate = timeData['date'] ?? '';

    return GestureDetector(
      onTap: () {
        // A match still to come opens a quarter of an hour before
        // kick-off, not earlier.
        if (!match.canOpen) {
          ScaffoldMessenger.of(context).removeCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                matchTime != 'VS'
                    ? 'تُفتح المباراة قبل انطلاقها بربع ساعة، الانطلاق في تمام الساعة $matchTime'
                    : 'تُفتح المباراة قبل انطلاقها بربع ساعة',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
              ),
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFF1E2638),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              duration: const Duration(seconds: 3),
            ),
          );
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SportsPlayerScreen(match: match),
          ),
        );
      },
      // Glass: the page shows through a deep blur and a faint white sheen
      // that brightens towards the top-left, under a thin light edge.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        // One layer, then the clip: the picture and its shading are
        // composited before the rounded edge is applied, so the
        // half-pixel bottom row is shaded like every other row.
        clipBehavior: Clip.antiAliasWithSaveLayer,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
          width: 250,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(_p.isDark ? 0.16 : 0.80),
                Colors.white.withOpacity(_p.isDark ? 0.05 : 0.55),
              ],
            ),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: Colors.white.withOpacity(_p.isDark ? 0.22 : 0.9),
              width: 0.8,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            children: [
              // Top Row: Status Badge & Tournament Name
              Row(
                children: [
                  _buildMatchStatusBadge(match, matchTime),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      leagueName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _p.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.sports_soccer_rounded,
                    color: _p.textMuted,
                    size: 14,
                  ),
                ],
              ),
              // Main Match Row: Home Club Logo - Center Score/Time - Away Club Logo,
              // centred in the space under the top row.
              Expanded(
                child: Center(
                  child: Row(
                    children: [
                      // Home Club
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GlowingCrest(url: match.home.logo, size: 76),
                            const SizedBox(height: 8),
                            Text(
                              match.home.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _p.text,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Center: score or local time, then the play button beneath
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (match.isLive || match.isEnded) ...[
                              MatchScoreLine(
                                homeScore: match.homeScore,
                                awayScore: match.awayScore,
                                style: TextStyle(
                                  color: _p.text,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2,
                                ),
                              ),
                              Text(
                                match.isLive
                                    ? (match.minute != null
                                        ? "${match.minute}'"
                                        : "مباشر")
                                    : 'انتهت',
                                style: TextStyle(
                                  color: match.isLive
                                      ? const Color(0xFFFF2A4A)
                                      : const Color(0xFF94A3B8),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ] else ...[
                              Text(
                                matchTime,
                                style: const TextStyle(
                                  color: Color(0xFFFF4D5B),
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              if (matchDate.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  matchDate,
                                  style: TextStyle(
                                    color: _p.textFaint,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),

                      // Away Club
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GlowingCrest(url: match.away.logo, size: 76),
                            const SizedBox(height: 8),
                            Text(
                              match.away.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _p.text,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildMatchStatusBadge(SportMatchItem match, String cleanTime) {
    if (match.isLive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFFF2A4A),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 4),
            const Text(
              'مباشر',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    } else if (match.isEnded) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: _p.isDark ? Colors.white.withOpacity(0.12) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: _p.isDark ? null : Border.all(color: _p.border),
        ),
        child: Text(
          'انتهت',
          style: TextStyle(
            color: _p.textMuted,
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          cleanTime.isNotEmpty && cleanTime != 'VS' ? cleanTime : 'قادمة',
          style: const TextStyle(
            color: Color(0xFF60A5FA),
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
  }

  Widget _buildHorizontalCategorySection({
    required String title,
    required List<CinemanaItem> items,
    required bool isLoading,
    VoidCallback? onViewAll,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Title with "عرض الكل"
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  // A short brand bar anchors the title to the section.
                  Container(
                    width: 3.5,
                    height: 18,
                    margin: const EdgeInsetsDirectional.only(end: 9),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFFF4757), Color(0xFFE50914)],
                      ),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Text(
                    title,
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : const Color(0xFF0F172A),
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
              if (onViewAll != null)
                InkWell(
                  onTap: onViewAll,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE50914).withOpacity(0.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'عرض الكل',
                          style: TextStyle(
                            color: Color(0xFFE50914),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(width: 2),
                        Icon(Icons.chevron_left_rounded,
                            size: 17, color: Colors.white),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Horizontal List of Movie Posters
        if (items.isNotEmpty)
          SizedBox(
            height: 156,
            child: WheelScroll(
              builder: (controller) => ListView.separated(
                // Keeps the row's offset while the section is recycled.
                key: PageStorageKey('row-$title'),
                controller: controller,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                // 104 wide plus the 12 of the separator: the motion needs to
                // know where a card sits without measuring it.
                itemBuilder: (context, index) => CardEntrance(
                  group: 'row-$title',
                  index: index,
                  child: CarouselFocus(
                    controller: controller,
                    index: index,
                    extent: 116,
                    width: 104,
                    child: _buildRealMoviePosterCard(items[index]),
                  ),
                ),
              ),
            ),
          )
        else if (isLoading)
          SizedBox(
            height: 156,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 4,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, __) => ClipRRect(
                borderRadius: BorderRadius.circular(6),
                // One layer, then the clip: the picture and its shading are
                // composited before the rounded edge is applied, so the
                // half-pixel bottom row is shaded like every other row.
                clipBehavior: Clip.antiAliasWithSaveLayer,
                child: Shimmer(
                  base: _p.skeleton,
                  highlight: _p.isDark
                      ? const Color(0xFF1E2636)
                      : const Color(0xFFF4F7FC),
                  child: const SizedBox(width: 104, height: 156),
                ),
              ),
            ),
          )
        else
          Container(
            height: 80,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: _p.cardAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _p.border),
            ),
            child: Center(
              child: Text(
                'لا توجد عناصر متاحة حالياً لهذا التصنيف',
                style: TextStyle(color: _p.textMuted, fontSize: 12.5),
              ),
            ),
          ),
      ],
    );
  }

  /// The scrim that carries a poster's title, and the little rating pill.
  ///
  /// Constants rather than expressions in the card: `withOpacity` builds a new
  /// Color, and with them inline every poster allocated a gradient, two
  /// colours and a border on every build of its row. As constants the same
  /// objects are handed to every card, and an unchanged const subtree is one
  /// Flutter can skip rebuilding outright.

  static const BoxDecoration _ratingBadge = BoxDecoration(
    color: Color(0xA6000000), // black at 65%
    borderRadius: BorderRadius.all(Radius.circular(8)),
    border: Border.fromBorderSide(
      BorderSide(color: Color(0x2EFFFFFF), width: 0.5), // white at 18%
    ),
  );

  // Real Movie Poster Card (High Resolution, Clean Border & Subtle Shadow)
  Widget _buildRealMoviePosterCard(CinemanaItem movie) {
    final poster = movie.cardImageUrl;

    return RepaintBoundary(
      child: PressScale(
        onTap: () {
          openCatalogueItem(context, movie);
        },
        child: SizedBox(
          width: 104,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            // One layer, then the clip: the picture and its shading are
            // composited before the rounded edge is applied, so the
            // half-pixel bottom row is shaded like every other row.
            clipBehavior: Clip.antiAliasWithSaveLayer,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Medium-size poster from the disk cache (104x156 is exactly 2:3,
                // so nothing is cropped)
                if (poster.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: movie.imageForWidth(
                        _decodeWidthFor(104).toDouble(),
                        hiRes: preferFullArtwork),
                    cacheManager: appImageCache,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.high,
                    memCacheWidth: _hiResDecodeWidth(104),
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                    placeholderFadeInDuration: Duration.zero,
                    useOldImageOnUrlChange: true,
                    placeholder: (_, __) => ColoredBox(color: _p.skeleton),
                    errorWidget: (_, __, ___) => _buildPosterPlaceholder(),
                  )
                else
                  _buildPosterPlaceholder(),

                // Rating Star Badge at Top Left
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: _ratingBadge,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded,
                            color: Color(0xFFFFB800), size: 13),
                        const SizedBox(width: 3),
                        Text(
                          movie.stars.isNotEmpty ? movie.stars : '8.0',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPosterPlaceholder() {
    return Container(
      color: _p.skeleton,
      child: Center(
          child: Icon(Icons.movie_outlined, color: _p.textFaint, size: 36)),
    );
  }

  // ==========================================
  // WIDE SERIES SECTION ("بطاقة كبيرة عريضة")
  // ==========================================
  Widget _buildWideSeriesSection({
    String title = 'المسلسلات',
    String badge = 'أحدث المواسم',
    required List<CinemanaItem> items,
    required bool isLoading,
    VoidCallback? onViewAll,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Title
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : const Color(0xFF0F172A),
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFE50914).withOpacity(0.18),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: const Color(0xFFE50914).withOpacity(0.4),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    color: Color(0xFFFF5252),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              if (onViewAll != null)
                InkWell(
                  onTap: onViewAll,
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'عرض الكل',
                          style: TextStyle(
                            color: Color(0xFFE50914),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(width: 2),
                        Icon(Icons.chevron_left_rounded,
                            size: 18, color: Colors.white),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Horizontal List of Wide Cards (224w x 138h)
        if (items.isNotEmpty)
          SizedBox(
            height: 148,
            // The same entrance and the same focus as every other row.
            child: WheelScroll(
              builder: (controller) => ListView.separated(
                // Keeps the row's offset while the section is recycled.
                key: PageStorageKey('wide-$title'),
                controller: controller,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                // 264 wide plus the 12 of the separator.
                itemBuilder: (context, index) => CardEntrance(
                  group: 'wide-$title',
                  index: index,
                  child: CarouselFocus(
                    controller: controller,
                    index: index,
                    extent: 276,
                    width: 264,
                    child: _buildWideSeriesCard(items[index]),
                  ),
                ),
              ),
            ),
          )
        else if (isLoading)
          SizedBox(
            height: 148,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 3,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              // A flat block the size of the card: reads as "already there".
              itemBuilder: (_, __) => Container(
                width: 264,
                decoration: BoxDecoration(
                  color: _p.skeleton,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          )
        else
          Container(
            height: 80,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: _p.cardAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _p.border),
            ),
            child: Center(
              child: Text(
                'لا توجد مسلسلات متاحة حالياً',
                style: TextStyle(color: _p.textMuted, fontSize: 12.5),
              ),
            ),
          ),
      ],
    );
  }

  // Large Wide Card for TV Series ("بطاقة كبيرة عريضة")
  /// A wide, clean picture: the series' backdrop edge to edge, nothing
  /// written on it. What it is, the page that opens says.
  Widget _buildWideSeriesCard(CinemanaItem series) {
    const double cardW = 264;
    const double cardH = 148;
    // The catalogue's own art is a poster, and a poster cropped wide shows
    // a strip of a face. A landscape still - the catalogue's own cover, or
    // TMDB's for the same title - is what a wide card wants. Without one,
    // the poster is shown whole, over a blurred, darkened copy of itself.
    final own = series.backdropUrl ?? '';
    final ownIsWide =
        own.isNotEmpty && own != series.imgUrl && own != series.imgThumbUrl;

    return RepaintBoundary(
      child: PressScale(
        // The row holds titles from more than one catalogue; this opens each
        // on the page that can actually play it.
        onTap: () => openCatalogueItem(context, series),
        child: SizedBox(
          width: cardW,
          height: cardH,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            // One layer, then the clip: the picture and its shading are
            // composited before the rounded edge is applied, so the
            // half-pixel bottom row is shaded like every other row.
            clipBehavior: Clip.antiAliasWithSaveLayer,
            child: Consumer(
              builder: (context, ref, _) {
                final fetched = ownIsWide
                    ? null
                    : ref
                        .watch(
                            spotlightBackdropProvider(wideStillKeyFor(series)))
                        .valueOrNull;
                final wide = ownIsWide ? own : fetched;
                final poster = series.imageForWidth(
                    _decodeWidthFor(cardH * 2 / 3).toDouble(),
                    hiRes: true);
                if (wide != null) {
                  return CachedNetworkImage(
                    imageUrl: wide,
                    cacheManager: appImageCache,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.high,
                    memCacheWidth: _hiResDecodeWidth(cardW),
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                    placeholderFadeInDuration: Duration.zero,
                    useOldImageOnUrlChange: true,
                    placeholder: (_, __) => ColoredBox(color: _p.skeleton),
                    errorWidget: (_, __, ___) => _buildPosterPlaceholder(),
                  );
                }
                if (poster.isEmpty) return _buildPosterPlaceholder();
                // No landscape anywhere: the poster fills the wide card
                // from its top, where the faces are. Never a narrow poster
                // standing in the middle of a wide card.
                return CachedNetworkImage(
                  imageUrl: poster,
                  cacheManager: appImageCache,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  filterQuality: FilterQuality.high,
                  memCacheWidth: _hiResDecodeWidth(cardW),
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  placeholderFadeInDuration: Duration.zero,
                  useOldImageOnUrlChange: true,
                  placeholder: (_, __) => ColoredBox(color: _p.skeleton),
                  errorWidget: (_, __, ___) => _buildPosterPlaceholder(),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
