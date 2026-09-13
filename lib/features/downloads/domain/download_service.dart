import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:youtube_downloader/core/network/http_cache.dart';
import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../data/models/download_task_model.dart';

class VideoQualityOption {
  final String label; // e.g., '1080p', '720p'
  final int tag; // itag or stream identifier
  final int approximateSizeBytes;
  final String container; // 'mp4', 'webm'
  final bool isMuxed;
  final StreamInfo? streamInfo;

  const VideoQualityOption({
    required this.label,
    required this.tag,
    required this.approximateSizeBytes,
    required this.container,
    required this.isMuxed,
    this.streamInfo,
  });
}

class AudioQualityOption {
  final String label; // e.g., '128 kbps', '256 kbps', '320 kbps'
  final String format; // 'mp3', 'm4a'
  final int bitrateKbps;
  final int approximateSizeBytes;
  final AudioStreamInfo? streamInfo;

  const AudioQualityOption({
    required this.label,
    required this.format,
    required this.bitrateKbps,
    required this.approximateSizeBytes,
    this.streamInfo,
  });
}

class VideoAnalysisResult {
  final String id;
  final String url;
  final String title;
  final String author;
  final Duration? duration;
  final String thumbnailUrl;
  final List<VideoQualityOption> videoQualities;
  final List<AudioQualityOption> audioQualities;
  final int bestSizeBytes;

  const VideoAnalysisResult({
    required this.id,
    required this.url,
    required this.title,
    required this.author,
    this.duration,
    required this.thumbnailUrl,
    required this.videoQualities,
    required this.audioQualities,
    required this.bestSizeBytes,
  });
}

class DownloadService {
  final YoutubeExplode _yt = YoutubeExplode();
  final Map<String, StreamSubscription> _activeSubscriptions = {};
  final Map<String, IOSink> _activeFileSinks = {};
  final Map<String, bool> _pauseFlags = {};
  final Map<String, bool> _cancelFlags = {};

  final Map<String, Process> _activeProcesses = {};
  final Map<String, DownloadTaskModel> _activeTasks = {};
  final Map<String, Function(DownloadTaskModel)> _onProgressCallbacks = {};

  VideoSearchList? _lastSearchList;

