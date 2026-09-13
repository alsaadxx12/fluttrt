import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:youtube_downloader/core/services/storage_service.dart';
import 'package:youtube_downloader/core/utils/file_utils.dart';
import 'package:youtube_downloader/features/settings/presentation/providers/settings_provider.dart';
import 'package:youtube_downloader/features/downloads/data/models/download_task_model.dart';
import 'package:youtube_downloader/features/downloads/domain/download_service.dart';

final downloadServiceProvider = Provider<DownloadService>((ref) {
  final service = DownloadService();
  ref.onDispose(() => service.dispose());
  return service;
});

class DownloadsState {
  final List<DownloadTaskModel> tasks;

  const DownloadsState({this.tasks = const []});

  List<DownloadTaskModel> get activeTasks =>
      tasks.where((t) => t.status == DownloadStatus.downloading || t.status == DownloadStatus.queued || t.status == DownloadStatus.paused).toList();

  List<DownloadTaskModel> get completedTasks =>
      tasks.where((t) => t.status == DownloadStatus.completed).toList();

  List<DownloadTaskModel> get failedTasks =>
      tasks.where((t) => t.status == DownloadStatus.failed || t.status == DownloadStatus.cancelled).toList();

  DownloadsState copyWith({List<DownloadTaskModel>? tasks}) {
    return DownloadsState(tasks: tasks ?? this.tasks);
  }
}

class DownloadsNotifier extends StateNotifier<DownloadsState> {
  final DownloadService _downloadService;
  final StorageService _storageService;
  final Ref _ref;

  DownloadsNotifier(this._downloadService, this._storageService, this._ref)
      : super(DownloadsState(
          tasks: _storageService.getDownloadHistory().map((t) {
            if (t.status == DownloadStatus.downloading || t.status == DownloadStatus.queued) {
              return t.copyWith(status: DownloadStatus.failed, errorMessage: 'تمت مقاطعة التنزيل');
            }
            return t;
          }).toList(),
        ));

  Future<void> _persist() async {
    await _storageService.saveDownloadHistory(state.tasks);
  }

  /// Adds and initiates a new download task
  Future<DownloadTaskModel> startDownload({
    required VideoAnalysisResult video,
    StreamInfo? streamInfo,
    required DownloadType type,
    required String qualityLabel,
    required String format,
  }) async {
    debugPrint('>>> [startDownload called] title="${video.title}", streamInfo=$streamInfo, format=$format, type=$type');
    final settings = _ref.read(settingsProvider);
    var targetFolder = settings.downloadFolder.trim();
    if (targetFolder.isEmpty) {
      targetFolder = _storageService.getDownloadFolder().trim();
    }
    if (targetFolder.isEmpty) {
      try {
        final docDir = await getApplicationDocumentsDirectory();
        targetFolder = docDir.path;
      } catch (_) {
        targetFolder = Directory.systemTemp.path;
      }
    }
    await Directory(targetFolder).create(recursive: true);

    // Clean Windows filename and ensure it has extension
    final safeTitle = FileUtils.sanitizeFilename(video.title);
    final fileName = '$safeTitle.$format';
    final initialPath = '$targetFolder${Platform.pathSeparator}$fileName';
    
    // Ensure uniqueness
    final finalPath = await FileUtils.getUniqueFilePath(initialPath);

    final taskId = '${video.id}_${DateTime.now().millisecondsSinceEpoch}';
    final newTask = DownloadTaskModel(
      id: taskId,
      videoId: video.id,
      videoUrl: video.url,
      title: video.title,
      author: video.author,
      thumbnailUrl: video.thumbnailUrl,
      duration: video.duration,
      qualityLabel: qualityLabel,
      downloadType: type,
      format: format,
      filePath: finalPath,
      totalBytes: streamInfo?.size.totalBytes ?? video.bestSizeBytes,
      status: DownloadStatus.downloading,
      createdAt: DateTime.now(),
    );

    state = state.copyWith(tasks: [newTask, ...state.tasks]);
    await _persist();

    // Start download process async
    _execute(newTask, streamInfo);

    return newTask;
  }

  void _execute(DownloadTaskModel task, StreamInfo? streamInfo) {
    _downloadService.executeDownload(
      task: task,
      streamInfo: streamInfo,
      onProgress: (updatedTask) {
        state = state.copyWith(
          tasks: state.tasks.map((t) => t.id == updatedTask.id ? updatedTask : t).toList(),
        );

        if (updatedTask.status == DownloadStatus.completed ||
            updatedTask.status == DownloadStatus.failed ||
            updatedTask.status == DownloadStatus.cancelled) {
          _persist();
        }
      },
    );
  }

  void pauseTask(String taskId) {
    _downloadService.pause(taskId);
    state = state.copyWith(
      tasks: state.tasks.map((t) {
        if (t.id == taskId) {
          return t.copyWith(status: DownloadStatus.paused);
        }
        return t;
      }).toList(),
    );
    _persist();
  }

  void resumeTask(String taskId) {
    _downloadService.resume(taskId);
    state = state.copyWith(
      tasks: state.tasks.map((t) {
        if (t.id == taskId) {
          return t.copyWith(status: DownloadStatus.downloading);
        }
        return t;
      }).toList(),
    );
  }

  void cancelTask(String taskId) {
    _downloadService.cancel(taskId);
    state = state.copyWith(
      tasks: state.tasks.map((t) {
        if (t.id == taskId) {
          return t.copyWith(status: DownloadStatus.cancelled);
        }
        return t;
      }).toList(),
    );
    _persist();
  }

  Future<void> removeTask(String taskId) async {
    _downloadService.cancel(taskId);
    state = state.copyWith(
      tasks: state.tasks.where((t) => t.id != taskId).toList(),
    );
    await _persist();
  }

  Future<void> clearAll() async {
    state = const DownloadsState(tasks: []);
    await _persist();
  }
}

final downloadsProvider = StateNotifierProvider<DownloadsNotifier, DownloadsState>((ref) {
  final downloadService = ref.watch(downloadServiceProvider);
  final storageService = ref.watch(storageServiceProvider);
  return DownloadsNotifier(downloadService, storageService, ref);
});
