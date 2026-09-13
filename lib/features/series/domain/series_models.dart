import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class EpisodeItem {
  final int episodeNumber;
  final int seasonNumber;
  final Video primaryVideo;
  final List<Video> alternativeVideos; // Other uploaders/channels who uploaded this same episode
  final String cleanTitle;

  const EpisodeItem({
    required this.episodeNumber,
    this.seasonNumber = 1,
    required this.primaryVideo,
    this.alternativeVideos = const [],
    required this.cleanTitle,
  });

  int get totalSources => 1 + alternativeVideos.length;

  EpisodeItem copyWith({
    int? episodeNumber,
    int? seasonNumber,
    Video? primaryVideo,
    List<Video>? alternativeVideos,
    String? cleanTitle,
  }) {
    return EpisodeItem(
      episodeNumber: episodeNumber ?? this.episodeNumber,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      primaryVideo: primaryVideo ?? this.primaryVideo,
      alternativeVideos: alternativeVideos ?? this.alternativeVideos,
      cleanTitle: cleanTitle ?? this.cleanTitle,
    );
  }

  /// Creates a new EpisodeItem with a different alternative video promoted to primary
  EpisodeItem switchPrimary(Video newPrimary) {
    if (newPrimary.id.value == primaryVideo.id.value) return this;
    final updatedAlternatives = [
      primaryVideo,
      ...alternativeVideos.where((v) => v.id.value != newPrimary.id.value),
    ];
    return copyWith(
      primaryVideo: newPrimary,
      alternativeVideos: updatedAlternatives,
    );
  }
}

class SeriesModel {
  final String seriesName;
  final List<EpisodeItem> episodes;
  final List<int> availableSeasons;
  final int totalSourcesFound;

  const SeriesModel({
    required this.seriesName,
    required this.episodes,
    this.availableSeasons = const [1],
    this.totalSourcesFound = 0,
  });

  int get totalEpisodes => episodes.length;

  bool get isEmpty => episodes.isEmpty;
  bool get isNotEmpty => episodes.isNotEmpty;

  List<EpisodeItem> getEpisodesForSeason(int season) {
    return episodes.where((e) => e.seasonNumber == season).toList();
  }
}
