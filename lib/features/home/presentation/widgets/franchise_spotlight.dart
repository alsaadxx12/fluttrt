import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:youtube_downloader/core/constants/app_palette.dart';
import 'package:youtube_downloader/core/network/image_cache.dart';
import 'package:youtube_downloader/features/asia2tv/presentation/open_catalogue_item.dart';
import 'package:youtube_downloader/features/cinemana/data/cinemana_franchises.dart';
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';
import 'package:youtube_downloader/features/cinemana/presentation/providers/cinemana_provider.dart';
import 'package:youtube_downloader/features/trailers/data/tmdb_service.dart';
import 'package:youtube_downloader/presentation/widgets/card_motion.dart';
import 'package:youtube_downloader/presentation/widgets/reveal.dart';
import 'franchise_showcase.dart' show FranchiseScreen;

/// A wide picture for one film, found wherever one exists.
///
/// The catalogue's own cover first, when it has one that is not just the
/// poster again; then TMDB's backdrop for the same title and year, which
/// is a real landscape still from the film; and nothing when neither has
/// one, in which case the poster is shown cropped wide.
final spotlightBackdropProvider = FutureProvider.family<String?, String>((ref, filmId) async {
  final service = ref.watch(cinemanaServiceProvider);
  CinemanaItem? film;
  try {
    film = await service.fetchItemDetails(filmId);
  } catch (_) {}
  final own = film?.backdropUrl ?? '';
  if (own.isNotEmpty && own != (film?.imgUrl ?? '') && own != (film?.imgThumbUrl ?? '')) {
    return own;
  }
  if (film == null) return null;
  final title = film.enTitle.trim().isNotEmpty ? film.enTitle.trim() : film.arTitle.trim();
  return _tmdb.backdropForTitle(title, year: film.year.trim());
});

final TmdbService _tmdb = TmdbService();

/// Film series staged big in the middle of the home page.
///
/// One series at a time: a wide still from its newest part, the width of
/// the page, with the series' name and a line about it over the foot of
/// the picture, and every part of the series in a row that sits over the
/// picture's bottom edge — the way a streaming service stages a
/// collection. A swipe on the picture brings the next series.
class FranchiseSpotlight extends StatefulWidget {
  const FranchiseSpotlight({super.key, this.ids = defaultIds});

  /// The series on offer, in the order a swipe reaches them.
  final List<String> ids;

  static const List<String> defaultIds = [
    'james-bond',
    'mission-impossible',
    'harry-potter',
    'fast-furious',
    'john-wick',
    'jurassic',
    'spider-man',
    'batman',
  ];

  @override
  State<FranchiseSpotlight> createState() => _FranchiseSpotlightState();
}

