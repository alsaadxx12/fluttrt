import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';
import 'package:youtube_downloader/core/constants/app_theme.dart';
import 'package:youtube_downloader/features/downloads/presentation/providers/downloads_provider.dart';
import '../../domain/series_models.dart';
import '../providers/series_provider.dart';

class BatchDownloadDialog extends ConsumerStatefulWidget {
  final SeriesModel series;
  final List<EpisodeItem> episodesToDownload;

  const BatchDownloadDialog({
    super.key,
    required this.series,
    required this.episodesToDownload,
  });

  static Future<void> show(BuildContext context, SeriesModel series, List<EpisodeItem> episodes) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => BatchDownloadDialog(series: series, episodesToDownload: episodes),
    );
  }

  @override
  ConsumerState<BatchDownloadDialog> createState() => _BatchDownloadDialogState();
}

class _BatchDownloadDialogState extends ConsumerState<BatchDownloadDialog> {
  String _selectedQuality = '720p';
  String _selectedFormat = 'mp4';
  bool _isStarting = false;

  final List<String> _qualityOptions = ['1080p', '720p', '480p', '360p', 'MP3 (صوت)'];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = AppPalette.of(context);
    final totalEps = widget.episodesToDownload.length;

    return Dialog(
      backgroundColor: isDark ? AppColors.darkCard : AppColors.lightCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.borderRadius),
        side: BorderSide(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 500,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.video_library_rounded, color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'تنزيل مجمع لحلقات المسلسل',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          widget.series.seriesName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Middle Scrollable Area
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Summary banner
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkSecondaryBg : AppColors.lightSecondaryBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                          boxShadow: palette.cardShadow,
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.playlist_play_rounded, color: AppColors.primary, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'تم تحديد $totalEps حلقة للتحميل المتتابع',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Quality Choice
                      const Text(
                        'اختر الجودة الموحدة لجميع الحلقات:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _qualityOptions.map((q) {
                          final isSelected = _selectedQuality == q;
                          return ChoiceChip(
                            label: Text(q),
                            selected: isSelected,
                            selectedColor: AppColors.primary,
                            backgroundColor: isDark ? AppColors.darkSecondaryBg : AppColors.lightSecondaryBg,
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.white : (isDark ? Colors.white : Colors.black87),
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              fontSize: 12,
                            ),
                            side: BorderSide(
                              color: isSelected ? AppColors.primary : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                            ),
                            onSelected: (selected) {
                              if (selected) {
                                setState(() {
                                  _selectedQuality = q;
                                  if (q.contains('MP3')) {
                                    _selectedFormat = 'mp3';
                                  } else {
                                    _selectedFormat = 'mp4';
                                  }
                                });
                              }
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Action button (Pinned)
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _isStarting
                      ? null
                      : () async {
                          setState(() => _isStarting = true);
                          final downloadsNotifier = ref.read(downloadsProvider.notifier);
                          final seriesNotifier = ref.read(seriesProvider.notifier);

                          await seriesNotifier.startBatchDownload(
                            episodes: widget.episodesToDownload,
                            qualityLabel: _selectedQuality,
                            format: _selectedFormat,
                            downloadsNotifier: downloadsNotifier,
                          );

                          if (context.mounted) {
                            Navigator.pop(context);
                          }
                        },
                  icon: _isStarting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.download_for_offline_rounded, size: 20),
                  label: Text(
                    _isStarting ? 'جاري إضافة الحلقات...' : 'بدء تنزيل $totalEps حلقة دفعة واحدة',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
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
