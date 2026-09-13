import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/core/constants/app_theme.dart';
import 'package:youtube_downloader/core/utils/formatters.dart';
import 'package:youtube_downloader/features/home/presentation/widgets/video_download_dialog.dart';
import 'package:youtube_downloader/features/watch/domain/watch_models.dart';
import 'package:youtube_downloader/features/watch/presentation/providers/watch_provider.dart';
import '../../domain/series_models.dart';
import '../providers/series_provider.dart';

class SeriesEpisodeCard extends ConsumerStatefulWidget {
  final EpisodeItem episode;

  const SeriesEpisodeCard({super.key, required this.episode});

  @override
  ConsumerState<SeriesEpisodeCard> createState() => _SeriesEpisodeCardState();
}

class _SeriesEpisodeCardState extends ConsumerState<SeriesEpisodeCard>
    with AutomaticKeepAliveClientMixin {
  bool _isHovered = false;

  @override
  bool get wantKeepAlive => true;

  void _watchEpisode(BuildContext context) {
    final seriesState = ref.read(seriesProvider);
    final episodes = seriesState.currentSeasonEpisodes;
    final seriesTitle = seriesState.seriesModel?.seriesName ?? seriesState.query;
    final currentIndex = episodes.indexWhere((e) => e.episodeNumber == widget.episode.episodeNumber);

    final items = episodes.map((e) => PlayableItem.fromEpisode(
      e,
      seriesName: seriesTitle,
    )).toList();

    final playlistContext = WatchPlaylistContext(
      title: seriesTitle.isNotEmpty ? 'مسلسل $seriesTitle' : 'حلقات المسلسل',
      items: items,
      currentIndex: currentIndex >= 0 ? currentIndex : 0,
    );

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
    final ep = widget.episode;
    final video = ep.primaryVideo;
    final isSelected = ref.watch(seriesProvider).selectedEpisodeNumbers.contains(ep.episodeNumber);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: BorderRadius.circular(AppTheme.borderRadius),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : (_isHovered
                    ? AppColors.primary.withOpacity(0.5)
                    : (isDark ? AppColors.darkBorder : AppColors.lightBorder)),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(_isHovered ? 0.12 : (isDark ? 0.2 : 0.03)),
              blurRadius: _isHovered ? 12 : 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.borderRadius),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 16:9 Thumbnail with Duration, Episode Badge & Click-to-Watch
              AspectRatio(
                aspectRatio: 16 / 9,
                child: GestureDetector(
                  onTap: () => _watchEpisode(context),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
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

                      // Hover darken
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 150),
                        opacity: _isHovered ? 0.35 : 0.0,
                        child: Container(color: Colors.black),
                      ),

                      // Center Play Button on hover
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

                      // Checkbox for selection (top right)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Checkbox(
                            value: isSelected,
                            activeColor: AppColors.primary,
                            onChanged: (_) {
                              ref.read(seriesProvider.notifier).toggleEpisodeSelection(ep.episodeNumber);
                            },
                          ),
                        ),
                      ),

                      // Episode Number Pill (top left)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.primary, Color(0xFFCC0000)],
                            ),
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.4),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.play_circle_fill_rounded, size: 13, color: Colors.white),
                              const SizedBox(width: 4),
                              Text(
                                'الحلقة ${ep.episodeNumber}',
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

                      // Duration badge (bottom right)
                      if (video.duration != null)
                        Positioned(
                          bottom: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.8),
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
                    ],
                  ),
                ),
              ),

              // Info Section
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Video Title
                      Text(
                        video.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5,
                              height: 1.25,
                            ),
                      ),

                      // Uploader / Channel Source & Alternatives Switcher
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: AppColors.primaryContainer,
                            child: Text(
                              video.author.isNotEmpty ? video.author.substring(0, 1).toUpperCase() : 'Y',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              video.author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Bottom actions: Alternatives popup + Watch + Download Button
                      Row(
                        children: [
                          if (ep.alternativeVideos.isNotEmpty)
                            PopupMenuButton<Video>(
                              tooltip: 'تغيير القناة المصدر (${ep.totalSources} مصادر متاحة)',
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              onSelected: (selectedVideo) {
                                ref.read(seriesProvider.notifier).switchEpisodeSource(ep.episodeNumber, selectedVideo);
                              },
                              itemBuilder: (ctx) => [
                                PopupMenuItem(
                                  enabled: false,
                                  child: Text(
                                    'اختر القناة المصدر للحلقة ${ep.episodeNumber}:',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ),
                                PopupMenuItem(
                                  value: ep.primaryVideo,
                                  child: Row(
                                    children: [
                                      const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 16),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          '${ep.primaryVideo.author} (الحالية)',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                ...ep.alternativeVideos.map(
                                  (alt) => PopupMenuItem(
                                    value: alt,
                                    child: Row(
                                      children: [
                                        const Icon(Icons.radio_button_unchecked, size: 16),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            alt.author,
                                            style: const TextStyle(fontSize: 12),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.layers_rounded, size: 13, color: AppColors.primary),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${ep.totalSources} قنوات',
                                      style: const TextStyle(
                                        color: AppColors.primary,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          const Spacer(),
                          // Watch Episode Button
                          ElevatedButton.icon(
                            onPressed: () => _watchEpisode(context),
                            icon: const Icon(Icons.play_arrow_rounded, size: 16),
                            label: const Text('مشاهدة', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Instant Download Button
                          IconButton.filledTonal(
                            icon: const Icon(Icons.download_rounded, size: 17),
                            tooltip: 'تنزيل الحلقة ${ep.episodeNumber}',
                            style: IconButton.styleFrom(
                              backgroundColor: AppColors.primary.withOpacity(0.12),
                              foregroundColor: AppColors.primary,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.all(6),
                            ),
                            onPressed: () => VideoDownloadDialog.show(context, video),
                          ),
                        ],
                      ),
                    ],
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
