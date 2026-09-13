import '../tmdb_config.dart';

/// A film and its official trailer on YouTube, from TMDB.
class MovieTrailer {
  final int movieId;
  final String title;
  final String overview;
  final String? backdropPath;
  final String? posterPath;
  final String? year;
  final double rating;

  /// The YouTube id of the best trailer, or null when the film has none.
  final String? youtubeId;

  const MovieTrailer({
    required this.movieId,
    required this.title,
    required this.overview,
    this.backdropPath,
    this.posterPath,
    this.year,
    this.rating = 0,
    this.youtubeId,
  });

  String? get backdropUrl => backdropPath == null ? null : TmdbConfig.backdrop(backdropPath!);
  String? get posterUrl => posterPath == null ? null : TmdbConfig.poster(posterPath!);

  /// YouTube's own still, used when TMDB has no backdrop.
  /// Uses maxresdefault for 4K / 1080p Ultra-HD resolution.
  String get youtubeThumb => 'https://img.youtube.com/vi/$youtubeId/maxresdefault.jpg';
  String get youtubeFallbackThumb => 'https://img.youtube.com/vi/$youtubeId/hqdefault.jpg';

  String get bestImage => backdropUrl ?? (youtubeId != null ? youtubeThumb : (posterUrl ?? ''));

  MovieTrailer withVideo(String? id) => MovieTrailer(
        movieId: movieId,
        title: title,
        overview: overview,
        backdropPath: backdropPath,
        posterPath: posterPath,
        year: year,
        rating: rating,
        youtubeId: id,
      );

  static MovieTrailer? fromMovieJson(Map<String, dynamic> j) {
    final id = j['id'];
    final title = '${j['title'] ?? j['name'] ?? ''}'.trim();
    if (id is! int || title.isEmpty) return null;
    final date = '${j['release_date'] ?? ''}';
    return MovieTrailer(
      movieId: id,
      title: title,
      overview: '${j['overview'] ?? ''}'.trim(),
      backdropPath: (j['backdrop_path'] as String?)?.isEmpty ?? true ? null : j['backdrop_path'] as String?,
      posterPath: (j['poster_path'] as String?)?.isEmpty ?? true ? null : j['poster_path'] as String?,
      year: date.length >= 4 ? date.substring(0, 4) : null,
      rating: (j['vote_average'] is num) ? (j['vote_average'] as num).toDouble() : 0,
    );
  }

  /// The best YouTube trailer key from a TMDB `/videos` result: an official
  /// YouTube "Trailer" if there is one, else any YouTube "Trailer", else any
  /// YouTube "Teaser" or "Clip".
  static String? pickVideoKey(List<dynamic> results) {
    Map<String, dynamic>? best;
    int score(Map<String, dynamic> v) {
      if ('${v['site']}'.toLowerCase() != 'youtube') return -1;
      final type = '${v['type']}'.toLowerCase();
      var s = 0;
      if (type == 'trailer') s += 10;
      if (type == 'teaser') s += 5;
      if (type == 'clip') s += 2;
      if (v['official'] == true) s += 3;
      return s;
    }

    var bestScore = 0;
    for (final v in results) {
      if (v is! Map<String, dynamic>) continue;
      final s = score(v);
      if (s > bestScore && '${v['key'] ?? ''}'.isNotEmpty) {
        bestScore = s;
        best = v;
      }
    }
    return best == null ? null : '${best['key']}';
  }
}
