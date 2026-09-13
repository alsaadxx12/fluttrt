import 'package:dio/dio.dart';
import 'package:youtube_downloader/core/network/http_cache.dart';
import '../models/cinemana_models.dart';

class KrmziService {
  KrmziService({Dio? dio})
      : _dio = dio ??
            createDio(
              BaseOptions(
                baseUrl: 'https://krmzitv.app/wp-json/',
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 12),
                headers: {
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
                  'Accept': 'application/json',
                },
              ),
            );

  final Dio _dio;

  /// Helper to convert Krmzi genre string (e.g. "Drama، حركة، عائلي") into clean categories list
  List<String> _parseGenres(dynamic raw) {
    if (raw == null) return const [];
    final str = raw.toString();
    if (str.isEmpty) return const [];
    return str
        .split(RegExp(r'[,،]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Clean title string removing extra trailing tags for display
  String _cleanDisplayTitle(String title) {
    return title.trim();
  }

  /// 1. Fetch Movies from Krmzi
  Future<List<CinemanaItem>> fetchMovies({int page = 1}) async {
    try {
      final response = await _dio.get('api-3chk/v1/movies', queryParameters: {'page': page});
      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data['data'];
        if (data is List) {
          return data.map((item) {
            final m = item as Map<String, dynamic>;
            final id = m['id']?.toString() ?? '';
            final title = _cleanDisplayTitle(m['title']?.toString() ?? '');
            final poster = m['poster']?.toString();
            final year = m['year']?.toString() ?? '';
            final imdb = m['imdb']?.toString() ?? '';
            final genres = _parseGenres(m['genres']);

            return CinemanaItem(
              id: 'krmzi_mov_$id',
              arTitle: title,
              enTitle: '',
              stars: imdb.isNotEmpty ? imdb : '7.5',
              year: year.isNotEmpty ? year : (m['date'] != null ? m['date'].toString().split('-').first : '2025'),
              kind: '1', // Movie
              arContent: '',
              enContent: '',
              imgUrl: poster,
              imgThumbUrl: poster,
              imgMediumUrl: poster,
              categories: genres,
              categoriesEn: const [],
              itemDate: m['date']?.toString(),
            );
          }).toList();
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// 2. Fetch Series (Dubbed or Translated)
  Future<List<CinemanaItem>> fetchSeries({int page = 1, bool translated = false}) async {
    try {
      final endpoint = translated ? 'api-3chk/v1/translated-series' : 'api-3chk/v1/series';
      final prefix = translated ? 'krmzi_trser_' : 'krmzi_ser_';
      final response = await _dio.get(endpoint, queryParameters: {'page': page});
      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data['data'];
        if (data is List) {
          return data.map((item) {
            final m = item as Map<String, dynamic>;
            final id = m['id']?.toString() ?? '';
            final title = _cleanDisplayTitle(m['title']?.toString() ?? '');
            final poster = m['poster']?.toString();
            final year = m['year']?.toString() ?? '';
            final imdb = m['imdb']?.toString() ?? '';
            final genres = _parseGenres(m['genres']);

            return CinemanaItem(
              id: '$prefix$id',
              arTitle: title,
              enTitle: '',
              stars: imdb.isNotEmpty ? imdb : '8.0',
              year: year.isNotEmpty ? year : (m['date'] != null ? m['date'].toString().split('-').first : '2025'),
              kind: '2', // Series
              arContent: '',
              enContent: '',
              imgUrl: poster,
              imgThumbUrl: poster,
              imgMediumUrl: poster,
              categories: genres,
              categoriesEn: const [],
              itemDate: m['date']?.toString(),
            );
          }).toList();
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// 3. Search across Krmzi with server-side query and multi-API support (api-3chk & api-ak)
  Future<List<CinemanaItem>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    final results = <CinemanaItem>[];
    final seen = <String>{};

    void addResults(dynamic response, String prefix, String kind) {
      if (response != null && response.statusCode == 200 && response.data is Map) {
        final data = response.data['data'];
        if (data is List) {
          final normQ = CinemanaItem.normalizeTitle(q);
          final qLower = q.toLowerCase();

          for (final item in data) {
            if (item is Map<String, dynamic>) {
              final id = item['id']?.toString() ?? '';
              final title = _cleanDisplayTitle(item['title']?.toString() ?? '');
              final poster = item['poster']?.toString();
              final year = item['year']?.toString() ?? '2025';
              final imdb = item['imdb']?.toString() ?? '7.5';
              final fullId = '$prefix$id';
              final genres = _parseGenres(item['genres']);

              // Filter out items that do not match the query (WP REST ignores ?s=)
              final rawTitleLower = title.toLowerCase();
              final normTitle = CinemanaItem.normalizeTitle(title);
              final matchesTitle = rawTitleLower.contains(qLower) ||
                  (normQ.isNotEmpty && normTitle.contains(normQ));
              final matchesGenre = genres.any((g) =>
                  g.toLowerCase().contains(qLower) ||
                  (normQ.isNotEmpty && CinemanaItem.normalizeTitle(g).contains(normQ)));

              if (!matchesTitle && !matchesGenre) {
                continue;
              }

              if (id.isNotEmpty && seen.add(fullId)) {
                results.add(
                  CinemanaItem(
                    id: fullId,
                    arTitle: title,
                    enTitle: '',
                    stars: imdb,
                    year: year,
                    kind: kind,
                    arContent: '',
                    enContent: '',
                    imgUrl: poster,
                    imgThumbUrl: poster,
                    imgMediumUrl: poster,
                    categories: genres,
                    itemDate: item['date']?.toString(),
                  ),
                );
              }
            }
          }
        }
      }
    }

    try {
      final futures = await Future.wait([
        _dio.get('api-3chk/v1/movies', queryParameters: {'s': q}).catchError((_) => Response(requestOptions: RequestOptions(path: ''))),
        _dio.get('api-3chk/v1/series', queryParameters: {'s': q}).catchError((_) => Response(requestOptions: RequestOptions(path: ''))),
        _dio.get('api-3chk/v1/translated-series', queryParameters: {'s': q}).catchError((_) => Response(requestOptions: RequestOptions(path: ''))),
        _dio.get('api-ak/v1/series', queryParameters: {'s': q}).catchError((_) => Response(requestOptions: RequestOptions(path: ''))),
      ]);

      addResults(futures[0], 'krmzi_mov_', '1');
      addResults(futures[1], 'krmzi_ser_', '2');
      addResults(futures[2], 'krmzi_trser_', '2');
      addResults(futures[3], 'krmzi_ak_', '2');
    } catch (_) {}

    return results;
  }

  /// 4. Fetch full item details (Story, duration, etc.)
  Future<CinemanaItem?> fetchItemDetails(String krmziId) async {
    try {
      if (krmziId.startsWith('krmzi_mov_')) {
        final id = krmziId.replaceFirst('krmzi_mov_', '');
        final res = await _dio.get('api-3chk/v1/movies/$id');
        if (res.statusCode == 200 && res.data is Map) {
          final m = res.data as Map<String, dynamic>;
          final title = _cleanDisplayTitle(m['title']?.toString() ?? '');
          final poster = m['poster']?.toString();
          final story = m['story']?.toString() ?? '';
          final year = m['year']?.toString() ?? '';
          final imdb = m['imdb']?.toString() ?? '';
          final duration = m['duration']?.toString() ?? '';
          final genres = _parseGenres(m['genres']);

          return CinemanaItem(
            id: krmziId,
            arTitle: title,
            enTitle: '',
            stars: imdb.isNotEmpty ? imdb : '7.5',
            year: year.isNotEmpty ? year : '2025',
            kind: '1',
            arContent: story,
            enContent: '',
            imgUrl: poster,
            imgThumbUrl: poster,
            imgMediumUrl: poster,
            categories: genres,
            duration: duration,
          );
        }
      } else if (krmziId.startsWith('krmzi_ak_')) {
        final id = krmziId.replaceFirst('krmzi_ak_', '');
        final res = await _dio.get('api-ak/v1/series/$id');
        if (res.statusCode == 200 && res.data is Map) {
          final m = res.data as Map<String, dynamic>;
          final title = _cleanDisplayTitle(m['title']?.toString() ?? '');
          final poster = m['poster']?.toString();
          final story = m['story']?.toString() ?? '';
          final year = m['year']?.toString() ?? '2025';
          final imdb = m['imdb']?.toString() ?? '7.5';

          return CinemanaItem(
            id: krmziId,
            arTitle: title,
            enTitle: '',
            stars: imdb,
            year: year,
            kind: '2',
            arContent: story,
            enContent: '',
            imgUrl: poster,
            imgThumbUrl: poster,
            imgMediumUrl: poster,
            categories: const ['مدبلج', 'تركي'],
          );
        }
      } else if (krmziId.startsWith('krmzi_ser_') || krmziId.startsWith('krmzi_trser_')) {
        final isTranslated = krmziId.startsWith('krmzi_trser_');
        final id = isTranslated
            ? krmziId.replaceFirst('krmzi_trser_', '')
            : krmziId.replaceFirst('krmzi_ser_', '');
        final endpoint = isTranslated ? 'api-3chk/v1/translated-series/$id' : 'api-3chk/v1/series/$id';
        final res = await _dio.get(endpoint);
        if (res.statusCode == 200 && res.data is Map) {
          final m = res.data as Map<String, dynamic>;
          final title = _cleanDisplayTitle(m['title']?.toString() ?? '');
          final poster = m['poster']?.toString();
          final story = m['story']?.toString() ?? '';
          final year = m['year']?.toString() ?? '';
          final imdb = m['imdb']?.toString() ?? '';
          final genres = _parseGenres(m['genres']);

          return CinemanaItem(
            id: krmziId,
            arTitle: title,
            enTitle: '',
            stars: imdb.isNotEmpty ? imdb : '8.0',
            year: year.isNotEmpty ? year : '2025',
            kind: '2',
            arContent: story,
            enContent: '',
            imgUrl: poster,
            imgThumbUrl: poster,
            imgMediumUrl: poster,
            categories: genres,
          );
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 5. Fetch Series Episodes
  Future<List<CinemanaEpisode>> fetchEpisodes(String krmziSeriesId) async {
    try {
      if (krmziSeriesId.startsWith('krmzi_ak_')) {
        final id = krmziSeriesId.replaceFirst('krmzi_ak_', '');
        final res = await _dio.get('api-ak/v1/series/$id');
        if (res.statusCode == 200 && res.data is Map) {
          final epList = res.data['episodes'];
          if (epList is List) {
            final List<CinemanaEpisode> episodes = [];
            for (int i = 0; i < epList.length; i++) {
              final ep = epList[i] as Map<String, dynamic>;
              final rawTitle = ep['title']?.toString() ?? 'الحلقة ${i + 1}';
              final numMatch = RegExp(r'\d+').firstMatch(rawTitle);
              final epNum = numMatch != null ? numMatch.group(0)! : '${i + 1}';

              episodes.add(
                CinemanaEpisode(
                  id: 'krmzi_akep_${id}_${i + 1}',
                  episodeNumber: epNum,
                  seasonNumber: '1',
                  arTitle: rawTitle,
                  enTitle: 'Episode $epNum',
                ),
              );
            }
            return episodes;
          }
        }
        return [];
      }

      final isTranslated = krmziSeriesId.startsWith('krmzi_trser_');
      final id = isTranslated
          ? krmziSeriesId.replaceFirst('krmzi_trser_', '')
          : krmziSeriesId.replaceFirst('krmzi_ser_', '');
      final endpoint = isTranslated ? 'api-3chk/v1/translated-series/$id' : 'api-3chk/v1/series/$id';
      final res = await _dio.get(endpoint);
      if (res.statusCode == 200 && res.data is Map) {
        final epList = res.data['episodes'];
        if (epList is List) {
          final List<CinemanaEpisode> episodes = [];
          for (int i = 0; i < epList.length; i++) {
            final ep = epList[i] as Map<String, dynamic>;
            final rawTitle = ep['title']?.toString() ?? 'الحلقة ${i + 1}';
            final season = ep['season']?.toString() ?? '1';
            final numMatch = RegExp(r'\d+').firstMatch(rawTitle);
            final epNum = numMatch != null ? numMatch.group(0)! : '${i + 1}';

            episodes.add(
              CinemanaEpisode(
                id: 'krmzi_ep_${id}_${i + 1}_${isTranslated ? 1 : 0}',
                episodeNumber: epNum,
                seasonNumber: season,
                arTitle: rawTitle,
                enTitle: 'Episode $epNum',
              ),
            );
          }
          return episodes;
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// 6. Resolve Direct Stream URL (.m3u8 or .mp4)
  Future<String?> resolveStreamUrl(String videoId) async {
    try {
      if (videoId.startsWith('krmzi_akep_')) {
        // Format: krmzi_akep_{seriesId}_{episodeIndex}
        final parts = videoId.split('_');
        if (parts.length >= 4) {
          final seriesId = parts[2];
          final epIndex = parts[3];
          final res = await _dio.get(
            'api-ak/v1/episode',
            queryParameters: {'series_id': seriesId, 'episode_index': epIndex},
          );
          if (res.statusCode == 200 && res.data is Map) {
            final mp4 = res.data['mp4_link']?.toString();
            if (mp4 != null && mp4.isNotEmpty) return mp4;
            final m3u8 = res.data['m3u8_url']?.toString();
            if (m3u8 != null && m3u8.isNotEmpty) return m3u8;
          }
        }
      } else if (videoId.startsWith('krmzi_mov_')) {
        final movieId = videoId.replaceFirst('krmzi_mov_', '');
        final res = await _dio.get('api-3chk/v1/movie-stream', queryParameters: {'movie_id': movieId});
        if (res.statusCode == 200 && res.data is Map) {
          final m3u8 = res.data['m3u8_url']?.toString();
          if (m3u8 != null && m3u8.isNotEmpty) return m3u8;
          final embed = res.data['embed_url']?.toString();
          if (embed != null && embed.isNotEmpty) return embed;
        }
      } else if (videoId.startsWith('krmzi_ep_')) {
        final parts = videoId.split('_');
        if (parts.length >= 5) {
          final seriesId = parts[2];
          final epIndex = parts[3];
          final isTranslated = parts[4] == '1';

          final endpoint = isTranslated ? 'api-3chk/v1/translated-episode' : 'api-3chk/v1/episode';
          final res = await _dio.get(
            endpoint,
            queryParameters: {
              'series_id': seriesId,
              'episode_index': epIndex,
            },
          );
          if (res.statusCode == 200 && res.data is Map) {
            final m3u8 = res.data['m3u8_url']?.toString();
            if (m3u8 != null && m3u8.isNotEmpty) return m3u8;
            final embed = res.data['embed_url']?.toString();
            if (embed != null && embed.isNotEmpty) return embed;
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 7. Convert resolved stream into CinemanaStreamFile for native player
  Future<List<CinemanaStreamFile>> fetchStreamFiles(String videoId) async {
    final streamUrl = await resolveStreamUrl(videoId);
    if (streamUrl != null && streamUrl.isNotEmpty) {
      return [
        CinemanaStreamFile(
          name: 'HD 1080p (بث مباشر عالي الدقة)',
          resolution: '1080p',
          container: streamUrl.contains('.m3u8') ? 'm3u8' : 'mp4',
          videoUrl: streamUrl,
        ),
      ];
    }
    return [];
  }
}
