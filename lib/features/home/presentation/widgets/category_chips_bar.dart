import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/features/series/presentation/providers/series_provider.dart';
import '../providers/youtube_feed_provider.dart';

class CategoryChipsBar extends ConsumerWidget {
  const CategoryChipsBar({super.key});

  static const List<String> categories = [
    'الكل',
    'رائج',
    'موسيقى',
    'ألعاب',
    'أخبار',
    'بودكاست',
    'مشاع إبداعي',
    'تقنية',
    'تعليم',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedState = ref.watch(youtubeFeedProvider);
    final seriesState = ref.watch(seriesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          // Smart Series Mode Quick Toggle Chip
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: FilterChip(
              avatar: Icon(
                seriesState.isSeriesMode ? Icons.theaters_rounded : Icons.theaters_outlined,
                size: 16,
                color: seriesState.isSeriesMode ? Colors.white : AppColors.primary,
              ),
              label: const Text(
                'مسلسلات ذكية',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              selected: seriesState.isSeriesMode,
              selectedColor: AppColors.primary,
              checkmarkColor: Colors.white,
              showCheckmark: false,
              backgroundColor:
                  isDark ? AppColors.darkCard : AppColors.lightSecondaryBg,
              side: BorderSide(
                color: seriesState.isSeriesMode ? AppColors.primary : AppColors.primary.withOpacity(0.4),
                width: 1.2,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              onSelected: (_) {
                ref.read(seriesProvider.notifier).toggleSeriesMode();
                if (!seriesState.isSeriesMode && feedState.searchQuery.isNotEmpty) {
                  ref.read(seriesProvider.notifier).searchSeries(feedState.searchQuery);
                }
              },
            ),
          ),

          // Refresh Feed Chip
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: ActionChip(
              avatar: Icon(
                Icons.refresh_rounded,
                size: 16,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
              label: const Text('تحديث', style: TextStyle(fontSize: 12)),
              backgroundColor: isDark ? AppColors.darkCard : AppColors.lightCard,
              side: BorderSide(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                width: 1,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              onPressed: () {
                if (seriesState.isSeriesMode) {
                  ref.read(seriesProvider.notifier).searchSeries(feedState.searchQuery);
                } else {
                  ref.read(youtubeFeedProvider.notifier).refresh();
                }
              },
            ),
          ),

          // Categories Chips
          ...categories.map((cat) {
            final isSelected = feedState.currentCategory == cat && feedState.searchQuery.isEmpty && !seriesState.isSeriesMode;
            return Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(
                label: Text(
                  cat,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected
                        ? (isDark ? Colors.black : Colors.white)
                        : (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
                  ),
                ),
                selected: isSelected,
                selectedColor: isDark ? Colors.white : AppColors.lightTextPrimary,
                backgroundColor: isDark ? AppColors.darkCard : AppColors.lightCard,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                side: BorderSide(
                  color: isSelected
                      ? Colors.transparent
                      : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                  width: 1,
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                showCheckmark: false,
                onSelected: (selected) {
                  if (selected) {
                    if (seriesState.isSeriesMode) {
                      ref.read(seriesProvider.notifier).toggleSeriesMode();
                    }
                    ref.read(youtubeFeedProvider.notifier).loadCategory(cat);
                  }
                },
              ),
            );
          }),
        ],
      ),
    );
  }
}
