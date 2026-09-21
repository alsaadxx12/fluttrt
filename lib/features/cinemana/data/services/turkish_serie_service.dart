import 'package:dio/dio.dart';
import 'package:youtube_downloader/core/network/http_cache.dart';
import '../models/cinemana_models.dart';

class TurkishSerieService {
  TurkishSerieService({Dio? dio})
      : _dio = dio ??
            createDio(
              BaseOptions(
                baseUrl: 'https://turkishserie.com/',
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 15),
                headers: {
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
                  'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                  'Accept-Language': 'ar,en;q=0.9',
                },
              ),
            );

  final Dio _dio;

  List<CinemanaItem>? _cachedCatalog;
  DateTime? _lastFetchTime;

  /// Concurrent callers (a search, the Arabic-series row, an item lookup)
  /// share one in-flight catalogue download.
  Future<List<CinemanaItem>>? _catalogInflight;

  /// Map of known Turkish to Arabic titles for enriched display
  static const Map<String, String> _arabicAliases = {
    'esaret': 'الأسيرة (Esaret)',
    'eskiya-dunyaya-hukumdar-olmaz': 'قطاع الطرق لن يحكموا العالم',
    'abdulhamid-episode': 'عاصمة عبد الحميد',
    'uc-kiz-kardes': 'ثلاث أخوات',
    'kadin': 'امرأة',
    'siyah-beyaz-ask': 'حب أبيض وأسود',
    'kara-sevda': 'حب أعمى',
    'aile': 'العائلة',
    'hudutsuz-sevda': 'حب بلا حدود',
    'kurulus-osman': 'المؤسس عثمان',
    'yargi': 'القضاء',
    'safir': 'حجر الياقوت',
    'kizilcik-serbeti': 'شراب التوت',
  };

  /// 1. Fetch all Turkish series catalog from turkishserie.com
  Future<List<CinemanaItem>> fetchCatalog({bool forceRefresh = false}) {
    if (!forceRefresh &&
        _cachedCatalog != null &&
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!).inMinutes < 30) {
      return Future.value(_cachedCatalog!);
    }
    return _catalogInflight ??= _fetchCatalog().whenComplete(() => _catalogInflight = null);
  }

  Future<List<CinemanaItem>> _fetchCatalog() async {
    try {
      final res = await _dio.get('ar/series');
      if (res.statusCode == 200) {
        final html = res.data.toString();
        final regex = RegExp(
          r'<a[^>]+href="\/ar\/serie\/([^"]+)"[^>]*>[\s\S]*?<img[^>]+src="([^"]+)"[^>]+alt="([^"]+)"',
          caseSensitive: false,
        );

        final items = <CinemanaItem>[];
        final seen = <String>{};

        for (final match in regex.allMatches(html)) {
          final slug = match.group(1)?.trim() ?? '';
          final poster = match.group(2)?.trim() ?? '';
          final rawAlt = match.group(3)?.trim() ?? '';

          if (slug.isEmpty || !seen.add(slug)) continue;

          // Build clean title
          var cleanName = rawAlt
              .replaceAll('مسلسل تركي مترجم للعربية', '')
              .replaceAll('مسلسل تركي', '')
              .replaceAll('مترجم', '')
              .trim();

          final alias = _arabicAliases[slug.toLowerCase()];
          final displayTitle = alias != null && alias.isNotEmpty ? alias : cleanName;

          items.add(
            CinemanaItem(
              id: 'ts_serie_$slug',
              arTitle: displayTitle,
              enTitle: slug.replaceAll('-', ' '),
              stars: '8.4',
              year: '2024',
              kind: '2', // Series
              arContent: 'مسلسل تركي مترجم بالكامل لجميع الحلقات بدقة عالية وسيرفرات مباشرة وبدون إعلانات.',
              enContent: '',
              imgUrl: poster.isNotEmpty ? poster : null,
              imgThumbUrl: poster.isNotEmpty ? poster : null,
              imgMediumUrl: poster.isNotEmpty ? poster : null,
              categories: const ['تركي', 'مترجم', 'دراما'],
              categoriesEn: const ['Turkish', 'Drama'],
            ),
          );
        }

        _cachedCatalog = items;
        _lastFetchTime = DateTime.now();
        return items;
      }
      return _cachedCatalog ?? [];
    } catch (_) {
      return _cachedCatalog ?? [];
    }
  }

  /// 2. Search across Turkish series catalog (by Turkish name, English, or Arabic)
  Future<List<CinemanaItem>> search(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];

    final normQ = CinemanaItem.normalizeTitle(q);
    final catalog = await fetchCatalog();
    return catalog.where((item) {
      final rawAr = item.arTitle.toLowerCase();
      final normAr = CinemanaItem.normalizeTitle(item.arTitle);
      final en = item.enTitle.toLowerCase();
      final id = item.id.toLowerCase();
      return rawAr.contains(q) ||
          en.contains(q) ||
          id.contains(q) ||
          (normQ.isNotEmpty && normAr.contains(normQ));
    }).toList();
  }

  /// 3. Fetch all episodes for a Turkish series (e.g. all 295+ episodes of Esaret)
  Future<List<CinemanaEpisode>> fetchEpisodes(String tsSeriesId) async {
    final slug = tsSeriesId.replaceFirst('ts_serie_', '');
    try {
      final res = await _dio.get('ar/serie/$slug');
      if (res.statusCode == 200) {
        final html = res.data.toString();

        // 1. Check for JSON payload in Next.js component stream
        final jsonEpRegex = RegExp(
          r'\{"number":(\d+),"title":"([^"]+)","slug":"([^"]+)"(?:,"duration":"[^"]*")?(?:,"date":"[^"]*")?(?:,"quality":"[^"]*")?,"sourceUrl":"([^"]+)"',
        );
        final jsonMatches = jsonEpRegex.allMatches(html).toList();
        if (jsonMatches.isNotEmpty) {
          final List<CinemanaEpisode> episodes = [];
          for (final m in jsonMatches) {
            final numStr = m.group(1) ?? '1';
            final titleStr = m.group(2) ?? 'الحلقة $numStr';
            final epSlug = m.group(3) ?? 'episode-$numStr';

            episodes.add(
              CinemanaEpisode(
                id: 'ts_ep_${slug}_$epSlug',
                episodeNumber: numStr,
                seasonNumber: '1',
                arTitle: titleStr,
                enTitle: 'Episode $numStr',
              ),
            );
          }
          episodes.sort((a, b) => a.intEpisodeNumber.compareTo(b.intEpisodeNumber));
          return episodes;
        }

        // 2. Fallback: Parse HTML links
        final linkRegex = RegExp(
          r'href="\/ar\/watch\/' + RegExp.escape(slug) + r'\/(episode-\d+)"[^>]*>([\s\S]*?)<\/a>',
          caseSensitive: false,
        );
        final linkMatches = linkRegex.allMatches(html).toList();
        final List<CinemanaEpisode> episodes = [];
        final seenNumbers = <int>{};

        for (final m in linkMatches) {
          final epSlug = m.group(1) ?? '';
          final numMatch = RegExp(r'\d+').firstMatch(epSlug);
          final num = numMatch != null ? int.tryParse(numMatch.group(0)!) ?? 1 : 1;

          if (seenNumbers.add(num)) {
            episodes.add(
              CinemanaEpisode(
                id: 'ts_ep_${slug}_$epSlug',
                episodeNumber: '$num',
                seasonNumber: '1',
                arTitle: 'الحلقة $num',
                enTitle: 'Episode $num',
              ),
            );
          }
        }
        episodes.sort((a, b) => a.intEpisodeNumber.compareTo(b.intEpisodeNumber));
        return episodes;
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// 4. Resolve direct video stream for a TurkishSerie episode
  Future<List<CinemanaStreamFile>> fetchStreamFiles(String videoId) async {
    // Format: ts_ep_{slug}_{episodeSlug}
    final parts = videoId.split('_');
    if (parts.length < 4) return [];

    final slug = parts[2];
    final epSlug = parts[3];

    try {
      final watchUrl = 'ar/watch/$slug/$epSlug';
      final res = await _dio.get(watchUrl);
      if (res.statusCode == 200) {
        final html = res.data.toString();

        // 1. Check for sourceUrl (e.g. turkvost.fr) in payload
        final sourceUrlMatch = RegExp(r'https?://turkvost\.fr/[^\s"<>]+').firstMatch(html);
        if (sourceUrlMatch != null) {
          final sourceUrl = sourceUrlMatch.group(0)!;
          // Fetch the direct video file from turkvost
          final tvRes = await _dio.get(sourceUrl);
          if (tvRes.statusCode == 200) {
            final tvHtml = tvRes.data.toString();
            final mp4Match = RegExp(r'https?://videos\.turkvost\.fr/[^\s"<>]+\.mp4').firstMatch(tvHtml);
            if (mp4Match != null) {
              final mp4Url = mp4Match.group(0)!;
              return [
                CinemanaStreamFile(
                  name: 'FHD 1080p (بث مباشر عالي السرعة)',
                  resolution: '1080p',
                  container: 'mp4',
                  videoUrl: mp4Url,
                ),
              ];
            }
          }
        }

        // 2. Direct video mp4/m3u8 regex fallback
        final directMatch = RegExp(r'https?://[^\s"<>]+\.(?:mp4|m3u8)[^\s"<>]*').firstMatch(html);
        if (directMatch != null) {
          final url = directMatch.group(0)!;
          return [
            CinemanaStreamFile(
              name: 'HD (بث مباشر)',
              resolution: '1080p',
              container: url.contains('.m3u8') ? 'm3u8' : 'mp4',
              videoUrl: url,
            ),
          ];
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }
}
