import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';
import 'package:youtube_downloader/core/network/image_cache.dart';
import '../../data/models/cinemana_models.dart';
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

class _CinemanaPosterCardState extends ConsumerState<CinemanaPosterCard> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = AppPalette.of(context);

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
                  // One layer, then the clip: the picture and its shading are
                  // composited before the rounded edge is applied, so the
                  // half-pixel bottom row is shaded like every other row.
                  clipBehavior: Clip.antiAliasWithSaveLayer,
                  child: Container(
                    decoration: BoxDecoration(
                      // Loading placeholder behind the poster: the palette's
                      // skeleton tone, so it still shows on the white page.
                      color: isDark ? const Color(0xFF22222B) : palette.skeleton,
                      borderRadius: BorderRadius.circular(6),
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
