import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import '../../data/models/cinemana_models.dart';
import '../providers/cinemana_provider.dart';
import 'cinemana_watch_screen.dart';
import '../../../trailers/presentation/detail_trailer.dart';
import 'package:youtube_downloader/presentation/widgets/favorite_toast.dart';

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

    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => CinemanaWatchScreen(
          item: item,
          episodes: _allEpisodes,
          initialEpisode: episode ?? (currentSeasonEps.isNotEmpty ? currentSeasonEps.first : null),
          initialSeason: _selectedSeason,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = _fullItem ?? widget.item;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F13) : Colors.white,
      body: CustomScrollView(
        slivers: [
          // Collapsible Hero App Bar with Poster
          SliverAppBar(
            // The whole portrait poster at full width (2:3), never cropped.
            expandedHeight: (MediaQuery.of(context).size.width * 1.5)
                .clamp(300.0, MediaQuery.of(context).size.height * 0.68),
            pinned: true,
            backgroundColor: isDark ? const Color(0xFF14141A) : Colors.white,
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
                  if (item.bestPosterUrl.isNotEmpty || item.bestBackdropUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: item.bestPosterUrl.isNotEmpty ? item.bestPosterUrl : item.bestBackdropUrl,
                      // contain: the full picture always shows, whatever its shape.
                      fit: BoxFit.contain,
                      alignment: Alignment.topCenter,
                      filterQuality: FilterQuality.high,
                      memCacheWidth:
                          (MediaQuery.of(context).size.width * MediaQuery.of(context).devicePixelRatio).round(),
                      placeholder: (_, __) => Container(color: Colors.black26),
                      errorWidget: (_, __, ___) => Container(color: Colors.black26),
                    )
                  else
                    Container(color: Colors.black26),
                  // Gradient Overlay
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          (isDark ? const Color(0xFF0F0F13) : Colors.white).withOpacity(0.9),
                          (isDark ? const Color(0xFF0F0F13) : Colors.white),
                        ],
                        stops: const [0.55, 0.9, 1.0],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
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
                            color: isDark ? const Color(0xFF22222B) : const Color(0xFFEBEBF0),
                            borderRadius: BorderRadius.circular(6),
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
                            color: isDark ? const Color(0xFF1E1E26) : const Color(0xFFEDEDF4),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isDark ? const Color(0xFF2E2E3C) : const Color(0xFFD8D8E4),
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

                  const SizedBox(height: 18),

                  // Big Watch Now Action Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () => _watchItem(),
                      icon: const Icon(Icons.play_arrow_rounded, size: 24, color: Colors.white),
                      label: Text(
                        item.isSeries ? 'مشاهدة المسلسل' : 'شاهد الآن',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 4,
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

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
                                  backgroundColor: isDark ? const Color(0xFF1E1E26) : const Color(0xFFEDEDF4),
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
                            height: 150,
                            child: Directionality(
                              textDirection: TextDirection.rtl,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
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
    );
  }

  Widget _buildEpisodeCard(CinemanaEpisode ep, CinemanaItem show, bool isDark) {
    final image = (ep.imgUrl != null && ep.imgUrl!.isNotEmpty) ? ep.imgUrl! : show.cardImageUrl;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return InkWell(
      onTap: () => _watchItem(episode: ep),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 150,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1B1B22) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? const Color(0xFF2C2C38) : const Color(0xFFE2E8F0)),
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
                      placeholder: (_, __) => const ColoredBox(color: Colors.black26),
                      errorWidget: (_, __, ___) => const ColoredBox(color: Colors.black26),
                    )
                  else
                    const ColoredBox(color: Colors.black26),
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
                decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
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
