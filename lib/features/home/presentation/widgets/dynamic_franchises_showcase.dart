import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_palette.dart';
import '../../../cinemana/data/cinemana_franchises.dart';
import '../../../cinemana/data/dynamic_franchises.dart';
import 'franchise_showcase.dart';

/// An endless home row of franchises discovered live from Cinemana — every
/// anime series, or every film that has other parts — opening with the
/// curated entries and then never running out. Same deck-style carousel and
/// poster-fan cards as the curated row.
class DynamicFranchisesShowcase extends ConsumerWidget {
  final FranchiseSection section;
  const DynamicFranchisesShowcase({super.key, required this.section});

  static const _titles = {
    FranchiseSection.films: 'سلاسل الأفلام',
    FranchiseSection.series: 'سلاسل المسلسلات',
    FranchiseSection.anime: 'سلاسل الأنمي',
  };
  static const _icons = {
    FranchiseSection.films: Icons.local_movies_rounded,
    FranchiseSection.series: Icons.live_tv_rounded,
    FranchiseSection.anime: Icons.auto_awesome_rounded,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final feed = ref.watch(franchiseFeedProvider(section));
    if (feed.items.isEmpty && feed.done) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(_icons[section], color: const Color(0xFFE50914), size: 22),
              const SizedBox(width: 8),
              Text(
                _titles[section]!,
                style: TextStyle(color: p.text, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.3),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ColoredBox(
          color: p.bg,
          child: SizedBox(
            height: 315,
            child: feed.items.isEmpty
                ? const _LoadingDeck()
                : _DynCarousel(section: section, items: feed.items, done: feed.done),
          ),
        ),
      ],
    );
  }
}

/// Three placeholder cards while the first franchises resolve.
class _LoadingDeck extends StatelessWidget {
  const _LoadingDeck();

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 3,
      separatorBuilder: (_, __) => const SizedBox(width: 18),
      itemBuilder: (_, __) => Container(
        width: _DynCard.width,
        decoration: BoxDecoration(
          color: p.bg,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Column(children: [Expanded(child: PosterFanPlaceholder())]),
      ),
    );
  }
}

/// Centre-focused deck: the middle card at full size, neighbours shrunk and
/// dimmed. Asks the feed for more as the last cards come into view.
class _DynCarousel extends ConsumerStatefulWidget {
  final FranchiseSection section;
  final List<DynamicFranchise> items;
  final bool done;
  const _DynCarousel({required this.section, required this.items, required this.done});

  @override
  ConsumerState<_DynCarousel> createState() => _DynCarouselState();
}

class _DynCarouselState extends ConsumerState<_DynCarousel> {
  PageController? _controller;
  double _fraction = 0;
  bool _kicked = false;
  ScrollPosition? _ancestorPos;
  bool _wasVisible = false;

