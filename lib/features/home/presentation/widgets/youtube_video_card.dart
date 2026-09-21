import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';
import 'package:youtube_downloader/core/network/image_cache.dart';
import 'package:youtube_downloader/core/utils/formatters.dart';
import 'package:youtube_downloader/features/home/presentation/providers/youtube_feed_provider.dart';
import 'package:youtube_downloader/features/home/presentation/widgets/inline_youtube_preview.dart';
import 'package:youtube_downloader/features/trailers/data/trailer_stream_resolver.dart';
import 'package:youtube_downloader/features/watch/domain/watch_models.dart';
import 'package:youtube_downloader/features/watch/presentation/providers/watch_provider.dart';
import 'package:youtube_downloader/features/watch/presentation/widgets/mobile_youtube_player.dart';
import 'package:youtube_downloader/features/watch/presentation/widgets/windows_youtube_player.dart';

class YouTubeVideoCard extends ConsumerStatefulWidget {
  final Video video;
  final List<Video>? playlist;
  final int? playlistIndex;

  const YouTubeVideoCard({
    super.key,
    required this.video,
    this.playlist,
    this.playlistIndex,
  });

  @override
  ConsumerState<YouTubeVideoCard> createState() => _YouTubeVideoCardState();
}

class _YouTubeVideoCardState extends ConsumerState<YouTubeVideoCard>
    with AutomaticKeepAliveClientMixin {
  bool _isHovered = false;

  /// Set when the direct stream could not be played: the card then falls
  /// back to the embedded player for this video.
  bool _nativeFailed = false;
  String? _prewarmedFor;

  /// While this card plays, the next two in the list get their streams
  /// resolved, so moving on starts at once.
  void _prewarmNeighbours() {
    final list = widget.playlist;
    final i = widget.playlistIndex;
    if (list == null || i == null || _prewarmedFor == widget.video.id.value) return;
    _prewarmedFor = widget.video.id.value;
    final next = list.skip(i + 1).take(2).map((v) => v.id.value);
    TrailerStreamResolver.instance.prewarm(next);
  }

  @override
  bool get wantKeepAlive => true;

  void _openWatch(BuildContext context) {
    WatchPlaylistContext? playlistContext;
    if (widget.playlist != null && widget.playlist!.isNotEmpty) {
      final items = widget.playlist!.map((v) => PlayableItem.fromVideo(v)).toList();
      playlistContext = WatchPlaylistContext(
        title: 'قائمة الفيديوهات',
        items: items,
        currentIndex: widget.playlistIndex ?? 0,
      );
    } else {
      playlistContext = WatchPlaylistContext(
        title: 'مشاهدة',
        items: [PlayableItem.fromVideo(widget.video)],
        currentIndex: 0,
      );
    }

    ref.read(watchProvider.notifier).loadAndPlay(
      playlistContext.items[playlistContext.currentIndex],
      playlistContext: playlistContext,
    );
    context.push('/watch');
  }

  void _onCardTap(BuildContext context, bool isActive) {
    if (!isActive) {
      ref.read(activeYouTubeCardIdProvider.notifier).state = widget.video.id.value;
    } else {
      _openWatch(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = AppPalette.of(context);
    final video = widget.video;

    final activeVideoId = ref.watch(activeYouTubeCardIdProvider);
    final isActive = (activeVideoId == video.id.value);
    if (isActive) _prewarmNeighbours();

    return RepaintBoundary(
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _onCardTap(context, isActive),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF151515) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive
                  ? AppColors.primary
                  : (_isHovered
                      ? AppColors.primary.withOpacity(0.5)
                      : (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06))),
              width: isActive ? 1.5 : 1.0,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.18),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 16:9 Thumbnail or Inline Player with compact height
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Active inline player: our own (direct stream, no
                      // iframe chrome), with the embedded player only as a
                      // fallback when no direct stream can be played.
                      if (isActive)
                        _nativeFailed
                            ? (Platform.isWindows
                                ? WindowsYouTubePlayer(videoId: video.id.value)
                                : MobileYouTubePlayer(videoId: video.id.value))
                            : InlineYouTubePreview(
                                key: ValueKey('preview-${video.id.value}'),
                                videoId: video.id.value,
                                thumbnailUrl: 'https://i.ytimg.com/vi/${video.id.value}/hqdefault.jpg',
                                onFailed: () {
                                  if (mounted) setState(() => _nativeFailed = true);
                                },
                              )
                      else
                        // Thumbnail Image: kept on disk, so a card seen once
                        // is simply there next time.
                        CachedNetworkImage(
                          imageUrl: 'https://i.ytimg.com/vi/${video.id.value}/hqdefault.jpg',
                          cacheManager: appImageCache,
                          fit: BoxFit.cover,
                          memCacheWidth: 480,
                          filterQuality: FilterQuality.medium,
                          fadeInDuration: Duration.zero,
                          fadeOutDuration: Duration.zero,
                          placeholderFadeInDuration: Duration.zero,
                          useOldImageOnUrlChange: true,
                          placeholder: (_, __) => ColoredBox(
                            color: isDark ? AppColors.darkSecondaryBg : palette.skeleton,
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: isDark ? AppColors.darkSecondaryBg : palette.skeleton,
                            child: const Center(
                              child: Icon(Icons.videocam_rounded, color: AppColors.primary, size: 30),
                            ),
                          ),
                        ),

                      // Inactive state overlay + Play icon + Duration badge
                      if (!isActive) ...[
                        // Subtle darken on hover
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 150),
                          opacity: _isHovered ? 0.25 : 0.0,
                          child: Container(color: Colors.black),
                        ),

                        // Center Play Button
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withOpacity(_isHovered ? 0.8 : 0.45),
                              border: Border.all(color: Colors.white24, width: 1),
                            ),
                            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                          ),
                        ),

                        // Duration badge (bottom right)
                        if (video.duration != null)
                          Positioned(
                            bottom: 5,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.85),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                Formatters.formatDuration(video.duration),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ),
                      ],

                      // Active State badges (Live Preview indicator + Open Fullscreen)
                      if (isActive) ...[
                        Positioned(
                          top: 6,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.78),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.primary.withOpacity(0.7), width: 0.8),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.circle, color: Colors.redAccent, size: 6.5),
                                SizedBox(width: 4),
                                Text(
                                  'معاينة مباشرة',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          top: 6,
                          left: 8,
                          child: GestureDetector(
                            onTap: () => _openWatch(context),
                            child: Container(
                              padding: const EdgeInsets.all(4.5),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.75),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.fullscreen_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Compact, Elegant Video Info Section
                Padding(
                  padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Channel Avatar with modern gradient
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFE50914), Color(0xFF990000)],
                          ),
                          border: Border.all(color: Colors.white12, width: 0.8),
                        ),
                        child: Center(
                          child: Text(
                            video.author.isNotEmpty ? video.author.characters.first.toUpperCase() : 'Y',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Title & Channel Metadata
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              video.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                height: 1.25,
                                color: isDark ? const Color(0xFFF1F1F1) : const Color(0xFF111111),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    video.author,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w500,
                                      color: isDark ? const Color(0xFFAAAAAA) : const Color(0xFF666666),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.check_circle_rounded,
                                  size: 10.5,
                                  color: isDark ? Colors.white38 : Colors.black38,
                                ),
                                if (video.duration != null) ...[
                                  Text(
                                    ' • ',
                                    style: TextStyle(
                                      color: isDark ? Colors.white38 : Colors.black38,
                                      fontSize: 10,
                                    ),
                                  ),
                                  Text(
                                    Formatters.formatDuration(video.duration),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                      color: isDark ? const Color(0xFF888888) : const Color(0xFF777777),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Direct Full Watch Icon Button
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                        icon: Icon(
                          Icons.open_in_new_rounded,
                          size: 14.5,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                        tooltip: 'مشاهدة كاملة',
                        onPressed: () => _openWatch(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
}
