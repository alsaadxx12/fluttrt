import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_palette.dart';
import '../../../cinemana/data/cinemana_franchises.dart';
import '../../../cinemana/data/models/cinemana_models.dart';
import '../../../cinemana/presentation/providers/cinemana_provider.dart';
import '../../../cinemana/presentation/screens/cinemana_detail_screen.dart';
import '../../../sports/presentation/widgets/glowing_crest.dart';

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
                style: TextStyle(color: p.text, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.3),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Page-coloured strip (the gaps between cards are just the page).
        ColoredBox(
          color: p.bg,
          child: SizedBox(height: 315, child: _FranchiseCarousel(franchises: franchises)),
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

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        // One card plus its gap per page, so the gaps are even.
        final fraction = ((_FranchiseCard.width + 18) / box.maxWidth).clamp(0.1, 1.0);
        final defaultInitial = widget.franchises.length > 2 ? 1 : 0;
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
          physics: const PageScrollPhysics(parent: BouncingScrollPhysics()),
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
                    filterQuality: FilterQuality.high,
                    child: Stack(
                      fit: StackFit.passthrough,
                      children: [
                        SizedBox(
                          width: _FranchiseCard.width,
                          child: _FranchiseCard(
                            franchise: widget.franchises[i],
                            isActive: isCurrent,
                          ),
                        ),
                        // Side cards sit a little in shade.
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

class _FranchiseCard extends ConsumerWidget {
  final FilmFranchise franchise;
  final bool isActive;
  const _FranchiseCard({required this.franchise, this.isActive = false});

  static const width = 252.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final async = ref.watch(franchiseFilmsProvider(franchise.id));
    final films = async.valueOrNull ?? const <CinemanaItem>[];
    // Nothing of this series on Cinemana: no card.
    if (async.hasValue && films.isEmpty) return const SizedBox.shrink();

    final partsCountLabel = films.isNotEmpty
        ? FilmFranchise.countLabel(films)
        : '${franchise.entries.length} أجزاء';

    return _Pressable(
      onTap: films.isEmpty
          ? null
          : () => Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(builder: (_) => FranchiseScreen(franchise: franchise)),
              ),
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(18),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: const Color(0xFFFF2A4A).withOpacity(0.20),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        // The edge is drawn over the content, so nothing inside can smudge it.
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isActive ? const Color(0xFFFF2A4A).withOpacity(0.85) : p.border,
            width: isActive ? 2.0 : 1.0,
          ),
        ),
        clipBehavior: Clip.antiAliasWithSaveLayer,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // A soft tint in the lead poster's own colour behind the posters,
            // fading into the card.
            if (films.isNotEmpty) _PosterTint(url: films.last.cardImageUrl, card: p.card, isDark: p.isDark),
            Column(
              children: [
                Expanded(
                  child: films.isEmpty
                      ? const _PosterFanPlaceholder()
                      : _PosterFan(films: films),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              franchise.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: p.text, fontSize: 16.5, fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              partsCountLabel,
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

/// The card's tint: the poster's dominant colour at the top, fading into
/// the card colour. Neutral until the colour is known, then eases in.
class _PosterTint extends StatefulWidget {
  final String url;
  final Color card;
  final bool isDark;
  const _PosterTint({required this.url, required this.card, required this.isDark});

  @override
  State<_PosterTint> createState() => _PosterTintState();
}

class _PosterTintState extends State<_PosterTint> {
  Color? _color;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_PosterTint old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _load();
  }

  Future<void> _load() async {
    final url = widget.url;
    final c = await GlowingCrest.dominantColorOf(url);
    if (mounted && widget.url == url) setState(() => _color = c);
  }

  @override
  Widget build(BuildContext context) {
    final top = (_color ?? const Color(0xFF8A94A6)).withOpacity(widget.isDark ? 0.42 : 0.26);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, widget.card],
          stops: const [0, 0.8],
        ),
      ),
    );
  }
}

/// Three posters fanned out: first and last of the series behind, the
/// middle one in front - big, so the artwork carries the card.
class _PosterFan extends StatelessWidget {
  final List<CinemanaItem> films;
  const _PosterFan({required this.films});

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    // Newest first: the latest release is the front poster, the two behind it
    // are earlier films in the series.
    final latest = films.last;
    final behind = <CinemanaItem>{films.first, films[films.length ~/ 2]}
        .where((f) => f.id != latest.id)
        .toList();
    final picks = <CinemanaItem>[latest, ...behind];
    const w = 104.0, h = 156.0;
    Widget poster(CinemanaItem f, double angle, double dx, double dy, double scale, double shade) =>
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
                  border: Border.all(color: Colors.white.withOpacity(0.25), width: 1.0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: f.cardImageUrl,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                      memCacheWidth: (w * dpr).clamp(180, 360).round(),
                      fadeInDuration: const Duration(milliseconds: 100),
                      placeholder: (_, __) => Container(
                        color: const Color(0xFF161E2E),
                        child: const Center(
                          child: Icon(Icons.movie_filter_rounded, color: Colors.white24, size: 24),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: const Color(0xFF161E2E),
                        child: const Center(
                          child: Icon(Icons.movie_filter_rounded, color: Colors.white24, size: 24),
                        ),
                      ),
                    ),
                    // The two behind sit a little in shadow.
                    if (shade > 0) ColoredBox(color: Colors.black.withOpacity(shade)),
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
          if (three) poster(picks[2], 10 * math.pi / 180, 48, 8, 0.88, 0.22),
          if (picks.length > 1) poster(picks[1], -10 * math.pi / 180, -48, 8, 0.88, 0.22),
          poster(picks[0], 0, 0, 0, 1.0, 0),
        ],
      ),
    );
  }
}

