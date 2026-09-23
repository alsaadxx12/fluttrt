import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/core/network/image_cache.dart';

import '../../../../core/constants/app_palette.dart';
import '../../../cinemana/data/cinemana_franchises.dart';
import '../../../cinemana/data/dynamic_franchises.dart';
import '../../../cinemana/data/models/cinemana_models.dart';
import '../../../cinemana/presentation/providers/cinemana_provider.dart';
import '../../../cinemana/presentation/screens/cinemana_detail_screen.dart';

/// A home row of franchises - the film series (Harry Potter, Spider-Man…),
/// the TV-series universes, or the anime franchises - each a tall card with
/// its posters fanned out.
class FranchisesShowcase extends StatelessWidget {
  final FranchiseSection section;

  const FranchisesShowcase({super.key, this.section = FranchiseSection.films});

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
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final franchises = FilmFranchise.inSection(section);
    if (franchises.isEmpty) return const SizedBox.shrink();
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
                style: TextStyle(
                    color: p.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Page-coloured strip (the gaps between cards are just the page).
        ColoredBox(
          color: p.bg,
          child: SizedBox(
              height: 250, child: _FranchiseCarousel(franchises: franchises)),
        ),
      ],
    );
  }
}

/// A centre-focused carousel: cards snap to the middle of the screen, the
/// one in the middle stands at full size and the others shrink and dim a
/// little as they slide away, so browsing feels like flipping through a deck.
class _FranchiseCarousel extends StatefulWidget {
  final List<FilmFranchise> franchises;
  const _FranchiseCarousel({required this.franchises});

  @override
  State<_FranchiseCarousel> createState() => _FranchiseCarouselState();
}

class _FranchiseCarouselState extends State<_FranchiseCarousel> {
  PageController? _controller;
  double _fraction = 0;
  bool _kicked = false;
  ScrollPosition? _ancestorPos;
  bool _wasVisible = false;