class _FranchiseSpotlightState extends State<FranchiseSpotlight> {
  final PageController _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final franchises = [
      for (final id in widget.ids)
        for (final f in FilmFranchise.all)
          if (f.id == id) f,
    ];
    if (franchises.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        final pictureHeight = width * 10 / 16;
        // The row of parts sits this far up over the picture's foot.
        const overlap = 56.0;
        const rowHeight = 156.0;
        final height = pictureHeight - overlap + rowHeight + 8;
        return Column(
          children: [
            SizedBox(
              height: height,
              child: PageView.builder(
                controller: _pages,
                onPageChanged: (i) => setState(() => _page = i),
                itemCount: franchises.length,
                itemBuilder: (context, i) => _SpotlightPage(
                  franchise: franchises[i],
                  pictureHeight: pictureHeight,
                  overlap: overlap,
                  rowHeight: rowHeight,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Which series is on show, and how many more a swipe reaches.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < franchises.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _page ? const Color(0xFFE50914) : Colors.white24,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _SpotlightPage extends ConsumerWidget {
  const _SpotlightPage({
    required this.franchise,
    required this.pictureHeight,
    required this.overlap,
    required this.rowHeight,
  });

  final FilmFranchise franchise;
  final double pictureHeight;
  final double overlap;
  final double rowHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final films = ref.watch(franchiseFilmsProvider(franchise.id)).valueOrNull ?? const <CinemanaItem>[];
    // Release order from the catalogue: the last is the newest, and the
    // newest is the picture and the first card.
    final newest = films.isEmpty ? null : films.last;
    final backdrop = newest == null
        ? null
        : ref.watch(spotlightBackdropProvider(newest.id)).valueOrNull;
    final fallback = newest?.cardImageUrl ?? '';
    final years = films.map((f) => int.tryParse(f.year.trim())).whereType<int>().toList()..sort();
    final line = films.isEmpty
        ? ''
        : 'شاهد سلسلة ${franchise.name} كاملة: ${FilmFranchise.countLabel(films)}'
            '${years.isEmpty ? '' : years.first == years.last ? ' · ${years.first}' : ' من ${years.first} إلى ${years.last}'}'
            '${newest == null ? '' : ' · الأحدث: ${newest.displayTitle}'}';

    return Stack(
      children: [
        // The picture, with the words over its foot.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: pictureHeight,
          child: GestureDetector(
            onTap: films.isEmpty ? null : () => _openAll(context),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: p.skeleton),
                if ((backdrop ?? fallback).isNotEmpty)
                  CachedNetworkImage(
                    key: ValueKey(backdrop ?? fallback),
                    imageUrl: backdrop ?? fallback,
                    cacheManager: appImageCache,
                    fit: BoxFit.cover,
                    // A poster cropped wide keeps its top, where the faces are.
                    alignment: backdrop == null ? Alignment.topCenter : Alignment.center,
                    filterQuality: FilterQuality.high,
                    fadeInDuration: const Duration(milliseconds: 250),
                    fadeOutDuration: Duration.zero,
                    placeholder: (_, __) => ColoredBox(color: p.skeleton),
                    errorWidget: (_, __, ___) => ColoredBox(color: p.skeleton),
                  ),
                // Dark towards the foot, where the words and the cards are.
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.transparent, const Color(0xCC000000), p.bg],
                      stops: const [0, 0.35, 0.72, 1],
                    ),
                  ),
                ),
                PositionedDirectional(
                  start: 16,
                  end: 16,
                  bottom: overlap + 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'سلسلة ${franchise.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                        ),
                      ),
                      if (line.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          line,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.35),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // The parts, newest first, over the foot of the picture.
        Positioned(
          left: 0,
          right: 0,
          top: pictureHeight - overlap,
          height: rowHeight,
          child: films.isEmpty
              ? ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: 4,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, __) => Container(
                    width: 104,
                    decoration: BoxDecoration(color: p.skeleton, borderRadius: BorderRadius.circular(6)),
                  ),
                )
              : WheelScroll(
                  builder: (controller) => ListView.separated(
                    key: PageStorageKey('spotlight-${franchise.id}'),
                    controller: controller,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    itemCount: films.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, i) {
                      final index = films.length - 1 - i;
                      return CardEntrance(
                        group: 'spotlight-${franchise.id}',
                        index: i,
                        child: CarouselFocus(
                          controller: controller,
                          index: i,
                          extent: 116,
                          width: 104,
                          child: _PartCard(film: films[index], number: index + 1, newest: i == 0),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  void _openAll(BuildContext context) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => FranchiseScreen(franchise: franchise)),
    );
  }
}

/// One part of the series: the poster with its number on a badge at the
/// foot, and «الأحدث» on the newest one.
class _PartCard extends StatelessWidget {
  const _PartCard({required this.film, required this.number, this.newest = false});

  final CinemanaItem film;
  final int number;
  final bool newest;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final poster = film.cardImageUrl;
    return PressScale(
      onTap: () => openCatalogueItem(context, film),
      child: SizedBox(
        width: 104,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: p.bg),
              if (poster.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: poster,
                  cacheManager: appImageCache,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.high,
                  memCacheWidth: (104 * dpr).round(),
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  placeholderFadeInDuration: Duration.zero,
                  useOldImageOnUrlChange: true,
                  placeholder: (_, __) => ColoredBox(color: p.skeleton),
                  errorWidget: (_, __, ___) => ColoredBox(color: p.skeleton),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 8,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (newest)
                      Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF19C3E6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'الأحدث',
                          style: TextStyle(color: Colors.black, fontSize: 9.5, fontWeight: FontWeight.w900),
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE50914),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        film.isSeries ? 'الموسم $number' : 'الجزء $number',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900),
                      ),
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
