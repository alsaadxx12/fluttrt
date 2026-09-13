/// Viu (MENA) catalogue types, read from the public web API.
library;

int _int(Object? v) => v is int ? v : int.tryParse('${v ?? ''}') ?? 0;
String _str(Object? v) => v == null ? '' : '$v'.trim();

String? _url(Object? v) {
  final s = _str(v);
  return s.startsWith('http') ? s : null;
}

/// The Viu categories shown on the home page.
class ViuCategory {
  final String id;
  final String title;
  final bool isMovies;

  const ViuCategory(this.id, this.title, {this.isMovies = false});

  static const arabic = ViuCategory('726', 'مسلسلات عربية');
  static const korean = ViuCategory('846', 'مسلسلات كورية');
  static const turkish = ViuCategory('847', 'مسلسلات تركية');
  static const movies = ViuCategory('848', 'أفلام أخرى', isMovies: true);

  static const home = [arabic, korean, turkish, movies];
}

/// A series (or a film, which Viu also files as a one-episode series).
class ViuShow {
  final String seriesId;
  final String name;
  final String description;
  final String? portraitUrl;
  final String? landscapeUrl;
  final String categoryName;
  final bool isMovie;

  /// Access level of the entry Viu lists for it (0 = free for everyone).
  final int userLevel;

  /// Viu lists the same title more than once - original and Arabic-dubbed,
  /// or an extra "يعرض الآن" entry while it airs. Those other entries ride
  /// along here so the title gets one card.
  final List<ViuShow> alternates;

  const ViuShow({
    required this.seriesId,
    required this.name,
    this.description = '',
    this.portraitUrl,
    this.landscapeUrl,
    this.categoryName = '',
    this.isMovie = false,
    this.userLevel = 0,
    this.alternates = const [],
  });

  static final _dubbedMark = RegExp(r'\s*[-–(]?\s*مدبلج\s*\)?');
  static final _airingMark = RegExp(r'\s*[-–]?\s*يعرض الآن');

  /// "بنات الشمس - مدبلج" -> "بنات الشمس"; the version shows as a badge.
  String get displayName => name.replaceAll(_dubbedMark, '').replaceAll(_airingMark, '').trim();

  bool get isDubbed => name.contains('مدبلج');

  bool get isAiring => name.contains('يعرض الآن');

  /// This entry and its other versions.
  List<ViuShow> get versions => [this, ...alternates];

  bool get hasDubbedVersion => versions.any((v) => v.isDubbed);
  bool get hasOriginalVersion => versions.any((v) => !v.isDubbed);

  /// What sets this version apart from the others of the same title.
  String get versionLabel {
    if (isDubbed) return 'مدبلج';
    if (isAiring) return 'يعرض الآن';
    return categoryName.contains('عربي') ? 'الأصلي' : 'مترجم';
  }

  /// Same for every version of a title: the name without version marks,
  /// with Arabic spelling variants (hamza, taa marbuta, commas) evened out.
  /// Seasons stay apart ("الموسم 2" is another title).
  String get titleKey {
    var k = displayName
        .replaceAll(RegExp('[أإآٱ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll('ـ', '')
        .replaceAll(RegExp('[،,.:؛;!?؟"\'()\\[\\]\\-–_]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
    // "معجزة القرن 1" is "معجزة القرن" (but "الموسم 1" / "الجزء 1" stay).
    k = k.replaceFirst(RegExp(r'(?<!الموسم|الجزء)\s+1$'), '');
    return k;
  }

  ViuShow withAlternate(ViuShow other) => ViuShow(
        seriesId: seriesId,
        name: name,
        description: description,
        portraitUrl: portraitUrl,
        landscapeUrl: landscapeUrl,
        categoryName: categoryName,
        isMovie: isMovie,
        userLevel: userLevel,
        alternates: [...alternates, other, ...other.alternates],
      );

  /// One entry per title, in the order Viu lists them.
  static List<ViuShow> mergeVersions(Iterable<ViuShow> shows) {
    final out = <ViuShow>[];
    final at = <String, int>{};
    for (final s in shows) {
      final i = at[s.titleKey];
      if (i == null) {
        at[s.titleKey] = out.length;
        out.add(s);
      } else if (!out[i].versions.any((v) => v.seriesId == s.seriesId)) {
        out[i] = out[i].withAlternate(s);
      }
    }
    return out;
  }

  /// Viu files trailers as their own "series"; they are not shows.
  bool get isTrailer => name.contains('إعلان') || name.toLowerCase().contains('trailer');

  factory ViuShow.fromSeries(Map<String, dynamic> j) => ViuShow(
        seriesId: _str(j['series_id'] ?? j['id']),
        name: _str(j['name'] ?? j['series_name']),
        description: _str(j['description']),
        portraitUrl: _url(j['cover_portrait_image_url']) ?? _url(j['series_image_url']) ?? _url(j['cover_image_url']),
        landscapeUrl: _url(j['cover_landscape_image_url']) ?? _url(j['cover_image_url']),
        categoryName: _str(j['category_name'] ?? j['series_category_name']),
        isMovie: _int(j['is_movie']) == 1,
        userLevel: _int(j['user_level']),
      );

  /// A product (episode/film) as it appears in the home page grids.
  factory ViuShow.fromGridProduct(Map<String, dynamic> j) => ViuShow(
        seriesId: _str(j['series_id']),
        name: _str(j['series_name']),
        description: _str(j['description']),
        portraitUrl: _url(j['cover_portrait_image_url']) ?? _url(j['cover_image_url']),
        landscapeUrl: _url(j['cover_landscape_image_url']) ?? _url(j['cover_image_url']),
        categoryName: _str(j['series_category_name']),
        isMovie: _int(j['is_movie']) == 1,
        userLevel: _int(j['user_level']),
      );
}

/// One episode (or the film itself).
class ViuEpisode {
  final String productId;
  final String ccsProductId;
  final int number;
  final String title;
  final String description;
  final String? coverUrl;
  final int durationSec;
  final int userLevel;

  const ViuEpisode({
    required this.productId,
    required this.ccsProductId,
    required this.number,
    this.title = '',
    this.description = '',
    this.coverUrl,
    this.durationSec = 0,
    this.userLevel = 0,
  });

  /// Free for everyone (no subscription).
  bool get isFree => userLevel == 0;

  String get durationLabel {
    if (durationSec <= 0) return '';
    final m = (durationSec / 60).round();
    return m >= 60 ? '${m ~/ 60} س ${m % 60} د' : '$m د';
  }

  factory ViuEpisode.fromJson(Map<String, dynamic> j) => ViuEpisode(
        productId: _str(j['product_id']),
        ccsProductId: _str(j['ccs_product_id']),
        number: _int(j['number']),
        title: _str(j['synopsis']),
        description: _str(j['description']),
        coverUrl: _url(j['cover_landscape_image_url']) ?? _url(j['cover_image_url']),
        durationSec: _int(j['time_duration']),
        userLevel: _int(j['user_level']),
      );
}

/// One playable quality of an episode.
class ViuQuality {
  final String label; // "720p"
  final String url; // HLS
  const ViuQuality(this.label, this.url);
}

/// What the player needs for one episode.
class ViuPlayback {
  final List<ViuQuality> qualities; // low -> high
  final String? arabicSubtitleUrl;

  const ViuPlayback({required this.qualities, this.arabicSubtitleUrl});
}

class ViuException implements Exception {
  final String message;
  const ViuException(this.message);
  @override
  String toString() => message;
}
