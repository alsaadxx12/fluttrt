import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/core/constants/app_theme.dart';
import 'package:youtube_downloader/core/utils/file_utils.dart';
import 'package:youtube_downloader/features/downloads/data/models/download_task_model.dart';
import 'package:youtube_downloader/features/downloads/presentation/providers/downloads_provider.dart';
import 'package:youtube_downloader/features/settings/presentation/providers/settings_provider.dart';
import 'package:youtube_downloader/features/home/presentation/providers/video_analyzer_provider.dart';

class QualitySelector extends ConsumerWidget {
  const QualitySelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyzerState = ref.watch(analyzerProvider);
    final strings = ref.watch(stringsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final result = analyzerState.result;

    if (result == null) return const SizedBox.shrink();

    final isAudio = analyzerState.selectedType == DownloadType.audio;

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(AppTheme.borderRadius),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Segmented Control: Video / Audio
          Row(
            children: [
              Text(
                strings.selectType,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              SegmentedButton<DownloadType>(
                segments: [
                  ButtonSegment<DownloadType>(
                    value: DownloadType.video,
                    label: Text(strings.video),
                    icon: const Icon(Icons.videocam_rounded, size: 18),
                  ),
                  ButtonSegment<DownloadType>(
                    value: DownloadType.audio,
                    label: Text(strings.audio),
                    icon: const Icon(Icons.music_note_rounded, size: 18),
                  ),
                ],
                selected: {analyzerState.selectedType},
                onSelectionChanged: (Set<DownloadType> selection) {
                  ref.read(analyzerProvider.notifier).setType(selection.first);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 14),

          // Quality Options List
          if (!isAudio) ...[
            Text(
              strings.selectQuality,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: result.videoQualities.map((q) {
                final isSelected = analyzerState.selectedVideoQuality?.tag == q.tag;
                return ChoiceChip(
                  label: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          q.label,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : (isDark ? Colors.white : AppColors.lightTextPrimary),
                          ),
                        ),
                        if (q.approximateSizeBytes > 0)
                          Text(
                            FileUtils.formatBytes(q.approximateSizeBytes),
                            style: TextStyle(
                              fontSize: 10,
                              color: isSelected ? Colors.white70 : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                            ),
                          ),
                      ],
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: AppColors.primary,
                  backgroundColor: isDark ? AppColors.darkSecondaryBg : AppColors.lightSecondaryBg,
                  side: BorderSide(
                    color: isSelected
                        ? AppColors.primary
                        : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                  ),
                  onSelected: (selected) {
                    if (selected) {
                      ref.read(analyzerProvider.notifier).selectVideoQuality(q);
                    }
                  },
                );
              }).toList(),
            ),
          ] else ...[
            Text(
              strings.selectAudioFormat,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: result.audioQualities.map((a) {
                final isSelected = analyzerState.selectedAudioQuality?.label == a.label &&
                    analyzerState.selectedAudioQuality?.format == a.format;
                return ChoiceChip(
                  label: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          a.label,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : (isDark ? Colors.white : AppColors.lightTextPrimary),
                          ),
                        ),
                        if (a.approximateSizeBytes > 0)
                          Text(
                            FileUtils.formatBytes(a.approximateSizeBytes),
                            style: TextStyle(
                              fontSize: 10,
                              color: isSelected ? Colors.white70 : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                            ),
                          ),
                      ],
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: AppColors.primary,
                  backgroundColor: isDark ? AppColors.darkSecondaryBg : AppColors.lightSecondaryBg,
                  side: BorderSide(
                    color: isSelected
                        ? AppColors.primary
                        : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                  ),
                  onSelected: (selected) {
                    if (selected) {
                      ref.read(analyzerProvider.notifier).selectAudioQuality(a);
                    }
                  },
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 18),

          // Main Download Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () async {
                if (isAudio) {
                  final audio = analyzerState.selectedAudioQuality;
                  if (audio != null) {
                    await ref.read(downloadsProvider.notifier).startDownload(
                          video: result,
                          streamInfo: audio.streamInfo,
                          type: DownloadType.audio,
                          qualityLabel: audio.label,
                          format: audio.format,
                        );
                  }
                } else {
                  final videoQ = analyzerState.selectedVideoQuality;
                  if (videoQ != null) {
                    await ref.read(downloadsProvider.notifier).startDownload(
                          video: result,
                          streamInfo: videoQ.streamInfo,
                          type: DownloadType.video,
                          qualityLabel: videoQ.label,
                          format: videoQ.container,
                        );
                  }
                }


              },
              icon: const Icon(Icons.download_rounded, size: 22),
              label: Text(
                strings.startDownload,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
