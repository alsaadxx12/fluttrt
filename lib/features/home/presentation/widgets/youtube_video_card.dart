import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/core/constants/app_theme.dart';
import 'package:youtube_downloader/core/utils/formatters.dart';
import 'package:youtube_downloader/features/watch/domain/watch_models.dart';
import 'package:youtube_downloader/features/watch/presentation/providers/watch_provider.dart';
import 'package:youtube_downloader/features/watch/presentation/widgets/windows_youtube_player.dart';
import 'video_download_dialog.dart';

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
  Timer? _hoverTimer;
  bool _isPlayingPreview = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _hoverTimer?.cancel();
    super.dispose();
  }

  void _onHoverEnter() {
    setState(() => _isHovered = true);
    if (Platform.isWindows) {
      _hoverTimer?.cancel();
      _hoverTimer = Timer(const Duration(milliseconds: 650), () {
        if (mounted && _isHovered) {
          setState(() => _isPlayingPreview = true);
        }
      });
    }
  }

  void _onHoverExit() {
    _hoverTimer?.cancel();
    setState(() {
      _isHovered = false;
      _isPlayingPreview = false;
    });
  }

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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final video = widget.video;

    return MouseRegion(
      onEnter: (_) => _onHoverEnter(),
      onExit: (_) => _onHoverExit(),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _openWatch(context),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : AppColors.lightCard,
            borderRadius: BorderRadius.circular(AppTheme.borderRadius),
            border: Border.all(
              color: _isHovered
                  ? AppColors.primary.withOpacity(0.6)
                  : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(_isHovered ? 0.14 : (isDark ? 0.2 : 0.03)),
                blurRadius: _isHovered ? 14 : 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.borderRadius),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 16:9 Thumbnail with Duration, Hover Play Button & Download Badge
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (Platform.isWindows && _isPlayingPreview)
                        WindowsYouTubePlayer(
                          videoId: video.id.value,
                        )
                      else
                        Image.network(
                          'https://i.ytimg.com/vi/${video.id.value}/maxresdefault.jpg',
                          fit: BoxFit.cover,
                          cacheWidth: 480,
                          filterQuality: FilterQuality.medium,
                          errorBuilder: (_, __, ___) => Image.network(
                            'https://i.ytimg.com/vi/${video.id.value}/hqdefault.jpg',
                            fit: BoxFit.cover,
                            cacheWidth: 480,
                            filterQuality: FilterQuality.medium,
                            errorBuilder: (_, __, ___) => Image.network(
                              video.thumbnails.highResUrl.isNotEmpty
                                  ? video.thumbnails.highResUrl
                                  : video.thumbnails.standardResUrl,
                              fit: BoxFit.cover,
                              cacheWidth: 480,
                              filterQuality: FilterQuality.medium,
                              errorBuilder: (_, __, ___) => Container(
                                color: isDark ? AppColors.darkSecondaryBg : AppColors.lightSecondaryBg,
                                child: const Center(
                                  child: Icon(Icons.videocam_rounded, color: AppColors.primary, size: 36),
                                ),
                              ),
                            ),
                          ),
                        ),

                      // Hover darken overlay
                      if (!_isPlayingPreview)
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 150),
                          opacity: _isHovered ? 0.35 : 0.0,
                          child: Container(color: Colors.black),
                        ),

                      // Animated Center Play Icon on Hover
                      AnimatedScale(
                        duration: const Duration(milliseconds: 180),
                        scale: _isHovered ? 1.0 : 0.7,
                        curve: Curves.easeOutBack,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 150),
                          opacity: _isHovered ? 1.0 : 0.0,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.primary.withOpacity(0.92),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.4),
                                    blurRadius: 10,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                            ),
                          ),
                        ),
                      ),

                      // Duration badge (bottom right)
                      if (video.duration != null)
                        Positioned(
                          bottom: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.82),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              Formatters.formatDuration(video.duration),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),

                      // Clickable Download badge (top left)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => VideoDownloadDialog.show(context, video),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.download_rounded, color: Colors.white, size: 13),
                                  SizedBox(width: 4),
                                  Text(
                                    'تنزيل',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Video Info Section
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Channel Avatar Circle
                      CircleAvatar(
                        radius: 15,
                        backgroundColor: AppColors.primaryContainer,
                        child: Text(
                          video.author.isNotEmpty ? video.author.substring(0, 1).toUpperCase() : 'Y',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Title, Author, and Action Row
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              video.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                    height: 1.25,
                                  ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              video.author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
