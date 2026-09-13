import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import '../../data/models/cinemana_models.dart';
import '../providers/cinemana_provider.dart';
import 'package:youtube_downloader/presentation/widgets/favorite_toast.dart';
import 'package:youtube_downloader/presentation/widgets/reveal.dart';
import 'package:youtube_downloader/core/video/desktop_video.dart';

class CinemanaPosterCard extends ConsumerStatefulWidget {
  final CinemanaItem item;
  final VoidCallback onTap;

  const CinemanaPosterCard({
    super.key,
    required this.item,
    required this.onTap,
  });

  @override
  ConsumerState<CinemanaPosterCard> createState() => _CinemanaPosterCardState();
}

class _CinemanaPosterCardState extends ConsumerState<CinemanaPosterCard>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rating = double.tryParse(widget.item.stars) ?? 0.0;
    final favorites = ref.watch(cinemanaFavoritesProvider);
    final isFav = favorites.any((it) => it.id == widget.item.id);

    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Poster with Badges and Favorite Heart
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF22222B) : const Color(0xFFE5E5EB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? const Color(0xFF33333F) : const Color(0xFFE0E0E6),
                        width: 1,
                      ),
                    ),
                    child: widget.item.cardImageUrl.isNotEmpty
                        ? LayoutBuilder(builder: (context, box) {
                            // Sized to the card as actually drawn: the medium
                            // poster on a phone, the full one when a wide window
                            // draws the card larger than the medium poster is.
                            final px = box.maxWidth * MediaQuery.of(context).devicePixelRatio;
                            return CachedNetworkImage(
                            imageUrl: widget.item.imageForWidth(px, hiRes: preferFullArtwork),
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.high,
                            // Decode at twice the card, capped, so downscaling
                            // the full poster keeps crisp edges.
                            memCacheWidth: px.isFinite && px > 0 ? (px * 2).clamp(200, 900).round() : null,
                            // The poster settles in from its shimmer rather
                            // than blinking into place.
                            fadeInDuration: Duration.zero,
                            fadeOutDuration: Duration.zero,
                            imageBuilder: (_, provider) => RevealImage(
                              child: Image(
                                image: provider,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                              ),
                            ),
                            placeholder: (_, __) => Shimmer(
                              base: isDark ? const Color(0xFF141926) : const Color(0xFFE6EAF2),
                              highlight: isDark ? const Color(0xFF1E2636) : const Color(0xFFF4F7FC),
                              child: const SizedBox.expand(),
                            ),
                            errorWidget: (_, __, ___) => _buildPlaceholder(isDark),
                          );
                          })
                        : _buildPlaceholder(isDark),
                  ),
                ),

                // Rating Badge (Top-Start)
                if (rating > 0)
                  PositionedDirectional(
                    top: 8,
                    start: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.78),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.amber.withOpacity(0.6),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded, size: 13, color: Colors.amber),
                          const SizedBox(width: 3),
                          Text(
                            widget.item.stars,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Type Badge (Top-End)
                PositionedDirectional(
                  top: 8,
                  end: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: widget.item.isSeries
                          ? const Color(0xFF1976D2).withOpacity(0.85)
                          : AppColors.primary.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      widget.item.isSeries ? 'مسلسل' : 'فيلم',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                // Favorite Heart Button (Bottom-End)
                PositionedDirectional(
                  bottom: 8,
                  end: 8,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        ref
                            .read(cinemanaFavoritesProvider.notifier)
                            .toggleFavorite(widget.item);
                        showFavoriteToast(context, added: !isFav);
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isFav
                              ? Colors.red.withOpacity(0.9)
                              : Colors.black.withOpacity(0.6),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isFav ? Colors.redAccent : Colors.white24,
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                            size: 17,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 6),

          // Title
          Text(
            widget.item.displayTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF111114),
            ),
          ),

          // Year and Genre
          Text(
            [
              if (widget.item.year.isNotEmpty) widget.item.year,
              if (widget.item.categories.isNotEmpty) widget.item.categories.take(2).join('، '),
            ].join(' • '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder(bool isDark) {
    return Center(
      child: Icon(
        Icons.movie_outlined,
        size: 40,
        color: isDark ? Colors.white24 : Colors.black26,
      ),
    );
  }
}
