import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';
import 'package:youtube_downloader/core/network/image_cache.dart';
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
    final palette = AppPalette.of(context);
    final rating = double.tryParse(widget.item.stars) ?? 0.0;
    final favorites = ref.watch(cinemanaFavoritesProvider);
    final isFav = favorites.any((it) => it.id == widget.item.id);

    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Poster with Badges and Favorite Heart
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    decoration: BoxDecoration(
                      // Loading placeholder behind the poster: the palette's
                      // skeleton tone, so it still shows on the white page.
                      color: isDark ? const Color(0xFF22222B) : palette.skeleton,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isDark ? const Color(0xFF33333F) : palette.border,
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
                            cacheManager: appImageCache,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.high,
                            // Decode at the card's own pixel size, capped.
                            memCacheWidth: px.isFinite && px > 0 ? px.clamp(200, 600).round() : null,
                            // A cached poster is simply there: no fade, no
                            // settle, and the old picture stays up while a
                            // resized card swaps its URL.
                            fadeInDuration: Duration.zero,
                            fadeOutDuration: Duration.zero,
                            placeholderFadeInDuration: Duration.zero,
                            useOldImageOnUrlChange: true,
                            placeholder: (_, __) => Shimmer(
                              base: isDark ? const Color(0xFF141926) : palette.skeleton,
                              highlight: isDark ? const Color(0xFF1E2636) : Colors.white,
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
                      borderRadius: BorderRadius.circular(10),
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

          // No words under the poster: the poster is the card, and the
          // page that opens says the rest.
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
