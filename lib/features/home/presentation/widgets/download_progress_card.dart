import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/core/constants/app_theme.dart';
import 'package:youtube_downloader/core/services/file_opener_service.dart';
import 'package:youtube_downloader/core/utils/file_utils.dart';
import 'package:youtube_downloader/core/utils/formatters.dart';
import 'package:youtube_downloader/features/downloads/data/models/download_task_model.dart';
import 'package:youtube_downloader/features/downloads/presentation/providers/downloads_provider.dart';
import 'package:youtube_downloader/features/settings/presentation/providers/settings_provider.dart';

class DownloadProgressCard extends ConsumerWidget {
  final DownloadTaskModel task;

  const DownloadProgressCard({super.key, required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);
    final settings = ref.watch(settingsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final isDone = task.status == DownloadStatus.completed;
    final isPaused = task.status == DownloadStatus.paused;
    final isFailed = task.status == DownloadStatus.failed;
    final isCancelled = task.status == DownloadStatus.cancelled;
    final isDownloading = task.status == DownloadStatus.downloading;

    final percentInt = (task.progress * 100).toInt();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(AppTheme.borderRadius),
        border: Border.all(
          color: isDone
              ? AppColors.success.withOpacity(0.4)
              : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Upper Row: Mini thumbnail, title, and action icons
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 52,
                  height: 38,
                  child: Image.network(
                    task.thumbnailUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: isDark ? AppColors.darkSecondaryBg : AppColors.lightSecondaryBg,
                      child: const Icon(Icons.video_library_rounded, size: 20, color: AppColors.primary),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${task.qualityLabel} • ${task.format.toUpperCase()} • ${task.author}',
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
              const SizedBox(width: 8),
              // Action buttons: Pause/Resume, Cancel
              if (!isDone && !isFailed && !isCancelled) ...[
                if (isDownloading)
                  IconButton(
                    icon: const Icon(Icons.pause_rounded, size: 20),
                    tooltip: strings.pause,
                    onPressed: () => ref.read(downloadsProvider.notifier).pauseTask(task.id),
                  )
                else if (isPaused)
                  IconButton(
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    tooltip: strings.resume,
                    onPressed: () => ref.read(downloadsProvider.notifier).resumeTask(task.id),
                  ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  tooltip: strings.cancel,
                  onPressed: () => ref.read(downloadsProvider.notifier).cancelTask(task.id),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),

          // Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: isDone ? 1.0 : task.progress,
              minHeight: 6,
              backgroundColor: isDark ? AppColors.darkSecondaryBg : AppColors.lightSecondaryBg,
              valueColor: AlwaysStoppedAnimation<Color>(
                isDone
                    ? AppColors.success
                    : (isFailed ? AppColors.error : AppColors.primary),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Status and Metrics
          if (isDone) ...[
            Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
                const SizedBox(width: 6),
                Text(
                  strings.downloadCompleted,
                  style: const TextStyle(
                    color: AppColors.success,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => FileOpenerService.openFile(task.filePath),
                  icon: const Icon(Icons.play_circle_outline_rounded, size: 16),
                  label: Text(strings.openFile, style: const TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  ),
                ),
                const SizedBox(width: 6),
                TextButton.icon(
                  onPressed: () => FileOpenerService.openFolder(task.filePath),
                  icon: const Icon(Icons.folder_open_rounded, size: 16),
                  label: Text(strings.openFolder, style: const TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  ),
                ),
              ],
            ),
          ] else if (isFailed) ...[
            Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    task.errorMessage ?? strings.downloadFailed,
                    style: const TextStyle(color: AppColors.error, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$percentInt% (${FileUtils.formatBytes(task.downloadedBytes)} / ${FileUtils.formatBytes(task.totalBytes)})',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                Row(
                  children: [
                    if (isDownloading && task.speedBytesPerSec > 0) ...[
                      Text(
                        Formatters.formatSpeed(task.speedBytesPerSec),
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('•', style: TextStyle(color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary)),
                      const SizedBox(width: 8),
                    ],
                    if (isDownloading && task.eta != null) ...[
                      Text(
                        Formatters.formatRemainingTime(task.eta!, settings.language),
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        ),
                      ),
                    ] else if (isPaused) ...[
                      Text(
                        strings.downloadPaused,
                        style: const TextStyle(color: AppColors.warning, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
