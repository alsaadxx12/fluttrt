import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/core/constants/app_theme.dart';
import 'package:youtube_downloader/features/home/presentation/providers/youtube_feed_provider.dart';
import 'package:youtube_downloader/features/trailers/data/trailer_stream_resolver.dart';
import 'package:youtube_downloader/features/home/presentation/widgets/category_chips_bar.dart';
import 'package:youtube_downloader/features/home/presentation/widgets/youtube_video_card.dart';
import 'package:youtube_downloader/features/series/presentation/providers/series_provider.dart';
import 'package:youtube_downloader/features/series/presentation/widgets/series_episode_card.dart';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:youtube_downloader/core/scroll/app_scroll_physics.dart';

class YoutubeCinematicScreen extends ConsumerStatefulWidget {
  const YoutubeCinematicScreen({super.key});

  @override
  ConsumerState<YoutubeCinematicScreen> createState() => _YoutubeCinematicScreenState();
}

class _YoutubeCinematicScreenState extends ConsumerState<YoutubeCinematicScreen> {
  bool _isSeriesQuery(String q) {
    final lower = q.toLowerCase();
    return lower.contains('مسلسل') ||
        lower.contains('حلقة') ||
        lower.contains('حلقات') ||
        lower.contains('الحلقة') ||
        lower.contains('الحلقات') ||
        lower.contains('season') ||
        lower.contains('series') ||
        lower.contains('episode');
  }

