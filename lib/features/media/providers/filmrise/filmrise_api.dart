import 'package:dio/dio.dart';

/// Which catalogue on the Future Today / FilmRise backend to read.
///
/// The host is shared by several of their apps and the catalogue is chosen
/// by [appId] / [siteId]. Point these at the film catalogue; the values below
/// are the ones that were supplied, and they serve the Fawesome/iFood short
/// video feed rather than films, so [FilmRiseApi.looksLikeFilm] filters
/// everything that is not a film or an episode out before it can reach the
/// library.
class FilmRiseConfig {
  final String baseUrl;
  final String appId;
  final String siteId;

  const FilmRiseConfig({
    this.baseUrl = 'https://rapi.ifood.tv/',
    this.appId = '7',
    this.siteId = '1',
  });
}

/// One raw row from the API, before anything interprets it.
class FilmRiseRow {
  final String id;
  final String title;
  final String type;
  final String feedType;
  final String? picture;
  final String? mainPicture;
  final String? videoUrl;
  final String? videoFormat;
  final String? nodeId;
  final String? author;
  final String? pathAlias;
  final String? description;
  final int? durationSeconds;
  final int? year;
  final String? captionsUrl;

  const FilmRiseRow({
    required this.id,
    required this.title,
    required this.type,
    required this.feedType,
    this.picture,
    this.mainPicture,
    this.videoUrl,
    this.videoFormat,
    this.nodeId,
    this.author,
    this.pathAlias,
    this.description,
    this.durationSeconds,
    this.year,
    this.captionsUrl,
  });

  factory FilmRiseRow.fromJson(Map<String, dynamic> j) {
    String? s(String k) {
      final v = j[k];
      final t = v == null ? '' : '$v'.trim();
      return t.isEmpty || t == 'null' || t == 'false' ? null : t;
    }

    int? i(String k) {
      final v = j[k];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('${v ?? ''}'.trim());
    }

    return FilmRiseRow(
      id: s('id') ?? s('node_id') ?? '',
      title: s('title') ?? '',
      type: s('type') ?? '',
      feedType: s('feed_type') ?? '',
      picture: s('picture'),
      mainPicture: s('main_picture'),
      videoUrl: s('video_url') ?? s('video_flv_url'),
      videoFormat: s('video_format'),
      nodeId: s('node_id'),
      author: s('author'),
      pathAlias: s('path_alias'),
      description: s('description') ?? s('summary') ?? s('teaser'),
      durationSeconds: i('duration') ?? i('video_duration') ?? i('length'),
      year: i('year') ?? i('release_year') ?? i('production_year'),
      captionsUrl: s('cc_url') ?? s('caption_url') ?? s('subtitle_url') ?? s('closed_caption'),
    );
  }

  /// The catalogue section this row sits in ("movies", "kids-edutainment"…).
  String get section => (pathAlias ?? '').split('/').first.toLowerCase();
}

/// Talks to the Future Today / FilmRise backend. Returns raw rows only; the
/// adapter decides what any of it means.
class FilmRiseApi {
  final FilmRiseConfig config;
  final Dio _dio;

  FilmRiseApi({this.config = const FilmRiseConfig(), Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
              headers: const {'User-Agent': 'okhttp/4.9.0'},
            ));

  Map<String, dynamic> get _base => {'appId': config.appId, 'siteId': config.siteId};

  /// One page of the catalogue. [searchType] is the backend's own word for
  /// a feed; 'popular' and 'search' are the two it accepts.
  Future<List<FilmRiseRow>> fetch({
    String searchType = 'popular',
    String? query,
    String? section,
    int page = 0,
  }) async {
    final res = await _dio.get<dynamic>(
      '${config.baseUrl}recipes.php',
      queryParameters: {
        ..._base,
        'searchType': searchType,
        if (query != null && query.isNotEmpty) 'searchString': query,
        if (section != null && section.isNotEmpty) 'parent': section,
        if (page > 0) 'page': page,
      },
    );
    final data = res.data;
    if (data is! Map) return const [];
    if ('${data['status']}' != 'ok') return const [];
    final rows = data['results'];
    if (rows is! List) return const [];
    return [
      for (final r in rows)
        if (r is Map<String, dynamic>) FilmRiseRow.fromJson(r),
    ];
  }

  /// Sections that hold films and series rather than short clips.
  static const filmSections = {'movies', 'movie', 'tv', 'tv-shows', 'series', 'shows', 'film', 'films'};

  /// Words that mark a row as a short clip whatever section it claims.
  static final _clipHints = RegExp(
    r'(recipe|how to|diy|vlog|challenge|tiktok|prank|unboxing|asmr|shorts?|episode \d+ of a podcast)',
    caseSensitive: false,
  );

  /// The backend serves cooking clips, kids videos and films from the same
  /// endpoint, so nothing is trusted into the library without evidence that
  /// it is a film or an episode: it must sit in a film section, or be long
  /// enough to be a feature, or say so in its feed type.
  static bool looksLikeFilm(FilmRiseRow row) {
    if (row.title.isEmpty || (row.videoUrl ?? '').isEmpty) return false;
    if (_clipHints.hasMatch(row.title)) return false;
    final feed = row.feedType.toLowerCase();
    if (feed == 'movie' || feed == 'series' || feed == 'episode' || feed == 'show') return true;
    if (filmSections.contains(row.section)) return true;
    // A feature runs longer than any clip in these feeds.
    final secs = row.durationSeconds ?? 0;
    return secs >= 40 * 60;
  }
}
