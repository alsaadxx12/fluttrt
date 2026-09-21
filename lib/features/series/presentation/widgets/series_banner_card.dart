import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/core/constants/app_theme.dart';
import '../providers/series_provider.dart';
import 'batch_download_dialog.dart';

class SeriesBannerCard extends ConsumerWidget {
  const SeriesBannerCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seriesState = ref.watch(seriesProvider);
    final model = seriesState.seriesModel;
    if (model == null || model.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentSeasonEps = seriesState.currentSeasonEpisodes;
    final selectedCount = seriesState.selectedEpisodeNumbers.length;
    final allSelected = selectedCount == currentSeasonEps.length && currentSeasonEps.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF131A27), AppColors.darkCard]
              : [Colors.white, Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppTheme.borderRadius),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.primary.withOpacity(0.2),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Upper Row: Title, Smart Badge & Actions
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.primary, Color(0xFFB30000)]),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(Icons.tv_rounded, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            model.seriesName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_awesome_rounded, size: 12, color: AppColors.primary),
                              SizedBox(width: 4),
                              Text(
                                'تجميع ذكي تلقائي',
                                style: TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'تم اكتشاف وترتيب ${model.totalEpisodes} حلقة تسلسلياً مجمعة من ${model.totalSourcesFound} مصدر وقناة مختلفة على YouTube',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Main Batch Download Button
              ElevatedButton.icon(
                onPressed: selectedCount > 0
                    ? () {
                        final selectedEpisodes = currentSeasonEps
                            .where((e) => seriesState.selectedEpisodeNumbers.contains(e.episodeNumber))
                            .toList();
                        BatchDownloadDialog.show(context, model, selectedEpisodes);
                      }
                    : null,
                icon: const Icon(Icons.download_for_offline_rounded, size: 18),
                label: Text(
                  selectedCount > 0 ? 'تنزيل الحلقات المحددة ($selectedCount)' : 'حدد حلقات للتنزيل',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Season Chips and Selection controls
          Row(
            children: [
              // Scrollable Seasons filter (if more than 1 season detected)
              if (model.availableSeasons.length > 1)
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
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
                        ...model.availableSeasons.map((season) {
                          final isCurrent = seriesState.selectedSeason == season;
                          return Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: FilterChip(
                              label: Text('الموسم $season'),
                              selected: isCurrent,
                              selectedColor: AppColors.primary,
                              onSelected: (_) => ref.read(seriesProvider.notifier).selectSeason(season),
                              labelStyle: TextStyle(
                                color: isCurrent ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                                fontSize: 11.5,
                                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          );
                        }),
                        if (seriesState.isSeasonLoading) ...[
                          const SizedBox(width: 8),
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              else
                const Spacer(),
              const SizedBox(width: 12),

              // Select All / Deselect All
              TextButton.icon(
                onPressed: () {
                  if (allSelected) {
                    ref.read(seriesProvider.notifier).deselectAllEpisodes();
                  } else {
                    ref.read(seriesProvider.notifier).selectAllEpisodes();
                  }
                },
                icon: Icon(
                  allSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
                  size: 16,
                ),
                label: Text(
                  allSelected ? 'إلغاء تحديد الكل' : 'تحديد جميع الحلقات (${currentSeasonEps.length})',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
