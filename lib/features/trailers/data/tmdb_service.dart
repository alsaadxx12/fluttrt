import 'dart:async';

import 'package:dio/dio.dart';

import 'package:youtube_downloader/core/network/http_cache.dart';
import '../tmdb_config.dart';
import 'movie_trailer.dart';

/// Reads films and their official trailers from TMDB.
///
/// TMDB is an official free API; nothing here scrapes or rebroadcasts. Films
/// come from the popular list, paged so the row never runs out, and each
/// film's trailer from the official `/movie/{id}/videos` endpoint. Playback is
/// the trailer's own stream, so no video is served by us.
class TmdbService {
  TmdbService({Dio? dio})
      : _dio = dio ??
            createDio(BaseOptions(
              baseUrl: TmdbConfig.apiBase,
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 15),
              headers: {
                'Authorization': 'Bearer ${TmdbConfig.bearerToken}',
                'Accept': 'application/json',
              },
            ));

  final Dio _dio;

  /// The first page of the endless feed. Kept for callers that want a quick
  /// initial batch.
  Future<List<MovieTrailer>> trending({int limit = 12}) => feedPage(1, want: limit);

  /// One page of the endless trailers feed: the newest released films first,
  /// that have a trailer.
  ///
  /// Uses `/discover/movie` sorted by release date descending and bounded to
  /// films already released (not future ones), so the feed opens with this
  /// year's latest theatrical releases and walks back in time from there —
  /// hundreds of pages, so it effectively never ends. Video lookups run in
  /// batches of five and stop as soon as [want] trailers are collected, so a
  /// page costs a few round trips rather than twenty requests at once.
  Future<List<MovieTrailer>> feedPage(int page, {int want = 10}) async {
    if (!TmdbConfig.isConfigured || page < 1) return const [];
    try {
      final today = DateTime.now();
      final todayStr = '${today.year.toString().padLeft(4, '0')}-'
          '${today.month.toString().padLeft(2, '0')}-'
          '${today.day.toString().padLeft(2, '0')}';
      final res = await _dio.get<Map<String, dynamic>>(
        '/discover/movie',
        queryParameters: {
          'language': 'ar',
          'region': 'US',
          'page': page,
          'sort_by': 'primary_release_date.desc',
          'primary_release_date.lte': todayStr,
          'with_release_type': '2|3', // theatrical (limited + wide)
          'vote_count.gte': 5, // trim noise while keeping recent mainstream
          'include_adult': false,
          'include_video': false,
        },
      );
      final results = (res.data?['results'] as List?) ?? const [];
      final films = results
          .whereType<Map<String, dynamic>>()
          .map((m) => MovieTrailer.fromMovieJson(m))
          .whereType<MovieTrailer>()
          .toList();

      // Resolve trailer keys five films at a time, keeping those that have
      // one, until enough are collected.
      const batchSize = 5;
      final out = <MovieTrailer>[];
      for (var i = 0; i < films.length && out.length < want; i += batchSize) {
        final batch = films.sublist(i, (i + batchSize).clamp(0, films.length));
        final keys = await Future.wait(batch.map((f) => _videoKey(f.movieId)));
        for (var j = 0; j < batch.length; j++) {
          final key = keys[j];
          if (key != null) out.add(batch[j].withVideo(key));
          if (out.length >= want) break;
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// The best YouTube trailer key for a title, found by searching TMDB by name
  /// (and year, when known). Used to give any film or series a trailer even
  /// when the library carries no trailer link of its own. Null when nothing
  /// matches.
  Future<String?> trailerForTitle(String title, {String? year}) async {
    final q = title.trim();
    if (!TmdbConfig.isConfigured || q.isEmpty) return null;
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/search/multi',
        queryParameters: {
          'query': q,
          'language': 'en-US',
          if (year != null && year.isNotEmpty) 'year': year,
          'include_adult': false,
        },
      );
      final results = (res.data?['results'] as List?) ?? const [];
      for (final r in results.whereType<Map<String, dynamic>>()) {
        final type = '${r['media_type']}';
        final id = r['id'];
        if (id is! int) continue;
        if (type == 'movie') {
          final key = await _videoKey(id, path: '/movie/$id/videos');
          if (key != null) return key;
        } else if (type == 'tv') {
          final key = await _videoKey(id, path: '/tv/$id/videos');
          if (key != null) return key;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// A wide still from the film called [title], or null when TMDB has none.
  ///
  /// The catalogue's own art is posters; a collection staged big wants a
  /// landscape, and TMDB has one for nearly every film people know by
  /// name. Searched by title and year, the first match with a backdrop
  /// wins.
  Future<String?> backdropForTitle(String title, {String? year}) async {
    final q = title.trim();
    if (!TmdbConfig.isConfigured || q.isEmpty) return null;
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/search/multi',
        queryParameters: {
          'query': q,
          'language': 'en-US',
          if (year != null && year.isNotEmpty) 'year': year,
          'include_adult': false,
        },
      );
      final results = (res.data?['results'] as List?) ?? const [];
      for (final r in results.whereType<Map<String, dynamic>>()) {
        if (r['media_type'] == 'person') continue;
        final path = r['backdrop_path'];
        if (path is String && path.isNotEmpty) {
          return 'https://image.tmdb.org/t/p/w1280$path';
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// The best trailer key for one film, or null.
  Future<String?> _videoKey(int movieId, {String? path}) async {
    try {
      // Ask in English too: many films have no Arabic-tagged trailer.
      final res = await _dio.get<Map<String, dynamic>>(
        path ?? '/movie/$movieId/videos',
        queryParameters: {'language': 'en-US'},
      );
      final results = (res.data?['results'] as List?) ?? const [];
      return MovieTrailer.pickVideoKey(results);
    } catch (_) {
      return null;
    }
  }
}
