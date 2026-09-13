import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/core/constants/app_theme.dart';
import 'package:youtube_downloader/features/downloads/data/models/download_task_model.dart';
import 'package:youtube_downloader/features/downloads/presentation/providers/downloads_provider.dart';
import 'package:youtube_downloader/features/home/presentation/providers/video_analyzer_provider.dart';
import 'package:youtube_downloader/features/home/presentation/providers/youtube_feed_provider.dart';
import 'package:youtube_downloader/features/home/presentation/widgets/category_chips_bar.dart';
import 'package:youtube_downloader/features/home/presentation/widgets/download_progress_card.dart';
import 'package:youtube_downloader/features/home/presentation/widgets/quality_selector.dart';
import 'package:youtube_downloader/features/home/presentation/widgets/video_preview_card.dart';
import 'package:youtube_downloader/features/home/presentation/widgets/youtube_video_card.dart';
import 'package:youtube_downloader/features/series/presentation/providers/series_provider.dart';
import 'package:youtube_downloader/features/series/presentation/widgets/series_episode_card.dart';
import 'package:youtube_downloader/features/settings/presentation/providers/settings_provider.dart';

class YoutubeCinematicScreen extends ConsumerWidget {
  const YoutubeCinematicScreen({super.key});

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
  Widget build(BuildContext context, WidgetRef ref) {
    final feedState = ref.watch(youtubeFeedProvider);
    final analyzerState = ref.watch(analyzerProvider);
    final downloadsState = ref.watch(downloadsProvider);
    final seriesState = ref.watch(seriesProvider);
    final strings = ref.watch(stringsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobile = MediaQuery.of(context).size.width < 700;

    // Same palette the home screen paints with, so both pages read as one app.
    final bgColor = isDark ? AppColors.darkBg : AppColors.lightSecondaryBg;
    final cardColor = isDark ? AppColors.darkCard : AppColors.lightCard;
    final elevatedColor = isDark ? const Color(0xFF131A27) : Colors.white;
    final borderColor =
        isDark ? Colors.white.withOpacity(0.08) : AppColors.lightBorder;

    final List<DownloadTaskModel> activeTasks = downloadsState.activeTasks;
    final isSeriesMode = seriesState.isSeriesMode;

    return Scaffold(
      backgroundColor: bgColor,
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: elevatedColor,
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
            return false;
          },
          child: CustomScrollView(
            cacheExtent: 1800,
            physics: const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              // Top Section (Headers, Categories, Status, or Series Banner)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: isMobile ? 12 : 20,
                    right: isMobile ? 12 : 20,
                    top: isMobile ? (activeTasks.isNotEmpty || analyzerState.hasResult ? 8 : 2) : 16,
                    bottom: isMobile && !analyzerState.hasResult && activeTasks.isEmpty && !isSeriesMode ? 0 : 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!isSeriesMode && !isMobile) const CategoryChipsBar(),

                    // If analyzing a specific link from search or paste
                    if (analyzerState.hasResult) ...[
                      const SizedBox(height: 12),
                      const VideoPreviewCard(),
                      const QualitySelector(),
                    ],

                    // Active Downloads Section
                    if (activeTasks.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            width: 4,
                            height: 16,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            strings.activeDownloads,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${activeTasks.length}',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ...activeTasks.map((t) => DownloadProgressCard(key: ValueKey(t.id), task: t)),
                    ],

                    // Smart Series Banner recommendation if user searched in normal mode
                    if (!isSeriesMode &&
                        feedState.searchQuery.isNotEmpty &&
                        _isSeriesQuery(feedState.searchQuery)) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [elevatedColor, cardColor],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.primary.withOpacity(0.35)),
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
                                    'يمكن للتطبيق تجميع كل الحلقات من مختلف القنوات وترتيبها رقمياً وتنزيلها بالكامل!',
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

                    // SERIES MODE: Clean display without the batch download container
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
                                      child: FilterChip(
                                        label: Text('الموسم $season'),
                                        selected: isCurrent,
                                        selectedColor: AppColors.primary,
                                        backgroundColor: cardColor,
                                        checkmarkColor: Colors.white,
                                        side: BorderSide(
                                          color: isCurrent ? AppColors.primary : borderColor,
                                        ),
                                        onSelected: (_) => ref.read(seriesProvider.notifier).selectSeason(season),
                                        labelStyle: TextStyle(
                                          color: isCurrent
                                              ? Colors.white
                                              : (isDark
                                                  ? AppColors.darkTextPrimary
                                                  : AppColors.lightTextPrimary),
                                          fontSize: 11.5,
                                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                        ),
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
                            gradient: LinearGradient(
                              colors: [elevatedColor, cardColor],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
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
                                          'ابحث عن أي مسلسل وسيقوم التطبيق بالبحث عبر جميع قنوات YouTube، استخراج الحلقات، إزالة المقاطع المكررة والإعلانات، وترتيبها تسلسلياً (الحلقة 1، 2، 3...) مع إمكانية تبديل القنوات وتنزيل المسلسل كاملاً دفعة واحدة!',
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
                                  return ActionChip(
                                    avatar: const Icon(Icons.play_arrow_rounded, size: 16, color: AppColors.primary),
                                    label: Text(s),
                                    onPressed: () {
                                      ref.read(seriesProvider.notifier).searchSeries(s);
                                    },
                                    backgroundColor: isDark
                                        ? AppColors.darkSecondaryBg
                                        : AppColors.lightSecondaryBg,
                                    side: BorderSide(color: borderColor),
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
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3),
                        ),
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
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 8),
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

                      return SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childAspectRatio: 1.18,
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
