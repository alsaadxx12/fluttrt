import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';
import '../../data/models/cinemana_models.dart';
import '../providers/cinemana_provider.dart';
import 'package:youtube_downloader/features/casting/controllers/cast_controller.dart';
import 'package:youtube_downloader/features/casting/controllers/cast_quality.dart';
import 'package:youtube_downloader/features/casting/services/cast_media_source.dart';
import 'package:youtube_downloader/features/casting/services/cast_service.dart';
import 'package:youtube_downloader/features/history/presentation/providers/watch_history_provider.dart';
import 'package:youtube_downloader/features/casting/widgets/cast_remote_page.dart';
import 'cinemana_watch_screen.dart';
import '../../../trailers/presentation/detail_trailer.dart';
import 'package:youtube_downloader/presentation/widgets/favorite_toast.dart';
import 'package:youtube_downloader/presentation/widgets/house_notice.dart';

class CinemanaDetailScreen extends ConsumerStatefulWidget {
  final CinemanaItem item;

  const CinemanaDetailScreen({
    super.key,
    required this.item,
  });

  @override
  ConsumerState<CinemanaDetailScreen> createState() => _CinemanaDetailScreenState();
}

class _CinemanaDetailScreenState extends ConsumerState<CinemanaDetailScreen> {
  CinemanaItem? _fullItem;
  List<CinemanaEpisode> _allEpisodes = [];
  Map<String, List<CinemanaEpisode>> _seasons = {};
  String? _selectedSeason;
  bool _isLoading = true;
  List<CinemanaItem> _similar = [];
  bool _isSimilarLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final service = ref.read(cinemanaServiceProvider);
    final detailsFuture = service.fetchItemDetails(widget.item.id);
    final episodesFuture = widget.item.isSeries
        ? service.fetchEpisodes(widget.item.id)
        : Future.value(<CinemanaEpisode>[]);
    service.fetchSimilar(widget.item).then((list) {
      if (mounted) {
        setState(() {
          _similar = list;
          _isSimilarLoading = false;
        });
      }
    });

