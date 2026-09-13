import 'dart:async';

import 'package:dio/dio.dart';

import '../tmdb_config.dart';
import 'movie_trailer.dart';

/// Reads films and their official trailers from TMDB.
///
/// TMDB is an official free API; nothing here scrapes or rebroadcasts. Films
/// come from the popular/now-playing lists, and each film's trailer from the
/// official `/movie/{id}/videos` endpoint. Playback is the trailer on
/// YouTube's own player, so no video is served by us.
class TmdbService {
  TmdbService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: TmdbConfig.apiBase,
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 15),
              headers: {
                'Authorization': 'Bearer ${TmdbConfig.bearerToken}',
                'Accept': 'application/json',
              },
            ));

  final Dio _dio;

  /// Films now in cinemas (Arabic where TMDB has it), each already carrying
  /// its best YouTube trailer; films without a trailer are dropped.
  Future<List<MovieTrailer>> trending({int limit = 12}) async {
    if (!TmdbConfig.isConfigured) return const [];
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/movie/now_playing',
        queryParameters: {'language': 'ar', 'page': 1, 'region': 'US'},
      );
      final results = (res.data?['results'] as List?) ?? const [];
      final films = results
          .whereType<Map<String, dynamic>>()
          .map((m) => MovieTrailer.fromMovieJson(m))
          .whereType<MovieTrailer>()
          .toList();

      // Resolve trailers for the first [limit] films, a few at a time so the
      // API is not hit with a burst.
      final out = <MovieTrailer>[];
      for (final film in films.take(limit + 6)) {
        final key = await _videoKey(film.movieId);
        if (key != null) out.add(film.withVideo(key));
        if (out.length >= limit) break;
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// The best trailer key for one film, or null.
  Future<String?> _videoKey(int movieId) async {
    try {
      // Ask in English too: many films have no Arabic-tagged trailer.
      final res = await _dio.get<Map<String, dynamic>>(
        '/movie/$movieId/videos',
        queryParameters: {'language': 'en-US'},
      );
      final results = (res.data?['results'] as List?) ?? const [];
      return MovieTrailer.pickVideoKey(results);
    } catch (_) {
      return null;
    }
  }
}
