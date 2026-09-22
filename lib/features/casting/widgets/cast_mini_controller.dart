import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:youtube_downloader/core/constants/app_palette.dart';
import 'package:youtube_downloader/core/network/image_cache.dart';
import '../controllers/cast_controller.dart';
import 'cast_remote_page.dart';

/// The strip that sits above the bottom bar while something plays on
/// another screen: what is on, where, and a way to pause or stop it.
///
/// It takes no room at all when nothing is casting, so it can sit in the
/// scaffold permanently.
class CastMiniController extends ConsumerWidget {
  const CastMiniController({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cast = ref.watch(castControllerProvider);
    if (!cast.hasMedia) return const SizedBox.shrink();

    final p = AppPalette.of(context);
    final media = cast.media!;
    final notifier = ref.read(castControllerProvider.notifier);
    final total = cast.duration ?? Duration.zero;
    final progress = total.inMilliseconds <= 0
        ? 0.0
        : (cast.position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

    return Material(
      color: p.card,
      child: InkWell(
        onTap: () => CastRemotePage.open(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!media.isLive)
              LinearProgressIndicator(
                value: progress,
                minHeight: 2,
                backgroundColor: p.border,
                valueColor: const AlwaysStoppedAnimation(Color(0xFFE50914)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 34,
                      height: 44,
                      child: media.posterUrl.isEmpty
                          ? ColoredBox(
                              color: p.cardAlt,
                              child: Icon(Icons.movie_rounded, color: p.textFaint, size: 18),
                            )
                          : CachedNetworkImage(
                              imageUrl: media.posterUrl,
                              cacheManager: appImageCache,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => ColoredBox(color: p.cardAlt),
                              errorWidget: (_, __, ___) => ColoredBox(color: p.cardAlt),
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          media.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: p.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.cast_connected_rounded,
                                color: Color(0xFFE50914), size: 12),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                cast.device!.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: p.textMuted, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: notifier.togglePlay,
                    icon: Icon(
                      cast.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: p.text,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    onPressed: notifier.stopMedia,
                    icon: Icon(Icons.stop_rounded, color: p.textMuted),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