  static const List<String> _suggestedSeries = [
    'مسلسل عمر',
    'المؤسس عثمان',
    'صلاح الدين الأيوبي',
    'جعفر العمدة',
    'قيامة أرطغرل',
    'Breaking Bad',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final videos = ref.read(youtubeFeedProvider).videos;
      if (videos.isNotEmpty && ref.read(activeYouTubeCardIdProvider) == null) {
        ref.read(activeYouTubeCardIdProvider.notifier).state = videos.first.id.value;
      }
      _prewarmTop(videos);
    });
  }

  /// The first cards' direct streams are resolved ahead of time, so the
  /// fronted preview starts the moment it is tapped or scrolled to.
  void _prewarmTop(List<Video> videos) {
    if (videos.isEmpty) return;
    TrailerStreamResolver.instance.prewarm(videos.take(4).map((v) => v.id.value));
  }

  void _onScrollSettled(double scrollOffset, List<Video> videos) {
    if (videos.isEmpty) return;
    final width = MediaQuery.of(context).size.width;
    if (width >= 680) return; // Only auto-switch on single-column mobile feed

    const topOffset = 65.0;
    final cardHeight = ((width - 28) / 1.45) + 12.0;

    final relativeOffset = (scrollOffset - topOffset).clamp(0.0, double.infinity);
    final targetIndex = (relativeOffset / cardHeight).round().clamp(0, videos.length - 1);

    final targetId = videos[targetIndex].id.value;
    if (ref.read(activeYouTubeCardIdProvider) != targetId) {
      ref.read(activeYouTubeCardIdProvider.notifier).state = targetId;
    }
  }

  @override
  Widget build(BuildContext context) {
    // When videos change or reload, automatically activate the first card
    ref.listen<YouTubeFeedState>(youtubeFeedProvider, (previous, next) {
      if (next.videos.isNotEmpty &&
          (previous == null ||
           previous.videos != next.videos ||
           ref.read(activeYouTubeCardIdProvider) == null)) {
        ref.read(activeYouTubeCardIdProvider.notifier).state = next.videos.first.id.value;
        _prewarmTop(next.videos);
      }
    });

    final feedState = ref.watch(youtubeFeedProvider);
    final seriesState = ref.watch(seriesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobile = MediaQuery.of(context).size.width < 700;

    // System design: a pure white page, flat white containers set apart only
    // by a hairline border, brand red for accents.
    final bgColor = isDark ? AppColors.darkBg : AppColors.lightBg;
    final cardColor = isDark ? AppColors.darkCard : AppColors.lightCard;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    final isSeriesMode = seriesState.isSeriesMode;

    return Scaffold(
      backgroundColor: bgColor,
      body: RefreshIndicator(
        triggerMode: RefreshIndicatorTriggerMode.anywhere,
        backgroundColor: Colors.white,
        color: const Color(0xFFE50914),
        strokeWidth: 2.4,
        onRefresh: () async {
          if (isSeriesMode && seriesState.query.isNotEmpty) {
            await ref.read(seriesProvider.notifier).searchSeries(seriesState.query);
          } else {
            await ref.read(youtubeFeedProvider.notifier).refresh();
          }
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (scrollInfo) {
            if (!isSeriesMode && scrollInfo.metrics.pixels >= scrollInfo.metrics.maxScrollExtent - 500) {
              ref.read(youtubeFeedProvider.notifier).loadMore();
            }
            if (!isSeriesMode && scrollInfo is ScrollEndNotification && feedState.videos.isNotEmpty) {
              _onScrollSettled(scrollInfo.metrics.pixels, feedState.videos);
            }
            return false;
          },
          child: CustomScrollView(
            cacheExtent: 1000,
            physics: kAppDefaultScrollPhysics,
            slivers: [
              // Top Section (Categories row, then Series Banner / Series hero)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Always visible, on every width, directly under the header.
                      const CategoryChipsBar(),

                    // Smart Series Banner recommendation if user searched in normal mode
                    if (!isSeriesMode &&
                        feedState.searchQuery.isNotEmpty &&
                        _isSeriesQuery(feedState.searchQuery)) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(AppTheme.borderRadius),
                          border: Border.all(color: borderColor),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'هل تبحث عن حلقات مسلسل "${feedState.searchQuery}"؟',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'يمكن للتطبيق تجميع كل الحلقات من مختلف القنوات وترتيبها رقمياً لمشاهدتها بالكامل!',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              onPressed: () {
                                ref.read(seriesProvider.notifier).searchSeries(feedState.searchQuery);
                              },
                              icon: const Icon(Icons.playlist_play_rounded, size: 18),
                              label: const Text('تجميع وترتيب الحلقات'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // SERIES MODE: seasons row (results) or the welcome hero (no search yet)
                    if (isSeriesMode) ...[
                      if (seriesState.hasResults && !seriesState.isLoading) ...[
                        if ((seriesState.seriesModel?.availableSeasons.length ?? 0) > 1)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              child: Row(
                                children: [
                                  Text(
                                    'المواسم:',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ...seriesState.seriesModel!.availableSeasons.map((season) {
                                    final isCurrent = seriesState.selectedSeason == season;
                                    return Padding(
                                      padding: const EdgeInsets.only(left: 6),
                                      child: SystemPillChip(
                                        label: 'الموسم $season',
                                        selected: isCurrent,
                                        onTap: () => ref.read(seriesProvider.notifier).selectSeason(season),
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ),
                      ]
                      else if (!seriesState.isLoading && seriesState.seriesModel == null) ...[
                        // Series Welcome / Search Hero
                        Container(
                          margin: const EdgeInsets.only(top: 8, bottom: 16),
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(AppTheme.borderRadius),
                            border: Border.all(color: borderColor),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.movie_filter_rounded, color: Colors.white, size: 28),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'مُجمّع حلقات المسلسلات الذكي (Smart Series Aggregator)',
                                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'ابحث عن أي مسلسل وسيقوم التطبيق بالبحث عبر جميع قنوات YouTube، استخراج الحلقات، إزالة المقاطع المكررة والإعلانات، وترتيبها تسلسلياً (الحلقة 1، 2، 3...) مع إمكانية تبديل القنوات ومشاهدة المسلسل كاملاً!',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                            height: 1.35,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              const Text(
                                'مسلسلات مقترحة للتجربة السريعة:',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _suggestedSeries.map((s) {
                                  return SystemPillChip(
                                    icon: Icons.play_arrow_rounded,
                                    iconColor: AppColors.primary,
                                    label: s,
                                    onTap: () {
                                      ref.read(seriesProvider.notifier).searchSeries(s);
                                    },
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],

                    // Standard Mode Header Row (Hidden on mobile for clean feed unless searching)
                    if (!isSeriesMode && (!isMobile || feedState.searchQuery.isNotEmpty)) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text(
                            feedState.searchQuery.isNotEmpty
                                ? 'نتائج البحث عن: "${feedState.searchQuery}"'
                                : 'فيديوهات YouTube المقترحة (${feedState.currentCategory})',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                                ),
                          ),
                          if (!isMobile) ...[
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              tooltip: 'تحديث',
                              onPressed: () => ref.read(youtubeFeedProvider.notifier).refresh(),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // BODY SECTION: Series Mode OR Feed Mode
            if (isSeriesMode) ...[
              // Series Loading Indicator
              if (seriesState.isLoading)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3),
                        const SizedBox(height: 18),
                        Text(
                          'جاري تجميع حلقات: "${seriesState.query}"',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'يتم الآن مسح مئات النتائج عبر YouTube واستخراج أرقام الحلقات واستبعاد الإعلانات...',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              // Series Error State
              else if (seriesState.errorMessage != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
                        const SizedBox(height: 12),
                        Text(seriesState.errorMessage!, style: const TextStyle(fontSize: 13)),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () => ref.read(seriesProvider.notifier).searchSeries(seriesState.query),
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: const Text('إعادة المحاولة'),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              onPressed: () {
                                ref.read(seriesProvider.notifier).setSeriesMode(false);
                                ref.read(youtubeFeedProvider.notifier).search(seriesState.query);
                              },
                              icon: const Icon(Icons.search_rounded, size: 18),
                              label: const Text('بحث عادي بدلاً من المسلسلات'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                )
              // Series Empty State (No Episodes Found)
              else if (seriesState.seriesModel != null && seriesState.seriesModel!.episodes.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.tv_off_rounded,
                          size: 52,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'لم يتم العثور على حلقات مرقمة لـ "${seriesState.query}"',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'تأكد من كتابة اسم المسلسل بدقة، أو تصفح النتائج بالبحث العادي',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () {
                            ref.read(seriesProvider.notifier).setSeriesMode(false);
                            ref.read(youtubeFeedProvider.notifier).search(seriesState.query);
                          },
                          icon: const Icon(Icons.search_rounded, size: 18),
                          label: const Text('عرض نتائج البحث العادية'),
                        ),
                      ],
                    ),
                  ),
                )
              // Series Episodes Grid
              else if (seriesState.hasResults)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  sliver: SliverLayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.crossAxisExtent;
                      int crossAxisCount = 3;
                      if (width < 680) {
                        crossAxisCount = 1;
                      } else if (width < 1050) {
                        crossAxisCount = 2;
                      } else if (width < 1450) {
                        crossAxisCount = 3;
                      } else {
                        crossAxisCount = 4;
                      }

                      final eps = seriesState.currentSeasonEpisodes;

                      return SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childAspectRatio: 1.18,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final ep = eps[index];
                            return SeriesEpisodeCard(
                              key: ValueKey('ep_${ep.seasonNumber}_${ep.episodeNumber}_${ep.primaryVideo.id.value}'),
                              episode: ep,
                            );
                          },
                          childCount: eps.length,
                        ),
                      );
                    },
                  ),
                )
              else
                const SliverToBoxAdapter(child: SizedBox.shrink()),
            ]
            // NORMAL FEED MODE
            else ...[
              if (feedState.isLoading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2.5),
                  ),
                )
              else if (feedState.errorMessage != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.wifi_off_rounded, size: 48, color: AppColors.error),
                        const SizedBox(height: 12),
                        Text(feedState.errorMessage!, style: const TextStyle(fontSize: 13)),
                        const SizedBox(height: 14),
                        ElevatedButton.icon(
                          onPressed: () => ref.read(youtubeFeedProvider.notifier).refresh(),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  ),
                )
              else if (feedState.videos.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      'لا توجد فيديوهات متاحة لهذا التصنيف حالياً',
                      style: TextStyle(
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary,
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  sliver: SliverLayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.crossAxisExtent;
                      int crossAxisCount = 3;
                      double childAspectRatio = 1.25;

                      if (width < 680) {
                        crossAxisCount = 1;
                        childAspectRatio = 1.45; // Reduced card height on mobile
                      } else if (width < 1050) {
                        crossAxisCount = 2;
                        childAspectRatio = 1.30;
                      } else if (width < 1450) {
                        crossAxisCount = 3;
                        childAspectRatio = 1.28;
                      } else {
                        crossAxisCount = 4;
                        childAspectRatio = 1.25;
                      }

                      return SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: childAspectRatio,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final video = feedState.videos[index];
                            return YouTubeVideoCard(
                              key: ValueKey(video.id.value),
                              video: video,
                              playlist: feedState.videos,
                              playlistIndex: index,
                            );
                          },
                          childCount: feedState.videos.length,
                        ),
                      );
                    },
                  ),
                ),

              if (feedState.isLoadingMore)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                          strokeWidth: 2.5,
                        ),
                      ),
                    ),
                  ),
                )
              else if (feedState.videos.isNotEmpty && feedState.hasMore)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 24, top: 12),
                    child: Center(
                      child: OutlinedButton.icon(
                        onPressed: () => ref.read(youtubeFeedProvider.notifier).loadMore(),
                        icon: const Icon(Icons.arrow_downward_rounded, size: 16),
                        label: const Text('عرض المزيد من النتائج'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                      ),
                    ),
                  ),
                ),
            ],

            const SliverToBoxAdapter(
              child: SizedBox(height: 30),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
