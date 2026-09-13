import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/core/utils/file_utils.dart';
import 'package:youtube_downloader/core/utils/formatters.dart';
import 'package:youtube_downloader/features/downloads/data/models/download_task_model.dart';
import 'package:youtube_downloader/features/downloads/domain/download_service.dart';
import 'package:youtube_downloader/features/downloads/presentation/providers/downloads_provider.dart';
import 'package:youtube_downloader/features/settings/presentation/providers/settings_provider.dart';

class VideoDownloadDialog extends ConsumerStatefulWidget {
  final Video video;

  const VideoDownloadDialog({super.key, required this.video});

  static Future<void> show(BuildContext context, Video video) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => VideoDownloadDialog(video: video),
    );
  }

  static Future<void> showById(BuildContext context, String videoId) async {
    final ytClient = YoutubeExplode();
    try {
      final video = await ytClient.videos.get(videoId).timeout(const Duration(seconds: 5));
      if (context.mounted) {
        await show(context, video);
      }
    } catch (_) {
      // ignored
    } finally {
      ytClient.close();
    }
  }

  @override
  ConsumerState<VideoDownloadDialog> createState() => _VideoDownloadDialogState();
}

class _VideoDownloadDialogState extends ConsumerState<VideoDownloadDialog> {
  bool _isLoading = true;
  String? _error;
  VideoAnalysisResult? _analysis;

  DownloadType _type = DownloadType.video;
  VideoQualityOption? _selectedVideoQuality;
  AudioQualityOption? _selectedAudioQuality;

  @override
  void initState() {
    super.initState();
    _fetchAnalysis();
  }

