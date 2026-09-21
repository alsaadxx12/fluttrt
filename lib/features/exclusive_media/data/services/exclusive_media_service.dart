import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/exclusive_media_models.dart';

class ExclusiveMediaService {
  static const String baseUrl = 'https://akwam.ss';

  static const Map<String, String> defaultHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    'Referer': '$baseUrl/',
    'Accept-Language': 'ar,en-US;q=0.9,en;q=0.8',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
  };

  final http.Client _client;

  ExclusiveMediaService({http.Client? client}) : _client = client ?? http.Client();

  void dispose() {
    _client.close();
  }

  // ===========================================================================
  // 1. Listings & Categories
  // ===========================================================================

  /// Fetches latest 60 items (movies & series) from /recent
  Future<List<ExclusiveMediaItem>> fetchRecent({int page = 1}) async {
    final url = page <= 1 ? '$baseUrl/recent' : '$baseUrl/recent?page=$page';
    return _fetchAndParseList(url);
  }

  /// Fetches latest series from /series
  Future<List<ExclusiveMediaItem>> fetchSeries({
    int page = 1,
    String? section, // e.g. "29" for Arabic, "30" for Foreign, "32" for Turkish
  }) async {
    final queryParams = <String>[];
    if (section != null && section.isNotEmpty) {
      queryParams.add('section=$section');
    }
    if (page > 1) {
      queryParams.add('page=$page');
    }
    final q = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
    return _fetchAndParseList('$baseUrl/series$q');
  }

  /// Fetches latest movies from /movies
  Future<List<ExclusiveMediaItem>> fetchMovies({
    int page = 1,
    String? year, // e.g. "2026", "2025"
    String? section, // e.g. "29" for Arabic, "30" for Foreign
  }) async {
    final queryParams = <String>[];
    if (year != null && year.isNotEmpty) {
      queryParams.add('year=$year');
    }
    if (section != null && section.isNotEmpty) {
      queryParams.add('section=$section');
    }
    if (page > 1) {
      queryParams.add('page=$page');
    }
    final q = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
    return _fetchAndParseList('$baseUrl/movies$q');
  }

  /// Fetches items for any predefined category
  Future<List<ExclusiveMediaItem>> fetchCategory(
    ExclusiveCategory category, {
    int page = 1,
  }) async {
    final path = category.path;
    final separator = path.contains('?') ? '&' : '?';
    final url = page <= 1 ? '$baseUrl/$path' : '$baseUrl/$path${separator}page=$page';
    return _fetchAndParseList(url);
  }

  /// Searches for titles across the exclusive catalog
  Future<List<ExclusiveMediaItem>> search(String query, {int page = 1}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return const [];
    final encoded = Uri.encodeQueryComponent(cleanQuery);
    final url = page <= 1 ? '$baseUrl/search?q=$encoded' : '$baseUrl/search?q=$encoded&page=$page';
    return _fetchAndParseList(url);
  }

  // ===========================================================================
  // 2. HTML Scraper & Parser
  // ===========================================================================

  Future<List<ExclusiveMediaItem>> _fetchAndParseList(String url) async {
    try {
      final uri = Uri.parse(Uri.encodeFull(url));
      final res = await _client.get(uri, headers: defaultHeaders).timeout(const Duration(seconds: 14));
      if (res.statusCode != 200) {
        debugPrint('[ExclusiveService] HTTP ${res.statusCode} for $url');
        return const [];
      }

      final html = utf8.decode(res.bodyBytes, allowMalformed: true);
      return _parseEntries(html);
    } catch (e) {
      debugPrint('[ExclusiveService] Error fetching $url: $e');
      return const [];
    }
  }

  List<ExclusiveMediaItem> _parseEntries(String html) {
    final items = <ExclusiveMediaItem>[];
    // Each item card is enclosed in <div class="entry-box ...">
    final entryRegex = RegExp(
      r'<div class="entry-box[^"]*".*?class="entry-title[^"]*">\s*<a\s+href="([^"]+)"[^>]*>([^<]+)</a>',
      dotAll: true,
    );

    final matches = entryRegex.allMatches(html);
    for (final m in matches) {
      final fullMatch = m.group(0) ?? '';
      final link = (m.group(1) ?? '').trim();
      final title = (m.group(2) ?? '').trim();

      if (link.isEmpty || title.isEmpty) continue;

      // Extract unique ID from link, e.g. https://akwam.ss/series/5773/oj-unseen... -> "5773"
      final idMatch = RegExp(r'/(?:movie|series|episode)/(\d+)').firstMatch(link);
      final id = idMatch != null ? 'ex-${idMatch.group(1)}' : 'ex-${link.hashCode}';

      // Poster image from data-src or src
      final posterMatch = RegExp(r'<img[^>]+(?:data-src|src)="([^"]+)"').firstMatch(fullMatch);
      String posterUrl = posterMatch?.group(1) ?? '';
      if (posterUrl.contains('placeholder.png')) {
        final dataSrcMatch = RegExp(r'data-src="([^"]+)"').firstMatch(fullMatch);
        if (dataSrcMatch != null) posterUrl = dataSrcMatch.group(1)!;
      }

      // Rating
      final ratingMatch = RegExp(r'<span class="label rating"[^>]*>.*?([0-9\.]+)').firstMatch(fullMatch);
      final rating = ratingMatch?.group(1)?.trim();

      // Quality
      final qualityMatch = RegExp(r'<span class="label quality"[^>]*>([^<]+)</span>').firstMatch(fullMatch);
      final quality = qualityMatch?.group(1)?.trim();

      // Year badge
      final yearMatch = RegExp(r'<span class="badge badge-pill badge-secondary[^"]*">(\d{4})</span>').firstMatch(fullMatch);
      final year = yearMatch?.group(1)?.trim();

      // Category / genre badges
      final genreMatches = RegExp(r'<span class="badge badge-pill badge-light[^"]*">([^<]+)</span>').allMatches(fullMatch);
      final genresList = genreMatches.map((g) => g.group(1)?.trim() ?? '').where((s) => s.isNotEmpty).toList();
      final genres = genresList.isNotEmpty ? genresList.join(' • ') : null;

      final isMovie = link.contains('/movie/');
      final isSeries = link.contains('/series/') || link.contains('/episode/');

      final cleanTitle = ExclusiveMediaItem.sanitizeText(title);

      items.add(
        ExclusiveMediaItem(
          id: id,
          title: cleanTitle,
          url: link,
          posterUrl: posterUrl,
          backdropUrl: posterUrl,
          year: year,
          rating: rating ?? '8.0',
          quality: quality ?? 'WEB-DL',
          genres: genres,
          isMovie: isMovie,
          isSeries: isSeries,
        ),
      );
    }

    return items;
  }

  // ===========================================================================
  // 3. Details & Episode Extraction
  // ===========================================================================

  /// Fetches detailed information and episodes list for a given series or movie
  Future<ExclusiveDetails> fetchDetails(String pageUrl) async {
    try {
      final uri = Uri.parse(Uri.encodeFull(pageUrl));
      final res = await _client.get(uri, headers: defaultHeaders).timeout(const Duration(seconds: 14));
      final html = utf8.decode(res.bodyBytes, allowMalformed: true);

      // Title
      final titleMatch = RegExp(r'<h1 class="entry-title[^"]*">([^<]+)</h1>').firstMatch(html);
      final title = titleMatch != null
          ? ExclusiveMediaItem.sanitizeText(titleMatch.group(1)!.trim())
          : 'عمل حصري';

      // Poster
      final posterMatch = RegExp(r'<picture[^>]*>\s*<img[^>]+(?:data-src|src)="([^"]+)"').firstMatch(html);
      String posterUrl = posterMatch?.group(1) ?? '';
      if (posterUrl.contains('placeholder.png')) {
        final dMatch = RegExp(r'data-src="([^"]+)"').firstMatch(html);
        if (dMatch != null) posterUrl = dMatch.group(1)!;
      }

      // Rating
      final ratingMatch = RegExp(r'<span class="label rating"[^>]*>.*?([0-9\.]+)').firstMatch(html);
      final rating = ratingMatch?.group(1)?.trim() ?? '8.0';

      // Quality
      final qualityMatch = RegExp(r'<span class="label quality"[^>]*>([^<]+)</span>').firstMatch(html);
      final quality = qualityMatch?.group(1)?.trim();

      // Story
      String story = '';
      final storyMatch = RegExp(r'header-link text-white">قصة.*?</h2>.*?<div[^>]*>.*?<p>([^<]+)</p>', dotAll: true).firstMatch(html) ??
          RegExp(r'<div class="widget-body">.*?<p>([^<]+)</p>', dotAll: true).firstMatch(html);
      if (storyMatch != null) {
        story = ExclusiveMediaItem.sanitizeText(storyMatch.group(1)!.trim());
      }

      // Metadata info lines (Year, Duration, Language, Country)
      String? year;
      String? duration;
      String? language;
      String? country;
      final infoMatches = RegExp(r'<div class="font-size-16[^"]*">(.*?)</div>', dotAll: true).allMatches(html);
      for (final im in infoMatches) {
        final text = (im.group(1) ?? '').replaceAll(RegExp(r'<[^>]+>'), ' ').trim();
        if (text.contains('السنة') || text.contains('سنة')) {
          final ym = RegExp(r'(\d{4})').firstMatch(text);
          if (ym != null) year = ym.group(1);
        } else if (text.contains('مدة')) {
          duration = text.replaceAll('مدة الفيلم :', '').replaceAll('مدة المسلسل :', '').replaceAll('مدة :', '').trim();
        } else if (text.contains('اللغة')) {
          language = text.replaceAll('اللغة :', '').trim();
        } else if (text.contains('انتاج') || text.contains('دولة')) {
          country = text.replaceAll('انتاج :', '').replaceAll('دولة :', '').trim();
        }
      }

      final isMovie = pageUrl.contains('/movie/');
      final isSeries = pageUrl.contains('/series/') || pageUrl.contains('/episode/');

      final idMatch = RegExp(r'/(?:movie|series|episode)/(\d+)').firstMatch(pageUrl);
      final id = idMatch != null ? 'ex-${idMatch.group(1)}' : 'ex-${pageUrl.hashCode}';

      final item = ExclusiveMediaItem(
        id: id,
        title: title,
        url: pageUrl,
        posterUrl: posterUrl,
        backdropUrl: posterUrl,
        year: year ?? '2026',
        rating: rating,
        quality: quality ?? 'WEB-DL',
        duration: duration,
        genres: isMovie ? 'أفلام حصرية' : 'مسلسلات حصرية',
        story: story,
        country: country,
        language: language,
        isMovie: isMovie,
        isSeries: isSeries,
      );

      // Extract episodes if series
      final episodes = <ExclusiveEpisode>[];
      final epIndex = html.indexOf('series-episodes');
      final sectionHtml = epIndex != -1 ? html.substring(epIndex) : html;

      final epMatches = RegExp(
        r'<a\s+href="(https://akwam\.ss/episode/\d+/[^"]+)"[^>]*class="text-white">([^<]+)</a>',
      ).allMatches(sectionHtml);

      final seenUrls = <String>{};
      int epCounter = 1;
      for (final em in epMatches) {
        final epUrl = em.group(1)!;
        if (!seenUrls.add(epUrl)) continue;

        final epTitleRaw = em.group(2)!.trim();
        final epTitle = ExclusiveMediaItem.sanitizeText(epTitleRaw);

        // Parse episode number
        final numMatch = RegExp(r'حلقة\s*(\d+)').firstMatch(epTitle) ??
            RegExp(r'/الحلقة-(\d+)').firstMatch(epUrl);
        final epNum = numMatch != null ? int.tryParse(numMatch.group(1)!) ?? epCounter : epCounter;

        episodes.add(
          ExclusiveEpisode(
            number: epNum,
            title: epTitle.isNotEmpty ? epTitle : 'حلقة $epNum',
            url: epUrl,
          ),
        );
        epCounter++;
      }

      // Sort episodes ascending (Episode 1, Episode 2, ...)
      episodes.sort((a, b) => a.number.compareTo(b.number));

      return ExclusiveDetails(item: item, episodes: episodes);
    } catch (e) {
      debugPrint('[ExclusiveService] Error fetching details for $pageUrl: $e');
      final fallbackItem = ExclusiveMediaItem(
        id: 'ex-${pageUrl.hashCode}',
        title: 'عمل حصري',
        url: pageUrl,
        posterUrl: '',
      );
      return ExclusiveDetails(item: fallbackItem, episodes: const []);
    }
  }

  // ===========================================================================
  // 4. Direct Stream Resolver (Zero Ads, No External Servers)
  // ===========================================================================

  /// Resolves the direct CDN MP4/MKV stream from Akwam watch page.
  /// Bypasses all webviews and ads, playing directly in native video player.
  Future<List<ExclusiveStream>> resolveDirectStreams(String pageOrWatchUrl) async {
    try {
      String watchUrl = pageOrWatchUrl;

      // If page is a movie or episode details page, scrape the watch link first
      if (!pageOrWatchUrl.contains('/watch/')) {
        final uri = Uri.parse(Uri.encodeFull(pageOrWatchUrl));
        final res = await _client.get(uri, headers: defaultHeaders).timeout(const Duration(seconds: 12));
        final html = utf8.decode(res.bodyBytes, allowMalformed: true);

        final watchMatch = RegExp(r'href="(https://akwam\.ss/watch/\d+/[^"]+)"').firstMatch(html);
        if (watchMatch != null) {
          watchUrl = watchMatch.group(1)!;
        } else {
          debugPrint('[ExclusiveService] No watch link found on $pageOrWatchUrl');
          return const [];
        }
      }

      // Fetch watch page
      final watchUri = Uri.parse(Uri.encodeFull(watchUrl));
      final watchHeaders = {
        ...defaultHeaders,
        'Referer': '$baseUrl/',
      };
      final watchRes = await _client.get(watchUri, headers: watchHeaders).timeout(const Duration(seconds: 12));
      final watchHtml = utf8.decode(watchRes.bodyBytes, allowMalformed: true);

      // Extract direct video source URLs: <source src="..." size="...">
      final sourceMatches = RegExp(r'<source[^>]+src="([^"]+)"(?:[^>]*size="([^"]*)")?').allMatches(watchHtml);
      final streams = <ExclusiveStream>[];

      for (final sm in sourceMatches) {
        final src = sm.group(1)!;
        final rawSize = sm.group(2) ?? '';
        final quality = rawSize.isNotEmpty ? '${rawSize}p' : 'HD';

        // Filter valid video extensions
        if (src.contains('.mp4') || src.contains('.mkv') || src.contains('.m3u8')) {
          streams.add(ExclusiveStream(url: src, quality: quality));
        }
      }

      // Sort streams: 1080p > 720p > 480p
      streams.sort((a, b) {
        final qA = int.tryParse(a.quality.replaceAll(RegExp(r'\D'), '')) ?? 0;
        final qB = int.tryParse(b.quality.replaceAll(RegExp(r'\D'), '')) ?? 0;
        return qB.compareTo(qA);
      });

      return streams;
    } catch (e) {
      debugPrint('[ExclusiveService] Error resolving stream for $pageOrWatchUrl: $e');
      return const [];
    }
  }
}
