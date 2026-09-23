import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/core/network/image_cache.dart';

import '../../cinemana/data/models/cinemana_models.dart';
import '../../cinemana/presentation/providers/cinemana_provider.dart';
import '../../cinemana/presentation/screens/cinemana_detail_screen.dart';
import '../data/viu_models.dart';
import 'viu_providers.dart';
import 'viu_widgets.dart';
import '../../../core/constants/app_palette.dart';
import '../../../presentation/widgets/card_motion.dart';
import '../../../presentation/widgets/reveal.dart';

/// A film in "أفلام أخرى": one of Viu's free films or a Cinemana film.
class OtherFilm {
  final ViuShow? viu;
  final CinemanaItem? cinemana;

  const OtherFilm.viu(ViuShow this.viu) : cinemana = null;
  const OtherFilm.cinemana(CinemanaItem this.cinemana) : viu = null;

  String get key => viu != null ? 'viu:${viu!.seriesId}' : 'cin:${cinemana!.id}';
  String get title => viu?.displayName ?? cinemana!.displayTitle;
  String? get poster => viu != null ? (viu!.portraitUrl ?? viu!.landscapeUrl) : cinemana!.cardImageUrl;

  void open(BuildContext context) {
    if (viu != null) {
      openViuShow(context, viu!);
    } else {
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(builder: (_) => CinemanaDetailScreen(item: cinemana!)),
      );
    }
  }
}

/// Page [page] of "أفلام أخرى": Viu's free films first, then popular films
/// dealt across many genres, so the list is varied and only films.
Future<List<OtherFilm>> fetchOtherFilms(WidgetRef ref, int page) async {
  final viuFilms = page == 0
      ? ref.read(viuServiceProvider).fetchFreeMovies().catchError((Object _) => <ViuShow>[])
      : Future.value(<ViuShow>[]);
  final results = await Future.wait<Object>([
    viuFilms,
    ref.read(cinemanaServiceProvider).fetchVariedMovies(page: page),
  ]);
  return [
    for (final v in ViuShow.mergeVersions(results[0] as List<ViuShow>)) OtherFilm.viu(v),
    for (final c in results[1] as List<CinemanaItem>) OtherFilm.cinemana(c),
  ];
}

final otherFilmsHomeProvider = FutureProvider<List<OtherFilm>>((ref) async {
  final viu = await ref.read(viuServiceProvider).fetchFreeMovies().catchError((Object _) => <ViuShow>[]);
  final varied = await ref.read(cinemanaServiceProvider).fetchVariedMovies();
  return [
    for (final v in ViuShow.mergeVersions(viu)) OtherFilm.viu(v),
    for (final c in varied.take(30)) OtherFilm.cinemana(c),
  ];
});

/// 2:3 poster with the title on it.
class OtherFilmCard extends StatelessWidget {
  final OtherFilm film;
  final double width;

  const OtherFilmCard({super.key, required this.film, this.width = 104});

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final poster = film.poster;
    return GestureDetector(
      onTap: () => film.open(context),
      child: SizedBox(
        width: width,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: AspectRatio(
            aspectRatio: 2 / 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // The card's own colour goes under the poster, inside the clip -
                // painted under the clip instead it bled through the rounded
                // edge as a grey outline.
                ColoredBox(color: AppPalette.of(context).bg),
                if (poster != null && poster.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: poster,
                    cacheManager: appImageCache,
                    fit: BoxFit.cover,
                    memCacheWidth: (width * dpr).round(),
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                    placeholderFadeInDuration: Duration.zero,
                    useOldImageOnUrlChange: true,
                    placeholder: (_, __) => const SizedBox.shrink(),
                    errorWidget: (_, __, ___) => const Icon(Icons.movie_rounded, color: Colors.white24),
                  ),
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.transparent, Color(0xB3000000), Color(0xF0000000)],
                        stops: [0, 0.45, 0.75, 1],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Home row "أفلام أخرى".
class OtherFilmsSection extends ConsumerWidget {
  const OtherFilmsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(otherFilmsHomeProvider);
    final films = async.valueOrNull ?? const <OtherFilm>[];
    if (!async.isLoading && films.isEmpty) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  ViuCategory.movies.title,
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
                if (films.isNotEmpty)
                  InkWell(
                    onTap: () => Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute(builder: (_) => const OtherFilmsScreen()),
                    ),
                    borderRadius: BorderRadius.circular(8),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('عرض الكل',
                              style: TextStyle(color: Color(0xFFE50914), fontSize: 13, fontWeight: FontWeight.bold)),
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
          SizedBox(
            height: 156,
            // The same entrance and the same focus as every other row.
            child: WheelScroll(
              builder: (controller) => ListView.separated(
                key: const PageStorageKey('row-other-films'),
                controller: controller,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                physics: films.isEmpty ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics(),
                itemCount: films.isEmpty ? 4 : films.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) => films.isEmpty
                    ? Container(
                        width: 104,
                        decoration: BoxDecoration(
                          color: AppPalette.of(context).skeleton,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      )
                    : CardEntrance(
                        group: 'row-other-films',
                        index: i,
                        child: CarouselFocus(
                          controller: controller,
                          index: i,
                          extent: 116,
                          width: 104,
                          child: OtherFilmCard(film: films[i]),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "أفلام أخرى" in full: a grid that keeps filling as you scroll.
class OtherFilmsScreen extends ConsumerStatefulWidget {
  const OtherFilmsScreen({super.key});

  @override
  ConsumerState<OtherFilmsScreen> createState() => _OtherFilmsScreenState();
}

class _OtherFilmsScreenState extends ConsumerState<OtherFilmsScreen> {
  final _films = <OtherFilm>[];
  final _seen = <String>{};
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final films = await fetchOtherFilms(ref, _page);
      var added = 0;
      for (final f in films) {
        if (_seen.add(f.key)) {
          _films.add(f);
          added++;
        }
      }
      _page++;
      if (added == 0) _hasMore = false;
    } catch (_) {
      _failed = true;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: AppPalette.of(context).bg,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF0D111A) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 0,
        title: Text(ViuCategory.movies.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
      ),
      body: _films.isEmpty
          ? Center(
              child: _loading
                  ? const CircularProgressIndicator(color: Color(0xFFE50914))
                  : TextButton(
                      onPressed: () {
                        _hasMore = true;
                        _loadMore();
                      },
                      child: Text(_failed ? 'تعذّر التحميل - إعادة المحاولة' : 'لا توجد أفلام حالياً'),
                    ),
            )
          : NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.extentAfter < 800) _loadMore();
                return false;
              },
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 10,
                        childAspectRatio: 2 / 3,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => LayoutBuilder(
                          builder: (context, box) => OtherFilmCard(film: _films[i], width: box.maxWidth),
                        ),
                        childCount: _films.length,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 24, top: 8),
                      child: Center(
                        child: _loading
                            ? const CircularProgressIndicator(color: Color(0xFFE50914), strokeWidth: 2.5)
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
