import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:youtube_downloader/presentation/widgets/episode_row.dart';
import 'package:youtube_downloader/presentation/widgets/title_profile.dart';
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
          ProfileHeader(
            posterUrl: item.bestPosterUrl.isNotEmpty ? item.bestPosterUrl : item.bestBackdropUrl,
            onPlay: _watchItem,
            busy: _casting,
            tooltip: item.isSeries ? 'مشاهدة المسلسل' : 'شاهد الآن',
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
            ],
          ),

          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ProfileTitle(
                    item.displayTitle,
                    subtitle: item.enTitle.isNotEmpty && item.arTitle.isNotEmpty ? item.enTitle : null,
                  ),
                  const SizedBox(height: 12),
                  ProfileMeta(rating: item.stars, year: item.year, kind: item.isSeries ? 'مسلسل' : 'فيلم'),
                  const SizedBox(height: 14),
                  ProfileTags(item.categories),
                  const SizedBox(height: 4),
                  ProfileStory(item.arContent.isNotEmpty ? item.arContent : item.enContent),

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
                    ProfileSectionTitle(
                      Icons.video_library_rounded,
                      _selectedSeason != null
                          ? 'حلقات الموسم $_selectedSeason (${_seasons[_selectedSeason]?.length ?? 0})'
                          : 'حلقات العمل (${_allEpisodes.length})',
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
                      // One row for every source: see EpisodeRow.
                      Builder(
                        builder: (context) {
                          final currentSeasonEpisodes = (_selectedSeason != null && _seasons.containsKey(_selectedSeason))
                              ? _seasons[_selectedSeason]!
                              : _allEpisodes;
                          return EpisodeRow(
                            tiles: [
                              for (final ep in currentSeasonEpisodes)
                                EpisodeTile(label: 'الحلقة ${ep.episodeNumber}', image: ep.imgUrl, note: ep.duration),
                            ],
                            fallbackImage: item.cardImageUrl,
                            onTap: (i) => _watchItem(episode: currentSeasonEpisodes[i]),
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