  int get _middleIndex =>
      widget.franchises.isNotEmpty ? widget.franchises.length ~/ 2 : 0;

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
    if (widget.franchises.isEmpty) return;
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        // One card plus its gap per page, so the gaps are even.
        final fraction =
            ((_FranchiseCard.width + 18) / box.maxWidth).clamp(0.1, 1.0);
        final defaultInitial = _middleIndex;
        if (_controller == null || (fraction - _fraction).abs() > 0.001) {
          final page = _controller?.hasClients == true
              ? (_controller!.page ?? defaultInitial.toDouble()).round()
              : defaultInitial;
          _controller?.dispose();
          _controller =
              PageController(viewportFraction: fraction, initialPage: page);
          _fraction = fraction;
        }
        final controller = _controller!;
        return PageView.builder(
          controller: controller,
          physics: const PageScrollPhysics(parent: ClampingScrollPhysics()),
          // Always centre the active card in the middle of the screen
          padEnds: true,
          clipBehavior: Clip.none,
          itemCount: widget.franchises.length,
          itemBuilder: (context, i) => AnimatedBuilder(
            animation: controller,
            builder: (context, child) {
              double page = controller.initialPage.toDouble();
              if (controller.hasClients && controller.position.haveDimensions) {
                page = controller.page ?? page;
              } else if (!_kicked) {
                // First frame has no scroll metrics yet; rebuild once they exist
                // so the side cards start out already shrunk.
                _kicked = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() {});
                });
              }
              final d = (page - i).abs().clamp(0.0, 1.0);
              final t = Curves.easeOut.transform(1 - d);
              final scale = 0.88 + 0.12 * t;
              final isCurrent = d < 0.4;
              return Center(
                child: Transform.translate(
                  offset: Offset(0, 10 * (1 - t)),
                  child: Transform.scale(
                    scale: scale,
                    child: Stack(
                      fit: StackFit.passthrough,
                      children: [
                        SizedBox(
                          width: _FranchiseCard.width,
                          child: _FranchiseCard(
                            franchise: widget.franchises[i],
                            isActive: isCurrent,
                            onReturned: () => _resetToMiddle(animate: true),
                          ),
                        ),
                        // Side cards sit a little in shade.
                        Positioned.fill(
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.26 * (1 - t)),
                                borderRadius: BorderRadius.circular(6),
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

class _FranchiseCard extends ConsumerWidget {
  final FilmFranchise franchise;
  final bool isActive;
  final VoidCallback? onReturned;
  const _FranchiseCard({
    required this.franchise,
    this.isActive = false,
    this.onReturned,
  });

  static const width = 200.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final async = ref.watch(franchiseFilmsProvider(franchise.id));
    final films = async.valueOrNull ?? const <CinemanaItem>[];
    // Nothing of this series on Cinemana: no card.
    if (async.hasValue && films.length < DynamicFranchise.minParts)
      return const SizedBox.shrink();

    return FranchisePressable(
      onTap: films.isEmpty
          ? null
          : () async {
              await Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(
                    builder: (_) => FranchiseScreen(franchise: franchise)),
              );
              onReturned?.call();
            },
      child: Container(
        width: width,
        // The page's own colour, and no edge at all - neither the hairline
        // the cards carried nor the red ring on the one in hand. Size and
        // shade already say which card that is.
        decoration: BoxDecoration(
          color: p.bg,
          borderRadius: BorderRadius.circular(6),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              children: [
                Expanded(
                  child: films.isEmpty
                      ? const PosterFanPlaceholder()
                      : PosterFan(films: films),
                ),
                // Nothing under the fan: the posters are the card.
                const SizedBox(height: 8),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Three posters fanned out: first and last of the series behind, the
/// middle one in front - big, so the artwork carries the card.
class PosterFan extends StatelessWidget {
  final List<CinemanaItem> films;
  const PosterFan({super.key, required this.films});

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    // The list arrives newest first, so the latest release is its head: that
    // is the front poster, and the two behind it are earlier films.
    final latest = films.first;
    final behind = <CinemanaItem>{films.last, films[films.length ~/ 2]}
        .where((f) => f.id != latest.id)
        .toList();
    final picks = <CinemanaItem>[latest, ...behind];
    const w = 134.0, h = 201.0;
    Widget poster(CinemanaItem f, double angle, double dx, double dy,
            double scale, double shade) =>
        Transform.translate(
          offset: Offset(dx, dy),
          child: Transform.rotate(
            angle: angle,
            child: Transform.scale(
              scale: scale,
              child: Container(
                width: w,
                height: h,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: f.cardImageUrl,
                      cacheManager: appImageCache,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                      memCacheWidth: (w * dpr).clamp(180, 480).round(),
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      placeholderFadeInDuration: Duration.zero,
                      useOldImageOnUrlChange: true,
                      placeholder: (_, __) => Container(
                        color: const Color(0xFF161E2E),
                        child: const Center(
                          child: Icon(Icons.movie_filter_rounded,
                              color: Colors.white24, size: 24),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: const Color(0xFF161E2E),
                        child: const Center(
                          child: Icon(Icons.movie_filter_rounded,
                              color: Colors.white24, size: 24),
                        ),
                      ),
                    ),
                    // The two behind sit a little in shadow.
                    if (shade > 0)
                      ColoredBox(color: Colors.black.withOpacity(shade)),
                  ],
                ),
              ),
            ),
          ),
        );

    final three = picks.length > 2;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (three) poster(picks[2], 10 * math.pi / 180, 56, 8, 0.88, 0.22),
          if (picks.length > 1)
            poster(picks[1], -10 * math.pi / 180, -56, 8, 0.88, 0.22),
          poster(picks[0], 0, 0, 0, 1.0, 0),
        ],
      ),
    );
  }
}

/// Instant visual placeholder for the fan cards while images load
class PosterFanPlaceholder extends StatelessWidget {
  const PosterFanPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    const w = 134.0, h = 201.0;
    Widget slot(double angle, double dx, double dy, double scale) =>
        Transform.translate(
          offset: Offset(dx, dy),
          child: Transform.rotate(
            angle: angle,
            child: Transform.scale(
              scale: scale,
              child: Container(
                width: w,
                height: h,
                decoration: BoxDecoration(
                  color: const Color(0xFF12161F),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: Icon(Icons.movie_filter_rounded,
                      color: Colors.white24, size: 28),
                ),
              ),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          slot(10 * math.pi / 180, 56, 8, 0.88),
          slot(-10 * math.pi / 180, -56, 8, 0.88),
          slot(0, 0, 0, 1.0),
        ],
      ),
    );
  }
}

/// Shrinks a little under the finger.
class FranchisePressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const FranchisePressable(
      {super.key, required this.child, required this.onTap});

  @override
  State<FranchisePressable> createState() => _PressableState();
}

class _PressableState extends State<FranchisePressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.96 : 1,
        duration: const Duration(milliseconds: 120),
        child: widget.child,
      ),
    );
  }
}

