import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/features/series/presentation/providers/series_provider.dart';
import '../providers/youtube_feed_provider.dart';

/// A flat pill chip in the app's system look: 36 px high, radius 20, pure
/// white fill with a hairline border and black87 text when unselected, brand
/// red fill with white text when selected. No elevation, no animation.
class SystemPillChip extends StatelessWidget {
  const SystemPillChip({
    super.key,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.icon,
    this.iconColor,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;
  final IconData? icon;

  /// Colour of [icon]; defaults to the label colour.
  final Color? iconColor;

  static const double height = 36;
  static const double radius = 20;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = selected ? AppColors.primary : (isDark ? AppColors.darkCard : Colors.white);
    final border = selected ? AppColors.primary : (isDark ? AppColors.darkBorder : AppColors.lightBorder);
    final fg = selected ? Colors.white : (isDark ? Colors.white70 : Colors.black87);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: border, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: selected ? Colors.white : (iconColor ?? fg)),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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

    return SizedBox(
      height: SystemPillChip.height,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        children: [
          // Smart Series Mode Quick Toggle Chip (the only way in and out of
          // series mode).
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: SystemPillChip(
              icon: Icons.auto_awesome_rounded,
              iconColor: AppColors.primary,
              label: 'مسلسلات ذكية',
              selected: seriesState.isSeriesMode,
              onTap: () {
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
            child: SystemPillChip(
              icon: Icons.refresh_rounded,
              label: 'تحديث',
              onTap: () {
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
              child: SystemPillChip(
                label: cat,
                selected: isSelected,
                onTap: () {
                  if (isSelected) return;
                  if (seriesState.isSeriesMode) {
                    ref.read(seriesProvider.notifier).toggleSeriesMode();
                  }
                  ref.read(youtubeFeedProvider.notifier).loadCategory(cat);
                },
              ),
            );
          }),
        ],
      ),
    );
  }
}
