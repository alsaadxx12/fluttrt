import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:youtube_downloader/core/constants/app_palette.dart';
import 'package:youtube_downloader/core/network/image_cache.dart';
import 'package:youtube_downloader/features/asia2tv/presentation/open_catalogue_item.dart';
import 'package:youtube_downloader/features/cinemana/data/cinemana_franchises.dart';
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';
import 'package:youtube_downloader/features/cinemana/presentation/providers/cinemana_provider.dart';
import 'package:youtube_downloader/presentation/widgets/card_motion.dart';
import 'package:youtube_downloader/presentation/widgets/reveal.dart';
import 'franchise_showcase.dart' show FranchiseScreen;

/// One film series, big, in the middle of the home page.
///
/// A backdrop the width of the page with the series' name over it, and
/// under it every part of the series in order, each with its number on a
/// small badge — the way a streaming service stages a collection. The
/// chips across the top swap in another series; the first one is the one
/// shown when the page opens.
class FranchiseSpotlight extends ConsumerStatefulWidget {
  const FranchiseSpotlight({super.key, this.ids = defaultIds});

  /// The series on offer, newest and best known first.
  final List<String> ids;

  static const List<String> defaultIds = [
    'harry-potter',
    'james-bond',
    'fast-furious',
    'mission-impossible',
    'john-wick',
    'jurassic',
    'spider-man',
    'batman',
  ];

  @override
  ConsumerState<FranchiseSpotlight> createState() => _FranchiseSpotlightState();
}

class _FranchiseSpotlightState extends ConsumerState<FranchiseSpotlight> {
  int _index = 0;

  FilmFranchise? get _franchise {
    final id = widget.ids[_index.clamp(0, widget.ids.length - 1)];
    for (final f in FilmFranchise.all) {
      if (f.id == id) return f;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final franchise = _franchise;
    if (franchise == null) return const SizedBox.shrink();
    final async = ref.watch(franchiseFilmsProvider(franchise.id));
    final films = async.valueOrNull ?? const <CinemanaItem>[];

    // The picture: the newest part that has a wide image, so the block
    // looks like the film people know it by.
    String backdrop = '';
    for (final film in films.reversed) {
      if ((film.backdropUrl ?? '').isNotEmpty) {
        backdrop = film.backdropUrl!;
        break;
      }
    }
    if (backdrop.isEmpty && films.isNotEmpty) backdrop = films.last.bestBackdropUrl;

    final years = films.map((f) => int.tryParse(f.year.trim())).whereType<int>().toList()..sort();
    final line = films.isEmpty
        ? ''
        : [
            FilmFranchise.countLabel(films),
            if (years.isNotEmpty) (years.first == years.last ? '${years.first}' : '${years.first} – ${years.last}'),
          ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The chips: which series is on show.
        SizedBox(
          height: 34,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: widget.ids.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final f = FilmFranchise.all.where((x) => x.id == widget.ids[i]).firstOrNull;
              if (f == null) return const SizedBox.shrink();
              final on = i == _index;
              return Material(
                color: on ? const Color(0xFFE50914) : p.cardAlt,
                borderRadius: BorderRadius.circular(17),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => setState(() => _index = i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Center(
                      child: Text(
                        f.name,
                        style: TextStyle(
                          color: on ? Colors.white : p.text,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),

        // The picture, the width of the page, with the name over it.
        GestureDetector(
          onTap: films.isEmpty ? null : () => _openAll(franchise),
          child: AspectRatio(
            aspectRatio: 16 / 10,
            child: Stack(
              fit: StackFit.expand,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  child: backdrop.isEmpty
                      ? ColoredBox(key: const ValueKey('none'), color: p.skeleton)
                      : CachedNetworkImage(
                          key: ValueKey(backdrop),
                          imageUrl: backdrop,
                          cacheManager: appImageCache,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.high,
                          fadeInDuration: Duration.zero,
                          fadeOutDuration: Duration.zero,
                          placeholder: (_, __) => ColoredBox(color: p.skeleton),
                          errorWidget: (_, __, ___) => ColoredBox(color: p.skeleton),
                        ),
                ),
                // Dark towards the foot, where the words are.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.transparent, Color(0xB3000000), Color(0xF2000000)],
                      stops: [0, 0.4, 0.78, 1],
                    ),
                  ),
                ),
                PositionedDirectional(
                  start: 16,
                  end: 16,
                  bottom: 14,
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
                        const SizedBox(height: 4),
                        Text(
                          line,
                          style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ],
                  ),
                ),
                if (films.isNotEmpty)
                  PositionedDirectional(
                    end: 12,
                    bottom: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.25), width: 0.8),
                      ),
                      child: const Text(
                        'عرض الكل',
                        style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Every part, in order, with its number.
        SizedBox(
          height: 156,
          child: films.isEmpty
              ? ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: 4,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, __) => Container(
                    width: 104,
                    decoration: BoxDecoration(color: p.skeleton, borderRadius: BorderRadius.circular(10)),
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
                    itemBuilder: (context, i) => CardEntrance(
                      group: 'spotlight-${franchise.id}',
                      index: i,
                      child: CarouselFocus(
                        controller: controller,
                        index: i,
                        extent: 116,
                        width: 104,
                        child: _PartCard(film: films[i], number: i + 1),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  void _openAll(FilmFranchise franchise) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => FranchiseScreen(franchise: franchise)),
    );
  }
}

/// One part of the series: the poster with its number on a badge at the
/// foot, the way a service marks «New Season».
class _PartCard extends StatelessWidget {
  const _PartCard({required this.film, required this.number});

  final CinemanaItem film;
  final int number;

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
          borderRadius: BorderRadius.circular(10),
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
                child: Center(
                  child: Container(
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
