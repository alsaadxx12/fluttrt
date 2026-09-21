import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:youtube_downloader/features/series/domain/series_models.dart';

class PlayableItem {
  final String id;
  final String title;
  final String author;
  final Duration? duration;
  final String thumbnailUrl;
  final int? episodeNumber;
  final int? seasonNumber;
  final String? seriesName;

  /// Metadata shown on the watch page's header and suggestion tiles. Each is
  /// optional: an item built by hand (a series episode, a test) has none.
  final int? viewCount;
  final DateTime? uploadDate;
  final String? description;
  final String? channelId;

  const PlayableItem({
    required this.id,
    required this.title,
    required this.author,
    this.duration,
    required this.thumbnailUrl,
    this.episodeNumber,
    this.seasonNumber,
    this.seriesName,
    this.viewCount,
    this.uploadDate,
    this.description,
    this.channelId,
  });

  factory PlayableItem.fromVideo(Video v, {String? seriesName, int? epNum, int? seasonNum}) {
    final thumb = v.thumbnails.highResUrl.isNotEmpty
        ? v.thumbnails.highResUrl
        : 'https://i.ytimg.com/vi/${v.id.value}/hqdefault.jpg';
    final description = v.description.trim();
    return PlayableItem(
      id: v.id.value,
      title: v.title,
      author: v.author,
      duration: v.duration,
      thumbnailUrl: thumb,
      episodeNumber: epNum,
      seasonNumber: seasonNum,
      seriesName: seriesName,
      viewCount: v.engagement.viewCount,
      uploadDate: v.uploadDate ?? v.publishDate,
      description: description.isEmpty ? null : description,
      channelId: v.channelId.value,
    );
  }

  factory PlayableItem.fromEpisode(EpisodeItem ep, {required String seriesName}) {
    return PlayableItem.fromVideo(
      ep.primaryVideo,
      seriesName: seriesName,
      epNum: ep.episodeNumber,
      seasonNum: ep.seasonNumber,
    );
  }
}

class StreamQualityOption {
  final String label;
  final String streamUrl;
  final String? audioUrl;
  final String? ytdlFormat;
  final bool isMuxed;

  const StreamQualityOption({
    required this.label,
    required this.streamUrl,
    this.audioUrl,
    this.ytdlFormat,
    this.isMuxed = true,
  });
}

class WatchPlaylistContext {
  final String? title;
  final List<PlayableItem> items;
  final int currentIndex;

  const WatchPlaylistContext({
    this.title,
    required this.items,
    this.currentIndex = 0,
  });

  PlayableItem? get currentItem =>
      (currentIndex >= 0 && currentIndex < items.length) ? items[currentIndex] : null;

  bool get hasNext => currentIndex + 1 < items.length;
  bool get hasPrevious => currentIndex > 0;

  PlayableItem? get nextItem => hasNext ? items[currentIndex + 1] : null;
  PlayableItem? get previousItem => hasPrevious ? items[currentIndex - 1] : null;

  WatchPlaylistContext copyWith({
    String? title,
    List<PlayableItem>? items,
    int? currentIndex,
  }) {
    return WatchPlaylistContext(
      title: title ?? this.title,
      items: items ?? this.items,
      currentIndex: currentIndex ?? this.currentIndex,
    );
  }
}