  Future<void> _fetchAnalysis() async {
    final downloadService = ref.read(downloadServiceProvider);
    final rawUrl = widget.video.url.trim();
    final url = rawUrl.isNotEmpty
        ? rawUrl
        : 'https://www.youtube.com/watch?v=${widget.video.id.value}';

    try {
      final analysis = await downloadService.analyzeUrl(url).timeout(const Duration(seconds: 6));
      if (mounted) {
        VideoQualityOption? defaultVideo;
        for (final q in analysis.videoQualities) {
          if (q.isMuxed) {
            defaultVideo = q;
            break;
          }
        }
        defaultVideo ??= analysis.videoQualities.isNotEmpty ? analysis.videoQualities.first : null;

        setState(() {
          _analysis = analysis;
          _isLoading = false;
          _selectedVideoQuality = defaultVideo;
          _selectedAudioQuality = analysis.audioQualities.isNotEmpty
              ? analysis.audioQualities.first
              : null;
        });
      }
    } catch (e) {
      if (mounted) {
        final fallback = VideoAnalysisResult(
          id: widget.video.id.value,
          url: url,
          title: widget.video.title.isNotEmpty ? widget.video.title : 'فيديو',
          author: widget.video.author,
          duration: widget.video.duration,
          thumbnailUrl: widget.video.thumbnails.maxResUrl.isNotEmpty
              ? widget.video.thumbnails.maxResUrl
              : (widget.video.thumbnails.highResUrl.isNotEmpty
                  ? widget.video.thumbnails.highResUrl
                  : 'https://i.ytimg.com/vi/${widget.video.id.value}/hqdefault.jpg'),
          videoQualities: const [
            VideoQualityOption(label: '360p (فيديو + صوت)', tag: 18, approximateSizeBytes: 0, container: 'mp4', isMuxed: true),
          ],
          audioQualities: const [
            AudioQualityOption(label: '320 kbps (MP3)', format: 'mp3', bitrateKbps: 320, approximateSizeBytes: 0),
            AudioQualityOption(label: '128 kbps (M4A)', format: 'm4a', bitrateKbps: 128, approximateSizeBytes: 0),
          ],
          bestSizeBytes: 0,
        );

        setState(() {
          _analysis = fallback;
          _isLoading = false;
          _selectedVideoQuality = fallback.videoQualities.first;
          _selectedAudioQuality = fallback.audioQualities.first;
          _error = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(stringsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenHeight = MediaQuery.of(context).size.height;

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF16171E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isDark ? const Color(0xFF2B2C3A) : const Color(0xFFE2E4EE),
          width: 1.2,
        ),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: screenHeight * 0.86,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Header (Fixed at top)
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 18,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'خيارات التنزيل',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16.5,
                      color: isDark ? Colors.white : const Color(0xFF11141A),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: isDark ? Colors.white70 : Colors.black54,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // 2. Middle Scrollable Section (Never overflows)
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Video Summary Card
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1D1F2B) : const Color(0xFFF4F6FB),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? const Color(0xFF282B3B) : const Color(0xFFE3E6F0),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Stack(
                                children: [
                                  SizedBox(
                                    width: 80,
                                    height: 50,
                                    child: Image.network(
                                      'https://i.ytimg.com/vi/${widget.video.id.value}/hqdefault.jpg',
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Image.network(
                                        widget.video.thumbnails.highResUrl.isNotEmpty
                                            ? widget.video.thumbnails.highResUrl
                                            : 'https://i.ytimg.com/vi/${widget.video.id.value}/maxresdefault.jpg',
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                          color: isDark ? AppColors.darkSecondaryBg : AppColors.lightSecondaryBg,
                                          child: const Icon(Icons.videocam_rounded, color: AppColors.primary),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (widget.video.duration != null)
                                    Positioned(
                                      bottom: 3,
                                      right: 3,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.8),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          Formatters.formatDuration(widget.video.duration),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.video.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.5,
                                      height: 1.25,
                                      color: isDark ? Colors.white : const Color(0xFF11141A),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.video.author,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: isDark ? Colors.white60 : Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Loading State
                      if (_isLoading) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Center(
                            child: Column(
                              children: [
                                CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary),
                                SizedBox(height: 12),
                                Text(
                                  'جاري فحص الجودات ومسارات البث...',
                                  style: TextStyle(fontSize: 12.5),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ] else if (_error != null) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: AppColors.error, fontSize: 13),
                          ),
                        ),
                      ] else if (_analysis != null) ...[
                        // Type Segmented Switcher (Full Width)
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<DownloadType>(
                            style: ButtonStyle(
                              visualDensity: VisualDensity.compact,
                              padding: WidgetStateProperty.all(
                                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                            ),
                            segments: [
                              ButtonSegment(
                                value: DownloadType.video,
                                label: Text(strings.video),
                                icon: const Icon(Icons.videocam_rounded, size: 16),
                              ),
                              ButtonSegment(
                                value: DownloadType.audio,
                                label: Text(strings.audio),
                                icon: const Icon(Icons.music_note_rounded, size: 16),
                              ),
                            ],
                            selected: {_type},
                            onSelectionChanged: (set) => setState(() => _type = set.first),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Quality Choices Section
                        if (_type == DownloadType.video) ...[
                          Text(
                            strings.selectQuality,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _analysis!.videoQualities.map((q) {
                              final isSelected = _selectedVideoQuality?.tag == q.tag;
                              final muxedSuffix = q.isMuxed ? ' (صوت+صورة)' : '';
                              return ChoiceChip(
                                label: Text(
                                  '${q.label}$muxedSuffix ${q.approximateSizeBytes > 0 ? "(${FileUtils.formatBytes(q.approximateSizeBytes)})" : ""}',
                                ),
                                selected: isSelected,
                                selectedColor: AppColors.primary,
                                backgroundColor: isDark ? const Color(0xFF1F2230) : const Color(0xFFEEF1F6),
                                labelStyle: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected ? Colors.white : (isDark ? Colors.white : AppColors.lightTextPrimary),
                                ),
                                side: BorderSide(
                                  color: isSelected ? AppColors.primary : (isDark ? const Color(0xFF2E3246) : const Color(0xFFE0E3EC)),
                                ),
                                onSelected: (selected) {
                                  if (selected) {
                                    setState(() => _selectedVideoQuality = q);
                                  }
                                },
                              );
                            }).toList(),
                          ),
                        ] else ...[
                          Text(
                            strings.selectAudioFormat,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _analysis!.audioQualities.map((a) {
                              final isSelected = _selectedAudioQuality?.label == a.label &&
                                  _selectedAudioQuality?.format == a.format;
                              return ChoiceChip(
                                label: Text(
                                  '${a.label} ${a.approximateSizeBytes > 0 ? "(${FileUtils.formatBytes(a.approximateSizeBytes)})" : ""}',
                                ),
                                selected: isSelected,
                                selectedColor: AppColors.primary,
                                backgroundColor: isDark ? const Color(0xFF1F2230) : const Color(0xFFEEF1F6),
                                labelStyle: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected ? Colors.white : (isDark ? Colors.white : AppColors.lightTextPrimary),
                                ),
                                side: BorderSide(
                                  color: isSelected ? AppColors.primary : (isDark ? const Color(0xFF2E3246) : const Color(0xFFE0E3EC)),
                                ),
                                onSelected: (selected) {
                                  if (selected) {
                                    setState(() => _selectedAudioQuality = a);
                                  }
                                },
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),

              // 3. Pinned Action Button (Always inside window, never overflows)
              if (_analysis != null) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      if (_type == DownloadType.audio) {
                        final audio = _selectedAudioQuality;
                        if (audio != null) {
                          await ref.read(downloadsProvider.notifier).startDownload(
                                video: _analysis!,
                                streamInfo: audio.streamInfo,
                                type: DownloadType.audio,
                                qualityLabel: audio.label,
                                format: audio.format,
                              );
                        }
                      } else {
                        final videoQ = _selectedVideoQuality;
                        if (videoQ != null) {
                          await ref.read(downloadsProvider.notifier).startDownload(
                                video: _analysis!,
                                streamInfo: videoQ.streamInfo,
                                type: DownloadType.video,
                                qualityLabel: videoQ.label,
                                format: videoQ.container,
                              );
                        }
                      }

                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                    },
                    icon: const Icon(Icons.download_rounded, size: 20),
                    label: Text(
                      strings.startDownload,
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