/// Instant visual placeholder for the fan cards while images load
class _PosterFanPlaceholder extends StatelessWidget {
  const _PosterFanPlaceholder();

  @override
  Widget build(BuildContext context) {
    const w = 104.0, h = 156.0;
    Widget slot(double angle, double dx, double dy, double scale) => Transform.translate(
          offset: Offset(dx, dy),
          child: Transform.rotate(
            angle: angle,
            child: Transform.scale(
              scale: scale,
              child: Container(
                width: w,
                height: h,
                decoration: BoxDecoration(
                  color: const Color(0xFF161E2E),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(Icons.movie_filter_rounded, color: Colors.white24, size: 28),
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
          slot(10 * math.pi / 180, 48, 8, 0.88),
          slot(-10 * math.pi / 180, -48, 8, 0.88),
          slot(0, 0, 0, 1.0),
        ],
      ),
    );
  }
}

/// Shrinks a little under the finger.
class _Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _Pressable({required this.child, required this.onTap});

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
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
            Text('سلسلة ${franchise.name}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
            if (films.isNotEmpty)
              Text('${FilmFranchise.countLabel(films)} بالترتيب',
                  style: TextStyle(fontSize: 11.5, color: p.textMuted, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      body: async.isLoading && films.isEmpty
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE50914)))
          : films.isEmpty
              ? Center(child: Text('تعذّر تحميل السلسلة', style: TextStyle(color: p.textMuted)))
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
                        childAspectRatio: 0.67, // Standard 2:3 poster aspect ratio
                      ),
                      itemCount: films.length,
                      itemBuilder: (context, i) => _FranchiseFilmTile(film: films[i], number: i + 1),
                    );
                  },
                ),
    );
  }
}

class _FranchiseFilmTile extends StatefulWidget {
  final CinemanaItem film;
  final int number;
  const _FranchiseFilmTile({required this.film, required this.number});

  @override
  State<_FranchiseFilmTile> createState() => _FranchiseFilmTileState();
}

class _FranchiseFilmTileState extends State<_FranchiseFilmTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final film = widget.film;
    final number = widget.number;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final title = film.arTitle.trim().isNotEmpty ? film.arTitle.trim() : film.enTitle.trim();
    // High-resolution image: bestPosterUrl or imgUrl
    final posterUrl = film.bestPosterUrl.isNotEmpty ? film.bestPosterUrl : film.cardImageUrl;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () => Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(builder: (_) => CinemanaDetailScreen(item: film)),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          transform: _isHovered ? (Matrix4.identity()..translate(0, -4)) : Matrix4.identity(),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _isHovered ? const Color(0xFFE50914) : p.border,
              width: _isHovered ? 1.5 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: _isHovered
                    ? const Color(0xFFE50914).withOpacity(0.25)
                    : Colors.black.withOpacity(0.22),
                blurRadius: _isHovered ? 14 : 7,
                offset: Offset(0, _isHovered ? 6 : 3),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Crystal Clear High-Res Poster
              CachedNetworkImage(
                imageUrl: posterUrl,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                memCacheWidth: (260 * dpr).clamp(400, 1200).round(),
                placeholder: (_, __) => ColoredBox(
                  color: p.skeleton,
                  child: const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE50914)),
                    ),
                  ),
                ),
                errorWidget: (_, __, ___) => ColoredBox(
                  color: p.skeleton,
                  child: Icon(Icons.movie_rounded, color: p.textFaint, size: 36),
                ),
              ),

              // 2. Smooth Dark Gradient Overlay for perfect readability
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Color(0x20000000),
                        Color(0xB5000000),
                        Color(0xF0000000),
                      ],
                      stops: [0.0, 0.42, 0.74, 1.0],
                    ),
                  ),
                ),
              ),

              // 3. Top Number Badge (سلسلة بالترتيب e.g. 1, 2, 3)
              PositionedDirectional(
                top: 8,
                start: 8,
                child: Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE50914),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.45),
                        blurRadius: 5,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    '$number',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),

              // Top End: Type Badge if series
              if (film.isSeries)
                PositionedDirectional(
                  top: 8,
                  end: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withOpacity(0.9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'مسلسل',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),

              // 4. Content INSIDE the card (Name, Year, Rating)
              Positioned(
                left: 9,
                right: 9,
                bottom: 9,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        height: 1.25,
                        shadows: [
                          Shadow(
                            color: Colors.black,
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (film.year.trim().isNotEmpty)
                          Text(
                            film.year.trim(),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        if (film.stars.trim().isNotEmpty && film.stars != '0.0') ...[
                          const SizedBox(width: 7),
                          const Icon(Icons.star_rounded, color: Color(0xFFFFB800), size: 12.5),
                          const SizedBox(width: 2),
                          Text(
                            film.stars.trim(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
