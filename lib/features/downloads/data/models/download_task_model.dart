enum DownloadType {
  video,
  audio;

  String get displayName => this == DownloadType.video ? 'Video' : 'Audio';
}

enum DownloadStatus {
  queued,
  downloading,
  paused,
  completed,
  failed,
  cancelled;

  bool get isActive => this == DownloadStatus.downloading || this == DownloadStatus.queued;
  bool get isDone => this == DownloadStatus.completed;
  bool get isFailed => this == DownloadStatus.failed;
}

class DownloadTaskModel {
  final String id;
  final String videoId;
  final String videoUrl;
  final String title;
  final String author;
  final String thumbnailUrl;
  final Duration? duration;
  final String qualityLabel;
  final DownloadType downloadType;
  final String format; // 'mp4', 'mp3', 'm4a', etc.
  final String filePath;
  final int totalBytes;
  final int downloadedBytes;
  final double speedBytesPerSec;
  final Duration? eta;
  final double progress; // 0.0 to 1.0
  final DownloadStatus status;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime? completedAt;

  const DownloadTaskModel({
    required this.id,
    required this.videoId,
    required this.videoUrl,
    required this.title,
    required this.author,
    required this.thumbnailUrl,
    this.duration,
    required this.qualityLabel,
    required this.downloadType,
    required this.format,
    required this.filePath,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.speedBytesPerSec = 0,
    this.eta,
    this.progress = 0.0,
    this.status = DownloadStatus.queued,
    this.errorMessage,
    required this.createdAt,
    this.completedAt,
  });

  DownloadTaskModel copyWith({
    String? id,
    String? videoId,
    String? videoUrl,
    String? title,
    String? author,
    String? thumbnailUrl,
    Duration? duration,
    String? qualityLabel,
    DownloadType? downloadType,
    String? format,
    String? filePath,
    int? totalBytes,
    int? downloadedBytes,
    double? speedBytesPerSec,
    Duration? eta,
    double? progress,
    DownloadStatus? status,
    String? errorMessage,
    DateTime? createdAt,
    DateTime? completedAt,
  }) {
    return DownloadTaskModel(
      id: id ?? this.id,
      videoId: videoId ?? this.videoId,
      videoUrl: videoUrl ?? this.videoUrl,
      title: title ?? this.title,
      author: author ?? this.author,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      duration: duration ?? this.duration,
      qualityLabel: qualityLabel ?? this.qualityLabel,
      downloadType: downloadType ?? this.downloadType,
      format: format ?? this.format,
      filePath: filePath ?? this.filePath,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
      eta: eta ?? this.eta,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'videoId': videoId,
      'videoUrl': videoUrl,
      'title': title,
      'author': author,
      'thumbnailUrl': thumbnailUrl,
      'durationMs': duration?.inMilliseconds,
      'qualityLabel': qualityLabel,
      'downloadType': downloadType.name,
      'format': format,
      'filePath': filePath,
      'totalBytes': totalBytes,
      'downloadedBytes': downloadedBytes,
      'progress': progress,
      'status': status.name,
      'errorMessage': errorMessage,
      'createdAt': createdAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
    };
  }

  factory DownloadTaskModel.fromJson(Map<String, dynamic> json) {
    return DownloadTaskModel(
      id: json['id'] as String,
      videoId: json['videoId'] as String? ?? '',
      videoUrl: json['videoUrl'] as String? ?? '',
      title: json['title'] as String? ?? '',
      author: json['author'] as String? ?? '',
      thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
      duration: json['durationMs'] != null ? Duration(milliseconds: json['durationMs'] as int) : null,
      qualityLabel: json['qualityLabel'] as String? ?? '',
      downloadType: DownloadType.values.firstWhere(
        (e) => e.name == json['downloadType'],
        orElse: () => DownloadType.video,
      ),
      format: json['format'] as String? ?? 'mp4',
      filePath: json['filePath'] as String? ?? '',
      totalBytes: json['totalBytes'] as int? ?? 0,
      downloadedBytes: json['downloadedBytes'] as int? ?? 0,
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      status: DownloadStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => DownloadStatus.completed,
      ),
      errorMessage: json['errorMessage'] as String?,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      completedAt: json['completedAt'] != null ? DateTime.tryParse(json['completedAt'] as String) : null,
    );
  }
}
