import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/core/network/image_cache.dart';

import '../../../core/constants/app_palette.dart';
import '../../../core/tv/tv_mode.dart';
import '../../../presentation/widgets/reveal.dart';
import '../data/movie_trailer.dart';
import '../data/tmdb_service.dart';
import '../data/trailer_stream_resolver.dart';
import '../tmdb_config.dart';
import 'inline_trailer_player.dart';
import '../../cinemana/data/models/cinemana_models.dart';
import '../../cinemana/data/services/cinemana_service.dart';
import '../../cinemana/presentation/screens/cinemana_detail_screen.dart';

/// An endless, paged feed of official trailers from TMDB.
class TrailerFeedState {
  final List<MovieTrailer> items;
  final bool loading;
  final bool done;
  const TrailerFeedState({this.items = const [], this.loading = false, this.done = false});

  TrailerFeedState copyWith({List<MovieTrailer>? items, bool? loading, bool? done}) => TrailerFeedState(
        items: items ?? this.items,
        loading: loading ?? this.loading,
        done: done ?? this.done,
      );
}

/// Loads the trailers feed one TMDB page at a time and never runs dry.
class TrailerFeedNotifier extends StateNotifier<TrailerFeedState> {
  TrailerFeedNotifier(this._service) : super(const TrailerFeedState()) {
    _init();
  }

  /// Make sure the TMDB token is loaded (from the bundled asset when the build
  /// did not compile one in) before the first fetch, so the section works even
  /// if startup did not preload it.
  Future<void> _init() async {
    await TmdbConfig.ensureLoaded();
    await loadMore();
  }

  final TmdbService _service;
  int _page = 1;
  int _empties = 0;
  final Set<String> _seen = {};

  Future<void> loadMore() async {
    if (state.loading || state.done) return;
    state = state.copyWith(loading: true);

    // Walk forward until this call adds at least one trailer, so a page that
    // holds no trailers never leaves the section empty (and therefore hidden).
    final gathered = <MovieTrailer>[...state.items];
    final before = gathered.length;
    var done = false;
    for (var guard = 0; guard < 6; guard++) {
      final page = await _service.feedPage(_page);
      _page++;
      for (final t in page) {
        final id = t.youtubeId;
        if (id == null || !_seen.add(id)) continue;
        gathered.add(t);
      }
      _empties = page.isEmpty ? _empties + 1 : 0;
      if (_page > 500 || _empties >= 3) {
        done = true;
        break;
      }
      if (gathered.length > before) break; // got at least one new trailer
    }
    state = state.copyWith(items: gathered, loading: false, done: done);
  }
}

final trailerFeedProvider = StateNotifierProvider<TrailerFeedNotifier, TrailerFeedState>(
  (ref) => TrailerFeedNotifier(TmdbService()),
);

/// "مقاطع وإعلانات": the endless trailers row. Phone only.
///
/// Plays like a short-video feed: the card at the front plays on its own, and
/// as the row is scrolled the newly fronted card takes over — no tapping.
/// Playback stops when the row leaves the screen, the app goes to the
/// background, or the card is tapped; a card whose trailer will not play is
/// skipped automatically.
class TrailersShowcase extends ConsumerStatefulWidget {
  const TrailersShowcase({super.key});

  @override
  ConsumerState<TrailersShowcase> createState() => _TrailersShowcaseState();
}

class _TrailersShowcaseState extends ConsumerState<TrailersShowcase> with WidgetsBindingObserver {
  static const double cardW = 360, imageH = 250, rowH = 330, gap = 12, lead = 16;

  bool get _isPhone => (Platform.isAndroid || Platform.isIOS);

  late final PageController _pageController = PageController(viewportFraction: 0.90);

  int _activeIndex = 0;
  int _warmedTo = 0;

  // Unknown until the ancestor scroll attach measures the row; false keeps
  // the first screen from paying for a trailer that may be off-screen.
  bool _visible = false;
  bool _foreground = true;
  bool _userPaused = false;

  // The route holding the row is on top (TickerMode): a page pushed over the
  // home must not keep the trailer running underneath it.
  bool _routeActive = true;

  // The row has been on screen for 1500 ms. Only then does it play or
  // prewarm, so a pass-by scroll or the first screen never pays for it.
  bool _settled = false;
  Timer? _settleTimer;

  // Once the row has settled the fronted card's player is kept mounted and
  // merely paused when playback should stop, so coming back never rebuilds it.
  bool _playerArmed = false;
  bool _hadItems = false;