  int get _middleIndex =>
      widget.items.isNotEmpty ? widget.items.length ~/ 2 : 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attachAncestor();
  }

  void _attachAncestor() {
    final pos = Scrollable.maybeOf(context)?.position;
    if (pos != _ancestorPos) {
      _ancestorPos?.isScrollingNotifier.removeListener(_onScrollChanged);
      _ancestorPos = pos;
      _ancestorPos?.isScrollingNotifier.addListener(_onScrollChanged);
    }
  }

  void _onScrollChanged() {
    if (!mounted || _ancestorPos == null) return;
    if (!_ancestorPos!.isScrollingNotifier.value) {
      _checkVisibility();
      // The page has come to rest: now is the time to fetch, if the deck has
      // run its cards out.
      _maybeLoadMore(_currentIndex);
    }
  }

  void _checkVisibility() {
    if (!mounted) return;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    final ancestor = Scrollable.maybeOf(context)?.context.findRenderObject();
    if (ancestor is! RenderBox || !ancestor.hasSize) return;

    final localTop =
        renderObject.localToGlobal(Offset.zero, ancestor: ancestor).dy;
    final localBottom = localTop + renderObject.size.height;
    final viewH = ancestor.size.height;
    final isVis = localBottom > 0 && localTop < viewH;

    if (!_wasVisible && isVis) {
      _resetToMiddle(animate: false);
    }
    _wasVisible = isVis;
  }

  void _resetToMiddle({bool animate = true}) {
    if (!mounted || _controller == null || !_controller!.hasClients) return;
    if (widget.items.isEmpty) return;
    final middle = _middleIndex;
    if (_controller!.page?.round() == middle) return;
    if (animate) {
      _controller!.animateToPage(
        middle,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    } else {
      _controller!.jumpToPage(middle);
    }
  }

  @override
  void dispose() {
    _ancestorPos?.isScrollingNotifier.removeListener(_onScrollChanged);
    _controller?.dispose();
    super.dispose();
  }

  /// Ask the feed for more franchises, but never while the page is moving.
  ///
  /// Scanning for a franchise is expensive - every candidate title costs a
  /// search and a parse, and a page of them costs dozens - and it used to be
  /// kicked off from `itemBuilder`, which runs on every frame the trailing
  /// loader card is on screen. So the scan ran right through the scroll it
  /// was stuttering. It waits for the page to come to rest instead.
  void _maybeLoadMore(int index) {
    if (widget.done || index < widget.items.length - 3) return;
    if (_ancestorPos?.isScrollingNotifier.value ?? false) return;
    ref.read(franchiseFeedProvider(widget.section).notifier).loadMore();
  }

  /// The page the deck is showing, for deciding whether more are needed.
  int get _currentIndex =>
      _controller?.hasClients == true ? (_controller!.page ?? 0).round() : _middleIndex;

  @override
  Widget build(BuildContext context) {
    final count = widget.items.length + (widget.done ? 0 : 1);
    return LayoutBuilder(
      builder: (context, box) {
        final fraction = ((_DynCard.width + 18) / box.maxWidth).clamp(0.1, 1.0);
        final defaultInitial = _middleIndex;
        if (_controller == null || (fraction - _fraction).abs() > 0.001) {
          final page = _controller?.hasClients == true
              ? (_controller!.page ?? defaultInitial.toDouble()).round()
              : defaultInitial;
          _controller?.dispose();
          _controller = PageController(viewportFraction: fraction, initialPage: page);
          _fraction = fraction;
        }
        final controller = _controller!;
        return PageView.builder(
          controller: controller,
          physics: const PageScrollPhysics(parent: ClampingScrollPhysics()),
          padEnds: true,
          clipBehavior: Clip.none,
          itemCount: count,
          onPageChanged: _maybeLoadMore,
          itemBuilder: (context, i) => AnimatedBuilder(
            animation: controller,
            builder: (context, child) {
              double page = controller.initialPage.toDouble();
              if (controller.hasClients && controller.position.haveDimensions) {
                page = controller.page ?? page;
              } else if (!_kicked) {
                _kicked = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() {});
                });
              }
              final d = (page - i).abs().clamp(0.0, 1.0);
              final t = Curves.easeOut.transform(1 - d);
              final scale = 0.88 + 0.12 * t;
              final isCurrent = d < 0.4;
              final Widget card = i >= widget.items.length
                  ? const _LoaderCard()
                  : _DynCard(
                      section: widget.section,
                      franchise: widget.items[i],
                      isActive: isCurrent,
                      onReturned: () => _resetToMiddle(animate: true),
                    );
              return Center(
                child: Transform.translate(
                  offset: Offset(0, 10 * (1 - t)),
                  child: Transform.scale(
                    scale: scale,
                    child: Stack(
                      fit: StackFit.passthrough,
                      children: [
                        SizedBox(width: _DynCard.width, child: card),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.26 * (1 - t)),
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// The trailing card while the next page of franchises loads.
class _LoaderCard extends StatelessWidget {
  const _LoaderCard();

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Center(
        child: CircularProgressIndicator(color: Color(0xFFE50914), strokeWidth: 2.4),
      ),
    );
  }
}

class _DynCard extends ConsumerStatefulWidget {
  final FranchiseSection section;
  final DynamicFranchise franchise;
  final bool isActive;
  final VoidCallback? onReturned;
  const _DynCard({
    required this.section,
    required this.franchise,
    this.isActive = false,
    this.onReturned,
  });

  static const width = 252.0;

  @override
  ConsumerState<_DynCard> createState() => _DynCardState();
}

class _DynCardState extends ConsumerState<_DynCard> {
  @override
  void initState() {
    super.initState();
    _ensureParts();
  }

  @override
  void didUpdateWidget(covariant _DynCard old) {
    super.didUpdateWidget(old);
    if (old.franchise.id != widget.franchise.id) _ensureParts();
  }

  /// An anime card learns its seasons and sequels the first time it shows.
  void _ensureParts() {
    if (widget.franchise.partsResolved) return;
    final id = widget.franchise.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(franchiseFeedProvider(widget.section).notifier).resolveParts(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final f = widget.franchise;
    final parts = f.parts;
    final label = f.partsResolved
        ? FilmFranchise.countLabel(parts)
        : (f.lead.isSeries ? 'مسلسل • جارٍ جلب الأجزاء…' : 'جارٍ جلب الأجزاء…');

    return FranchisePressable(
      onTap: () async {
        await Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(builder: (_) => DynamicFranchiseScreen(section: widget.section, franchise: f)),
        );
        widget.onReturned?.call();
      },
      child: Container(
        width: _DynCard.width,
        // The page's own colour, and no edge at all - not the hairline the
        // cards used to carry, nor the red ring that marked the one in hand.
        // The deck already says which card that is: it is the big one in the
        // middle, and its neighbours are shrunk and shaded.
        decoration: BoxDecoration(
          color: p.bg,
          borderRadius: BorderRadius.circular(18),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              children: [
                Expanded(child: PosterFan(films: parts)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              f.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: p.text, fontSize: 16.5, fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: p.textMuted, fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE50914),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFE50914).withOpacity(0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// All parts of one live franchise, in order, numbered. Reads the live entry
/// so an anime whose seasons resolved after the card was tapped still fills.
class DynamicFranchiseScreen extends ConsumerWidget {
  final FranchiseSection section;
  final DynamicFranchise franchise;
  const DynamicFranchiseScreen({super.key, required this.section, required this.franchise});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final feed = ref.watch(franchiseFeedProvider(section));
    final live = feed.items.where((f) => f.id == franchise.id).cast<DynamicFranchise?>().firstOrNull ?? franchise;
    if (!live.partsResolved) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(franchiseFeedProvider(section).notifier).resolveParts(live.id);
      });
    }
    final films = live.parts;
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.isDark ? const Color(0xFF0B0F19) : Colors.white,
        foregroundColor: p.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('سلسلة ${live.name}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
            Text(
              live.partsResolved ? '${FilmFranchise.countLabel(films)} · الأحدث أولاً' : 'جارٍ جلب الأجزاء…',
              style: TextStyle(fontSize: 11.5, color: p.textMuted, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final count = (constraints.maxWidth / 175).floor().clamp(3, 7);
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: count,
              mainAxisSpacing: 14,
              crossAxisSpacing: 12,
              childAspectRatio: 0.67,
            ),
            itemCount: films.length,
            itemBuilder: (context, i) => FranchiseFilmTile(film: films[i], number: films.length - i),
          );
        },
      ),
    );
  }
}
