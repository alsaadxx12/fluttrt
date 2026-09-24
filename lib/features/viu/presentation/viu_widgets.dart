import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/core/network/image_cache.dart';
import 'package:youtube_downloader/presentation/widgets/section_title.dart';

import '../data/viu_models.dart';
import 'viu_category_screen.dart';
import 'viu_providers.dart';
import 'viu_details_screen.dart';
import '../../../core/constants/app_palette.dart';
import '../../../presentation/widgets/card_motion.dart';
import '../../../presentation/widgets/reveal.dart';

void openViuShow(BuildContext context, ViuShow show) {
  Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(builder: (_) => ViuDetailsScreen(show: show)),
  );
}

/// A 2:3 poster with the title on it.
class ViuPosterCard extends StatelessWidget {
  final ViuShow show;
  final double width;

  const ViuPosterCard({super.key, required this.show, this.width = 104});

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final poster = show.portraitUrl ?? show.landscapeUrl;
    return GestureDetector(
      onTap: () => openViuShow(context, show),
      child: SizedBox(
        width: width,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          // One layer, then the clip: the picture and its shading are
          // composited before the rounded edge is applied, so the
          // half-pixel bottom row is shaded like every other row.
          clipBehavior: Clip.antiAliasWithSaveLayer,
          child: AspectRatio(
            aspectRatio: 2 / 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // The page's own colour under the poster, so nothing shows
                // at an edge the picture leaves a hair short of.
                ColoredBox(color: AppPalette.of(context).bg),
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
                    errorWidget: (_, __, ___) =>
                        const Icon(Icons.movie_rounded, color: Colors.white24),
                  ),
                // No name on the poster: the poster is the card.
              ],
            ),
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
    final shows = async.valueOrNull ?? const <ViuShow>[];
    if (!async.isLoading && shows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            category.title,
            onViewAll: shows.isEmpty
                ? null
                : () => Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute(builder: (_) => ViuCategoryScreen(category: category)),
                    ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 156,
            // The same entrance and the same focus as every other row.
            child: WheelScroll(
              builder: (controller) => ListView.separated(
                key: PageStorageKey('viu-${category.title}'),
                controller: controller,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                cacheExtent: 900,
                physics: shows.isEmpty
                    ? const NeverScrollableScrollPhysics()
                    : const ClampingScrollPhysics(),
                itemCount: shows.isEmpty ? 4 : shows.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) => shows.isEmpty
                    ? Container(
                        width: 104,
                        decoration: BoxDecoration(
                          color: AppPalette.of(context).skeleton,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      )
                    : CardEntrance(
                        group: 'viu-${category.title}',
                        index: i,
                        child: CarouselFocus(
                          controller: controller,
                          index: i,
                          extent: 116,
                          width: 104,
                          child: ViuPosterCard(show: shows[i]),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
