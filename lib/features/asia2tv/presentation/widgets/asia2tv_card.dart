import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../data/models/asia2tv_models.dart';
import '../screens/asia2tv_details_screen.dart';
import '../screens/asia2tv_watch_screen.dart';

class Asia2TvCard extends StatelessWidget {
  final Asia2TvItem item;
  final double width;
  final double height;
  final VoidCallback? onTap;

  const Asia2TvCard({
    super.key,
    required this.item,
    this.width = 135,
    this.height = 200,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap ??
          () {
            if (item.isEpisode) {
              // Direct watch
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => Asia2TvWatchScreen(
                    item: item,
                    initialWatchUrl: item.url,
                    title: item.title,
                  ),
                ),
              );
            } else {
              // Open details
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => Asia2TvDetailsScreen(item: item),
                ),
              );
            }
          },
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Poster
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              // One layer, then the clip: the picture and its shading are
              // composited before the rounded edge is applied, so the
              // half-pixel bottom row is shaded like every other row.
              clipBehavior: Clip.antiAliasWithSaveLayer,
              child: Stack(
                children: [
                  Container(
                    width: width,
                    height: height,
                    color: isDark ? const Color(0xFF0D121D) : const Color(0xFFE2E8F0),
                    child: item.posterUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: item.posterUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: 400,
                            placeholder: (_, __) => Center(
                              child: Container(
                                color: isDark ? const Color(0xFF0B101B) : Colors.grey[200],
                              ),
                            ),
                            errorWidget: (_, __, ___) => const Center(
                              child: Icon(Icons.movie_creation_outlined, color: Colors.white24, size: 36),
                            ),
                          )
                        : const Center(
                            child: Icon(Icons.movie_creation_outlined, color: Colors.white24, size: 36),
                          ),
                  ),

                  // Bottom badge: Episode number or Type
                  Positioned(
                    bottom: 6,
                    right: 6,
                    left: 6,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (item.episodeNumber != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              'الحلقة ${item.episodeNumber}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          )
                        else if (item.isMovie)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.deepPurpleAccent.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: const Text(
                              'فيلم',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          )
                        else
                          const SizedBox.shrink(),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // No title under the poster: the poster is the card.
          ],
        ),
      ),
    );
  }
}