/// All films of one series, in order, numbered.
class FranchiseScreen extends ConsumerWidget {
  final FilmFranchise franchise;
  const FranchiseScreen({super.key, required this.franchise});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final async = ref.watch(franchiseFilmsProvider(franchise.id));
    final films = async.valueOrNull ?? const <CinemanaItem>[];
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
            Text('سلسلة ${franchise.name}',
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
            if (films.isNotEmpty)
              Text('${FilmFranchise.countLabel(films)} · الأحدث أولاً',
                  style: TextStyle(
                      fontSize: 11.5,
                      color: p.textMuted,
                      fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      body: async.isLoading && films.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFE50914)))
          : films.isEmpty
              ? Center(
                  child: Text('تعذّر تحميل السلسلة',
                      style: TextStyle(color: p.textMuted)))
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    // Responsive column count: smaller, elegant cards on all screen sizes!
                    // Desktop (>1200px): 6-7 cards. Medium (800-1200px): 5 cards. Tablet: 4. Mobile: 3.
                    final count = (width / 175).floor().clamp(3, 7);
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: count,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 12,
                        childAspectRatio:
                            0.67, // Standard 2:3 poster aspect ratio
                      ),
                      itemCount: films.length,
                      itemBuilder: (context, i) => FranchiseFilmTile(
                          film: films[i], number: films.length - i),
                    );
                  },
                ),
    );
  }
}

class FranchiseFilmTile extends StatefulWidget {
  final CinemanaItem film;
  final int number;
  const FranchiseFilmTile(
      {super.key, required this.film, required this.number});

  @override
  State<FranchiseFilmTile> createState() => _FranchiseFilmTileState();
}

class _FranchiseFilmTileState extends State<FranchiseFilmTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final film = widget.film;
    final number = widget.number;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    // High-resolution image: bestPosterUrl or imgUrl
    final posterUrl =
        film.bestPosterUrl.isNotEmpty ? film.bestPosterUrl : film.cardImageUrl;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () => Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(builder: (_) => CinemanaDetailScreen(item: film)),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          transform: _isHovered
              ? (Matrix4.identity()..translate(0, -4))
              : Matrix4.identity(),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(14),
            border: _isHovered
                ? Border.all(color: Colors.white.withOpacity(0.2), width: 1.2)
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Crystal Clear High-Res Poster
              CachedNetworkImage(
                imageUrl: posterUrl,
                cacheManager: appImageCache,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                // Decode at the tile's own pixel width.
                memCacheWidth: (260 * dpr).round(),
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                placeholderFadeInDuration: Duration.zero,
                useOldImageOnUrlChange: true,
                placeholder: (_, __) => ColoredBox(color: p.skeleton),
                errorWidget: (_, __, ___) => ColoredBox(
                  color: p.skeleton,
                  child:
                      Icon(Icons.movie_rounded, color: p.textFaint, size: 36),
                ),
              ),

              // 3. Top Season / Part Badge (بطاقة الموسم النظيفة)
              PositionedDirectional(
                top: 8,
                start: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: film.isSeries
                        ? const Color(0xFF2563EB)
                        : const Color(0xFFE50914),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.45),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        film.isSeries ? Icons.tv_rounded : Icons.movie_rounded,
                        color: Colors.white,
                        size: 11,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        film.isSeries ? 'الموسم $number' : 'الجزء $number',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Top End: HD / Quality Badge
              PositionedDirectional(
                top: 8,
                end: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white24, width: 0.8),
                  ),
                  child: const Text(
                    'HD',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
