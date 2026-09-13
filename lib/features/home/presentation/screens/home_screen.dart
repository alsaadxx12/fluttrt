import 'dart:ui' show ImageFilter;
import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';
import '../../../../presentation/widgets/window_caption_buttons.dart';
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';
import 'package:youtube_downloader/features/cinemana/presentation/providers/cinemana_provider.dart';
import 'package:youtube_downloader/features/cinemana/presentation/screens/cinemana_catalog_screen.dart';
import 'package:youtube_downloader/features/cinemana/presentation/screens/cinemana_detail_screen.dart';
import 'package:youtube_downloader/features/sports/data/models/sports_models.dart';
import 'package:youtube_downloader/features/sports/presentation/providers/sports_provider.dart';
import 'package:youtube_downloader/features/sports/presentation/screens/sports_player_screen.dart';
import 'package:youtube_downloader/features/sports/presentation/widgets/match_score_line.dart';
import 'package:youtube_downloader/features/settings/presentation/providers/settings_provider.dart';
import 'package:youtube_downloader/presentation/screens/main_scaffold.dart';
import 'package:youtube_downloader/features/sports/presentation/screens/channels_screen.dart';
import 'package:youtube_downloader/features/viu/data/viu_models.dart';
import 'package:youtube_downloader/features/viu/presentation/viu_widgets.dart';
import 'package:youtube_downloader/features/viu/presentation/other_films.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';
import 'package:youtube_downloader/features/home/presentation/widgets/football_showcase.dart';
import 'package:youtube_downloader/features/home/presentation/widgets/franchise_showcase.dart';
import 'package:youtube_downloader/features/cinemana/data/cinemana_franchises.dart';
import 'package:youtube_downloader/features/sports/presentation/widgets/glowing_crest.dart';
import '../../../../presentation/widgets/reveal.dart';
import '../../../sports/data/match_merge.dart';
import '../widgets/film_deck.dart';
import '../../../../core/video/desktop_video.dart';
import '../../../trailers/presentation/trailers_showcase.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final PageController _heroPageController;
  late final TextEditingController _searchController;
  final FocusNode _searchFocusNode = FocusNode();
  int _currentHeroPage = 0;

  // Number of slides the hero is actually rendering, kept in sync from build so
  // the auto-slide timer advances over the same list the user sees.
  int _heroSlideCount = 0;
  // Colours lifted from the top and bottom rows of the banner on screen, used
  // to paint the hero around the artwork instead of a cropped copy of it.
  Timer? _heroAutoSlideTimer;
  bool _isAutoSlidePaused = false;
  bool _isSearchExpanded = false;

  // In-place search state with posters
  List<CinemanaItem> _searchResults = [];
  bool _isSearchLoading = false;
  String? _searchErrorMessage;
  Timer? _searchDebounceTimer;
  CancelToken? _searchCancelToken;

  @override
  void initState() {
    super.initState();
    _heroPageController = PageController();
    _searchController = TextEditingController();

    _startAutoSlideTimer();
  }

  /// Warm the disk/memory cache for the slides right after the current one,
  /// so a swipe (or the auto-advance) never waits on the network.
  void _precacheNextHeroSlides(List<CinemanaItem> movies, double width) {
    if (!mounted || movies.isEmpty) return;
    final isDesktop = width >= 700;
    for (var i = 1; i <= 2; i++) {
      final m = movies[(_currentHeroPage + i) % movies.length];
      final wideCover = (m.backdropUrl != null && m.backdropUrl!.isNotEmpty && m.backdropUrl!.contains('cover'))
          ? m.backdropUrl!
          : '';
      final highResPoster = (m.imgUrl != null && m.imgUrl!.isNotEmpty) ? m.imgUrl! : m.bestPosterUrl;
      final url = isDesktop
          ? (wideCover.isNotEmpty ? wideCover : (m.bestBackdropUrl.isNotEmpty ? m.bestBackdropUrl : highResPoster))
          : (highResPoster.isNotEmpty ? highResPoster : m.bestBackdropUrl);
      if (url.isEmpty) continue;
      precacheImage(
        CachedNetworkImageProvider(url),
        context,
      ).catchError((_) {});
    }
  }

  void _startAutoSlideTimer() {
    _heroAutoSlideTimer?.cancel();
    _heroAutoSlideTimer = Timer.periodic(const Duration(seconds: 8), (timer) {
      if (!mounted || _isAutoSlidePaused || !_heroPageController.hasClients) return;
      final total = _heroSlideCount;
      if (total <= 1) return;
      final nextPage = (_currentHeroPage + 1) % total;
      _heroPageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _heroAutoSlideTimer?.cancel();
    _searchDebounceTimer?.cancel();
    _searchCancelToken?.cancel('disposed');
    _heroPageController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _toggleSearch(bool expand) {
    if (!expand) {
      _searchFocusNode.unfocus();
      _searchController.clear();
      _searchCancelToken?.cancel('closed');
    }
    setState(() {
      _isSearchExpanded = expand;
      if (!expand) {
        _searchResults.clear();
        _isSearchLoading = false;
        _searchErrorMessage = null;
      }
    });
    if (expand) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted && _isSearchExpanded && _searchFocusNode.canRequestFocus) {
          _searchFocusNode.requestFocus();
        }
      });
    }
  }

  // Live in-place search with posters, 400ms debounce, CancelToken and network safety
  void _onSearchQueryChanged(String query) {
    _searchDebounceTimer?.cancel();
    _searchCancelToken?.cancel('new query');
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _searchResults.clear();
        _isSearchLoading = false;
        _searchErrorMessage = null;
      });
      return;
    }
    setState(() {
      _isSearchLoading = true;
      _searchErrorMessage = null;
    });

    _searchCancelToken = CancelToken();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      try {
        final service = ref.read(cinemanaServiceProvider);
        final results = await service.search(q, cancelToken: _searchCancelToken);
        if (mounted) {
          setState(() {
            _searchResults = results;
            _isSearchLoading = false;
            _searchErrorMessage = null;
          });
        }
      } catch (e) {
        if (mounted && !(e is DioException && CancelToken.isCancel(e))) {
          setState(() {
            _isSearchLoading = false;
            _searchErrorMessage = 'تعذر الاتصال بالخادم، يُرجى التأكد من اتصال الإنترنت والمحاولة ثانيةً.';
          });
        }
      }
    });
  }

  void _performSearchNow(String query) async {
    _searchDebounceTimer?.cancel();
    _searchCancelToken?.cancel('instant search');
    final q = query.trim();
    if (q.isEmpty) return;
    setState(() {
      _isSearchLoading = true;
      _searchErrorMessage = null;
    });

    _searchCancelToken = CancelToken();
    try {
      final service = ref.read(cinemanaServiceProvider);
      final results = await service.search(q, cancelToken: _searchCancelToken);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearchLoading = false;
          _searchErrorMessage = null;
        });
      }
    } catch (e) {
      if (mounted && !(e is DioException && CancelToken.isCancel(e))) {
        setState(() {
          _isSearchLoading = false;
          _searchErrorMessage = 'تعذر الاتصال بالخادم، يُرجى التأكد من اتصال الإنترنت والمحاولة ثانيةً.';
        });
      }
    }
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

  // Format kickoff ISO timestamp into clean local time (e.g. 19:45) and small date (e.g. 09/09)
  Map<String, String> _formatMatchTimeAndDate(String rawKickoff) {
    if (rawKickoff.isEmpty) {
      return {'time': 'VS', 'date': ''};
    }
    final dt = DateTime.tryParse(rawKickoff);
    if (dt == null) {
      return {'time': rawKickoff, 'date': ''};
    }
    final local = dt.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    final timeStr = '$hour:$min';
    final dateStr = '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}';
    return {'time': timeStr, 'date': dateStr};
  }

  // The merged list, kept until one of the two feeds actually changes.
  List<SportMatchItem>? _mergedMatches;
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
    final merged = MatchMerge.mergeAll([
      live,
      [for (final g in groups) ...g.matches],
    ]);
    _mergedFromLive = live;
    _mergedFromGroups = groups;
    _mergedMatches = merged;
    return merged;
  }

  @override
  Widget build(BuildContext context) {
    final sportsState = ref.watch(sportsNotifierProvider('today'));
    final bannerAsync = ref.watch(heroBannerMoviesProvider);
    final featuredAsync = ref.watch(homeFeaturedProvider);
    final recentlyAddedAsync = ref.watch(homeRecentlyAddedProvider);
    final latestMoviesAsync = ref.watch(homeLatestMoviesProvider);
    final latestSeriesAsync = ref.watch(homeLatestSeriesProvider);
    final animeAsync = ref.watch(homeAnimeProvider);
    final mostViewedAsync = ref.watch(homeMostViewedProvider);
    final arabicMoviesAsync = ref.watch(homeArabicMoviesProvider);
    final arabicSeriesAsync = ref.watch(homeArabicSeriesProvider);

    // Hero Section: Strictly official Cinemana banners ("الإصدارات الجديدة")
    final heroMovies = bannerAsync.when(
      data: (banners) => banners.take(20).toList(),
      loading: () => featuredAsync.when(
        data: (f) => f.take(20).toList(),
        loading: () => const <CinemanaItem>[],
        error: (_, __) => const <CinemanaItem>[],
      ),
      error: (_, __) => featuredAsync.when(
        data: (f) => f.take(20).toList(),
        loading: () => const <CinemanaItem>[],
        error: (_, __) => const <CinemanaItem>[],
      ),
    );

    _heroSlideCount = heroMovies.length;

    // Collect all real matches for today.
    //
    // The two feeds number their matches differently, so comparing ids let
    // the same fixture through twice and it sat twice in the row. Identity is
    // the two teams, and the surviving card keeps every channel either feed
    // knew about, so the source is chosen inside the match.
    final allTodayMatches = _mergedTodayMatches(sportsState);


    // Dynamic title: "المباريات المباشرة" if live, otherwise "مباريات اليوم"
    final bool hasLiveMatches = sportsState.liveMatches.isNotEmpty;
    final String sportsSectionTitle = hasLiveMatches ? 'المباريات المباشرة' : 'مباريات اليوم';

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = _p.bg;
    final refreshBg = isDark ? const Color(0xFF131A27) : Colors.white;

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
            backgroundColor: refreshBg,
            onRefresh: () async {
              await Future.wait([
                ref.refresh(heroBannerMoviesProvider.future),
                ref.refresh(homeFeaturedProvider.future),
                ref.refresh(homeRecentlyAddedProvider.future),
                ref.refresh(homeLatestMoviesProvider.future),
                ref.refresh(homeLatestSeriesProvider.future),
                ref.refresh(homeAnimeProvider.future),
                ref.refresh(sportsChannelsProvider.future),
                ref.refresh(homeMostViewedProvider.future),
                ref.refresh(homeArabicMoviesProvider.future),
                ref.refresh(homeArabicSeriesProvider.future),
                ref.read(sportsNotifierProvider('today').notifier).refresh(),
              ]);
            },
            child: CustomScrollView(
              key: const PageStorageKey('home'),
              // Pull to refresh shows the spinner without dragging the page.
              physics: const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              slivers: [
                // 1. Full-Bleed Hero Movie Section (Screen-filling, Crystal Clear, Latest 20, Interactive & Pausable)
                SliverToBoxAdapter(
                  child: _buildHeroSection(heroMovies, bannerAsync.isLoading && heroMovies.isEmpty),
                ),

                // Sports Section: Real Matches (Dynamic title, increased card height, clean time/date, team logos)
                SliverToBoxAdapter(
                  child: _buildSportsSection(
                    title: sportsSectionTitle,
                    isLiveMode: hasLiveMatches,
                    matches: allTodayMatches,
                    isLoading: sportsState.isLoading,
                  ),
                ),

                const SliverToBoxAdapter(
                  child: SizedBox(height: 24),
                ),

                // Channels Section (قسم القنوات التلفزيونية والرياضية)
                SliverToBoxAdapter(
                  child: Reveal(index: 1, child: _buildLiveChannelsSection()),
                ),

                const SliverToBoxAdapter(
                  child: SizedBox(height: 24),
                ),

                // 2. أضيف حديثًا (Recently Added)
                SliverToBoxAdapter(
                  child: recentlyAddedAsync.when(
                    data: (items) => _buildHorizontalCategorySection(
                      title: 'أضيف حديثًا',
                      items: items,
                      isLoading: false,
                      onViewAll: () => _openCatalog(kind: 'movies', order: 'desc'),
                    ),
                    loading: () => _buildHorizontalCategorySection(
                      title: 'أضيف حديثًا',
                      items: const [],
                      isLoading: true,
                    ),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                ),

                const SliverToBoxAdapter(
                  child: SizedBox(height: 24),
                ),

                // 3. أحدث الأفلام (Latest Movies)
                SliverToBoxAdapter(
                  child: latestMoviesAsync.when(
                    data: (items) => _buildHorizontalCategorySection(
                      title: 'أحدث الأفلام',
                      items: items,
                      isLoading: false,
                      onViewAll: () => _openCatalog(kind: 'movies', order: 'release'),
                    ),
                    loading: () => _buildHorizontalCategorySection(
                      title: 'أحدث الأفلام',
                      items: const [],
                      isLoading: true,
                    ),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                ),

                const SliverToBoxAdapter(
                  child: SizedBox(height: 24),
                ),

                // Decorative: the big leagues, tall branded cards.
                const SliverToBoxAdapter(child: Reveal(index: 1, child: LeaguesShowcase())),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),

                // 4. أحدث المسلسلات (Latest Series) - Wide Card layout
                SliverToBoxAdapter(
                  child: latestSeriesAsync.when(
                    data: (items) => _buildWideSeriesSection(
                      title: 'أحدث المسلسلات',
                      badge: 'جديد',
                      items: items,
                      isLoading: false,
                      onViewAll: () => _openCatalog(kind: 'series', order: 'release'),
                    ),
                    loading: () => _buildWideSeriesSection(
                      title: 'أحدث المسلسلات',
                      items: const [],
                      isLoading: true,
                    ),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                ),

                const SliverToBoxAdapter(
                  child: SizedBox(height: 24),
                ),

                // The big film series, each complete and in order.
                const SliverToBoxAdapter(child: Reveal(index: 2, child: FranchisesShowcase())),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),

                // 5. قسم الأنمي (Anime)
                SliverToBoxAdapter(
                  child: animeAsync.when(
                    data: (items) => _buildHorizontalCategorySection(
                      title: 'الأنمي',
                      items: items,
                      isLoading: false,
                      onViewAll: () => _openCatalog(kind: 'anime', order: 'release'),
                    ),
                    loading: () => _buildHorizontalCategorySection(
                      title: 'الأنمي',
                      items: const [],
                      isLoading: true,
                    ),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                ),

                const SliverToBoxAdapter(
                  child: SizedBox(height: 24),
                ),

                // Anime franchises: each franchise's series and films together.
                const SliverToBoxAdapter(
                    child: Reveal(index: 3, child: FranchisesShowcase(section: FranchiseSection.anime))),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),

                // Decorative: the game's stars, tall portrait cards.
                const SliverToBoxAdapter(child: Reveal(index: 4, child: StarsShowcase())),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),

                // 6. الأكثر مشاهدة (Most Viewed)
                SliverToBoxAdapter(
                  child: mostViewedAsync.when(
                    data: (items) => _buildHorizontalCategorySection(
                      title: 'الأكثر مشاهدة',
                      items: items,
                      isLoading: false,
                      onViewAll: () => _openCatalog(kind: 'movies', order: 'views'),
                    ),
                    loading: () => _buildHorizontalCategorySection(
                      title: 'الأكثر مشاهدة',
                      items: const [],
                      isLoading: true,
                    ),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                ),

                const SliverToBoxAdapter(
                  child: SizedBox(height: 24),
                ),

                // Decorative: the Arab leagues.
                const SliverToBoxAdapter(
                  child: LeaguesShowcase(title: 'الدوريات العربية', leagues: FootballLeague.arab),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),

                // 7. الأفلام العربية (Arabic Movies)
                SliverToBoxAdapter(
                  child: arabicMoviesAsync.when(
                    data: (items) => _buildHorizontalCategorySection(
                      title: 'الأفلام العربية',
                      items: items,
                      isLoading: false,
                      onViewAll: () => _openCatalog(kind: 'movies', categoryId: 130),
                    ),
                    loading: () => _buildHorizontalCategorySection(
                      title: 'الأفلام العربية',
                      items: const [],
                      isLoading: true,
                    ),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                ),

                const SliverToBoxAdapter(
                  child: SizedBox(height: 24),
                ),

                // 8. المسلسلات العربية (Arabic Series) - Wide Card layout
                SliverToBoxAdapter(
                  child: arabicSeriesAsync.when(
                    data: (items) => _buildWideSeriesSection(
                      title: 'المسلسلات العربية',
                      badge: 'عربي',
                      items: items,
                      isLoading: false,
                      onViewAll: () => _openCatalog(kind: 'series', categoryId: 130),
                    ),
                    loading: () => _buildWideSeriesSection(
                      title: 'المسلسلات العربية',
                      items: const [],
                      isLoading: true,
                    ),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                ),

                const SliverToBoxAdapter(
                  child: SizedBox(height: 24),
                ),

                // TV-series universes (spin-offs and sequels together).
                const SliverToBoxAdapter(
                    child: Reveal(index: 5, child: FranchisesShowcase(section: FranchiseSection.series))),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),

                // 9. Viu: Arabic / Korean / Turkish series and free films,
                // played in the app's own player. Each row loads when it
                // scrolls near and hides itself if it has nothing.
                for (final category in ViuCategory.home.where((c) => !c.isMovies))
                  SliverToBoxAdapter(child: Reveal(index: 6, child: ViuHomeSection(category: category))),
                // "أفلام أخرى": Viu's free films plus varied films by genre.
                const SliverToBoxAdapter(child: Reveal(index: 7, child: OtherFilmsSection())),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),

                // Official trailers from TMDB, played on YouTube. Phone only:
                // the widget hides itself on TV, desktop, and when TMDB is not
                // configured.
                const SliverToBoxAdapter(child: Reveal(index: 8, child: TrailersShowcase())),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),

          // Fixed Pinned Top App Bar (Permanent compact header that stays at the top when scrolling)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: _barColor,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  child: _buildFloatingTopBar(),
                ),
              ),
            ),
          ),

          // In-Place Search Results Overlay (Showing live results WITH POSTERS)
          if (_isSearchExpanded &&
              (_isSearchLoading || _searchResults.isNotEmpty || _searchController.text.trim().isNotEmpty))
            Positioned.fill(
              top: MediaQuery.of(context).padding.top + 46,
              child: _buildSearchResultsView(),
            ),

          // The newest films wait on the rail rather than interrupting the
          // page. This is the one side surface: the old card that slid in by
          // itself on start-up is gone.
          if (!_isSearchExpanded) const FilmDeck(),
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

  /// The top bar: matches the page and sidebar background so everything is one seamless canvas.
  Color get _barColor => _p.bg;
  static const double _heroTopRadius = 16;

  Widget _buildHeroSection(List<CinemanaItem> movies, bool isLoading) {
    return LayoutBuilder(
      builder: (context, constraints) => _buildHeroContent(movies, isLoading, constraints.maxWidth),
    );
  }

  Widget _buildHeroContent(
    List<CinemanaItem> movies,
    bool isLoading,
    double availableWidth,
  ) {
    final media = MediaQuery.of(context);
    final isDesktop = availableWidth > 680;
    final artworkTop = media.padding.top + (isDesktop ? 34.0 : 38.0);
    // On Windows/Desktop, provide a generous, well-proportioned height (420-520px)
    // so the hero artwork has ample space, clear visibility, and doesn't get squeezed.
    final artworkHeight = isDesktop
        ? (availableWidth * 0.35).clamp(420.0, 520.0)
        : availableWidth / _heroArtworkAspect;

    final currentMovie = movies.isEmpty ? null : movies[_currentHeroPage.clamp(0, movies.length - 1)];
    if (movies.length > 1) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _precacheNextHeroSlides(movies, availableWidth),
      );
    }

    return Stack(
      children: [
        // The bar's colour above the artwork, the page's colour below it.
        Positioned.fill(child: _buildHeroSurround(artworkTop, artworkHeight)),

        // The Column is the only unpositioned child, so it sizes the Stack:
        // the hero is exactly as tall as the artwork plus its details.
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: artworkTop),

            // Full-bleed artwork carousel with Tap-to-Pause, rounded at the top
            // where it meets the bar.
            SizedBox(
              height: artworkHeight,
              width: double.infinity,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(_heroTopRadius)),
                child: movies.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          setState(() {
                            _isAutoSlidePaused = !_isAutoSlidePaused;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                _isAutoSlidePaused ? 'تم إيقاف التحريك التلقائي' : 'تم استئناف التحريك التلقائي',
                                style: const TextStyle(fontSize: 12),
                              ),
                              duration: const Duration(seconds: 1),
                              behavior: SnackBarBehavior.floating,
                              backgroundColor: const Color(0xFF1B2232),
                            ),
                          );
                        },
                        child: PageView.builder(
                          controller: _heroPageController,
                          physics: const BouncingScrollPhysics(),
                          onPageChanged: (index) {
                            setState(() => _currentHeroPage = index);
                          },
                          itemCount: movies.length,
                          itemBuilder: (context, index) {
                            return _buildHeroFullPoster(movies[index], availableWidth);
                          },
                        ),
                      )
                    : (isLoading ? _buildHeroLoadingSkeleton() : _buildHeroEmptyPlaceholder()),
              ),
            ),

            // Only the dots sit below the picture; everything else is on it.
            SizedBox(
              height: 18,
              child: movies.length > 1 ? Center(child: _buildHeroDots(movies.length)) : null,
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
        if (currentMovie != null)
          Positioned(
            left: 20,
            right: 20,
            top: artworkTop,
            height: artworkHeight,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildHeroRealMovieDetails(currentMovie),
              ),
            ),
          ),
      ],
    );
  }

  /// Paints the hero around the artwork: the bar's fixed colour above it
  /// (and behind its rounded top corners), the page's own colour below.
  Widget _buildHeroSurround(double artworkTop, double artworkHeight) {
    final pageBg = _homeBg;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        if (height <= 0) return ColoredBox(color: pageBg);
        final barEnd = ((artworkTop + _heroTopRadius) / height).clamp(0.0, 1.0);
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_barColor, _barColor, pageBg, pageBg],
              stops: [0.0, barEnd, barEnd, 1.0],
            ),
          ),
        );
      },
    );
  }

  /// The home page's background - the colour the hero's fog fades into.
  Color get _homeBg => _p.bg;

  // One hero slide: the complete artwork, uncropped, edge to edge.
  Widget _buildHeroFullPoster(CinemanaItem movie, double availableWidth) {
    final isDesktop = availableWidth >= 700;
    final wideCover = (movie.backdropUrl != null &&
            movie.backdropUrl!.isNotEmpty &&
            movie.backdropUrl!.contains('cover'))
        ? movie.backdropUrl!
        : '';
    final highResPoster = (movie.imgUrl != null && movie.imgUrl!.isNotEmpty)
        ? movie.imgUrl!
        : movie.bestPosterUrl;

    // On mobile phone portrait, always prioritize the official high-resolution
    // portrait poster (1280x1920) rather than the low-res 2.7:1 horizontal strip!
    final imageUrl = isDesktop
        ? (wideCover.isNotEmpty ? wideCover : (movie.bestBackdropUrl.isNotEmpty ? movie.bestBackdropUrl : highResPoster))
        : (highResPoster.isNotEmpty ? highResPoster : movie.bestBackdropUrl);

    if (imageUrl.isEmpty) return _buildHeroEmptyPlaceholder();

    if (isDesktop) {
      if (wideCover.isNotEmpty) {
        return Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: wideCover,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              filterQuality: FilterQuality.high,
              memCacheWidth: null, // Full native razor-sharp resolution
              memCacheHeight: null,
              fadeInDuration: const Duration(milliseconds: 150),
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
              fit: BoxFit.cover,
              alignment: Alignment.center,
              memCacheWidth: 400, // a blur needs no detail
              fadeInDuration: const Duration(milliseconds: 150),
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
          const ColoredBox(color: Color(0x45000000)),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  memCacheWidth: null, // Native full resolution without downsampling
                  memCacheHeight: null,
                  fadeInDuration: const Duration(milliseconds: 150),
                  placeholder: (_, __) => _buildHeroLoadingSkeleton(),
                  errorWidget: (_, __, ___) => _buildHeroEmptyPlaceholder(),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Mobile: Full-bleed crystal-clear native resolution without downsampling
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      filterQuality: FilterQuality.high,
      memCacheWidth: null,
      memCacheHeight: null,
      fadeInDuration: const Duration(milliseconds: 150),
      placeholder: (_, __) => _buildHeroLoadingSkeleton(),
      errorWidget: (_, __, ___) => _buildHeroEmptyPlaceholder(),
    );
  }

  Widget _buildHeroLoadingSkeleton() {
    return Container(
      color: _p.skeleton,
      child: const Center(
        child: SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(
            color: Color(0xFFE50914),
            strokeWidth: 2.5,
          ),
        ),
      ),
    );
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
    final searchBarBg = isDark ? const Color(0xFF111726).withOpacity(0.96) : Colors.white.withOpacity(0.98);
    final searchBorder = isDark
        ? Border.all(color: Colors.white.withOpacity(0.12), width: 0.8)
        : Border.all(color: const Color(0xFFCBD5E1), width: 1.0);
    final searchTextColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final searchHintColor = isDark ? Colors.white38 : const Color(0xFF94A3B8);
    const searchIconColor = Color(0xFFE50914);
    final closeIconColor = isDark ? Colors.white70 : const Color(0xFF64748B);

    final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    final topBarContent = SizedBox(
      height: 36,
      child: Stack(
        children: [
          // Base Top Bar (User Profile + Theme Toggle + Search Trigger + Caption Buttons + CINEBALL Logo)
          AnimatedOpacity(
            opacity: _isSearchExpanded ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: IgnorePointer(
              ignoring: _isSearchExpanded,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Left: User Button - Tapping pops out the sidebar Drawer immediately!
                  _buildTranslucentIconButton(
                    icon: Icons.person_outline_rounded,
                    onTap: () {
                      mainScaffoldKey.currentState?.openDrawer();
                    },
                  ),
                  const SizedBox(width: 8),

                  // Quick Theme Mode Toggle (Sun / Moon)
                  _buildTranslucentIconButton(
                    icon: isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                    onTap: () {
                      ref.read(settingsProvider.notifier).setThemeMode(
                            isDark ? ThemeMode.light : ThemeMode.dark,
                          );
                    },
                  ),
                  const SizedBox(width: 8),

                  // Search Trigger Button
                  _buildTranslucentIconButton(
                    icon: Icons.search_rounded,
                    onTap: () => _toggleSearch(true),
                  ),

                  // On Desktop: Elegant integrated window controls (frameless, seamless)
                  if (isDesktop) ...[
                    const SizedBox(width: 6),
                    Container(
                      height: 18,
                      width: 1,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      color: isDark ? Colors.white12 : Colors.black12,
                    ),
                    const WindowCaptionButtons(),
                  ],

                  const Spacer(),

                  // Right: Enlarged, Professional CINEBALL Logo
                  _buildCineballLogo(),
                ],
              ),
            ),
          ),

          // Unfolding & Folding Animated Search Bar
          Align(
            alignment: Alignment.center,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              width: _isSearchExpanded ? double.infinity : 0.0,
              height: 36,
              decoration: BoxDecoration(
                color: searchBarBg,
                borderRadius: BorderRadius.circular(18),
                border: _isSearchExpanded ? searchBorder : null,
                boxShadow: _isSearchExpanded
                    ? [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDark ? 0.45 : 0.12),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: _isSearchExpanded
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const NeverScrollableScrollPhysics(),
                        child: SizedBox(
                          width: MediaQuery.of(context).size.width - 32,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Row(
                              children: [
                                const Icon(Icons.search_rounded, color: searchIconColor, size: 22),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: _searchController,
                                    focusNode: _searchFocusNode,
                                    onChanged: _onSearchQueryChanged,
                                    style: TextStyle(
                                      color: searchTextColor,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'ابحث عن أفلام، مسلسلات، أجزاء، مباريات...',
                                      hintStyle: TextStyle(color: searchHintColor, fontSize: 13),
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      contentPadding: EdgeInsets.zero,
                                      isDense: true,
                                    ),
                                    textInputAction: TextInputAction.search,
                                    onSubmitted: _performSearchNow,
                                  ),
                                ),
                                if (_isSearchLoading)
                                  const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(color: Color(0xFFE50914), strokeWidth: 2),
                                  )
                                else
                                  IconButton(
                                    icon: Icon(Icons.close_rounded, color: closeIconColor, size: 20),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () => _toggleSearch(false),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
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
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _p.isDark ? Colors.white.withOpacity(0.16) : const Color(0x0D0F172A),
            border: Border.all(color: _p.isDark ? Colors.white.withOpacity(0.24) : const Color(0x1F0F172A), width: 1),
          ),
          child: Icon(
            icon,
            color: _p.isDark ? Colors.white.withOpacity(0.95) : _p.icon,
            size: 17,
          ),
        ),
      ),
    );
  }

  // Compact, Professional CINEBALL Logo
  Widget _buildCineballLogo() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'CINEBALL',
          style: TextStyle(
            color: _p.isDark ? Colors.white : _p.text,
            fontSize: 14.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
            shadows: _p.isDark ? const [Shadow(color: Color(0xFFE50914), blurRadius: 10)] : null,
          ),
        ),
        const SizedBox(width: 7),
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFFFF4D5B).withOpacity(0.55),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE50914).withOpacity(0.35),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Image.asset(
              'assets/images/app_logo.png',
              width: 28,
              height: 28,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Container(
                width: 28,
                height: 28,
                color: const Color(0xFFE50914),
                child: const Icon(Icons.movie_rounded, color: Colors.white, size: 16),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // REAL HERO DETAILS (Crisp Title Without Muddy Shadows, Compact Play Button)
  // ==========================================
  Widget _buildHeroRealMovieDetails(CinemanaItem movie) {
    final genreText =
        movie.categories.isNotEmpty ? movie.categories.take(2).join(' • ') : (movie.isSeries ? 'مسلسل' : 'فيلم');
    final yearText = movie.year.isNotEmpty ? movie.year : '2026';
    final storyText = movie.arContent.isNotEmpty ? movie.arContent : movie.enContent;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Movie Title
        Text(
          movie.displayTitle,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.2,
            // Two stacked shadows instead of dimming the picture: a tight dark
            // core for edge contrast and a wide soft one to lift the glyphs off
            // whatever part of the artwork sits behind them.
            shadows: [
              Shadow(color: Colors.black, blurRadius: 4, offset: Offset(0, 1.5)),
              Shadow(color: Colors.black87, blurRadius: 14),
            ],
          ),
        ),
        const SizedBox(height: 2),

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

        // Story summary (if present, as seen on Cinemana website)
        if (storyText.isNotEmpty) ...[
          const SizedBox(height: 3),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              storyText,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withOpacity(0.85),
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                height: 1.3,
                shadows: const [
                  Shadow(color: Colors.black, blurRadius: 3),
                  Shadow(color: Colors.black87, blurRadius: 10),
                ],
              ),
            ),
          ),
        ],

        const SizedBox(height: 8),

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
            'شاهد الآن',
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

        const SizedBox(height: 6),
      ],
    );
  }

  Widget _buildHeroDots(int totalSlides) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        totalSlides,
        (dotIndex) {
          final isCurrent = dotIndex == _currentHeroPage;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 2.5),
            width: isCurrent ? 18 : 6,
            height: 5.5,
            decoration: BoxDecoration(
              color: isCurrent ? const Color(0xFFE50914) : (_p.isDark ? Colors.white24 : const Color(0x330F172A)),
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

  /// A generous decode width for a card [logicalWidth] wide: twice its pixels,
  /// so downscaling the full poster keeps its edges crisp, capped at 720 so a
  /// large poster never decodes more than it can show.
  int _hiResDecodeWidth(double logicalWidth) {
    final px = logicalWidth * MediaQuery.of(context).devicePixelRatio * 2;
    return px.clamp(200, 720).round();
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

  // ==========================================
  // IN-PLACE SEARCH RESULTS VIEW (Showing Posters & Details)
  // ==========================================
  Widget _buildSearchResultsView() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final overlayBg = isDark ? const Color(0xFF07090E).withOpacity(0.98) : const Color(0xFFF8FAFC).withOpacity(0.98);
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return Container(
      color: overlayBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  'نتائج البحث (${_searchResults.length})',
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => _toggleSearch(false),
                  child: const Text(
                    'إغلاق',
                    style: TextStyle(color: Color(0xFFE50914), fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isSearchLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFE50914)),
                  )
                : _searchErrorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline_rounded, color: Color(0xFFE50914), size: 40),
                              const SizedBox(height: 10),
                              Text(
                                _searchErrorMessage!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isDark ? Colors.white70 : const Color(0xFF64748B),
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 14),
                              ElevatedButton.icon(
                                onPressed: () => _performSearchNow(_searchController.text),
                                icon: const Icon(Icons.refresh_rounded, size: 16),
                                label: const Text('إعادة المحاولة'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFE50914),
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _searchResults.isEmpty
                        ? Center(
                            child: Text(
                              'لم يتم العثور على نتائج لـ "${_searchController.text.trim()}"',
                              style: TextStyle(
                                color: isDark ? Colors.white54 : const Color(0xFF64748B),
                                fontSize: 13,
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: _searchResults.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final item = _searchResults[index];
                              return _buildSearchResultItem(item);
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResultItem(CinemanaItem item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final poster = item.bestPosterUrl.isNotEmpty ? item.bestPosterUrl : (item.imgUrl ?? item.imgThumbUrl);
    final cardBg = isDark ? const Color(0xFF121724) : Colors.white;
    final cardBorder = isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFE2E8F0);
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final metaColor = isDark ? Colors.white.withOpacity(0.65) : const Color(0xFF64748B);

    return GestureDetector(
      onTap: () {
        _toggleSearch(false);
        Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(
            builder: (_) => CinemanaDetailScreen(item: item),
          ),
        );
      },
      child: Container(
        height: 85,
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.25 : 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            // Poster Image
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: (poster != null && poster.isNotEmpty)
                  ? CachedNetworkImage(
                      imageUrl: poster,
                      width: 55,
                      height: 70,
                      memCacheWidth: _decodeWidthFor(55),
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                      errorWidget: (_, __, ___) => Container(
                        width: 55,
                        height: 70,
                        color: isDark ? const Color(0xFF1A2234) : const Color(0xFFE2E8F0),
                        child: Icon(
                          Icons.movie_outlined,
                          color: isDark ? Colors.white24 : Colors.black26,
                        ),
                      ),
                    )
                  : Container(
                      width: 55,
                      height: 70,
                      color: isDark ? const Color(0xFF1A2234) : const Color(0xFFE2E8F0),
                      child: Icon(
                        Icons.movie_outlined,
                        color: isDark ? Colors.white24 : Colors.black26,
                      ),
                    ),
            ),
            const SizedBox(width: 12),

            // Title & Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: titleColor,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, color: Color(0xFFFFB800), size: 14),
                      const SizedBox(width: 3),
                      Text(
                        item.stars.isNotEmpty ? item.stars : '8.0',
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (item.year.isNotEmpty) ...[
                        Text(' • ', style: TextStyle(color: metaColor.withOpacity(0.5))),
                        Text(
                          item.year,
                          style: TextStyle(color: metaColor, fontSize: 11),
                        ),
                      ],
                      if (item.categories.isNotEmpty) ...[
                        Text(' • ', style: TextStyle(color: metaColor.withOpacity(0.5))),
                        Flexible(
                          child: Text(
                            item.categories.first,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: metaColor, fontSize: 11),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Play Icon
            const Icon(Icons.play_circle_fill_rounded, color: Color(0xFFE50914), size: 28),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // 2. REAL MATCHES SECTION (Dynamic Title, Increased Height, Clean Time/Date)
  // ==========================================
  // ==========================================
  // LIVE TV & SPORTS CHANNELS SECTION
  // ==========================================
  Widget _buildLiveChannelsSection() {
    final channelsAsync = ref.watch(sportsChannelsProvider);
    // Once the list is in, fetch every logo into the image cache, so the
    // channels page and the list under the player show them at once.
    ref.listen<AsyncValue<List<SportsChannel>>>(sportsChannelsProvider, (_, next) {
      final list = next.valueOrNull;
      if (list != null && mounted) precacheChannelLogos(context, list);
    });
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header: "القنوات المباشرة" with LIVE badge and "عرض الكل"
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFFF2A4A),
                      boxShadow: [
                        BoxShadow(color: Color(0xFFFF2A4A), blurRadius: 6, spreadRadius: 1),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'القنوات المباشرة',
                    style: TextStyle(
                      color: titleColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () => context.push('/channels'),
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
                      Icon(Icons.chevron_left_rounded, size: 18, color: Color(0xFFE50914)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Horizontal Channels List
        channelsAsync.when(
          loading: () => SizedBox(
            height: 108,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 5,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, __) => Container(
                width: 192,
                decoration: BoxDecoration(
                  color: _p.skeleton,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          error: (_, __) => const SizedBox.shrink(),
          data: (channels) {
            if (channels.isEmpty) return const SizedBox.shrink();
            final shared = channelsSharingLogo(channels);
            return SizedBox(
              height: 108,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: channels.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                  final channel = channels[index];
                  return Reveal(
                    index: index,
                    step: const Duration(milliseconds: 45),
                    maxDelay: const Duration(milliseconds: 320),
                    offset: 12,
                    child: _buildHomeChannelCard(channel, isDark,
                        caption: shared.contains(channel.channelName) ? channel.channelName : null),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildHomeChannelCard(SportsChannel channel, bool isDark, {String? caption}) {
    // A 16:9 channel tile, a little larger than before, no name under it.
    // Tapping goes to the channels page, which opens this channel in the
    // native player - not the sports match page.
    return GestureDetector(
      onTap: () => context.push('/channels', extra: channel),
      child: Container(
        width: 192,
        height: 108,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF121724) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFE2E8F0),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(child: channelTileImage(channel, caption: caption)),
            PositionedDirectional(
              top: 8,
              start: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF2A4A),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text(
                  'LIVE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
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
                const Icon(Icons.sports_soccer_rounded, color: Color(0xFFE50914), size: 19),
                const SizedBox(width: 8),
              ],

              // Dynamic Title: "المباريات المباشرة" or "مباريات اليوم"
              Text(
                title,
                style: TextStyle(color: _p.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () => context.push('/sports'),
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

        // Horizontal List of Real Match Cards with increased height
        if (matches.isNotEmpty)
          SizedBox(
            height: 196,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
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
            height: 196,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(color: Color(0xFFE50914), strokeWidth: 2),
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
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _p.border),
            ),
            child: Center(
              child: Text(
                'لا توجد مباريات مجدولة حالياً',
                style: TextStyle(color: _p.textMuted, fontSize: 13),
              ),
            ),
          ),
      ],
    );
  }

  // Real Match Card with increased height & clean local time + small date
  Widget _buildRealMatchCard(SportMatchItem match) {
    final leagueName = (match.league != null && match.league!.isNotEmpty) ? match.league! : 'مباراة';

    final timeData = _formatMatchTimeAndDate(match.kickoffAt);
    final matchTime = timeData['time'] ?? 'VS';
    final matchDate = timeData['date'] ?? '';

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SportsPlayerScreen(match: match),
          ),
        );
      },
      child: Container(
        width: 300,
        decoration: BoxDecoration(
          color: _p.isDark ? const Color(0xFF101522) : _p.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: match.isLive ? const Color(0xFFFF2A4A).withOpacity(0.55) : const Color(0xFFE50914).withOpacity(0.25),
            width: 1.2,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                              match.isLive ? (match.minute != null ? "${match.minute}'" : "مباشر") : 'انتهت',
                              style: TextStyle(
                                color: match.isLive ? const Color(0xFFFF2A4A) : const Color(0xFF94A3B8),
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
                          const SizedBox(height: 8),
                          // Play / Watch - flat, no glow
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: match.isLive ? const Color(0xFFFF2A4A) : const Color(0xFFE50914),
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
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
          color: _p.isDark ? Colors.white.withOpacity(0.12) : const Color(0x140F172A),
          borderRadius: BorderRadius.circular(8),
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
          color: const Color(0xFFE50914).withOpacity(0.2),
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

  // ==========================================
  // CATEGORY SECTION TEMPLATE (With onViewAll and High Quality Posters)
  // ==========================================
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
                      color: Theme.of(context).brightness == Brightness.dark ? Colors.white : const Color(0xFF0F172A),
                      fontSize: 18,
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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                        Icon(Icons.chevron_left_rounded, size: 17, color: Color(0xFFE50914)),
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
            height: 195,
            child: WheelScroll(
              builder: (controller) => ListView.separated(
              controller: controller,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final movie = items[index];
                // Cards arrive one after the other as the row is read.
                return Reveal(
                  index: index,
                  step: const Duration(milliseconds: 45),
                  maxDelay: const Duration(milliseconds: 320),
                  offset: 12,
                  child: _buildRealMoviePosterCard(movie),
                );
              },
            ),
            ),
          )
        else if (isLoading)
          SizedBox(
            height: 195,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 4,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, __) => ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Shimmer(
                  base: _p.skeleton,
                  highlight: _p.isDark ? const Color(0xFF1E2636) : const Color(0xFFF4F7FC),
                  child: const SizedBox(width: 130, height: 195),
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
              borderRadius: BorderRadius.circular(16),
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

  // Real Movie Poster Card (High Resolution, Clean Border & Subtle Shadow)
  Widget _buildRealMoviePosterCard(CinemanaItem movie) {
    final poster = movie.cardImageUrl;

    return PressScale(
      onTap: () {
        Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(
            builder: (_) => CinemanaDetailScreen(item: movie),
          ),
        );
      },
      child: Container(
        width: 130,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _p.border),
          boxShadow: _p.cardShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Medium-size poster from the disk cache (130x195 is exactly 2:3,
              // so nothing is cropped)
              if (poster.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: movie.imageForWidth(_decodeWidthFor(130).toDouble(), hiRes: preferFullArtwork),
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.high,
                  memCacheWidth: _hiResDecodeWidth(130),
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  imageBuilder: (_, provider) => RevealImage(
                    child: Image(
                      image: provider,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                  placeholder: (_, __) => Shimmer(
                    base: _p.skeleton,
                    highlight: _p.isDark ? const Color(0xFF1E2636) : const Color(0xFFF4F7FC),
                    child: const SizedBox.expand(),
                  ),
                  errorWidget: (_, __, ___) => _buildPosterPlaceholder(),
                )
              else
                _buildPosterPlaceholder(),

              // Gradient Overlay at bottom
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black.withOpacity(0.35),
                        Colors.black.withOpacity(0.92),
                      ],
                      stops: const [0.0, 0.40, 0.70, 1.0],
                    ),
                  ),
                ),
              ),

              // Rating Star Badge at Top Left
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.65),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withOpacity(0.18), width: 0.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star_rounded, color: Color(0xFFFFB800), size: 13),
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

              // Real Movie Title at Bottom (Clean single shadow - NO blur halo)
              Positioned(
                left: 8,
                right: 8,
                bottom: 10,
                child: Text(
                  movie.displayTitle,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    shadows: [
                      Shadow(color: Colors.black87, blurRadius: 3, offset: Offset(0, 1)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPosterPlaceholder() {
    return Container(
      color: _p.skeleton,
      child: Center(child: Icon(Icons.movie_outlined, color: _p.textFaint, size: 36)),
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
                  color: Theme.of(context).brightness == Brightness.dark ? Colors.white : const Color(0xFF0F172A),
                  fontSize: 18,
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
                        Icon(Icons.chevron_left_rounded, size: 18, color: Color(0xFFE50914)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Horizontal List of Large Wide Cards (~270w x 165h)
        if (items.isNotEmpty)
          SizedBox(
            height: 172,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final series = items[index];
                return _buildWideSeriesCard(series);
              },
            ),
          )
        else if (isLoading)
          SizedBox(
            height: 172,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 3,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (_, __) => Container(
                width: 270,
                decoration: BoxDecoration(
                  color: _p.skeleton,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _p.border),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(color: Color(0xFFE50914), strokeWidth: 2),
                  ),
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
              borderRadius: BorderRadius.circular(16),
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
  Widget _buildWideSeriesCard(CinemanaItem series) {
    // Series come with portrait posters only; forcing one into a 260x165
    // box cropped most of it. Show it whole in a 2:3 slot and put the text
    // beside it instead of over it.
    final poster = series.cardImageUrl;
    final seasonNum = int.tryParse(series.season) ?? 0;
    final seasonText = seasonNum > 0 ? 'الموسم $seasonNum' : 'مسلسل';
    final genreText = series.categories.isNotEmpty ? series.categories.first : 'دراما';
    final yearText = series.year.isNotEmpty ? series.year : '2026';
    final rating = series.stars.isNotEmpty ? series.stars : '0.0';

    return GestureDetector(
      onTap: () {
        Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(
            builder: (_) => CinemanaDetailScreen(item: series),
          ),
        );
      },
      child: Container(
        width: 260,
        height: 165,
        decoration: BoxDecoration(
          color: _p.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _p.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            // Poster, whole: 110 x 165 = 2:3
            SizedBox(
              width: 110,
              height: 165,
              child: poster.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: series.imageForWidth(_decodeWidthFor(110).toDouble(), hiRes: preferFullArtwork),
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                      memCacheWidth: _hiResDecodeWidth(110),
                      fadeInDuration: const Duration(milliseconds: 120),
                      fadeOutDuration: const Duration(milliseconds: 60),
                      placeholder: (_, __) => _buildPosterPlaceholder(),
                      errorWidget: (_, __, ___) => _buildPosterPlaceholder(),
                    )
                  : _buildPosterPlaceholder(),
            ),
            // Text panel
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE50914),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            seasonText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const Spacer(),
                        const Icon(Icons.star_rounded, color: Color(0xFFFFB800), size: 13),
                        const SizedBox(width: 2),
                        Text(
                          rating,
                          style: TextStyle(
                            color: _p.text,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      series.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _p.text,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$genreText • $yearText',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _p.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          decoration: const BoxDecoration(
                            color: Color(0xFFE50914),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'شاهد',
                          style: TextStyle(
                            color: _p.text,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