  // True while the home page is under the finger or still gliding. A video
  // decoding and compositing its texture through a scroll is the most
  // expensive thing on the page, and it is the one thing on it nobody is
  // looking at while the page is moving, so it holds until the page stops.
  bool _ancestorScrolling = false;

  bool get _onScreen => _visible && _routeActive;
  bool get _shouldPlay => _visible &&
      _routeActive &&
      _settled &&
      _foreground &&
      !_userPaused &&
      !_ancestorScrolling;

  ScrollPosition? _ancestorPos;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _attachAncestor());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settleTimer?.cancel();
    _ancestorPos?.isScrollingNotifier.removeListener(_onScrollingChanged);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A rebuild is already under way here, so the field is set directly.
    final active = TickerMode.of(context);
    if (active != _routeActive) {
      _routeActive = active;
      _updateSettle();
    }
    _attachAncestor();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only a real background counts. `inactive` (a system sheet, the app
    // switcher opening) must not tear the player down.
    final fg = state != AppLifecycleState.paused &&
        state != AppLifecycleState.hidden &&
        state != AppLifecycleState.detached;
    if (fg != _foreground && mounted) setState(() => _foreground = fg);
  }

  void _attachAncestor() {
    if (!mounted) return;
    final pos = Scrollable.maybeOf(context)?.position;
    if (pos != _ancestorPos) {
      _ancestorPos?.isScrollingNotifier.removeListener(_onScrollingChanged);
      _ancestorPos = pos;
      _ancestorPos?.isScrollingNotifier.addListener(_onScrollingChanged);
      // A new position may already be still or already moving; either way the
      // flag has to describe this one, not the one we just let go of.
      _ancestorScrolling = pos?.isScrollingNotifier.value ?? false;
    }
    _checkVisibility();
  }

  void _onScrollingChanged() {
    if (!mounted) return;
    final scrolling = _ancestorPos?.isScrollingNotifier.value ?? false;
    if (scrolling != _ancestorScrolling) {
      // Pausing is a setState, but only on the two edges of a scroll, not
      // per frame: the row holds its player and merely stops the picture.
      setState(() => _ancestorScrolling = scrolling);
    }
    // Check visibility ONLY when user finishes scrolling - never during active gestures!
    if (!scrolling) {
      _checkVisibility();
    }
  }

  void _checkVisibility() {
    if (!mounted) return;
    final visible = _computeVisible();
    if (visible != _visible) {
      setState(() {
        _visible = visible;
        _updateSettle();
      });
    }
  }

  /// Starts the settle timer while the row is on screen; the moment it is
  /// not, the pending timer is cancelled and the settled state cleared.
  /// Callers are inside a setState or a pending rebuild, so the fields are
  /// set directly here.
  void _updateSettle() {
    if (_onScreen) {
      if (_settled || _settleTimer != null) return;
      _settleTimer = Timer(const Duration(milliseconds: 1500), () {
        _settleTimer = null;
        if (!mounted || !_onScreen) return;
        setState(() {
          _settled = true;
          _playerArmed = true;
        });
        _prewarmAround(_activeIndex);
      });
    } else {
      _settleTimer?.cancel();
      _settleTimer = null;
      _settled = false;
    }
  }

  bool _computeVisible() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return _visible;
    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = top + box.size.height;
    final screenH = MediaQuery.of(context).size.height;
    final shown = bottom.clamp(0.0, screenH) - top.clamp(0.0, screenH);
    return shown > box.size.height * 0.33;
  }

  List<MovieTrailer> get _items => ref.read(trailerFeedProvider).items;

  void _onPageChanged(int idx) {
    if (idx != _activeIndex) {
      setState(() {
        _activeIndex = idx;
        _userPaused = false; // a freshly fronted card plays on its own
      });
      if (_settled) _prewarmAround(idx);
      final items = _items;
      if (idx >= items.length - 2) {
        ref.read(trailerFeedProvider.notifier).loadMore();
      }
    }
  }

  void _onVideoEnded(int index) {
    if (!mounted || index != _activeIndex) return;
    final next = index + 1;
    final items = _items;
    if (next < items.length) {
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  String? _idAt(int index) {
    final items = _items;
    if (index < 0 || index >= items.length) return null;
    return items[index].youtubeId;
  }

  /// Resolve stream URLs and precache artwork for the active card and the next
  /// couple, so switching to them is fast.
  void _prewarmAround(int active) {
    final items = _items;
    if (items.isEmpty) return;
    final ids = <String>[];
    for (var k = active; k <= active + 2 && k < items.length; k++) {
      final id = items[k].youtubeId;
      if (id != null) ids.add(id);
    }
    TrailerStreamResolver.instance.prewarm(ids);
  }

  /// Precache artwork for the next few items not yet warmed (three, so the
  /// first screen's own pictures are never queued behind trailer stills).
  void _warmImages(List<MovieTrailer> items) {
    if (_warmedTo >= items.length) return;
    final next = items.sublist(_warmedTo);
    _warmedTo = items.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cacheW = (cardW * MediaQuery.of(context).devicePixelRatio).round();
      for (final t in next.take(3)) {
        if (t.bestImage.isEmpty) continue;
        precacheImage(
          ResizeImage(CachedNetworkImageProvider(t.bestImage, cacheManager: appImageCache), width: cacheW),
          context,
        ).ignore();
      }
    });
  }

  void _scrollTo(int index) {
    if (!_pageController.hasClients) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeInOutCubic,
    );
  }

  /// A single tap: pause/resume the fronted card, or bring another to front.
  void _tap(int i) {
    if (i == _activeIndex) {
      setState(() => _userPaused = !_userPaused);
    } else {
      _userPaused = false;
      _scrollTo(i);
    }
  }

  /// The fronted trailer could not be played: move on to the next one. A
  /// failure reported for a card that is no longer fronted is ignored, so it
  /// never skips the card the user has since moved to.
  void _skipFailed(String? failedId) {
    if (failedId == null || _idAt(_activeIndex) != failedId) return;
    final items = _items;
    if (_activeIndex + 1 < items.length) _scrollTo(_activeIndex + 1);
  }

  /// Double-tap opens the film: search the library for its title and open it.
  Future<void> _open(MovieTrailer t) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final nav = Navigator.of(context);
    messenger?.showSnackBar(
      const SnackBar(content: Text('جارٍ فتح الفيلم…'), duration: Duration(milliseconds: 900)),
    );
    List<CinemanaItem> results = const [];
    try {
      results = await CinemanaService().search(t.title);
    } catch (_) {}
    if (!mounted) return;
    if (results.isEmpty) {
      messenger?.showSnackBar(const SnackBar(content: Text('هذا الفيلم غير متوفر في المكتبة')));
      return;
    }
    nav.push(MaterialPageRoute(builder: (_) => CinemanaDetailScreen(item: results.first)));
  }

  @override
  Widget build(BuildContext context) {
    final isTv = ref.watch(tvModeProvider).valueOrNull ?? false;
    // Phone only, and never on a television. The token is ensured by the feed
    // notifier, so a missing token simply yields an empty feed (hidden below)
    // rather than hiding the section before the token finishes loading.
    if (!_isPhone || isTv) return const SizedBox.shrink();

    final feed = ref.watch(trailerFeedProvider);
    final p = AppPalette.of(context);

    if (feed.items.isEmpty) {
      if (feed.loading) return _shell(p, child: _loadingRow(p));
      return const SizedBox.shrink();
    }

    _warmImages(feed.items);
    if (!_hadItems) {
      // The row has just gained its full size: measure its visibility once
      // it is laid out, since no scroll may follow to do it.
      _hadItems = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _checkVisibility();
      });
    }
    // Warm the first cards once the row has settled, so the opening trailer
    // starts quickly without competing with the first screen.
    if (_activeIndex == 0 && _settled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _prewarmAround(0);
      });
    }

    final activeId = _idAt(_activeIndex);
    final showTrailingLoader = !feed.done;
    final count = feed.items.length + (showTrailingLoader ? 1 : 0);

    return _shell(
      p,
      child: SizedBox(
        height: rowH,
        child: PageView.builder(
          controller: _pageController,
          physics: const PageScrollPhysics(parent: ClampingScrollPhysics()),
          onPageChanged: _onPageChanged,
          itemCount: count,
          itemBuilder: (context, i) {
            if (i >= feed.items.length) {
              return const Center(
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(color: Color(0xFFE50914), strokeWidth: 2.4),
                ),
              );
            }
            final trailer = feed.items[i];
            final isActive = trailer.youtubeId != null && trailer.youtubeId == activeId;
            return RepaintBoundary(
              child: _TrailerCard(
                trailer: trailer,
                isActive: isActive,
                showVideo: isActive && _playerArmed,
                play: isActive && _shouldPlay,
                isPaused: isActive && _userPaused,
                onTap: () => _tap(i),
                onOpen: () => _open(trailer),
                onFailed: () => _skipFailed(trailer.youtubeId),
                onEnded: () => _onVideoEnded(i),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _shell(AppPalette p, {required Widget child}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
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
                Text('مقاطع وإعلانات',
                    style: TextStyle(color: p.text, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
                const SizedBox(width: 8),
                Icon(Icons.theaters_rounded, size: 17, color: p.textFaint),
              ],
            ),
          ),
          child,
        ],
      );

  Widget _loadingRow(AppPalette p) => SizedBox(
        height: rowH,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: lead),
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 3,
          separatorBuilder: (_, __) => const SizedBox(width: gap),
          itemBuilder: (_, __) => ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Shimmer(
              base: p.skeleton,
              highlight: p.isDark ? const Color(0xFF1E2636) : const Color(0xFFF4F7FC),
              child: const SizedBox(width: cardW, height: imageH),
            ),
          ),
        ),
      );
}

