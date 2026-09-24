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
typedef WideStillKey = ({
  String id,
  String title,
  String altTitle,
  String hint,
  bool series,
  String year
});

/// The key for [spotlightBackdropProvider] from a catalogue item: both of
/// its names, since an Arabic or Turkish series is often on TMDB under
/// the one the catalogue did not put first.
WideStillKey wideStillKeyFor(CinemanaItem item) {
  final en = item.enTitle.trim();
  final ar = item.arTitle.trim();
  return (
    id: item.id,
    title: en.isNotEmpty ? en : ar,
    altTitle: en.isNotEmpty && ar != en ? ar : '',
    // The original name, when the catalogue left it in the poster's file
    // name - the way to TMDB for a dub it names in Arabic only.
    hint: TmdbService.hintFromImageName(item.imgUrl ?? item.imgThumbUrl),
    series: item.isSeries,
    year: item.year.trim(),
  );
}

final spotlightBackdropProvider =
    FutureProvider.family<String?, WideStillKey>((ref, key) async {
  // The catalogue's own cover, for its own titles.
  if (int.tryParse(key.id) != null) {
    try {
      final film =
          await ref.watch(cinemanaServiceProvider).fetchItemDetails(key.id);
      final own = film?.backdropUrl ?? '';
      if (film != null &&
          own.isNotEmpty &&
          own != (film.imgUrl ?? '') &&
          own != (film.imgThumbUrl ?? '')) {
        return own;
      }
    } catch (_) {}
  }
  if (key.title.isEmpty) return null;
  // TMDB by title and year; then by title alone, since a year the source
  // guessed at is a year TMDB will not agree with; then the other name.
  return await _tmdb.backdropForTitle(key.title, year: key.year, series: key.series, hint: key.hint) ??
      (key.altTitle.isEmpty
          ? null
          : await _tmdb.backdropForTitle(key.altTitle, year: key.year, series: key.series)) ??
      (key.altTitle.isEmpty || key.year.isEmpty
          ? null
          : await _tmdb.backdropForTitle(key.altTitle));
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

  /// Marvel and the other big worlds first, then every film series the
  /// app knows, so a swipe keeps finding another.
  static const List<String> defaultIds = [
    'marvel',
    'james-bond',
    'dc',
    'mission-impossible',
    'harry-potter',
    'avengers',
    'fast-furious',
    'x-men',
    'john-wick',
    'jurassic',
    'spider-man',
    'batman',
    'superman',
    'star-wars',
    'lotr',
    'hobbit',
    'avatar',
    'dune',
    'top-gun',
    'guardians',
    'captain-america',
    'iron-man',
    'thor',
    'wolverine',
    'deadpool',
    'venom',
    'spider-verse',
    'joker',
    'transformers',
    'monsterverse',
    'pacific-rim',
    'gladiator',
    'blade-runner',
    'matrix',
    'terminator',
    'indiana-jones',
    'pirates',
    'star-trek-films',
    'planet-apes',
    'alien',
    'predator',
    'the-hunger-games',
    'twilight',
    'divergent',
    'maze-runner',
    'percy-jackson',
    'bourne',
    'die-hard',
    'taken',
    'expendables',
    'equalizer',
    'rambo',
    'rocky',
    'creed',
    'karate-kid',
    'extraction',
    'sicario',
    'knives-out',
    'sherlock-holmes',
    'oceans',
    'now-you-see-me',
    'kingsman',
    'bad-boys',
    'men-in-black',
    'rush-hour',
    'hangover',
    'ted',
    'pitch-perfect',
    'fifty-shades',
    'night-museum',
    'jumanji',
    'ghostbusters',
    'the-meg',
    'mad-max',
    'the-godfather',
    'conjuring',
    'annabelle',
    'insidious',
    'halloween',
    'paranormal-activity',
    'it',
    'smile',
    'quiet-place',
    'purge',
    'saw',
    'scream',
    'resident-evil',
    'final-destination',
    'underworld',
    'toy-story',
    'shrek',
    'ice-age',
    'kung-fu-panda',
    'despicable-me',
    'minions',
    'how-to-train-dragon',
    'madagascar',
    'frozen',
    'cars',
    'hotel-transylvania',
    'lion-king',
    'inside-out',
    'zootopia',
    'moana',
    'sing',
    'trolls',
    'sonic',
  ];

  @override
  State<FranchiseSpotlight> createState() => _FranchiseSpotlightState();
}

class _FranchiseSpotlightState extends State<FranchiseSpotlight> {
  final PageController _pages = PageController();

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
        // Taller than it is wide, the way a collection is staged: the still
        // is the whole block, and the words and the cards sit on its foot.
        final pictureHeight = width * 1.08;
        // The row of parts sits this far up over the picture's foot.
        const overlap = 64.0;
        const rowHeight = 156.0;
        final height = pictureHeight - overlap + rowHeight + 8;
        return Column(
          children: [
            SizedBox(
              height: height,
              child: PageView.builder(
                controller: _pages,
                // The other way round from the page's own direction: the
                // way the user's thumb expects the next series to come.
                reverse: true,
                itemCount: franchises.length,
                itemBuilder: (context, i) => _SpotlightPage(
                  franchise: franchises[i],
                  pictureHeight: pictureHeight,
                  overlap: overlap,
                  rowHeight: rowHeight,
                ),
              ),
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
    final given = ref.watch(franchiseFilmsProvider(franchise.id)).valueOrNull ??
        const <CinemanaItem>[];
    // Newest first, by year, whatever order the catalogue handed them in:
    // the first is the newest, and the newest is the picture and the first
    // card. Ties keep the catalogue's order.
    final films = List<CinemanaItem>.of(given)
      ..sort((a, b) => (int.tryParse(b.year.trim()) ?? 0)
          .compareTo(int.tryParse(a.year.trim()) ?? 0));
    final newest = films.isEmpty ? null : films.first;
    final backdrop = newest == null
        ? null
        : ref
            .watch(spotlightBackdropProvider(wideStillKeyFor(newest)))
            .valueOrNull;
    final fallback = newest?.cardImageUrl ?? '';
    final years = films
        .map((f) => int.tryParse(f.year.trim()))
        .whereType<int>()
        .toList()
      ..sort();
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
                    alignment: backdrop == null
                        ? Alignment.topCenter
                        : Alignment.center,
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
                      colors: [
                        Colors.transparent,
                        Colors.transparent,
                        const Color(0xCC000000),
                        p.bg
                      ],
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
                          style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              height: 1.35),
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
                    decoration: BoxDecoration(
                        color: p.skeleton,
                        borderRadius: BorderRadius.circular(6)),
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
                    // Newest first, as handed over; the number on each is
                    // its place in release order, so the oldest is «الجزء 1».
                    itemBuilder: (context, i) => CardEntrance(
                      group: 'spotlight-${franchise.id}',
                      index: i,
                      child: CarouselFocus(
                        controller: controller,
                        index: i,
                        extent: 116,
                        width: 104,
                        child: _PartCard(
                            film: films[i],
                            number: films.length - i,
                            newest: i == 0),
                      ),
                    ),
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
  const _PartCard(
      {required this.film, required this.number, this.newest = false});

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
          // One layer, then the clip: the picture and its shading are
          // composited before the rounded edge is applied, so the
          // half-pixel bottom row is shaded like every other row.
          clipBehavior: Clip.antiAliasWithSaveLayer,
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF19C3E6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'الأحدث',
                          style: TextStyle(
                              color: Colors.black,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900),
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE50914),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        film.isSeries ? 'الموسم $number' : 'الجزء $number',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900),
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
