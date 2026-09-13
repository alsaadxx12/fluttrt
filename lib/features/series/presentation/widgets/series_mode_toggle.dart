import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import '../providers/series_provider.dart';
import 'package:youtube_downloader/features/home/presentation/providers/youtube_feed_provider.dart';

class SeriesModeToggle extends ConsumerWidget {
  const SeriesModeToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seriesState = ref.watch(seriesProvider);
    final feedState = ref.watch(youtubeFeedProvider);
    final isSeriesMode = seriesState.isSeriesMode;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return IconButton(
      icon: Icon(
        isSeriesMode ? Icons.theaters_rounded : Icons.theaters_outlined,
        size: 21,
        color: isSeriesMode
            ? AppColors.primary
            : (isDark ? Colors.white70 : Colors.black87),
      ),
      tooltip: isSeriesMode
          ? 'إلغاء وضع المسلسلات والعودة للوضع العادي'
          : 'وضع المسلسلات الذكي (تجميع وترتيب الحلقات)',
      onPressed: () {
        ref.read(seriesProvider.notifier).toggleSeriesMode();
        if (!isSeriesMode && feedState.searchQuery.isNotEmpty) {
          ref.read(seriesProvider.notifier).searchSeries(feedState.searchQuery);
        }
      },
    );
  }
}
