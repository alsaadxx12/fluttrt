import 'package:flutter/foundation.dart';
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';

/// One title in the history: what was watched, which episode of it, how
/// far it got, and when.
@immutable
class WatchHistoryEntry {
  const WatchHistoryEntry({
    required this.item,
    required this.videoId,
    required this.watchedAt,
    this.episodeLabel = '',
    this.position = Duration.zero,
    this.duration,
  });

  /// The film, or the show — a series is one entry however many episodes.
  final CinemanaItem item;

  /// The catalogue id of what actually played: the film's, or the
  /// episode's. It is what the resume position is kept under.
  final String videoId;

  /// «الموسم 2 · الحلقة 5», or empty for a film.
  final String episodeLabel;

  /// Where it was left.
  final Duration position;

  /// How long it is, once the player has said.
  final Duration? duration;

  final DateTime watchedAt;

  /// 0..1 of the way through, or null before the length is known.
  double? get progress {
    final total = duration;
    if (total == null || total <= Duration.zero) return null;
    return (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
  }

  bool get hasPosition => position > Duration.zero;

  /// True when the title, in either language, holds [query].
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return item.arTitle.toLowerCase().contains(q) ||
        item.enTitle.toLowerCase().contains(q) ||
        episodeLabel.toLowerCase().contains(q) ||
        item.year.contains(q);
  }

  WatchHistoryEntry copyWith({
    CinemanaItem? item,
    String? videoId,
    String? episodeLabel,
    Duration? position,
    Duration? duration,
    DateTime? watchedAt,
  }) =>
      WatchHistoryEntry(
        item: item ?? this.item,
        videoId: videoId ?? this.videoId,
        episodeLabel: episodeLabel ?? this.episodeLabel,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        watchedAt: watchedAt ?? this.watchedAt,
      );

  /// What gets stored for one entry, on the device and in the cloud.
  ///
  /// [CinemanaItem.toJson] is the API shape and leaves out a few fields that
  /// [CinemanaItem.fromJson] does read: the backdrop (`coverUrl`), season and
  /// episode numbers and the two dates. They are added here, under the keys
  /// `fromJson` expects, so an entry comes back exactly as it went in.
  static Map<String, dynamic> encodeItem(CinemanaItem item) => {
        ...item.toJson(),
        'coverUrl': item.backdropUrl,
        'season': item.season,
        'episodeNummer': item.episodeNummer,
        'itemDate': item.itemDate,
        'mDate': item.mDate,
      };

  Map<String, dynamic> toJson() => {
        'item': encodeItem(item),
        'videoId': videoId,
        'episodeLabel': episodeLabel,
        'position': position.inSeconds,
        'duration': duration?.inSeconds ?? 0,
        'watchedAt': watchedAt.toUtc().toIso8601String(),
      };

  static WatchHistoryEntry? fromJson(Map<String, dynamic> json) {
    final rawItem = json['item'];
    if (rawItem is! Map) return null;
    final item = CinemanaItem.fromJson(Map<String, dynamic>.from(rawItem));
    if (item.id.isEmpty) return null;
    final durationSeconds = (json['duration'] as num?)?.toInt() ?? 0;
    return WatchHistoryEntry(
      item: item,
      videoId: '${json['videoId'] ?? item.id}',
      episodeLabel: '${json['episodeLabel'] ?? ''}',
      position: Duration(seconds: (json['position'] as num?)?.toInt() ?? 0),
      duration: durationSeconds > 0 ? Duration(seconds: durationSeconds) : null,
      watchedAt: DateTime.tryParse('${json['watchedAt']}')?.toLocal() ?? DateTime.now(),
    );
  }

  /// «الموسم 2 · الحلقة 5» for [episode], or empty for a film.
  static String labelFor(CinemanaEpisode? episode) {
    if (episode == null) return '';
    final season = episode.seasonNumber.trim();
    final number = episode.episodeNumber.trim();
    return [
      if (season.isNotEmpty && season != '0') 'الموسم $season',
      if (number.isNotEmpty) 'الحلقة $number',
    ].join(' · ');
  }
}
