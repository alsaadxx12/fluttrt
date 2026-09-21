import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/core/network/image_cache.dart';

import '../data/viu_models.dart';
import 'viu_category_screen.dart';
import 'viu_providers.dart';
import 'viu_watch_screen.dart';
import '../../../core/constants/app_palette.dart';

void openViuShow(BuildContext context, ViuShow show) {
  Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(builder: (_) => ViuWatchScreen(show: show)),
  );
}

/// A 2:3 poster with the title on it.
class ViuPosterCard extends StatelessWidget {
  final ViuShow show;
  final double width;

  const ViuPosterCard({super.key, required this.show, this.width = 130});

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final poster = show.portraitUrl ?? show.landscapeUrl;
    return GestureDetector(
      onTap: () => openViuShow(context, show),
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: AppPalette.of(context).skeleton,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppPalette.of(context).border),
        ),
        clipBehavior: Clip.antiAlias,
        child: AspectRatio(
          aspectRatio: 2 / 3,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (poster != null)
                CachedNetworkImage(
                  imageUrl: poster,
                  cacheManager: appImageCache,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.high,
                  // Decode at the card's own pixel size.
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
              PositionedDirectional(
                start: 8,
                end: 8,
                bottom: 8,
                child: Text(
                  show.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A home page row for one Viu category, with "عرض الكل".
/// Hidden when the category has nothing to show (or Viu can't be reached).
class ViuHomeSection extends ConsumerWidget {
  final ViuCategory category;

  const ViuHomeSection({super.key, required this.category});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(viuHomeRowProvider(category));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shows = async.valueOrNull ?? const <ViuShow>[];
    if (!async.isLoading && shows.isEmpty) return const SizedBox.shrink();

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
                  category.title,
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
                if (shows.isNotEmpty)
                  InkWell(
                    onTap: () => Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute(builder: (_) => ViuCategoryScreen(category: category)),
                    ),
                    borderRadius: BorderRadius.circular(8),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'عرض الكل',
                            style: TextStyle(color: Color(0xFFE50914), fontSize: 13, fontWeight: FontWeight.bold),
                          ),
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
            height: 195,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              physics: shows.isEmpty ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics(),
              itemCount: shows.isEmpty ? 4 : shows.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => shows.isEmpty
                  ? Container(
                      width: 130,
                      decoration: BoxDecoration(
                        color: AppPalette.of(context).skeleton,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    )
                  : ViuPosterCard(show: shows[i]),
            ),
          ),
        ],
      ),
    );
  }
}
