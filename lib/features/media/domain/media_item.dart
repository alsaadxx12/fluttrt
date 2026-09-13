/// One work, whatever provider it came from.
///
/// The UI only ever sees this model, never a provider's own JSON shape. A
/// work that exists in more than one provider is still ONE [MediaItem] with
/// several entries in [sources].
library;

enum MediaKind { movie, series, episode }

/// Where one provider keeps this work. Kept even when another provider is
/// the one being played, so a failed stream can fall back.
class MediaSource {
  /// 'cinemana', 'filmrise', …
  final String provider;

  /// The provider's own id for this work.
  final String externalId;

  /// A direct stream when the provider hands one out up front; otherwise
  /// null and the provider resolves it at play time.
  final String? streamUrl;

  final String? posterUrl;
  final String? backdropUrl;

  /// The provider offers subtitles or closed captions for this work.
  final bool hasSubtitles;

  const MediaSource({
    required this.provider,
    required this.externalId,
    this.streamUrl,
    this.posterUrl,
    this.backdropUrl,
    this.hasSubtitles = false,
  });

  @override
  String toString() => '$provider:$externalId';
}

class MediaItem {
  /// The normalised identity of the work, shared across providers.
  /// See MediaKey.
  final String contentId;

  /// What the user reads. Arabic when a provider has it.
  final String title;

  /// The Latin/original title, used for matching across providers.
  final String originalTitle;

  final int? year;
  final MediaKind kind;
  final String? overview;

  /// Minutes, when known.
  final int? duration;
  final List<String> genres;

  /// Episodes only.
  final String? seriesTitle;
  final int? seasonNumber;
  final int? episodeNumber;

  /// Every provider that carries this work, best first.
  final List<MediaSource> sources;

  const MediaItem({
    required this.contentId,
    required this.title,
    required this.originalTitle,
    required this.kind,
    this.year,
    this.overview,
    this.duration,
    this.genres = const [],
    this.seriesTitle,
    this.seasonNumber,
    this.episodeNumber,
    this.sources = const [],
  });

  /// The provider to play from: the first that survived merging.
  MediaSource? get primarySource => sources.isEmpty ? null : sources.first;

  /// The next provider to try when [primarySource] fails.
  MediaSource? get fallbackSource => sources.length < 2 ? null : sources[1];

  /// The best artwork among the sources: the primary provider's, unless it
  /// has none, in which case any other provider's fills the gap. A different
  /// picture never makes a second card.
  String? get posterUrl {
    for (final s in sources) {
      if ((s.posterUrl ?? '').isNotEmpty) return s.posterUrl;
    }
    return null;
  }

  String? get backdropUrl {
    for (final s in sources) {
      if ((s.backdropUrl ?? '').isNotEmpty) return s.backdropUrl;
    }
    return null;
  }

  bool hasProvider(String provider) => sources.any((s) => s.provider == provider);

  /// Same work, seen by another provider: keep this item's own fields and
  /// add the other's source and anything this one was missing.
  MediaItem mergedWith(MediaItem other) => MediaItem(
        contentId: contentId,
        title: title,
        originalTitle: originalTitle.isNotEmpty ? originalTitle : other.originalTitle,
        kind: kind,
        year: year ?? other.year,
        overview: (overview ?? '').isNotEmpty ? overview : other.overview,
        duration: duration ?? other.duration,
        genres: genres.isNotEmpty ? genres : other.genres,
        seriesTitle: seriesTitle ?? other.seriesTitle,
        seasonNumber: seasonNumber ?? other.seasonNumber,
        episodeNumber: episodeNumber ?? other.episodeNumber,
        sources: [
          ...sources,
          ...other.sources.where((o) => !sources.any((s) => s.provider == o.provider && s.externalId == o.externalId)),
        ],
      );

  @override
  String toString() => '$title (${year ?? '-'}) [${sources.join(', ')}]';
}