class _TrailerCard extends StatelessWidget {
  final MovieTrailer trailer;
  final bool isActive;

  /// Keep the video mounted on this (fronted) card.
  final bool showVideo;

  /// Play the mounted video; false pauses it in place rather than tearing
  /// it down, so it resumes at once.
  final bool play;

  /// Fronted card, paused by a tap.
  final bool isPaused;
  final VoidCallback onTap;
  final VoidCallback onOpen;
  final VoidCallback onFailed;
  final VoidCallback? onEnded;

  const _TrailerCard({
    required this.trailer,
    required this.isActive,
    required this.showVideo,
    required this.play,
    required this.isPaused,
    required this.onTap,
    required this.onOpen,
    required this.onFailed,
    this.onEnded,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    const imageH = _TrailersShowcaseState.imageH;
    final cacheW = (_TrailersShowcaseState.cardW * MediaQuery.of(context).devicePixelRatio).round();
    final mountVideo = showVideo && trailer.youtubeId != null;

    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onOpen,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              height: imageH,
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.all(Radius.circular(18)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Artwork always underneath, so the card is filled at once.
                  CachedNetworkImage(
                    imageUrl: trailer.bestImage,
                    cacheManager: appImageCache,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                    memCacheWidth: cacheW,
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                    placeholderFadeInDuration: Duration.zero,
                    useOldImageOnUrlChange: true,
                    placeholder: (_, __) => ColoredBox(color: p.skeleton),
                    // The TMDB still failed: fall back to YouTube's own thumb
                    // before giving up on a picture.
                    errorWidget: (_, __, ___) => CachedNetworkImage(
                      imageUrl: trailer.youtubeFallbackThumb,
                      cacheManager: appImageCache,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                      memCacheWidth: cacheW,
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      placeholderFadeInDuration: Duration.zero,
                      useOldImageOnUrlChange: true,
                      placeholder: (_, __) => ColoredBox(color: p.skeleton),
                      errorWidget: (_, __, ___) => ColoredBox(
                        color: p.skeleton,
                        child: Icon(Icons.theaters_rounded, color: p.textFaint, size: 40),
                      ),
                    ),
                  ),

                  // The video, mounted for the fronted card and kept there:
                  // it is paused, not unmounted, when it should not play.
                  if (mountVideo)
                    InlineTrailerPlayer(
                      key: ValueKey(trailer.youtubeId),
                      videoId: trailer.youtubeId!,
                      playing: play,
                      onFailed: onFailed,
                      onEnded: onEnded,
                    ),

                  // A play badge when the fronted card is paused by a tap.
                  if (isPaused)
                    Center(
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), shape: BoxShape.circle),
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // The title, the rating and the scrim that carried them used to
            // sit on the picture. Nothing is painted over the trailer now -
            // it is the whole card - and the title reads on the page below it.
            Text(trailer.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.text, fontSize: 14.5, fontWeight: FontWeight.w900)),
            const SizedBox(height: 3),
            Row(
              children: [
                if (trailer.year != null)
                  Text(trailer.year!, style: TextStyle(color: p.textFaint, fontSize: 11.5, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Text('إعلان رسمي', style: TextStyle(color: p.textMuted, fontSize: 11.5, fontWeight: FontWeight.w700)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
