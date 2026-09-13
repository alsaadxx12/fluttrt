import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../core/constants/app_palette.dart';
import '../../../core/tv/tv_mode.dart';
import '../../../presentation/widgets/reveal.dart';
import '../data/movie_trailer.dart';
import '../data/tmdb_service.dart';
import '../data/trailer_stream_resolver.dart';
import '../tmdb_config.dart';
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

/// Loads the trailers feed one TMDB page at a time and never runs dry: it
/// walks the popular list (hundreds of pages), dropping films without a
/// trailer and repeats already shown.
class TrailerFeedNotifier extends StateNotifier<TrailerFeedState> {
  TrailerFeedNotifier(this._service) : super(const TrailerFeedState()) {
    loadMore();
  }

  final TmdbService _service;
  int _page = 1;
  int _empties = 0;
  final Set<String> _seen = {};

  Future<void> loadMore() async {
    if (state.loading || state.done) return;
    state = state.copyWith(loading: true);
    final page = await _service.feedPage(_page);
    _page++;

    final fresh = <MovieTrailer>[];
    for (final t in page) {
      final id = t.youtubeId;
      if (id == null || !_seen.add(id)) continue;
      fresh.add(t);
    }
    _empties = page.isEmpty ? _empties + 1 : 0;
    // TMDB caps popular paging at 500; stop there or after a few empty pages.
    final done = _page > 500 || _empties >= 3;
    state = state.copyWith(items: [...state.items, ...fresh], loading: false, done: done);
  }
}

final trailerFeedProvider = StateNotifierProvider<TrailerFeedNotifier, TrailerFeedState>(
  (ref) => TrailerFeedNotifier(TmdbService()),
);

/// One trailer's player, held in the pool: its controller and readiness.
class _Pooled {
  final VideoPlayerController controller;
  bool ready = false;
  bool failed = false;
  _Pooled(this.controller);
}

/// "مقاطع وإعلانات": the endless trailers row. Phone only.
///
/// Plays like a short-video feed: the card at the front plays on its own, and
/// as the row is scrolled the newly fronted card takes over — no tapping. A
/// small pool keeps the neighbouring trailers initialised and buffering ahead
/// of time, so moving to the next one starts it at once.
class TrailersShowcase extends ConsumerStatefulWidget {
  const TrailersShowcase({super.key});

  @override
  ConsumerState<TrailersShowcase> createState() => _TrailersShowcaseState();
}

class _TrailersShowcaseState extends ConsumerState<TrailersShowcase> with WidgetsBindingObserver {
  static const double cardW = 360, imageH = 250, rowH = 330, gap = 12, lead = 16;
  static const double itemExtent = cardW + gap;

  /// A phone: not a television, not a desktop.
  bool get _isPhone => (Platform.isAndroid || Platform.isIOS);

  final ScrollController _scroll = ScrollController();

  /// The fronted card that is playing.
  int _activeIndex = 0;

  /// How far into the list we have already precached artwork for.
  int _warmedTo = 0;

  /// Whether the row is on screen, the app is in the foreground, and the user
  /// has not tapped to pause. The active trailer plays only when all hold.
  bool _visible = true;
  bool _foreground = true;
  bool _userPaused = false;
  bool get _shouldPlay => _visible && _foreground && !_userPaused;

  /// The scrollable the row sits inside (the home page), watched so playback
  /// can pause when the row is scrolled out of view.
  ScrollPosition? _ancestorPos;

