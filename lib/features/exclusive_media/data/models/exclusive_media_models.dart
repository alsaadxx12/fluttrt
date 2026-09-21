import 'package:flutter/foundation.dart';
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';

enum ExclusiveCategory {
  recent('أحدث الإصدارات', 'recent'),
  series('أحدث المسلسلات', 'series'),
  movies('أحدث الأفلام', 'movies'),
  arabicSeries('مسلسلات عربية', 'series?section=29'),
  foreignSeries('مسلسلات أجنبية', 'series?section=30'),
  turkishSeries('مسلسلات تركية', 'series?section=32'),
  arabicMovies('أفلام عربية', 'movies?section=29'),
  foreignMovies('أفلام أجنبية', 'movies?section=30');

  final String label;
  final String path;
  const ExclusiveCategory(this.label, this.path);
}

@immutable
class ExclusiveMediaItem {
  final String id;
  final String title;
  final String url;
  final String posterUrl;
  final String? backdropUrl;
  final String? year;
  final String? rating;
  final String? quality;
  final String? duration;
  final String? genres;
  final String? story;
  final String? country;
  final String? language;
  final bool isMovie;
  final bool isSeries;

  const ExclusiveMediaItem({
    required this.id,
    required this.title,
    required this.url,
    required this.posterUrl,
    this.backdropUrl,
    this.year,
    this.rating,
    this.quality,
    this.duration,
    this.genres,
    this.story,
    this.country,
    this.language,
    this.isMovie = false,
    this.isSeries = false,
  });

  ExclusiveMediaItem copyWith({
    String? id,
    String? title,
    String? url,
    String? posterUrl,
    String? backdropUrl,
    String? year,
    String? rating,
    String? quality,
    String? duration,
    String? genres,
    String? story,
    String? country,
    String? language,
    bool? isMovie,
    bool? isSeries,
  }) {
    return ExclusiveMediaItem(
      id: id ?? this.id,
      title: title ?? this.title,
      url: url ?? this.url,
      posterUrl: posterUrl ?? this.posterUrl,
      backdropUrl: backdropUrl ?? this.backdropUrl,
      year: year ?? this.year,
      rating: rating ?? this.rating,
      quality: quality ?? this.quality,
      duration: duration ?? this.duration,
      genres: genres ?? this.genres,
      story: story ?? this.story,
      country: country ?? this.country,
      language: language ?? this.language,
      isMovie: isMovie ?? this.isMovie,
      isSeries: isSeries ?? this.isSeries,
    );
  }

  /// Converts this item to a [CinemanaItem] so it displays natively inside
  /// app home sections, poster carousels, and lists.
  CinemanaItem toCinemanaItem() {
    remember(this);
    final cleanYear = year ?? '2026';
    return CinemanaItem(
      id: id,
      arTitle: title,
      enTitle: title,
      stars: rating ?? '8.0',
      year: cleanYear,
      kind: isMovie ? '1' : '2',
      arContent: story ?? '',
      enContent: story ?? '',
      imgUrl: posterUrl,
      imgMediumUrl: posterUrl,
      imgThumbUrl: posterUrl,
      backdropUrl: backdropUrl ?? posterUrl,
      externalSource: externalSourceKey,
      categories: genres != null && genres!.isNotEmpty
          ? genres!.split('•').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
          : (isMovie ? ['أفلام حصرية'] : ['مسلسلات حصرية']),
    );
  }

  static const String externalSourceKey = 'exclusive-media';

  static final Map<String, ExclusiveMediaItem> _byId = {};

  static void remember(ExclusiveMediaItem item) {
    if (_byId.length > 800) _byId.clear();
    _byId[item.id] = item;
  }

  static ExclusiveMediaItem? byId(String id) => _byId[id];

  /// Strips any trace of source branding words from synopses/descriptions
  static String sanitizeText(String text) {
    return text
        .replaceAll('اكوام', '')
        .replaceAll('أكوام', '')
        .replaceAll('akwam.ss', '')
        .replaceAll('Akwam.ss', '')
        .replaceAll('Akwam', '')
        .replaceAll('akwam', '')
        .replaceAll('موقع', '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExclusiveMediaItem && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

@immutable
class ExclusiveEpisode {
  final int number;
  final String title;
  final String url;
  final String? thumbnailUrl;
  final String? date;

  const ExclusiveEpisode({
    required this.number,
    required this.title,
    required this.url,
    this.thumbnailUrl,
    this.date,
  });
}

@immutable
class ExclusiveStream {
  final String url;
  final String quality; // e.g. "1080p", "720p", "480p"
  final String? size;

  const ExclusiveStream({
    required this.url,
    required this.quality,
    this.size,
  });
}

@immutable
class ExclusiveDetails {
  final ExclusiveMediaItem item;
  final List<ExclusiveEpisode> episodes;

  const ExclusiveDetails({
    required this.item,
    required this.episodes,
  });
}