    final results = await Future.wait([detailsFuture, episodesFuture]);
    if (mounted) {
      final episodes = results[1] as List<CinemanaEpisode>;
      final Map<String, List<CinemanaEpisode>> seasonsMap = {};
      for (final ep in episodes) {
        final s = ep.seasonNumber.isNotEmpty ? ep.seasonNumber : '1';
        seasonsMap.putIfAbsent(s, () => []).add(ep);
      }
      for (final s in seasonsMap.keys) {
        seasonsMap[s]!.sort((a, b) => a.intEpisodeNumber.compareTo(b.intEpisodeNumber));
      }
      final sortedKeys = seasonsMap.keys.toList()
        ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));

      final Map<String, List<CinemanaEpisode>> sortedSeasons = {};
      for (final k in sortedKeys) {
        sortedSeasons[k] = seasonsMap[k]!;
      }

      setState(() {
        _fullItem = results[0] as CinemanaItem? ?? widget.item;
        _allEpisodes = episodes;
        _seasons = sortedSeasons;
        _selectedSeason = sortedKeys.isNotEmpty ? sortedKeys.first : null;
        _isLoading = false;
      });
    }
  }

  void _watchItem({CinemanaEpisode? episode}) {
    final item = _fullItem ?? widget.item;
    final currentSeasonEps = (_selectedSeason != null && _seasons.containsKey(_selectedSeason))
        ? _seasons[_selectedSeason]!
        : _allEpisodes;
    final chosen = episode ?? (currentSeasonEps.isNotEmpty ? currentSeasonEps.first : null);

    // A screen is connected: the title goes there and the phone stays where
    // it is, free to keep browsing.
    if (ref.read(castControllerProvider).isConnected) {
      _castItem(item, chosen);
      return;
    }

    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => CinemanaWatchScreen(
          item: item,
          episodes: _allEpisodes,
          initialEpisode: chosen,
          initialSeason: _selectedSeason,
        ),
      ),
    );
  }

  /// Resolves the stream and hands it to the connected screen.
  ///
  /// The url is fetched here and travels only in the command that carries
  /// it — the app never keeps it, so nothing outside this session can replay
  /// it (see [CastMediaSource]).
  Future<void> _castItem(CinemanaItem item, CinemanaEpisode? episode) async {
    if (_casting) return;
    setState(() => _casting = true);
    try {
      final media = await CastMediaSource(ref.read(cinemanaServiceProvider))
          .forItem(
        item,
        episode: episode,
        maxHeight: ref.read(castMaxHeightProvider),
        adaptive: ref.read(castQualityProvider).adaptive,
      );
      if (!mounted) return;
      if (media == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('لا تتوفر روابط تشغيل مباشرة لهذا المحتوى حالياً'),
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
      // Into the history as it starts on the screen, the way the phone's
      // player does when it opens.
      unawaited(ref.read(watchHistoryProvider.notifier).record(item, episode: episode));
      await ref.read(castControllerProvider.notifier).cast(media);
      if (mounted) await CastRemotePage.open(context);
    } catch (e) {
      // The reason, when there is one: «the set refused», «the set did not
      // answer» — not the same sentence for every fault.
      final why = e is CastException ? e.message : 'تعذّر إرسال المحتوى إلى الجهاز';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(why),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _casting = false);
    }
  }

  /// True while a stream is being resolved for the connected screen.
  bool _casting = false;

  @override
  Widget build(BuildContext context) {
    final item = _fullItem ?? widget.item;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = AppPalette.of(context);

    return Scaffold(
      backgroundColor: palette.bg,
      // The popcorn notice sits over the page until the viewer sends it away.
      body: Stack(
        children: [
          CustomScrollView(
        slivers: [
          // Collapsible Hero App Bar with Poster
          SliverAppBar(
            // The whole portrait poster at full width (2:3), never cropped.
            expandedHeight: () {
              final maxH = MediaQuery.of(context).size.height * 0.68;
              final minH = maxH < 300.0 ? (maxH > 150.0 ? maxH * 0.8 : maxH) : 300.0;
              final target = MediaQuery.of(context).size.width * 1.5;
              if (minH >= maxH) return maxH;
              return target.clamp(minH, maxH);
            }(),
            pinned: true,
            backgroundColor: palette.bg,
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
              ),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              Consumer(
                builder: (context, ref, _) {
                  final favorites = ref.watch(cinemanaFavoritesProvider);
                  final isFav = favorites.any((it) => it.id == item.id);
                  return IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: isFav ? Colors.red.withOpacity(0.9) : Colors.black.withOpacity(0.6),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isFav ? Colors.redAccent : Colors.white24,
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    onPressed: () {
                      ref.read(cinemanaFavoritesProvider.notifier).toggleFavorite(item);
                      showFavoriteToast(context, added: !isFav);
                    },
                  );
                },
              ),
              const SizedBox(width: 6),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // The artwork, its bottom edge curved around the play
                  // button below.
                  ClipPath(
                    clipper: const _PosterNotchClipper(),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                  if (item.bestPosterUrl.isNotEmpty || item.bestBackdropUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: item.bestPosterUrl.isNotEmpty ? item.bestPosterUrl : item.bestBackdropUrl,
                      // contain: the full picture always shows, whatever its shape.
                      fit: BoxFit.contain,
                      alignment: Alignment.topCenter,
                      filterQuality: FilterQuality.high,
                      memCacheWidth:
                          (MediaQuery.of(context).size.width * MediaQuery.of(context).devicePixelRatio).round(),
                      placeholder: (_, __) => Container(color: isDark ? Colors.black26 : palette.skeleton),
                      errorWidget: (_, __, ___) => Container(color: isDark ? Colors.black26 : palette.skeleton),
                    )
                  else
                    Container(color: isDark ? Colors.black26 : palette.skeleton),
                  // A scrim at the very top only, so the back and favourite
                  // buttons read over a bright poster. The picture used to
                  // fade into the page across its lower half; the edge is
                  // what the curve is cut into now, so it has to stay.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0x73000000), Colors.transparent],
                        stops: [0, 0.28],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                      ],
                    ),
                  ),

                  // The play button, its centre on the edge the curve is cut
                  // into: half of it over the artwork, half over the page.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: _kEdgeInset - _RoundPlayButton.diameter / 2,
                    child: Center(
                      child: _RoundPlayButton(
                        onTap: _watchItem,
                        busy: _casting,
                        tooltip: item.isSeries ? 'مشاهدة المسلسل' : 'شاهد الآن',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    item.displayTitle,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : const Color(0xFF111115),
                    ),
                  ),
                  if (item.enTitle.isNotEmpty && item.arTitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.enTitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),

                  // Metadata Badges Row (Rating, Year, Type, Likes)
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.amber.withOpacity(0.4), width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded, size: 16, color: Colors.amber),
                            const SizedBox(width: 4),
                            Text(
                              item.stars,
                              style: const TextStyle(
                                color: Colors.amber,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (item.year.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF22222B) : palette.card,
                            borderRadius: BorderRadius.circular(6),
                            border: isDark ? null : Border.all(color: palette.border),
                          ),
                          child: Text(
                            item.year,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          item.isSeries ? 'مسلسل' : 'فيلم',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Categories Chips
                  if (item.categories.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: item.categories.map((cat) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E1E26) : palette.card,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isDark ? const Color(0xFF2E2E3C) : palette.border,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            cat,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                  const SizedBox(height: 4),

                  // Description Section
                  Text(
                    'القصة والنبذة',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.arContent.isNotEmpty
                        ? item.arContent
                        : (item.enContent.isNotEmpty ? item.enContent : 'لا يوجد وصف متاح لهذا المحتوى.'),
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.5,
                      color: isDark ? const Color(0xFFD0D0D8) : const Color(0xFF475569),
                    ),
                  ),

                  // The title's own trailer, played in place. Phone only.
                  DetailTrailer(
                    title: item.enTitle.isNotEmpty ? item.enTitle : item.arTitle,
                    year: item.year.isNotEmpty ? item.year : null,
                    trailerUrl: item.trailerUrl,
                    posterUrl: item.bestBackdropUrl.isNotEmpty ? item.bestBackdropUrl : item.bestPosterUrl,
                  ),

                  // Episodes section if series
                  if (item.isSeries) ...[
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        const Icon(Icons.video_library_rounded, color: AppColors.primary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          _selectedSeason != null
                              ? 'حلقات الموسم $_selectedSeason (${_seasons[_selectedSeason]?.length ?? 0})'
                              : 'حلقات العمل (${_allEpisodes.length})',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Season Chips Selector (RTL)
                    if (_seasons.keys.length > 1) ...[
                      Directionality(
                        textDirection: TextDirection.rtl,
                        child: SizedBox(
                          height: 38,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: _seasons.keys.map((sNum) {
                              final isSelected = _selectedSeason == sNum;
                              final count = _seasons[sNum]?.length ?? 0;
                              return Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: ChoiceChip(
                                  label: Text(
                                    'الموسم $sNum ($count)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      color: isSelected ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF334155)),
                                    ),
                                  ),
                                  selected: isSelected,
                                  selectedColor: AppColors.primary,
                                  backgroundColor: isDark ? const Color(0xFF1E1E26) : palette.card,
                                  side: isDark ? null : BorderSide(color: isSelected ? AppColors.primary : palette.border),
                                  onSelected: (_) {
                                    setState(() {
                                      _selectedSeason = sNum;
                                    });
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    if (_isLoading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24.0),
                          child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2.5),
                        ),
                      )
                    else if (_allEpisodes.isEmpty)
                      Text(
                        'جاري فحص وتحديث الحلقات...',
                        style: TextStyle(
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                          fontSize: 13,
                        ),
                      )
                    else ...[
                      Builder(
                        builder: (context) {
                          final currentSeasonEpisodes = (_selectedSeason != null && _seasons.containsKey(_selectedSeason))
                              ? _seasons[_selectedSeason]!
                              : _allEpisodes;

                          // Right-to-left row of episode cards, each with
                          // its picture (the episode's own, else the show's).
                          return SizedBox(
                            // 150 for the cards plus the list's bottom padding.
                            height: 160,
                            child: Directionality(
                              textDirection: TextDirection.rtl,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.only(bottom: 10),
                                physics: const BouncingScrollPhysics(),
                                itemCount: currentSeasonEpisodes.length,
                                separatorBuilder: (_, __) => const SizedBox(width: 10),
                                itemBuilder: (context, index) =>
                                    _buildEpisodeCard(currentSeasonEpisodes[index], item, isDark),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ],

                  _buildSimilarSection(item, isDark),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ],
          ),
          const HouseNotice.snacks(),
        ],
      ),
    );
  }

  Widget _buildEpisodeCard(CinemanaEpisode ep, CinemanaItem show, bool isDark) {
    final image = (ep.imgUrl != null && ep.imgUrl!.isNotEmpty) ? ep.imgUrl! : show.cardImageUrl;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final palette = AppPalette.of(context);
    return InkWell(
      onTap: () => _watchItem(episode: ep),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 150,
        decoration: BoxDecoration(
          // Light mode: a flat white card on the white page, hairline border only.
          color: isDark ? const Color(0xFF1B1B22) : palette.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? const Color(0xFF2C2C38) : palette.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (image.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: image,
                      fit: BoxFit.cover,
                      memCacheWidth: (150 * dpr).round(),
                      placeholder: (_, __) => ColoredBox(color: isDark ? Colors.black26 : palette.skeleton),
                      errorWidget: (_, __, ___) => ColoredBox(color: isDark ? Colors.black26 : palette.skeleton),
                    )
                  else
                    ColoredBox(color: isDark ? Colors.black26 : palette.skeleton),
                  const Center(
                    child: Icon(
                      Icons.play_circle_fill_rounded,
                      color: Colors.white,
                      size: 34,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'الحلقة ${ep.episodeNumber}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  if (ep.duration.isNotEmpty)
                    Text(ep.duration, style: const TextStyle(fontSize: 10, color: AppColors.darkTextSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "أفلام مقترحة" / "مسلسلات مقترحة": the same kind from this title's genre,
  /// newest release first (the newest releases if it has no genre).
  Widget _buildSimilarSection(CinemanaItem item, bool isDark) {
    if (!_isSimilarLoading && _similar.isEmpty) return const SizedBox.shrink();
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final genre = item.categories.isNotEmpty ? item.categories.first : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Row(
          children: [
            const Icon(Icons.recommend_rounded, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.isSeries ? 'مسلسلات مقترحة' : 'أفلام مقترحة',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ),
            if (genre != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  genre,
                  style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: _isSimilarLoading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2.5))
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: _similar.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, i) => _buildSimilarCard(_similar[i], isDark, dpr),
                ),
        ),
      ],
    );
  }

  Widget _buildSimilarCard(CinemanaItem m, bool isDark, double dpr) {
    final palette = AppPalette.of(context);
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CinemanaDetailScreen(item: m)),
      ),
      child: SizedBox(
        width: 118,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  // Loading placeholder behind the poster: the palette's
                  // skeleton tone, so it still shows on the white page.
                  color: isDark ? Colors.black26 : palette.skeleton,
                  borderRadius: BorderRadius.circular(12),
                  border: isDark ? null : Border.all(color: palette.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (m.cardImageUrl.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: m.cardImageUrl,
                        fit: BoxFit.cover,
                        memCacheWidth: (118 * dpr).round(),
                        placeholder: (_, __) => const SizedBox.shrink(),
                        errorWidget: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    if (m.year.isNotEmpty)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE50914).withOpacity(0.85),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            m.year,
                            style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              m.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
      ),
    );
  }

}


/// How far the artwork stops short of the bottom of its box.
///
/// The lower half of the play button stands in that gap, over the page's own
/// colour. The button cannot hang outside the box — the collapsing app bar
/// clips whatever its background draws — so the artwork gives up the room
/// instead.
const double _kEdgeInset = 36;

/// The artwork's outline: a rectangle whose bottom edge dips smoothly around
/// the play button, so the button sits in a bite taken out of the picture.
///
/// The curve is Flutter's own [CircularNotchedRectangle] — the shape a
/// floating action button makes in a bottom bar. Drawing the dip by hand as
/// a half-circle against a straight edge left a sharp corner where the two
/// met; this eases in and out of the circle instead. It notches the top edge,
/// so the path is flipped to put the bite at the foot.
class _PosterNotchClipper extends CustomClipper<Path> {
  const _PosterNotchClipper();

  /// The bite's radius: the button, plus a little air all round it.
  static const double notchRadius = _RoundPlayButton.diameter / 2 + 9;

  @override
  Path getClip(Size size) {
    final w = size.width;
    final edge = size.height - _kEdgeInset;
    final notched = const CircularNotchedRectangle().getOuterPath(
      Rect.fromLTWH(0, 0, w, edge),
      Rect.fromCircle(center: Offset(w / 2, 0), radius: notchRadius),
    );
    // (x, y) -> (x, edge - y): the notch moves from the top edge to the foot.
    final flip = Matrix4.identity()
      ..translate(0.0, edge)
      ..scale(1.0, -1.0);
    return notched.transform(flip.storage);
  }

  @override
  bool shouldReclip(_PosterNotchClipper oldClipper) => false;
}

/// The round play button that sits in the artwork's curve.
class _RoundPlayButton extends StatelessWidget {
  const _RoundPlayButton({required this.onTap, required this.tooltip, this.busy = false});

  final VoidCallback onTap;
  final String tooltip;

  /// A stream is being resolved for a connected screen.
  final bool busy;

  static const double diameter = 64;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.primary,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: diameter,
            height: diameter,
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                  )
                : const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 38),
          ),
        ),
      ),
    );
  }
}
