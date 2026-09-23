import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/core/network/image_cache.dart';

import '../../../../core/constants/app_palette.dart';
import '../../../cinemana/data/models/cinemana_models.dart';
import '../../../cinemana/presentation/providers/cinemana_provider.dart';
import '../../../cinemana/presentation/screens/cinemana_detail_screen.dart';

/// The newest films, offered from the edge of the screen.
///
/// Collapsed, a small tab clings to the side rail at mid-height, as though a
/// deck of posters were tucked just off-screen. Pulling it out fans the films
/// like a hand of cards, dealt through one at a time. Nothing is thrown in
/// front of the viewer when the app opens.
class FilmDeck extends ConsumerStatefulWidget {
  const FilmDeck({super.key});

  @override
  ConsumerState<FilmDeck> createState() => _FilmDeckState();
}

class _FilmDeckState extends ConsumerState<FilmDeck> {
  bool _open = false;
  PageController? _pages;
  double _lastFraction = 0;
  int _index = 0;

  static const _limit = 10;

  @override
  void dispose() {
    _pages?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final films = (ref.watch(homeLatestMoviesProvider).valueOrNull ?? const <CinemanaItem>[])
        .where((f) => f.cardImageUrl.isNotEmpty)
        .take(_limit)
        .toList();
    if (films.isEmpty) return const SizedBox.shrink();

    final size = MediaQuery.of(context).size;
    final h = size.height;
    final w = size.width;
    // Perfect proportions on both desktop and mobile:
    final targetCardWidth = w > 800 ? (w * 0.46).clamp(420.0, 560.0) : w * 0.86;
    final fraction = (targetCardWidth / w).clamp(0.35, 0.92);
    if (_pages == null || (fraction - _lastFraction).abs() > 0.01) {
      final initial = _pages?.hasClients == true ? (_pages!.page ?? 0).round() : _index;
      _pages?.dispose();
      _pages = PageController(viewportFraction: fraction, initialPage: initial);
      _lastFraction = fraction;
    }

    return Stack(
      children: [
        AnimatedPositioned(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          top: h * 0.36,
          right: _open ? -46 : 0,
          child: _Handle(onTap: () => setState(() => _open = true)),
        ),
        if (_open) ...[
          // A veil: a tap anywhere puts the hand away.
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _open = false),
              child: ColoredBox(color: Colors.black.withOpacity(0.6)),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: h * 0.16,
            child: _Hand(
              films: films,
              controller: _pages!,
              index: _index,
              onIndex: (i) => setState(() => _index = i),
              onClose: () => setState(() => _open = false),
            ),
          ),
        ],
      ],
    );
  }
}

/// The tab on the rail.
class _Handle extends StatelessWidget {
  final VoidCallback onTap;
  const _Handle({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'أحدث الأفلام',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 26,
          height: 96,
          decoration: const BoxDecoration(
            color: Color(0xFFE50914),
            borderRadius: BorderRadius.only(topLeft: Radius.circular(13), bottomLeft: Radius.circular(13)),
            boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(-3, 3))],
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.movie_rounded, color: Colors.white, size: 16),
              SizedBox(height: 10),
              Icon(Icons.chevron_left_rounded, color: Colors.white, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

/// The posters, fanned and dealt one at a time.
class _Hand extends StatelessWidget {
  final List<CinemanaItem> films;
  final PageController controller;
  final int index;
  final ValueChanged<int> onIndex;
  final VoidCallback onClose;

  const _Hand({
    required this.films,
    required this.controller,
    required this.index,
    required this.onIndex,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 300,
          child: PageView.builder(
            controller: controller,
            onPageChanged: onIndex,
            itemCount: films.length,
            itemBuilder: (context, i) => AnimatedBuilder(
              animation: controller,
              builder: (context, child) {
                final page = controller.position.haveDimensions ? (controller.page ?? index.toDouble()) : index.toDouble();
                final d = (page - i).clamp(-1.5, 1.5);
                // Cards either side lie back and tilt, the way a hand fans.
                return Transform.rotate(
                  angle: d * 0.08,
                  child: Transform.scale(
                    scale: 1 - d.abs() * 0.12,
                    child: Opacity(opacity: (1 - d.abs() * 0.4).clamp(0.0, 1.0), child: child),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _FilmCard(film: films[i], onClose: onClose),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < films.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == index ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == index ? const Color(0xFFE50914) : Colors.white38,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _FilmCard extends StatelessWidget {
  final CinemanaItem film;
  final VoidCallback onClose;
  const _FilmCard({required this.film, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final dpr = MediaQuery.of(context).devicePixelRatio;
    // Use highest resolution image available: bestPosterUrl or imgUrl
    final posterUrl = film.bestPosterUrl.isNotEmpty ? film.bestPosterUrl : film.cardImageUrl;

    return GestureDetector(
      onTap: () {
        onClose();
        Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(builder: (_) => CinemanaDetailScreen(item: film)),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: posterUrl,
              cacheManager: appImageCache,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
              // The card is 300 lp tall at 2:3; decode at its own pixel width.
              memCacheWidth: (300 * 2 / 3 * dpr).round(),
              fadeInDuration: Duration.zero,
              fadeOutDuration: Duration.zero,
              placeholderFadeInDuration: Duration.zero,
              useOldImageOnUrlChange: true,
              placeholder: (_, __) => ColoredBox(color: p.skeleton),
              errorWidget: (_, __, ___) => ColoredBox(
                color: p.skeleton,
                child: Icon(Icons.movie_rounded, color: p.textFaint, size: 40),
              ),
            ),
            // Keeps the title readable over any poster.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xE6000000)],
                  stops: [0.5, 1.0],
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (film.year.trim().isNotEmpty)
                        Text(film.year.trim(),
                            style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w700)),
                      if (film.stars.trim().isNotEmpty) ...[
                        const SizedBox(width: 10),
                        const Icon(Icons.star_rounded, color: Color(0xFFFFB800), size: 14),
                        const SizedBox(width: 3),
                        Text(film.stars.trim(),
                            style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const Positioned(
              top: 10,
              left: 10,
              child: CircleAvatar(
                radius: 17,
                backgroundColor: Color(0xE6E50914),
                child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