  /// Searches YouTube videos by query with pagination support
  Future<List<Video>> searchVideos(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return [];

    try {
      final results = await _yt.search.search(clean);
      _lastSearchList = results;
      return results.toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetches a live feed of videos for a given category with pagination support
  Future<List<Video>> getFeedVideos({String category = 'الكل'}) async {
    String searchQuery = 'popular creative commons';
    switch (category) {
      case 'رائج':
      case 'Trending':
        searchQuery = 'trending';
        break;
      case 'موسيقى':
      case 'Music':
        searchQuery = 'popular music';
        break;
      case 'ألعاب':
      case 'Gaming':
        searchQuery = 'top gaming videos';
        break;
      case 'أخبار':
      case 'News':
        searchQuery = 'latest news';
        break;
      case 'بودكاست':
      case 'Podcasts':
        searchQuery = 'popular podcast';
        break;
      case 'مشاع إبداعي':
      case 'Creative Commons':
        searchQuery = 'creative commons';
        break;
      case 'تقنية':
      case 'Tech':
        searchQuery = 'tech technology';
        break;
      case 'تعليم':
      case 'Education':
        searchQuery = 'educational tutorial';
        break;
      default:
        searchQuery = 'trending';
        break;
    }

    try {
      final results = await _yt.search.search(searchQuery);
      _lastSearchList = results;
      return results.toList();
    } catch (_) {
      return [];
    }
  }

  /// Loads the next page of videos from YouTube search or feed
  Future<List<Video>> loadMoreVideos() async {
    final currentList = _lastSearchList;
    if (currentList == null) return [];

    try {
      final nextResults = await currentList.nextPage();
      if (nextResults != null && nextResults.isNotEmpty) {
        _lastSearchList = nextResults;
        return nextResults.toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Analyzes a YouTube video URL and extracts clean metadata and stream options
  Future<VideoAnalysisResult> analyzeUrl(String inputUrl) async {
    final cleanUrl = inputUrl.trim();
    final videoId = VideoId.parseVideoId(cleanUrl);

    // 1. Try YoutubeExplode first for fast metadata extraction
    if (videoId != null) {
      try {
        final videoFuture = _yt.videos.get(videoId).timeout(const Duration(seconds: 7));
        final manifestFuture = _yt.videos.streamsClient
            .getManifest(videoId, requireWatchPage: false)
            .timeout(const Duration(seconds: 8));

        final video = await videoFuture;
        StreamManifest manifest;
        try {
          manifest = await manifestFuture;
        } catch (_) {
          manifest = await _yt.videos.streamsClient
              .getManifest(videoId, requireWatchPage: true)
              .timeout(const Duration(seconds: 8));
        }

        final isMobile = Platform.isAndroid || Platform.isIOS;
        final Map<String, VideoQualityOption> qualityMap = {};

        for (final stream in manifest.muxed) {
          final label = stream.qualityLabel;
          final size = stream.size.totalBytes;
          if (!qualityMap.containsKey(label) || size > qualityMap[label]!.approximateSizeBytes) {
            qualityMap[label] = VideoQualityOption(
              label: '$label (فيديو + صوت)',
              tag: stream.tag,
              approximateSizeBytes: size,
              container: stream.container.name,
              isMuxed: true,
              streamInfo: stream,
            );
          }
        }

        // On desktop with yt-dlp + ffmpeg, include videoOnly streams for merging
        if (!isMobile) {
          for (final stream in manifest.videoOnly) {
            final label = stream.qualityLabel;
            final size = stream.size.totalBytes;
            if (!qualityMap.containsKey(label)) {
              qualityMap[label] = VideoQualityOption(
                label: label,
                tag: stream.tag,
                approximateSizeBytes: size,
                container: stream.container.name,
                isMuxed: false,
                streamInfo: stream,
              );
            }
          }
        }

        final sortedVideoQualities = qualityMap.values.toList()
          ..sort((a, b) {
            final aNum = int.tryParse(a.label.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
            final bNum = int.tryParse(b.label.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
            return bNum.compareTo(aNum);
          });

        final List<AudioQualityOption> audioOptions = [];
        final audioStreams = manifest.audioOnly.sortByBitrate();

        for (final stream in audioStreams) {
          final kbps = (stream.bitrate.kiloBitsPerSecond).round();
          final format = stream.container.name == 'mp4' ? 'm4a' : 'mp3';
          audioOptions.add(
            AudioQualityOption(
              label: '$kbps kbps',
              format: format,
              bitrateKbps: kbps,
              approximateSizeBytes: stream.size.totalBytes,
              streamInfo: stream,
            ),
          );
        }

        if (audioOptions.isNotEmpty) {
          final bestAudio = audioStreams.withHighestBitrate();
          audioOptions.insert(
            0,
            AudioQualityOption(
              label: '${(bestAudio.bitrate.kiloBitsPerSecond).round()} kbps (MP3)',
              format: 'mp3',
              bitrateKbps: (bestAudio.bitrate.kiloBitsPerSecond).round(),
              approximateSizeBytes: bestAudio.size.totalBytes,
              streamInfo: bestAudio,
            ),
          );
        }

        final thumbnail = video.thumbnails.maxResUrl.isNotEmpty
            ? video.thumbnails.maxResUrl
            : (video.thumbnails.highResUrl.isNotEmpty
                ? video.thumbnails.highResUrl
                : 'https://i.ytimg.com/vi/${video.id.value}/hqdefault.jpg');

        final bestSize = sortedVideoQualities.isNotEmpty
            ? sortedVideoQualities.first.approximateSizeBytes
            : (audioOptions.isNotEmpty ? audioOptions.first.approximateSizeBytes : 0);

        return VideoAnalysisResult(
          id: video.id.value,
          url: cleanUrl,
          title: video.title,
          author: video.author,
          duration: video.duration,
          thumbnailUrl: thumbnail,
          videoQualities: sortedVideoQualities,
          audioQualities: audioOptions,
          bestSizeBytes: bestSize,
        );
      } catch (_) {
        // Fall back to yt-dlp metadata extraction
      }
    }

    // 2. Fallback using yt-dlp
    final ytDlp = _findYtDlp();
    if (ytDlp != null) {
      return await _analyzeWithYtDlp(cleanUrl, ytDlp);
    }

    throw const FormatException('تعذر استخراج بيانات الفيديو من الرابط');
  }

  Future<VideoAnalysisResult> _analyzeWithYtDlp(String cleanUrl, String ytDlpPath) async {
    final node = _findNode();
    final args = [
      if (node != null) ...['--js-runtimes', 'node:"$node"'],
      '--extractor-args', 'youtube:player_client=android,web,ios',
      '--geo-bypass',
      '--no-check-certificates',
      '-j',
      cleanUrl,
    ];

    try {
      final res = await Process.run(ytDlpPath, args);
      if (res.exitCode == 0) {
        final data = jsonDecode(res.stdout as String) as Map<String, dynamic>;
        final id = data['id'] as String? ?? '';
        final title = data['title'] as String? ?? 'بدون عنوان';
        final author = data['uploader'] as String? ?? data['channel'] as String? ?? '';
        final durationSec = (data['duration'] as num?)?.toInt();
        final duration = durationSec != null ? Duration(seconds: durationSec) : null;
        final thumbnail = data['thumbnail'] as String? ?? '';

        final formats = (data['formats'] as List<dynamic>?) ?? [];
        final Map<int, VideoQualityOption> qualityMap = {};

        for (final f in formats) {
          final h = (f['height'] as num?)?.toInt();
          if (h != null && h >= 144) {
            final size = (f['filesize'] as num?)?.toInt() ??
                (f['filesize_approx'] as num?)?.toInt() ??
                0;
            if (!qualityMap.containsKey(h) || size > qualityMap[h]!.approximateSizeBytes) {
              qualityMap[h] = VideoQualityOption(
                label: '${h}p',
                tag: (f['format_id'] is num) ? (f['format_id'] as num).toInt() : (int.tryParse('${f['format_id']}') ?? h),
                approximateSizeBytes: size,
                container: 'mp4',
                isMuxed: true,
                streamInfo: null,
              );
            }
          }
        }

        final sortedQualities = qualityMap.values.toList()
          ..sort((a, b) {
            final aNum = int.tryParse(a.label.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
            final bNum = int.tryParse(b.label.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
            return bNum.compareTo(aNum);
          });

        if (sortedQualities.isEmpty) {
          sortedQualities.addAll(const [
            VideoQualityOption(label: '1080p', tag: 137, approximateSizeBytes: 0, container: 'mp4', isMuxed: false),
            VideoQualityOption(label: '720p', tag: 22, approximateSizeBytes: 0, container: 'mp4', isMuxed: true),
            VideoQualityOption(label: '480p', tag: 135, approximateSizeBytes: 0, container: 'mp4', isMuxed: false),
            VideoQualityOption(label: '360p', tag: 18, approximateSizeBytes: 0, container: 'mp4', isMuxed: true),
          ]);
        }

        const audioQualities = [
          AudioQualityOption(
            label: '320 kbps (MP3)',
            format: 'mp3',
            bitrateKbps: 320,
            approximateSizeBytes: 0,
            streamInfo: null,
          ),
          AudioQualityOption(
            label: '192 kbps (MP3)',
            format: 'mp3',
            bitrateKbps: 192,
            approximateSizeBytes: 0,
            streamInfo: null,
          ),
          AudioQualityOption(
            label: '128 kbps (M4A)',
            format: 'm4a',
            bitrateKbps: 128,
            approximateSizeBytes: 0,
            streamInfo: null,
          ),
        ];

        return VideoAnalysisResult(
          id: id,
          url: cleanUrl,
          title: title,
          author: author,
          duration: duration,
          thumbnailUrl: thumbnail,
          videoQualities: sortedQualities,
          audioQualities: audioQualities,
          bestSizeBytes: sortedQualities.isNotEmpty ? sortedQualities.first.approximateSizeBytes : 0,
        );
      }
    } catch (_) {}

    // Universal Direct Fallback if metadata extraction was restricted
    return VideoAnalysisResult(
      id: VideoId.parseVideoId(cleanUrl) ?? '',
      url: cleanUrl,
      title: 'فيديو YouTube',
      author: '',
      duration: null,
      thumbnailUrl: '',
      videoQualities: const [
        VideoQualityOption(label: '1080p', tag: 137, approximateSizeBytes: 0, container: 'mp4', isMuxed: false),
        VideoQualityOption(label: '720p', tag: 22, approximateSizeBytes: 0, container: 'mp4', isMuxed: true),
        VideoQualityOption(label: '480p', tag: 135, approximateSizeBytes: 0, container: 'mp4', isMuxed: false),
        VideoQualityOption(label: '360p', tag: 18, approximateSizeBytes: 0, container: 'mp4', isMuxed: true),
      ],
      audioQualities: const [
        AudioQualityOption(label: '320 kbps (MP3)', format: 'mp3', bitrateKbps: 320, approximateSizeBytes: 0),
        AudioQualityOption(label: '128 kbps (M4A)', format: 'm4a', bitrateKbps: 128, approximateSizeBytes: 0),
      ],
      bestSizeBytes: 0,
    );
  }

  /// Downloads the chosen stream with real-time updates for progress, bytes, speed, and ETA
  Future<void> executeDownload({
    required DownloadTaskModel task,
    StreamInfo? streamInfo,
    required Function(DownloadTaskModel updatedTask) onProgress,
  }) async {
    final taskId = task.id;
    debugPrint('>>> [EXECUTE_DOWNLOAD] id=$taskId, title=${task.title}, streamInfo=${streamInfo?.qualityLabel}, totalBytes=${task.totalBytes}');
    _pauseFlags[taskId] = false;
    _cancelFlags[taskId] = false;
    _activeTasks[taskId] = task;
    _onProgressCallbacks[taskId] = onProgress;

    // Ensure output directory exists
    final targetFile = File(task.filePath);
    if (!await targetFile.parent.exists()) {
      await targetFile.parent.create(recursive: true);
    }

    // Try yt-dlp first for fast, unblocked downloading
    final ytDlpPath = _findYtDlp();
    if (ytDlpPath != null) {
      await _executeWithYtDlp(
        task: task,
        ytDlpPath: ytDlpPath,
        onProgress: onProgress,
      );
      return;
    }

    // Fallback to youtube_explode stream client or dynamic stream resolver
    StreamInfo? activeStreamInfo = streamInfo;

    final isMobile = Platform.isAndroid || Platform.isIOS;
    // On mobile, video downloads must use an unthrottled muxed stream (with audio).
    // Adaptive videoOnly streams fail with 403 on mobile and lack audio.
    if (isMobile && task.downloadType == DownloadType.video) {
      if (activeStreamInfo == null || activeStreamInfo is VideoOnlyStreamInfo) {
        final videoId = VideoId.parseVideoId(task.videoUrl);
        if (videoId != null) {
          try {
            final manifest = await _yt.videos.streamsClient
                .getManifest(videoId, requireWatchPage: false)
                .timeout(const Duration(seconds: 6));
            if (manifest.muxed.isNotEmpty) {
              activeStreamInfo = manifest.muxed.withHighestBitrate();
            }
          } catch (_) {}
        }
      }
    }

    // Dynamic resolution if streamInfo is null on mobile
    if (activeStreamInfo == null) {
      final videoId = VideoId.parseVideoId(task.videoUrl);
      if (videoId != null) {
        try {
          StreamManifest manifest;
          try {
            manifest = await _yt.videos.streamsClient
                .getManifest(videoId, requireWatchPage: false)
                .timeout(const Duration(seconds: 8));
          } catch (_) {
            manifest = await _yt.videos.streamsClient
                .getManifest(videoId, requireWatchPage: true)
                .timeout(const Duration(seconds: 8));
          }
          if (task.downloadType == DownloadType.audio) {
            final audioStreams = manifest.audioOnly.sortByBitrate();
            if (audioStreams.isNotEmpty) {
              activeStreamInfo = audioStreams.withHighestBitrate();
            }
          } else {
            final heightMatch = RegExp(r'(\d{3,4})p?').firstMatch(task.qualityLabel);
            final targetHeight = heightMatch != null ? int.tryParse(heightMatch.group(1)!) : 720;

            StreamInfo? bestMuxed;
            for (final s in manifest.muxed) {
              final h = int.tryParse(s.qualityLabel.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
              if (h <= (targetHeight ?? 720)) {
                if (bestMuxed == null || h > (int.tryParse(bestMuxed.qualityLabel.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)) {
                  bestMuxed = s;
                }
              }
            }
            activeStreamInfo = bestMuxed ?? (manifest.muxed.isNotEmpty ? manifest.muxed.withHighestBitrate() : null);
            if (activeStreamInfo == null && manifest.videoOnly.isNotEmpty) {
              activeStreamInfo = manifest.videoOnly.withHighestBitrate();
            }
          }
        } catch (_) {}
      }
    }

    if (activeStreamInfo != null) {
      await _executeWithYoutubeExplode(
        task: task,
        streamInfo: activeStreamInfo,
        onProgress: onProgress,
      );
      return;
    }

    // Direct HTTP/HTTPS download for external or direct video streams
    if (task.videoUrl.startsWith('http://') || task.videoUrl.startsWith('https://')) {
      await _executeTurboDownload(
        task: task,
        downloadUri: Uri.parse(task.videoUrl),
        totalBytes: task.totalBytes,
        onProgress: onProgress,
      );
      return;
    }

    onProgress(task.copyWith(
      status: DownloadStatus.failed,
      errorMessage: 'تعذر العثور على مسار صالح لتنزيل هذا الفيديو',
    ));
  }

  Future<void> _executeWithYtDlp({
    required DownloadTaskModel task,
    required String ytDlpPath,
    required Function(DownloadTaskModel updatedTask) onProgress,
  }) async {
    final taskId = task.id;
    final ffmpegDir = _findFfmpegDir();
    final nodePath = _findNode();

    final List<String> args;

    if (task.downloadType == DownloadType.audio) {
      final isMp3 = task.format.toLowerCase().contains('mp3');
      final audioFormat = isMp3 ? 'mp3' : 'm4a';
      final outTemplate = '${task.filePath.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '')}.%(ext)s';

      args = <String>[
        if (ffmpegDir != null) ...['--ffmpeg-location', ffmpegDir],
        if (nodePath != null) ...['--js-runtimes', 'node:"$nodePath"'],
        '--extractor-args', 'youtube:player_client=android,web,ios',
        '--geo-bypass',
        '--no-check-certificates',
        '-x',
        '--audio-format', audioFormat,
        '-f', 'bestaudio/best/b/ba*',
        '-o', outTemplate,
        '--newline',
        '--no-playlist',
        task.videoUrl,
      ];
    } else {
      final heightMatch = RegExp(r'(\d{3,4})p?').firstMatch(task.qualityLabel);
      final height = heightMatch != null ? int.tryParse(heightMatch.group(1)!) : null;

      final formatSelector = height != null
          ? 'bestvideo[height<=$height][ext=mp4]+bestaudio[ext=m4a]/bestvideo[height<=$height]+bestaudio/best[height<=$height]/best/bv*+ba/b'
          : 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/bestvideo+bestaudio/best/bv*+ba/b';

      args = <String>[
        if (ffmpegDir != null) ...['--ffmpeg-location', ffmpegDir],
        if (nodePath != null) ...['--js-runtimes', 'node:"$nodePath"'],
        '--extractor-args', 'youtube:player_client=android,web,ios',
        '--geo-bypass',
        '--no-check-certificates',
        '-f', formatSelector,
        '--merge-output-format', task.format.isNotEmpty ? task.format : 'mp4',
        '-o', task.filePath,
        '--newline',
        '--no-playlist',
        task.videoUrl,
      ];
    }

    try {
      final process = await Process.start(
        ytDlpPath,
        args,
        runInShell: false,
        workingDirectory: ffmpegDir ?? Directory.current.path,
      );
      _activeProcesses[taskId] = process;

      int currentStream = 1;
      final isTwoStreams = task.downloadType == DownloadType.video;
      double currentProgress = 0.0;
      int estimatedTotal = task.totalBytes;
      final stderrBuffer = StringBuffer();

      process.stderr.transform(utf8.decoder).listen((errChunk) {
        stderrBuffer.write(errChunk);
      });

      final progressRegex = RegExp(
        r'\[download\]\s+([\d\.]+)%\s+of\s+(?:~\s*)?([\d\.]+)\s*([a-zA-Z]+)(?:\s+at\s+([^E]+?))?(?:\s+ETA\s+([^\s]+))?$',
      );

      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (_cancelFlags[taskId] == true || _pauseFlags[taskId] == true) return;

        final trimmed = line.trim();

        if (trimmed.contains('[download] Destination:') && currentProgress > 0.05) {
          currentStream = 2;
        }

        final match = progressRegex.firstMatch(trimmed);
        if (match != null) {
          final percent = double.tryParse(match.group(1) ?? '0') ?? 0.0;
          final sizeVal = double.tryParse(match.group(2) ?? '0') ?? 0.0;
          final sizeUnit = match.group(3) ?? 'B';
          final speedStr = match.group(4)?.trim();
          final etaStr = match.group(5)?.trim();

          final parsedBytes = _parseBytes(sizeVal, sizeUnit);
          final parsedSpeed = _parseSpeed(speedStr);
          final parsedEta = _parseEta(etaStr);

          if (estimatedTotal <= 0 && parsedBytes > 0) {
            estimatedTotal = parsedBytes;
          }

          if (isTwoStreams) {
            if (currentStream == 1) {
              currentProgress = (percent / 100.0) * 0.75;
            } else {
              currentProgress = 0.75 + (percent / 100.0) * 0.20;
            }
          } else {
            currentProgress = (percent / 100.0) * 0.95;
          }
          currentProgress = currentProgress.clamp(0.0, 0.99);

          final downloaded = (estimatedTotal > 0)
              ? (estimatedTotal * currentProgress).round()
              : parsedBytes;

          onProgress(
            task.copyWith(
              status: DownloadStatus.downloading,
              downloadedBytes: downloaded,
              totalBytes: estimatedTotal > 0 ? estimatedTotal : parsedBytes,
              progress: currentProgress,
              speedBytesPerSec: parsedSpeed,
              eta: parsedEta,
            ),
          );
        } else if (trimmed.contains('[Merger]') || trimmed.contains('[ExtractAudio]')) {
          currentProgress = 0.98;
          onProgress(
            task.copyWith(
              status: DownloadStatus.downloading,
              progress: 0.98,
              downloadedBytes: estimatedTotal > 0 ? (estimatedTotal * 0.98).round() : estimatedTotal,
              totalBytes: estimatedTotal,
              speedBytesPerSec: 0,
              eta: Duration.zero,
            ),
          );
        }
      });

      final exitCode = await process.exitCode;
      _activeProcesses.remove(taskId);

      if (_cancelFlags[taskId] == true) {
        _cleanupTaskFiles(task.filePath);
        onProgress(task.copyWith(status: DownloadStatus.cancelled));
        return;
      }

      if (_pauseFlags[taskId] == true) {
        onProgress(task.copyWith(status: DownloadStatus.paused));
        return;
      }

      if (exitCode == 0) {
        final finalFile = _resolveFinalFile(task.filePath);
        final finalBytes = finalFile.existsSync() ? finalFile.lengthSync() : estimatedTotal;

        onProgress(
          task.copyWith(
            status: DownloadStatus.completed,
            filePath: finalFile.path,
            downloadedBytes: finalBytes,
            totalBytes: finalBytes,
            progress: 1.0,
            speedBytesPerSec: 0,
            eta: Duration.zero,
            completedAt: DateTime.now(),
          ),
        );
      } else {
        final errText = stderrBuffer.toString().trim();
        onProgress(
          task.copyWith(
            status: DownloadStatus.failed,
            errorMessage: errText.isNotEmpty ? errText : 'فشل التنزيل (رمز الخطأ: $exitCode)',
          ),
        );
      }
    } catch (e) {
      _activeProcesses.remove(taskId);
      onProgress(
        task.copyWith(
          status: DownloadStatus.failed,
          errorMessage: e.toString(),
        ),
      );
    }
  }

  Future<void> _executeWithYoutubeExplode({
    required DownloadTaskModel task,
    required StreamInfo streamInfo,
    required Function(DownloadTaskModel updatedTask) onProgress,
  }) async {
    final taskId = task.id;
    final targetFile = File(task.filePath);

    final totalBytes = streamInfo.size.totalBytes;
    var downloadedBytes = 0;
    var lastBytes = 0;
    var lastTime = DateTime.now();

    final sink = targetFile.openWrite(mode: FileMode.writeOnly);
    _activeFileSinks[taskId] = sink;

    final dio = createDio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );

    try {
      // 4MB chunks with HTTP Range headers prevent YouTube TCP throttling and 403 blocks
      const chunkSize = 4 * 1024 * 1024;
      var currentStreamUri = streamInfo.url;

      if (totalBytes > 0) {
        while (downloadedBytes < totalBytes) {
          if (_cancelFlags[taskId] == true) {
            await sink.close();
            if (await targetFile.exists()) {
              await targetFile.delete();
            }
            onProgress(task.copyWith(status: DownloadStatus.cancelled));
            return;
          }

          while (_pauseFlags[taskId] == true) {
            await Future.delayed(const Duration(milliseconds: 300));
            if (_cancelFlags[taskId] == true) break;
          }

          final from = downloadedBytes;
          final to = (downloadedBytes + chunkSize - 1) < totalBytes
              ? (downloadedBytes + chunkSize - 1)
              : (totalBytes - 1);

          var chunkSuccess = false;
          int retries = 0;

          while (!chunkSuccess && retries < 3) {
            if (_cancelFlags[taskId] == true) break;

            try {
              final resp = await dio.get<ResponseBody>(
                currentStreamUri.toString(),
                options: Options(
                  responseType: ResponseType.stream,
                  headers: {
                    'Range': 'bytes=$from-$to',
                    'User-Agent': 'Mozilla/5.0 (Android 14; Mobile; rv:128.0) Gecko/128.0 Firefox/128.0',
                    'Accept': '*/*',
                  },
                  validateStatus: (_) => true,
                ),
              );

              debugPrint('>>> [DIO CHUNK] $from-$to -> HTTP ${resp.statusCode}');

              if (resp.statusCode == 200 || resp.statusCode == 206) {
                await for (final data in resp.data!.stream) {
                  if (_cancelFlags[taskId] == true) break;
                  sink.add(data);
                  downloadedBytes += data.length;

                  final now = DateTime.now();
                  final elapsedMs = now.difference(lastTime).inMilliseconds;

                  if (elapsedMs >= 300 || downloadedBytes >= totalBytes) {
                    final bytesDelta = downloadedBytes - lastBytes;
                    final speed = elapsedMs > 0 ? (bytesDelta / (elapsedMs / 1000.0)) : 0.0;
                    final remainingBytes = totalBytes - downloadedBytes;
                    Duration? eta;
                    if (speed > 0 && remainingBytes > 0) {
                      final secondsLeft = (remainingBytes / speed).ceil();
                      eta = Duration(seconds: secondsLeft);
                    }

                    final progress = totalBytes > 0 ? (downloadedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;

                    onProgress(
                      task.copyWith(
                        status: DownloadStatus.downloading,
                        downloadedBytes: downloadedBytes,
                        totalBytes: totalBytes,
                        progress: progress,
                        speedBytesPerSec: speed,
                        eta: eta,
                      ),
                    );

                    lastBytes = downloadedBytes;
                    lastTime = now;
                  }
                }
                chunkSuccess = true;
              } else if (resp.statusCode == 403) {
                debugPrint('>>> [DIO CHUNK 403] Refreshing manifest for tag ${streamInfo.tag}...');
                final videoId = VideoId.parseVideoId(task.videoUrl);
                if (videoId != null) {
                  try {
                    final freshManifest = await _yt.videos.streamsClient
                        .getManifest(videoId, requireWatchPage: false)
                        .timeout(const Duration(seconds: 6));
                    final freshStream = freshManifest.streams
                        .firstWhere((s) => s.tag == streamInfo.tag, orElse: () => freshManifest.muxed.first);
                    currentStreamUri = freshStream.url;
                  } catch (_) {}
                }
                retries++;
                await Future.delayed(Duration(milliseconds: 500 * retries));
              } else {
                retries++;
                await Future.delayed(Duration(milliseconds: 400 * retries));
              }
            } catch (e) {
              debugPrint('>>> [DIO CHUNK EXCEPTION] $e');
              retries++;
              await Future.delayed(Duration(milliseconds: 400 * retries));
            }
          }

          if (!chunkSuccess && _cancelFlags[taskId] != true) {
            throw Exception('تعذر استكمال تنزيل أجزاء الفيديو بعد عدة محاولات');
          }
        }
      } else {
        final resp = await dio.get<ResponseBody>(
          currentStreamUri.toString(),
          options: Options(
            responseType: ResponseType.stream,
            headers: {
              'User-Agent': 'Mozilla/5.0 (Android 14; Mobile; rv:128.0) Gecko/128.0 Firefox/128.0',
              'Accept': '*/*',
            },
            validateStatus: (_) => true,
          ),
        );
        if (resp.statusCode == 200 || resp.statusCode == 206) {
          await for (final data in resp.data!.stream) {
            if (_cancelFlags[taskId] == true) break;
            sink.add(data);
            downloadedBytes += data.length;
          }
        }
      }

      await sink.flush();
      await sink.close();
      _activeFileSinks.remove(taskId);

      if (_cancelFlags[taskId] != true) {
        onProgress(
          task.copyWith(
            status: DownloadStatus.completed,
            downloadedBytes: downloadedBytes,
            totalBytes: downloadedBytes > totalBytes ? downloadedBytes : totalBytes,
            progress: 1.0,
            speedBytesPerSec: 0,
            eta: Duration.zero,
            completedAt: DateTime.now(),
          ),
        );
      }
    } catch (e, st) {
      debugPrint('>>> [_executeWithYoutubeExplode FAILED] $e\n$st');
      await sink.close();
      _activeFileSinks.remove(taskId);
      onProgress(
        task.copyWith(
          status: DownloadStatus.failed,
          errorMessage: e.toString(),
        ),
      );
    } finally {
      dio.close();
    }
  }

  /// High-Speed Multi-Connection Turbo Downloader
  Future<void> _executeTurboDownload({
    required DownloadTaskModel task,
    required Uri downloadUri,
    required int totalBytes,
    required Function(DownloadTaskModel updatedTask) onProgress,
  }) async {
    final taskId = task.id;
    final targetFile = File(task.filePath);

    final int segments = (totalBytes > 3 * 1024 * 1024) ? 4 : 1;

    bool supportsRange = false;
    if (segments > 1) {
      final probeClient = HttpClient()
        ..connectionTimeout = const Duration(seconds: 6);
      try {
        final req = await probeClient.getUrl(downloadUri);
        req.headers.set('Range', 'bytes=0-0');
        req.headers.set(
          HttpHeaders.userAgentHeader,
          'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        );
        final res = await req.close();
        if (res.statusCode == 206) {
          supportsRange = true;
        }
        await res.drain();
      } catch (_) {
        supportsRange = false;
      } finally {
        probeClient.close();
      }
    }

    if (!supportsRange || segments <= 1) {
      await _executeSingleStreamFastDownload(
        task: task,
        downloadUri: downloadUri,
        totalBytes: totalBytes,
        onProgress: onProgress,
      );
      return;
    }

    final segmentSize = (totalBytes / segments).floor();
    final List<File> partFiles = [];
    final List<IOSink> partSinks = [];
    final List<HttpClient> clients = [];
    final List<StreamSubscription> subscriptions = [];
    final List<int> segmentDownloaded = List.filled(segments, 0);

    var lastReportTime = DateTime.now();
    var lastReportBytes = 0;

    void reportProgress() {
      if (_cancelFlags[taskId] == true) return;
      final currentDownloaded = segmentDownloaded.fold<int>(0, (sum, b) => sum + b);
      final now = DateTime.now();
      final elapsedMs = now.difference(lastReportTime).inMilliseconds;

      if (elapsedMs >= 300 || currentDownloaded >= totalBytes) {
        final bytesDelta = currentDownloaded - lastReportBytes;
        final speed = elapsedMs > 0 ? (bytesDelta / (elapsedMs / 1000.0)) : 0.0;
        final remaining = totalBytes - currentDownloaded;
        Duration? eta;
        if (speed > 0 && remaining > 0) {
          eta = Duration(seconds: (remaining / speed).ceil());
        }
        final progress = totalBytes > 0 ? (currentDownloaded / totalBytes).clamp(0.0, 0.99) : 0.0;

        onProgress(
          task.copyWith(
            status: DownloadStatus.downloading,
            downloadedBytes: currentDownloaded,
            totalBytes: totalBytes,
            progress: progress,
            speedBytesPerSec: speed,
            eta: eta,
          ),
        );

        lastReportBytes = currentDownloaded;
        lastReportTime = now;
      }
    }

    try {
      final futures = <Future<void>>[];

      for (int i = 0; i < segments; i++) {
        final start = i * segmentSize;
        final end = (i == segments - 1) ? (totalBytes - 1) : ((i + 1) * segmentSize - 1);
        final partFile = File('${task.filePath}.part$i');
        partFiles.add(partFile);
        final sink = partFile.openWrite(mode: FileMode.writeOnly);
        partSinks.add(sink);

        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 15)
          ..maxConnectionsPerHost = 10;
        clients.add(client);

        final completer = Completer<void>();

        () async {
          try {
            final req = await client.getUrl(downloadUri);
            req.headers.set('Range', 'bytes=$start-$end');
            req.headers.set(HttpHeaders.connectionHeader, 'keep-alive');
            req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
            req.headers.set(
              HttpHeaders.userAgentHeader,
              'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
            );
            final res = await req.close();

            if (res.statusCode != 200 && res.statusCode != 206) {
              throw HttpException('Segment $i failed with status ${res.statusCode}');
            }

            late StreamSubscription sub;
            sub = res.listen(
              (chunk) {
                if (_cancelFlags[taskId] == true) {
                  sub.cancel();
                  return;
                }
                while (_pauseFlags[taskId] == true) {
                  sub.pause();
                  break;
                }
                sink.add(chunk);
                segmentDownloaded[i] += chunk.length;
                reportProgress();
              },
              onDone: () async {
                await sink.flush();
                await sink.close();
                if (!completer.isCompleted) completer.complete();
              },
              onError: (e) {
                if (!completer.isCompleted) completer.completeError(e);
              },
              cancelOnError: true,
            );
            subscriptions.add(sub);
          } catch (e) {
            if (!completer.isCompleted) completer.completeError(e);
          }
        }();

        futures.add(completer.future);
      }

      await Future.wait(futures);

      for (final c in clients) {
        c.close();
      }

      if (_cancelFlags[taskId] == true) {
        for (final p in partFiles) {
          try {
            if (await p.exists()) await p.delete();
          } catch (_) {}
        }
        onProgress(task.copyWith(status: DownloadStatus.cancelled));
        return;
      }

      final outSink = targetFile.openWrite(mode: FileMode.writeOnly);
      for (final p in partFiles) {
        if (await p.exists()) {
          await outSink.addStream(p.openRead());
          try {
            await p.delete();
          } catch (_) {}
        }
      }
      await outSink.flush();
      await outSink.close();

      final finalBytes = await targetFile.exists() ? await targetFile.length() : totalBytes;

      onProgress(
        task.copyWith(
          status: DownloadStatus.completed,
          downloadedBytes: finalBytes,
          totalBytes: finalBytes,
          progress: 1.0,
          speedBytesPerSec: 0,
          eta: Duration.zero,
          completedAt: DateTime.now(),
        ),
      );
    } catch (e) {
      for (final c in clients) {
        c.close();
      }
      for (final s in partSinks) {
        try {
          await s.close();
        } catch (_) {}
      }
      for (final p in partFiles) {
        try {
          if (await p.exists()) await p.delete();
        } catch (_) {}
      }
      await _executeSingleStreamFastDownload(
        task: task,
        downloadUri: downloadUri,
        totalBytes: totalBytes,
        onProgress: onProgress,
      );
    }
  }

  Future<void> _executeSingleStreamFastDownload({
    required DownloadTaskModel task,
    required Uri downloadUri,
    required int totalBytes,
    required Function(DownloadTaskModel updatedTask) onProgress,
  }) async {
    final taskId = task.id;
    final targetFile = File(task.filePath);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..maxConnectionsPerHost = 8;
    final completer = Completer<void>();

    try {
      final request = await client.getUrl(downloadUri);
      request.headers.set(HttpHeaders.connectionHeader, 'keep-alive');
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      );
      final response = await request.close();

      if (response.statusCode != 200 && response.statusCode != 206) {
        throw HttpException('HTTP Error ${response.statusCode}');
      }

      final actualTotal = response.contentLength > 0 ? response.contentLength : totalBytes;
      var downloadedBytes = 0;
      var lastBytes = 0;
      var lastTime = DateTime.now();

      final sink = targetFile.openWrite(mode: FileMode.writeOnly);
      _activeFileSinks[taskId] = sink;

      late StreamSubscription<List<int>> subscription;
      subscription = response.listen(
        (data) async {
          if (_cancelFlags[taskId] == true) {
            subscription.cancel();
            await sink.close();
            if (await targetFile.exists()) await targetFile.delete();
            onProgress(task.copyWith(status: DownloadStatus.cancelled));
            if (!completer.isCompleted) completer.complete();
            return;
          }

          while (_pauseFlags[taskId] == true) {
            subscription.pause();
            await Future.delayed(const Duration(milliseconds: 300));
            if (_cancelFlags[taskId] == true) break;
          }

          sink.add(data);
          downloadedBytes += data.length;

          final now = DateTime.now();
          final elapsedMs = now.difference(lastTime).inMilliseconds;

          if (elapsedMs >= 300 || (actualTotal > 0 && downloadedBytes >= actualTotal)) {
            final bytesDelta = downloadedBytes - lastBytes;
            final speed = elapsedMs > 0 ? (bytesDelta / (elapsedMs / 1000.0)) : 0.0;
            final remainingBytes = actualTotal > downloadedBytes ? (actualTotal - downloadedBytes) : 0;
            Duration? eta;
            if (speed > 0 && remainingBytes > 0) {
              eta = Duration(seconds: (remainingBytes / speed).ceil());
            }
            final progress = actualTotal > 0 ? (downloadedBytes / actualTotal).clamp(0.0, 1.0) : 0.0;

            onProgress(
              task.copyWith(
                status: DownloadStatus.downloading,
                downloadedBytes: downloadedBytes,
                totalBytes: actualTotal > 0 ? actualTotal : downloadedBytes,
                progress: progress,
                speedBytesPerSec: speed,
                eta: eta,
              ),
            );

            lastBytes = downloadedBytes;
            lastTime = now;
          }
        },
        onDone: () async {
          await sink.flush();
          await sink.close();
          client.close();
          _activeFileSinks.remove(taskId);
          _activeSubscriptions.remove(taskId);

          if (_cancelFlags[taskId] != true) {
            onProgress(
              task.copyWith(
                status: DownloadStatus.completed,
                downloadedBytes: downloadedBytes,
                totalBytes: downloadedBytes,
                progress: 1.0,
                speedBytesPerSec: 0,
                eta: Duration.zero,
                completedAt: DateTime.now(),
              ),
            );
          }
          if (!completer.isCompleted) completer.complete();
        },
        onError: (err) async {
          await sink.close();
          client.close();
          _activeFileSinks.remove(taskId);
          _activeSubscriptions.remove(taskId);
          onProgress(task.copyWith(
            status: DownloadStatus.failed,
            errorMessage: err.toString(),
          ));
          if (!completer.isCompleted) completer.completeError(err);
        },
        cancelOnError: true,
      );

      _activeSubscriptions[taskId] = subscription;
      await completer.future;
    } catch (e) {
      client.close();
      onProgress(task.copyWith(
        status: DownloadStatus.failed,
        errorMessage: e.toString(),
      ));
    }
  }

  void pause(String taskId) {
    _pauseFlags[taskId] = true;
    final proc = _activeProcesses[taskId];
    if (proc != null) {
      proc.kill();
    }
    _activeSubscriptions[taskId]?.pause();
  }

  void resume(String taskId) {
    _pauseFlags[taskId] = false;
    final task = _activeTasks[taskId];
    final cb = _onProgressCallbacks[taskId];
    final ytDlp = _findYtDlp();
    if (task != null && cb != null && ytDlp != null && _activeProcesses[taskId] == null) {
      _executeWithYtDlp(task: task, ytDlpPath: ytDlp, onProgress: cb);
    }
    _activeSubscriptions[taskId]?.resume();
  }

  void cancel(String taskId) {
    _cancelFlags[taskId] = true;
    final proc = _activeProcesses[taskId];
    if (proc != null) {
      proc.kill();
      _activeProcesses.remove(taskId);
    }
    final task = _activeTasks[taskId];
    if (task != null) {
      _cleanupTaskFiles(task.filePath);
    }
    _activeSubscriptions[taskId]?.cancel();
  }

  void dispose() {
    for (final p in _activeProcesses.values) {
      p.kill();
    }
    _activeProcesses.clear();

    for (final s in _activeSubscriptions.values) {
      s.cancel();
    }
    for (final sink in _activeFileSinks.values) {
      sink.close();
    }
    _yt.close();
  }

  // --- Helpers ---

  String? _findYtDlp() {
    if (Platform.isAndroid || Platform.isIOS) return null;
    final candidates = [
      'yt-dlp.exe',
      '${Directory.current.path}\\yt-dlp.exe',
      '${File(Platform.resolvedExecutable).parent.path}\\yt-dlp.exe',
      r'c:\Users\Medinat AlElm\Desktop\youtube\yt-dlp.exe',
      'yt-dlp',
      '${Directory.current.path}/yt-dlp',
      '${File(Platform.resolvedExecutable).parent.path}/yt-dlp',
      '/opt/homebrew/bin/yt-dlp',
      '/usr/local/bin/yt-dlp',
      '/usr/bin/yt-dlp',
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }

  String? _findFfmpegDir() {
    final candidates = [
      Directory.current.path,
      File(Platform.resolvedExecutable).parent.path,
      r'c:\Users\Medinat AlElm\Desktop\youtube',
      r'C:\Users\Medinat AlElm\AppData\Local\Microsoft\WinGet\Packages\Gyan.FFmpeg.Essentials_Microsoft.Winget.Source_8wekyb3d8bbwe\ffmpeg-8.1.1-essentials_build\bin',
      '/opt/homebrew/bin',
      '/usr/local/bin',
      '/usr/bin',
    ];
    for (final c in candidates) {
      if (File('$c\\ffmpeg.exe').existsSync() || File('$c/ffmpeg').existsSync()) return c;
    }
    return null;
  }

  String? _findNode() {
    final candidates = [
      r'C:\Program Files\nodejs\node.exe',
      r'C:\Program Files (x86)\nodejs\node.exe',
      '/opt/homebrew/bin/node',
      '/usr/local/bin/node',
      '/usr/bin/node',
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }

  int _parseBytes(double val, String unit) {
    final u = unit.toUpperCase();
    if (u.startsWith('K')) return (val * 1024).round();
    if (u.startsWith('M')) return (val * 1024 * 1024).round();
    if (u.startsWith('G')) return (val * 1024 * 1024 * 1024).round();
    if (u.startsWith('T')) return (val * 1024 * 1024 * 1024 * 1024).round();
    return val.round();
  }

  double _parseSpeed(String? speedStr) {
    if (speedStr == null || speedStr.contains('Unknown')) return 0.0;
    final clean = speedStr.trim();
    final match = RegExp(r'([\d\.]+)\s*([a-zA-Z/]+)').firstMatch(clean);
    if (match == null) return 0.0;
    final val = double.tryParse(match.group(1)!) ?? 0.0;
    final unit = match.group(2)!.toUpperCase();
    if (unit.startsWith('K')) return val * 1024;
    if (unit.startsWith('M')) return val * 1024 * 1024;
    if (unit.startsWith('G')) return val * 1024 * 1024 * 1024;
    return val;
  }

  Duration? _parseEta(String? etaStr) {
    if (etaStr == null || etaStr.contains('Unknown')) return null;
    final parts = etaStr.trim().split(':');
    if (parts.length == 2) {
      final m = int.tryParse(parts[0]) ?? 0;
      final s = int.tryParse(parts[1]) ?? 0;
      return Duration(minutes: m, seconds: s);
    } else if (parts.length == 3) {
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      final s = int.tryParse(parts[2]) ?? 0;
      return Duration(hours: h, minutes: m, seconds: s);
    }
    return null;
  }

  File _resolveFinalFile(String preferredPath) {
    final direct = File(preferredPath);
    if (direct.existsSync()) return direct;

    final parent = direct.parent;
    if (parent.existsSync()) {
      final baseName = direct.uri.pathSegments.last.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
      try {
        final matches = parent.listSync().whereType<File>().where((f) {
          final fname = f.uri.pathSegments.last;
          return fname.startsWith(baseName) && !fname.endsWith('.part') && !fname.endsWith('.ytdl');
        }).toList();
        if (matches.isNotEmpty) {
          return matches.first;
        }
      } catch (_) {}
    }
    return direct;
  }

  void _cleanupTaskFiles(String filePath) {
    try {
      final f = File(filePath);
      if (f.existsSync()) f.deleteSync();

      final parent = f.parent;
      if (parent.existsSync()) {
        final baseName = f.uri.pathSegments.last.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
        for (final entry in parent.listSync()) {
          if (entry is File) {
            final fname = entry.uri.pathSegments.last;
            if (fname.startsWith(baseName) && (fname.endsWith('.part') || fname.endsWith('.ytdl'))) {
              try {
                entry.deleteSync();
              } catch (_) {}
            }
          }
        }
      }
    } catch (_) {}
  }
}