  /// Initialised players, keyed by video id, for the active card and its
  /// neighbours; the rest are disposed to stay light.
  final Map<String, _Pooled> _pool = {};
  final Set<String> _creating = {};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _attachAncestor());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ancestorPos?.removeListener(_onAncestorScroll);
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    for (final e in _pool.values) {
      e.controller.dispose();
    }
    _pool.clear();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attachAncestor();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    if (fg != _foreground) {
      _foreground = fg;
      _applyPlayback();
    }
  }

  /// Watch the enclosing page's scroll so the row pauses when it leaves view.
  void _attachAncestor() {
    if (!mounted) return;
    final pos = Scrollable.maybeOf(context)?.position;
    if (pos == _ancestorPos) return;
    _ancestorPos?.removeListener(_onAncestorScroll);
    _ancestorPos = pos;
    _ancestorPos?.addListener(_onAncestorScroll);
    _onAncestorScroll();
  }

  void _onAncestorScroll() {
    final visible = _computeVisible();
    if (visible != _visible) {
      _visible = visible;
      _applyPlayback();
      if (mounted) setState(() {});
    }
  }

  /// True when any meaningful part of the row is within the screen.
  bool _computeVisible() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return _visible;
    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = top + box.size.height;
    final screenH = MediaQuery.of(context).size.height;
    // Consider it in view once at least a third of it shows.
    final visiblePx = (bottom.clamp(0.0, screenH)) - (top.clamp(0.0, screenH));
    return visiblePx > box.size.height * 0.33;
  }

  /// Play or pause the active card to match [_shouldPlay].
  void _applyPlayback() {
    final activeId = _idAt(_activeIndex);
    final pooled = activeId == null ? null : _pool[activeId];
    if (pooled == null || !pooled.ready) return;
    if (_shouldPlay) {
      pooled.controller.play();
    } else {
      pooled.controller.pause();
    }
  }

  List<MovieTrailer> get _items => ref.read(trailerFeedProvider).items;

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    // Fetch the next page well before the edge, so it is ready on arrival.
    if (pos.pixels > pos.maxScrollExtent - cardW * 3) {
      ref.read(trailerFeedProvider.notifier).loadMore();
    }
    // Whichever card is centred in the viewport becomes the one that plays.
    final items = _items;
    if (items.isEmpty) return;
    final center = pos.pixels + pos.viewportDimension / 2;
    final idx = ((center - lead - cardW / 2) / itemExtent).round().clamp(0, items.length - 1);
    if (idx != _activeIndex) {
      _activeIndex = idx;
      _userPaused = false; // a freshly fronted card plays on its own
      _syncPool();
      if (mounted) setState(() {});
    }
  }

  /// The video id at [index], or null.
  String? _idAt(int index) {
    final items = _items;
    if (index < 0 || index >= items.length) return null;
    return items[index].youtubeId;
  }

  /// Keep initialised players for the active card and its immediate
  /// neighbours (so the next one is buffered ahead), dispose the rest, and
  /// play the active card while pausing the others.
  void _syncPool() {
    final activeId = _idAt(_activeIndex);
    final keep = <String>{};
    // The active card, the next two (scroll direction), and the previous one.
    for (final k in [_activeIndex, _activeIndex + 1, _activeIndex + 2, _activeIndex - 1]) {
      final id = _idAt(k);
      if (id != null) {
        keep.add(id);
        _ensure(id);
      }
    }
    for (final id in _pool.keys.toList()) {
      if (!keep.contains(id)) {
        _pool.remove(id)!.controller.dispose();
      }
    }
    for (final entry in _pool.entries) {
      final pooled = entry.value;
      if (!pooled.ready) continue;
      if (entry.key == activeId) {
        if (_shouldPlay) {
          pooled.controller.play();
        } else {
          pooled.controller.pause();
        }
      } else {
        pooled.controller
          ..pause()
          ..seekTo(Duration.zero);
      }
    }
  }

  /// If the active card's trailer cannot be played, move on to the next one.
  void _autoSkip(String failedId) {
    if (_idAt(_activeIndex) != failedId) return;
    final items = _items;
    if (_activeIndex + 1 < items.length) {
      _scrollTo(_activeIndex + 1);
    }
  }

  /// Create and initialise a player for [videoId] if not already present.
  Future<void> _ensure(String videoId) async {
    if (_pool.containsKey(videoId) || _creating.contains(videoId)) return;
    _creating.add(videoId);
    try {
      final url = await TrailerStreamResolver.instance.resolve(videoId);
      if (!mounted) return;
      if (url == null) {
        // No playable stream: skip past it if it is the fronted card.
        _autoSkip(videoId);
        return;
      }
      final controller = VideoPlayerController.networkUrl(url);
      final pooled = _Pooled(controller);
      _pool[videoId] = pooled;
      await controller.setLooping(true);
      await controller.initialize();
      pooled.ready = true;
      if (!mounted) {
        _pool.remove(videoId);
        await controller.dispose();
        return;
      }
      // If it became the active card while initialising, start it now.
      if (_idAt(_activeIndex) == videoId && _shouldPlay) controller.play();
      setState(() {});
    } catch (_) {
      final pooled = _pool[videoId];
      if (pooled != null) pooled.failed = true;
      if (mounted) {
        setState(() {});
        _autoSkip(videoId);
      }
    } finally {
      _creating.remove(videoId);
    }
  }

  /// Precache the artwork of items not yet warmed, and resolve their streams.
  void _warm(List<MovieTrailer> items) {
    if (_warmedTo >= items.length) return;
    final next = items.sublist(_warmedTo);
    _warmedTo = items.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      TrailerStreamResolver.instance.prewarm(next.map((t) => t.youtubeId).whereType<String>().take(8));
      for (final t in next.take(8)) {
        if (t.bestImage.isEmpty) continue;
        precacheImage(CachedNetworkImageProvider(t.bestImage), context).ignore();
      }
    });
  }

  void _scrollTo(int index) {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      (index * itemExtent).clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  /// A single tap: on the fronted card, pause or resume it; on another card,
  /// bring it to the front so it starts playing.
  void _tap(int i) {
    if (i == _activeIndex) {
      setState(() => _userPaused = !_userPaused);
      _applyPlayback();
    } else {
      _userPaused = false;
      _scrollTo(i);
    }
  }

  /// Double-tapping a card opens the film: search the library for its title
  /// and go to that title's detail page, or say so when it is not carried.
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
    // Phone only; hidden entirely on TV, desktop, and when TMDB is not set up.
    final isTv = ref.watch(tvModeProvider).valueOrNull ?? false;
    if (!_isPhone || isTv || !TmdbConfig.isConfigured) return const SizedBox.shrink();

    final feed = ref.watch(trailerFeedProvider);
    final p = AppPalette.of(context);

    if (feed.items.isEmpty) {
      if (feed.loading) return _shell(p, child: _loadingRow(p));
      return const SizedBox.shrink();
    }

    _warm(feed.items);
    // Once the first items are in, start the fronted card playing.
    if (_pool.isEmpty && _creating.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncPool();
      });
    }

    final activeId = _idAt(_activeIndex);
    final showTrailingLoader = !feed.done;
    final count = feed.items.length + (showTrailingLoader ? 1 : 0);

    return _shell(
      p,
      child: SizedBox(
        height: rowH,
        child: ListView.separated(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(horizontal: lead),
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: count,
          separatorBuilder: (_, __) => const SizedBox(width: gap),
          itemBuilder: (context, i) {
            if (i >= feed.items.length) {
              return const SizedBox(
                width: 120,
                child: Center(child: CircularProgressIndicator(color: Color(0xFFE50914), strokeWidth: 2.4)),
              );
            }
            final trailer = feed.items[i];
            final isActive = trailer.youtubeId != null && trailer.youtubeId == activeId;
            final pooled = trailer.youtubeId == null ? null : _pool[trailer.youtubeId];
            return _TrailerCard(
              trailer: trailer,
              isActive: isActive,
              isPaused: isActive && _userPaused,
              controller: isActive && (pooled?.ready ?? false) ? pooled!.controller : null,
              onTap: () => _tap(i),
              onOpen: () => _open(trailer),
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

  /// The fronted card that should be playing.
  final bool isActive;

  /// The fronted card, paused by a tap.
  final bool isPaused;

  /// The ready player for this card, when it is the active one; else null.
  final VideoPlayerController? controller;
  final VoidCallback onTap;

  /// Double-tap: open the film.
  final VoidCallback onOpen;

  const _TrailerCard({
    required this.trailer,
    required this.isActive,
    required this.isPaused,
    required this.controller,
    required this.onTap,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    const width = _TrailersShowcaseState.cardW, imageH = _TrailersShowcaseState.imageH;
    final playing = controller != null && controller!.value.isInitialized;

    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onOpen,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: width,
              height: imageH,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: isActive ? const Color(0xFFE50914) : p.border, width: isActive ? 1.6 : 1),
                boxShadow: p.cardShadow,
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Artwork always underneath, so the card is filled at once.
                  CachedNetworkImage(
                    imageUrl: trailer.bestImage,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.high,
                    fadeInDuration: const Duration(milliseconds: 120),
                    placeholder: (_, __) => ColoredBox(color: p.skeleton),
                    errorWidget: (_, __, ___) => CachedNetworkImage(
                      imageUrl: trailer.youtubeFallbackThumb,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                      errorWidget: (_, __, ___) => ColoredBox(
                        color: p.skeleton,
                        child: Icon(Icons.theaters_rounded, color: p.textFaint, size: 40),
                      ),
                    ),
                  ),

                  // The video on top of its poster once it is ready.
                  if (playing)
                    FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox(
                        width: controller!.value.size.width,
                        height: controller!.value.size.height,
                        child: VideoPlayer(controller!),
                      ),
                    ),

                  // A loading bar on the active card while its video buffers.
                  if (isActive && !playing && !isPaused)
                    const Align(
                      alignment: Alignment.bottomCenter,
                      child: LinearProgressIndicator(
                        minHeight: 3,
                        backgroundColor: Colors.white10,
                        valueColor: AlwaysStoppedAnimation(Color(0xFFE50914)),
                      ),
                    ),

                  // A play badge when the fronted card was tapped to pause.
                  if (isPaused)
                    Center(
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
                      ),
                    ),

                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xB3000000)],
                        stops: [0.45, 1.0],
                      ),
                    ),
                  ),
                  if (trailer.rating > 0)
                    PositionedDirectional(
                      top: 8,
                      start: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(8)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.star_rounded, color: Color(0xFFFFB800), size: 13),
                          const SizedBox(width: 3),
                          Text(trailer.rating.toStringAsFixed(1),
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                        ]),
                      ),
                    ),
                  PositionedDirectional(
                    start: 10,
                    end: 10,
                    bottom: 10,
                    child: Text(trailer.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
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
