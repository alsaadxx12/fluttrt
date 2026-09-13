import 'dart:convert';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:youtube_downloader/core/network/http_cache.dart';
import '../cinemana_franchises.dart';
import '../cinemana_subtitles.dart';
import '../models/cinemana_models.dart';
import 'krmzi_service.dart';
import 'turkish_serie_service.dart';

class CinemanaService {
  CinemanaService({
    Dio? dio,
    KrmziService? krmziService,
    TurkishSerieService? turkishSerieService,
  })  : _dio = dio ??
            createDio(
              BaseOptions(
                baseUrl: 'https://cinemana.shabakaty.com/api/android/',
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 15),
                headers: {
                  'User-Agent':
                      'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
                },
              ),
            ),
        _krmzi = krmziService ?? KrmziService(),
        _turkish = turkishSerieService ?? TurkishSerieService();

  final Dio _dio;
  final KrmziService _krmzi;
  final TurkishSerieService _turkish;

  /// Normalizes titles to detect duplicates across different naming conventions
  static String normalizeTitle(String raw) => CinemanaItem.normalizeTitle(raw);

  /// Calculates search relevance score (higher score = more relevant).
  /// Exact matches, starts-with matches, and word matches get highest priority.
  static int calculateRelevance(CinemanaItem item, String query) {
    final rawQ = query.trim().toLowerCase();
    final normQ = CinemanaItem.normalizeTitle(query);
    if (rawQ.isEmpty) return 0;

    final rawAr = item.arTitle.toLowerCase();
    final rawEn = item.enTitle.toLowerCase();
    final normAr = CinemanaItem.normalizeTitle(item.arTitle);
    final normEn = CinemanaItem.normalizeTitle(item.enTitle);
    final display = item.displayTitle;
    final rawDisplay = display.toLowerCase();
    final normDisplay = CinemanaItem.normalizeTitle(display);
    final id = item.id.toLowerCase();

    int score = 0;

    // 1. Exact full match on display title, Arabic title, or English title (Highest Priority)
    if (rawDisplay == rawQ ||
        rawAr == rawQ ||
        rawEn == rawQ ||
        (normDisplay.isNotEmpty && normDisplay == normQ) ||
        (normEn.isNotEmpty && normEn == normQ) ||
        (normAr.isNotEmpty && normAr == normQ)) {
      score += 10000;
    }

    // 2. Parentheses match: e.g. "الأسيرة (Esaret)"
    final parenMatch = RegExp(r'\(([^)]+)\)').firstMatch(display);
    if (parenMatch != null) {
      final inside = parenMatch.group(1)!.trim().toLowerCase();
      final outside = display.replaceAll(RegExp(r'\([^)]*\)'), '').trim().toLowerCase();
      final normInside = CinemanaItem.normalizeTitle(inside);
      final normOutside = CinemanaItem.normalizeTitle(outside);

      if (inside == rawQ || (normInside.isNotEmpty && normInside == normQ)) {
        score += 9000;
      }
      if (outside == rawQ || (normOutside.isNotEmpty && normOutside == normQ)) {
        score += 9000;
      }
    }

    // 3. Starts-with match: e.g. "Esaret..." or "الأسيرة..."
    if (rawDisplay.startsWith(rawQ) ||
        rawEn.startsWith(rawQ) ||
        (normDisplay.isNotEmpty && normDisplay.startsWith(normQ)) ||
        (normEn.isNotEmpty && normEn.startsWith(normQ))) {
      score += 5000;
    }

    // 4. Token & Exact Word matches
    final displayTokens = normDisplay.split(RegExp(r'\s+'));
    final qTokens = normQ.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

    int exactWordMatches = 0;
    int partialMatches = 0;

    for (final qt in qTokens) {
      if (displayTokens.contains(qt)) {
        exactWordMatches++;
      } else if (normDisplay.contains(qt) || rawEn.contains(qt) || id.contains(qt)) {
        partialMatches++;
      }
    }

    if (exactWordMatches > 0) {
      score += 3000 * exactWordMatches;
    }
    if (partialMatches > 0) {
      score += 1000 * partialMatches;
    }

    // 5. Substring match
    if (rawDisplay.contains(rawQ) ||
        rawEn.contains(rawQ) ||
        (normDisplay.isNotEmpty && normDisplay.contains(normQ))) {
      score += 1500;
    }

    // 6. Slug / ID match (e.g. ts_serie_esaret)
    if (id.contains(rawQ)) {
      score += 800;
    }

    // 7. Genre match
    final matchesGenre = item.categories.any((c) =>
        c.toLowerCase().contains(rawQ) ||
        (normQ.isNotEmpty && CinemanaItem.normalizeTitle(c).contains(normQ)));
    if (matchesGenre) {
      score += 200;
    }

    // 8. Quality / Rating tie-breaker
    final rating = double.tryParse(item.stars) ?? 0.0;
    score += (rating * 5).toInt();

    return score;
  }

  /// Merges primary and supplementary items while strictly preventing duplicates
  List<CinemanaItem> mergeAndDeduplicate(
    List<CinemanaItem> primary,
    List<CinemanaItem> supplementary,
  ) {
    final seen = <String>{};
    final result = <CinemanaItem>[];

    void addIfUnique(CinemanaItem item) {
      final key = normalizeTitle(item.displayTitle);
      if (key.isNotEmpty) {
        final isDup = seen.any((s) {
          if (s == key) return true;
          if (s.length > 5 && key.length > 5 && (s.contains(key) || key.contains(s))) {
            return true;
          }
          return false;
        });
        if (!isDup) {
          seen.add(key);
          result.add(item);
        }
      } else {
        result.add(item);
      }
    }

    for (final it in primary) {
      addIfUnique(it);
    }
    for (final it in supplementary) {
      addIfUnique(it);
    }
    return result;
  }

  /// Helper to encode search queries with Base64 URL-safe (as required by Cinemana backend)
  String _base64UrlSafe(String str) {
    final bytes = utf8.encode(str);
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Search across all sources (Cinemana + Krmzi + TurkishSerie) with relevance ranking & fallback
  static final Map<String, List<CinemanaItem>> _titleSearchCache = {};
  static final Map<String, List<CinemanaItem>> _franchiseMemoryCache = {};

  /// Title search against Cinemana only - no Krmzi, no Turkish source.
  /// Used where merging other sources would only add latency and noise, such
  /// as building a film franchise's parts.
  Future<List<CinemanaItem>> searchCinemanaTitles(
    String query, {
    int page = 0,
    CancelToken? cancelToken,
  }) async {
    final clean = query.trim();
    if (clean.isEmpty) return [];
    final cacheKey = '$clean:$page';
    if (_titleSearchCache.containsKey(cacheKey)) {
      return _titleSearchCache[cacheKey]!;
    }
    try {
      final encoded = _base64UrlSafe(clean);
      final Map<String, CinemanaItem> uniqueMap = {};
      final titleResponse = await _dio.get(
        'video/V/2/itemsPerPage/24/video_title_search/$encoded/itemsPerPage/24/pageNumber/$page/level/0',
        cancelToken: cancelToken,
      );
      if (titleResponse.statusCode == 200 && titleResponse.data is List) {
        for (final item in titleResponse.data as List) {
          if (item is Map<String, dynamic>) {
            final parsed = CinemanaItem.fromJson(item);
            if (parsed.id.isNotEmpty) uniqueMap[parsed.id] = parsed;
          }
        }
      }
      final res = uniqueMap.values.toList();
      _titleSearchCache[cacheKey] = res;
      return res;
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) rethrow;
      return [];
    }
  }

  Future<List<CinemanaItem>> search(
    String query, {
    int page = 0,
    CancelToken? cancelToken,
  }) async {
    final clean = query.trim();
    if (clean.isEmpty) return [];

    final cinemanaFuture = searchCinemanaTitles(clean, page: page, cancelToken: cancelToken);
    final krmziFuture = _krmzi.search(clean);
    final turkishFuture = _turkish.search(clean);

    final results = await Future.wait([
      cinemanaFuture.catchError((_) => <CinemanaItem>[]),
      krmziFuture.catchError((_) => <CinemanaItem>[]),
      turkishFuture.catchError((_) => <CinemanaItem>[]),
    ]);

    final primary = results[0];
    final krmziResults = results[1];
    final turkishResults = results[2];

    final merged = mergeAndDeduplicate(primary, [...krmziResults, ...turkishResults]);

    // Rank by relevance score
    final scoredItems = merged.map((item) {
      return MapEntry(item, calculateRelevance(item, clean));
    }).toList();

    // If there are relevant items (score > 0), filter out any items with score == 0
    final hasMatches = scoredItems.any((entry) => entry.value > 0);
    final filtered = hasMatches
        ? scoredItems.where((entry) => entry.value > 0).toList()
        : scoredItems;

    // Sort descending by relevance score; if tied, sort by rating and year
    filtered.sort((a, b) {
      final scoreComparison = b.value.compareTo(a.value);
      if (scoreComparison != 0) return scoreComparison;

      final ratingA = double.tryParse(a.key.stars) ?? 0.0;
      final ratingB = double.tryParse(b.key.stars) ?? 0.0;
      final ratingComparison = ratingB.compareTo(ratingA);
      if (ratingComparison != 0) return ratingComparison;

      final yearA = int.tryParse(a.key.year) ?? 0;
      final yearB = int.tryParse(b.key.year) ?? 0;
      return yearB.compareTo(yearA);
    });

    return filtered.map((e) => e.key).toList();
  }

  /// Cinemana category id used for anime / animated content.
  static const int animationCategoryId = 57;

  /// English title of the animation category, used to keep anime results anime
  /// when the user also picks a genre (the API cannot intersect two categories).
  static const String animationCategoryEnTitle = 'Animation';

  /// Fetch content filtered by kind, category, and order
  /// [kind]: 'movies', 'series', 'anime'
  /// [categoryId]: null or 0 for all, or specific category id (e.g. 84 for Action, 70 for Horror)
  /// [orderby]: 'desc' (latest), 'stars' (highest rated), 'featured' (featured)
  /// [videoKind]: 1 = movie, 2 = series. Derived from [kind] when omitted, and
  /// always sent to the API so a section never leaks the other kind.
  Future<List<CinemanaItem>> fetchContent({
    required String kind,
    int? categoryId,
    String orderby = 'desc',
    int? videoKind,
    int page = 0,
    String? year,
    double? minRating,
    CancelToken? cancelToken,
  }) async {
    try {
      final int effectiveKind = videoKind ?? (kind == 'movies' ? 1 : 2);
      final bool hasGenre = categoryId != null && categoryId > 0;
      List<CinemanaItem> items = [];

      // Anime section:
      if (kind == 'anime') {
        if (!hasGenre) {
          items = await _fetchByCategory(
            categoryId: animationCategoryId,
            orderby: orderby,
            videoKind: effectiveKind,
            offset: page * 30,
            cancelToken: cancelToken,
          );
        } else {
          final chunks = await Future.wait([
            _fetchByCategory(
              categoryId: categoryId,
              orderby: orderby,
              videoKind: effectiveKind,
              offset: page * 60,
              cancelToken: cancelToken,
            ),
            _fetchByCategory(
              categoryId: categoryId,
              orderby: orderby,
              videoKind: effectiveKind,
              offset: page * 60 + 30,
              cancelToken: cancelToken,
            ),
          ]);
          items = [...chunks[0], ...chunks[1]]
              .where((it) => it.hasCategoryEn(animationCategoryEnTitle))
              .toList();
        }
      } else if (hasGenre) {
        items = await _fetchByCategory(
          categoryId: categoryId,
          orderby: orderby,
          videoKind: effectiveKind,
          offset: page * 30,
          cancelToken: cancelToken,
        );
      } else {
        // No genre selected ("الكل")
        if (orderby == 'stars') {
          items = await _fetchByCategory(
            categoryId: 0,
            orderby: 'stars',
            videoKind: effectiveKind,
            offset: page * 30,
            cancelToken: cancelToken,
          );
        } else if (orderby == 'views' || orderby == 'trending') {
          items = await _fetchByCategory(
            categoryId: 0,
            orderby: 'views',
            videoKind: effectiveKind,
            offset: page * 30,
            cancelToken: cancelToken,
          );
        } else if (orderby == 'featured') {
          final endpoint = effectiveKind == 1
              ? 'featuredMovies/level/0/itemsPerPage/24/page/$page/'
              : 'featuredSeries/level/0/itemsPerPage/24/page/$page/';
          final response = await _dio.get(endpoint, cancelToken: cancelToken);
          if (response.statusCode == 200 && response.data is List) {
            items = (response.data as List)
                .map((item) => CinemanaItem.fromJson(item as Map<String, dynamic>))
                .toList();
          }
        } else {
          // Default: latest
          if (effectiveKind == 1) {
            items = await fetchMovies(page: page, cancelToken: cancelToken);
          } else {
            items = await fetchSeries(page: page, cancelToken: cancelToken);
          }
        }
      }

      // Apply sorting if release or name
      if (orderby == 'release') {
        items = sortLatestReleases(items, isSeries: effectiveKind == 2);
      } else if (orderby == 'name') {
        items = List<CinemanaItem>.from(items)
          ..sort((a, b) => a.displayTitle.compareTo(b.displayTitle));
      } else if (orderby == 'desc') {
        items = sortRecentlyAdded(items);
      }

      // Filter by year if specified
      if (year != null && year.isNotEmpty && year != 'الكل') {
        items = items.where((it) => it.year == year).toList();
      }

      // Filter by min rating if specified
      if (minRating != null && minRating > 0) {
        items = items.where((it) {
          final r = double.tryParse(it.stars) ?? 0.0;
          return r >= minRating;
        }).toList();
      }

      return items;
    } catch (e) {
      return [];
    }
  }

  List<CinemanaCategoryItem>? _categoryCache;

  /// Titles like [item]: the same kind (film / series) from its first genre,
  /// newest release first. With no genre (or nothing found) the newest
  /// releases of that kind. [item] itself is left out.
  Future<List<CinemanaItem>> fetchSimilar(CinemanaItem item, {int limit = 20}) async {
    final kind = item.isSeries ? 2 : 1;
    try {
      _categoryCache ??= await fetchCategories();
      // In the title's own genre order, so its first genre is tried first.
      final names = [
        ...item.categories.map((c) => c.trim()),
        ...item.categoriesEn.map((c) => c.toLowerCase().trim()),
      ].where((c) => c.isNotEmpty);
      final genreIds = <int>[];
      for (final n in names) {
        for (final c in _categoryCache!) {
          if ((c.arTitle.trim() == n || c.enTitle.toLowerCase().trim() == n) && !genreIds.contains(c.id)) {
            genreIds.add(c.id);
          }
        }
      }
      var items = <CinemanaItem>[];
      for (final id in genreIds) {
        items = await _fetchByCategory(categoryId: id, orderby: 'r_desc', videoKind: kind, offset: 0);
        items = items.where((x) => x.id != item.id).toList();
        if (items.length >= 6) break;
      }
      if (items.length < 6) {
        final latest = await _fetchByCategory(categoryId: 0, orderby: 'r_desc', videoKind: kind, offset: 0);
        final seen = items.map((x) => x.id).toSet()..add(item.id);
        items = [...items, ...latest.where((x) => seen.add(x.id))];
      }
      return sortLatestReleases(items, isSeries: item.isSeries).take(limit).toList();
    } catch (_) {
      return [];
    }
  }

  /// Genres mixed into [fetchVariedMovies]: action, comedy, drama, horror,
  /// sci-fi, thriller, adventure, romance, crime, animation, mystery, family.
  static const variedMovieGenres = [84, 59, 62, 70, 78, 80, 56, 77, 60, 57, 76, 65];

  /// Popular films across many genres, dealt out one genre at a time so
  /// neighbours differ. Films only; a title in several genres appears once.
  /// [page] walks deeper into every genre (30 per genre per page).
  Future<List<CinemanaItem>> fetchVariedMovies({int page = 0, List<int> genres = variedMovieGenres}) async {
    final lists = await Future.wait([
      for (final g in genres)
        _fetchByCategory(categoryId: g, orderby: 'views', videoKind: 1, offset: page * 30)
            .catchError((Object _) => <CinemanaItem>[]),
    ]);
    final seen = <String>{};
    final out = <CinemanaItem>[];
    final longest = lists.fold<int>(0, (m, l) => l.length > m ? l.length : m);
    for (var i = 0; i < longest; i++) {
      for (final list in lists) {
        if (i >= list.length) continue;
        final item = list[i];
        if (item.isSeries || item.cardImageUrl.isEmpty || !seen.add(item.id)) continue;
        out.add(item);
      }
    }
    return out;
  }

  /// Shared `videosByCategory` call.
  Future<List<CinemanaItem>> _fetchByCategory({
    required int categoryId,
    required String orderby,
    required int videoKind,
    required int offset,
    CancelToken? cancelToken,
  }) async {
    // 'release' asks Cinemana for its own release-date order (r_desc), so a
    // page holds the newest titles rather than a re-sort of recent uploads.
    final mappedOrder = orderby == 'release'
        ? 'r_desc'
        : (orderby == 'featured' || orderby == 'name')
            ? 'desc'
            : orderby;
    final response = await _dio.get(
      'videosByCategory',
      queryParameters: {
        'categoryID': categoryId,
        'orderby': mappedOrder,
        'videoKind': videoKind,
        'offset': offset,
        'level': 0,
      },
      cancelToken: cancelToken,
    );
    if (response.statusCode == 200 && response.data is Map) {
      final info = response.data['info'];
      if (info is List) {
        return info
            .map((item) => CinemanaItem.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    }
    return [];
  }

  /// Fetch latest movies (Cinemana + Krmzi Movies backup & supplementary)
  Future<List<CinemanaItem>> fetchMovies({int page = 0, int itemsPerPage = 60, CancelToken? cancelToken}) async {
    List<CinemanaItem> primary = [];
    try {
      final response = await _dio.get('latestMovies/level/0/itemsPerPage/$itemsPerPage/page/$page/', cancelToken: cancelToken);
      if (response.statusCode == 200 && response.data is List) {
        primary = (response.data as List)
            .map((item) => CinemanaItem.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}

    // Fetch supplementary Krmzi movies
    List<CinemanaItem> krmziMovies = [];
    try {
      krmziMovies = await _krmzi.fetchMovies(page: page + 1);
    } catch (_) {}

    if (primary.isEmpty) return krmziMovies;
    if (krmziMovies.isEmpty) return primary;
    return mergeAndDeduplicate(primary, krmziMovies);
  }

  /// Fetch latest TV series (Cinemana + Krmzi Dubbed & Translated Series backup & supplementary)
  Future<List<CinemanaItem>> fetchSeries({int page = 0, int itemsPerPage = 35, CancelToken? cancelToken}) async {
    List<CinemanaItem> primary = [];
    try {
      final response = await _dio.get('latestSeries/level/0/itemsPerPage/$itemsPerPage/page/$page/', cancelToken: cancelToken);
      if (response.statusCode == 200 && response.data is List) {
        primary = (response.data as List)
            .map((item) => CinemanaItem.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}

    // Fetch supplementary Krmzi series (both dubbed and translated)
    List<CinemanaItem> krmziSeries = [];
    try {
      final dubbedFuture = _krmzi.fetchSeries(page: page + 1, translated: false);
      final translatedFuture = _krmzi.fetchSeries(page: page + 1, translated: true);
      final serResults = await Future.wait([
        dubbedFuture.catchError((_) => <CinemanaItem>[]),
        translatedFuture.catchError((_) => <CinemanaItem>[]),
      ]);
      krmziSeries = [...serResults[0], ...serResults[1]];
    } catch (_) {}

    if (primary.isEmpty) return krmziSeries;
    if (krmziSeries.isEmpty) return primary;
    return mergeAndDeduplicate(primary, krmziSeries);
  }

  /// Fetch official Cinemana Hero Banners (Exact match with Cinemana website "الإصدارات الجديدة")
  Future<List<CinemanaItem>> fetchBanners() async {
    try {
      final response = await _dio.get('banner');
      if (response.statusCode == 200 && response.data is List) {
        return (response.data as List)
            .map((item) => CinemanaItem.fromJson(item as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// The banner feed only carries the wide 2.7:1 cover art, which is barely
  /// 142px tall across a phone. Each item's own record holds a full-size
  /// portrait poster (1280x1920), so the hero is built from those instead:
  /// four times the height, no cropping, and sharp at native resolution.
  /// Details are fetched in parallel and any that fail keep their banner entry.
  Future<List<CinemanaItem>> fetchBannersWithPosters({int limit = 20}) async {
    final banners = await fetchBanners();
    if (banners.isEmpty) return banners;

    final head = banners.take(limit).toList();
    final details = await Future.wait(head.map((b) => fetchItemDetails(b.id)));

    return [
      for (var i = 0; i < head.length; i++)
        if (details[i] != null && details[i]!.bestPosterUrl.isNotEmpty)
          details[i]!.copyWith(
            backdropUrl: (head[i].backdropUrl != null &&
                    head[i].backdropUrl!.isNotEmpty &&
                    head[i].backdropUrl!.contains('cover'))
                ? head[i].backdropUrl
                : (details[i]!.backdropUrl ?? head[i].backdropUrl),
          )
        else
          head[i],
    ];
  }

  /// 1. المحتوى المميز (Featured)
  Future<List<CinemanaItem>> fetchFeatured({int page = 0}) async {
    final banners = await fetchBanners();
    if (banners.isNotEmpty) return banners;
    return fetchContent(kind: 'movies', orderby: 'featured', page: page);
  }

  /// 2. أضيف حديثًا (Recently Added: by itemDate / created_at DESC)
  Future<List<CinemanaItem>> fetchRecentlyAdded({int page = 0, int itemsPerPage = 24}) async {
    try {
      final response = await _dio.get(
        'videosByCategory',
        queryParameters: {
          'categoryID': 0,
          'orderby': 'desc',
          'videoKind': 0, // All kinds
          'offset': page * itemsPerPage,
          'level': 0,
        },
      );
      if (response.statusCode == 200 && response.data is Map) {
        final info = response.data['info'];
        if (info is List) {
          final items = info
              .map((it) => CinemanaItem.fromJson(it as Map<String, dynamic>))
              .toList();
          return sortRecentlyAdded(items);
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// 3. أحدث الأفلام (Latest Movies: by release_date / mDate DESC)
  Future<List<CinemanaItem>> fetchLatestMoviesRelease({int page = 0, int itemsPerPage = 24}) async {
    try {
      final movies = await fetchMovies(page: page, itemsPerPage: itemsPerPage);
      return sortLatestReleases(movies);
    } catch (_) {
      return [];
    }
  }

  /// 4. أحدث المسلسلات (Latest Series: by first_air_date / mDate DESC)
  Future<List<CinemanaItem>> fetchLatestSeriesRelease({int page = 0, int itemsPerPage = 24}) async {
    try {
      final series = await fetchSeries(page: page, itemsPerPage: itemsPerPage);
      return sortLatestReleases(series, isSeries: true);
    } catch (_) {
      return [];
    }
  }

  /// 5. أحدث الحلقات (Latest Episodes: on-air series)
  Future<List<CinemanaItem>> fetchLatestEpisodes({int page = 0, int itemsPerPage = 24}) async {
    try {
      final response = await _dio.get(
        'videosByCategory',
        queryParameters: {
          'categoryID': 0,
          'orderby': 'desc',
          'videoKind': 2, // Series
          'offset': page * itemsPerPage,
          'level': 0,
        },
      );
      if (response.statusCode == 200 && response.data is Map) {
        final info = response.data['info'];
        if (info is List) {
          return info
              .map((it) => CinemanaItem.fromJson(it as Map<String, dynamic>))
              .toList();
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// 6. الأكثر مشاهدة (Most Viewed: by real views count)
  Future<List<CinemanaItem>> fetchMostViewed({int page = 0, int itemsPerPage = 24, int videoKind = 0}) async {
    try {
      final response = await _dio.get(
        'videosByCategory',
        queryParameters: {
          'categoryID': 0,
          'orderby': 'views',
          'videoKind': videoKind,
          'offset': page * itemsPerPage,
          'level': 0,
        },
      );
      if (response.statusCode == 200 && response.data is Map) {
        final info = response.data['info'];
        if (info is List) {
          return info
              .map((it) => CinemanaItem.fromJson(it as Map<String, dynamic>))
              .toList();
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// 7. الرائج هذا الأسبوع (Trending)
  Future<List<CinemanaItem>> fetchTrending({int page = 0, int itemsPerPage = 24}) async {
    try {
      final response = await _dio.get(
        'videosByCategory',
        queryParameters: {
          'categoryID': 0,
          'orderby': 'views',
          'videoKind': 1, // Trending movies
          'offset': page * itemsPerPage,
          'level': 0,
        },
      );
      if (response.statusCode == 200 && response.data is Map) {
        final info = response.data['info'];
        if (info is List) {
          return info
              .map((it) => CinemanaItem.fromJson(it as Map<String, dynamic>))
              .toList();
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// 8. الأعلى تقييمًا (Top Rated: by stars, excluding 0 ratings)
  Future<List<CinemanaItem>> fetchTopRated({int page = 0, int itemsPerPage = 24, int videoKind = 0}) async {
    try {
      final response = await _dio.get(
        'videosByCategory',
        queryParameters: {
          'categoryID': 0,
          'orderby': 'stars',
          'videoKind': videoKind,
          'offset': page * itemsPerPage,
          'level': 0,
        },
      );
      if (response.statusCode == 200 && response.data is Map) {
        final info = response.data['info'];
        if (info is List) {
          final items = info
              .map((it) => CinemanaItem.fromJson(it as Map<String, dynamic>))
              .toList();
          return sortTopRated(items);
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// 9. الأفلام العربية (Arabic Movies)
  Future<List<CinemanaItem>> fetchArabicMovies({int page = 0, int itemsPerPage = 24}) async {
    try {
      // Category 130 is the official Cinemana category for local Arabic cinema ("بالعراقي")
      final response = await _dio.get(
        'videosByCategory',
        queryParameters: {
          'categoryID': 130,
          'orderby': 'desc',
          'videoKind': 1,
          'offset': page * itemsPerPage,
          'level': 0,
        },
      );
      List<CinemanaItem> items = [];
      if (response.statusCode == 200 && response.data is Map) {
        final info = response.data['info'];
        if (info is List && info.isNotEmpty) {
          items = info
              .map((it) => CinemanaItem.fromJson(it as Map<String, dynamic>))
              .toList();
        }
      }
      // If page 0, also supplement with top Arabic movies from search to enrich variety
      if (page == 0 && items.length < itemsPerPage) {
        try {
          final extra = await search('مصري', page: 0);
          final existingIds = items.map((e) => e.id).toSet();
          for (final m in extra) {
            if (!m.isSeries && !existingIds.contains(m.id)) {
              items.add(m);
              existingIds.add(m.id);
            }
          }
        } catch (_) {}
      }
      return sortRecentlyAdded(items);
    } catch (_) {
      return [];
    }
  }

  /// 10. المسلسلات العربية (Arabic Series & Turkish Dubbed)
  Future<List<CinemanaItem>> fetchArabicSeries({int page = 0, int itemsPerPage = 24}) async {
    List<CinemanaItem> primary = [];
    try {
      // Category 130 is the official Cinemana category for Arabic series
      final response = await _dio.get(
        'videosByCategory',
        queryParameters: {
          'categoryID': 130,
          'orderby': 'desc',
          'videoKind': 2,
          'offset': page * itemsPerPage,
          'level': 0,
        },
      );
      if (response.statusCode == 200 && response.data is Map) {
        final info = response.data['info'];
        if (info is List && info.isNotEmpty) {
          primary = info
              .map((it) => CinemanaItem.fromJson(it as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (_) {}

    // Supplement with Krmzi dubbed series (Turkish dubbed to Arabic)
    List<CinemanaItem> krmziDubbed = [];
    try {
      krmziDubbed = await _krmzi.fetchSeries(page: page + 1, translated: false);
    } catch (_) {}

    // Supplement with TurkishSerie catalog (e.g. Esaret, Kara Sevda, etc.)
    List<CinemanaItem> turkishSeries = [];
    try {
      turkishSeries = await _turkish.fetchCatalog();
    } catch (_) {}

    final extra = [...krmziDubbed, ...turkishSeries];
    if (primary.isEmpty) return extra;
    if (extra.isEmpty) return sortRecentlyAdded(primary);
    return sortRecentlyAdded(mergeAndDeduplicate(primary, extra));
  }

  /// قسم الأنمي (Anime)
  /// The newest anime by release date (not the latest uploads, which mix in
  /// old titles added recently). `r_desc` is Cinemana's release-date order.
  Future<List<CinemanaItem>> fetchAnime({int page = 0, int itemsPerPage = 24}) async {
    try {
      final items = await _fetchByCategory(
        categoryId: animationCategoryId,
        orderby: 'r_desc',
        videoKind: 2,
        offset: page * 30,
      );
      return sortLatestReleases(items, isSeries: true);
    } catch (_) {
      return [];
    }
  }

  /// 11. اقتراحات لك (Suggestions For You)
  Future<List<CinemanaItem>> fetchSuggestions({int page = 0, int itemsPerPage = 24}) async {
    try {
      // Combines high-rated recent content
      final rated = await fetchTopRated(page: page, itemsPerPage: itemsPerPage);
      return rated.take(itemsPerPage).toList();
    } catch (_) {
      return [];
    }
  }

  /// Deterministic stable sort: Recently added by date DESC, id DESC
  static List<CinemanaItem> sortRecentlyAdded(List<CinemanaItem> items) {
    final list = List<CinemanaItem>.from(items);
    list.sort((a, b) {
      final dateA = a.itemDate ?? '';
      final dateB = b.itemDate ?? '';
      if (dateA.isEmpty && dateB.isEmpty) {
        return (int.tryParse(b.id) ?? 0).compareTo(int.tryParse(a.id) ?? 0);
      }
      if (dateA.isEmpty) return 1; // null/empty at end
      if (dateB.isEmpty) return -1;
      final cmp = dateB.compareTo(dateA);
      if (cmp != 0) return cmp;
      return (int.tryParse(b.id) ?? 0).compareTo(int.tryParse(a.id) ?? 0);
    });
    return list;
  }

  /// Deterministic stable sort: Latest releases by release_date / mDate DESC, id DESC
  /// Excludes future release dates (where date > today). Empty dates placed at end.
  static List<CinemanaItem> sortLatestReleases(List<CinemanaItem> items, {bool isSeries = false}) {
    final nowStr = DateTime.now().toIso8601String().substring(0, 10);
    final filtered = items.where((it) {
      if (it.mDate != null && it.mDate!.isNotEmpty) {
        if (it.mDate!.compareTo(nowStr) > 0) return false;
      }
      return true;
    }).toList();

    filtered.sort((a, b) {
      final valA = (a.mDate != null && a.mDate!.isNotEmpty) ? a.mDate! : a.year;
      final valB = (b.mDate != null && b.mDate!.isNotEmpty) ? b.mDate! : b.year;
      if (valA.isEmpty && valB.isEmpty) {
        return (int.tryParse(b.id) ?? 0).compareTo(int.tryParse(a.id) ?? 0);
      }
      if (valA.isEmpty) return 1;
      if (valB.isEmpty) return -1;
      final cmp = valB.compareTo(valA);
      if (cmp != 0) return cmp;
      return (int.tryParse(b.id) ?? 0).compareTo(int.tryParse(a.id) ?? 0);
    });
    return filtered;
  }

  /// Deterministic stable sort: Top rated by stars DESC, id DESC
  static List<CinemanaItem> sortTopRated(List<CinemanaItem> items) {
    final list = items.where((it) => (double.tryParse(it.stars) ?? 0.0) > 0).toList();
    list.sort((a, b) {
      final sA = double.tryParse(a.stars) ?? 0.0;
      final sB = double.tryParse(b.stars) ?? 0.0;
      final cmp = sB.compareTo(sA);
      if (cmp != 0) return cmp;
      return (int.tryParse(b.id) ?? 0).compareTo(int.tryParse(a.id) ?? 0);
    });
    return list;
  }


  /// Fetch item details
  Future<CinemanaItem?> fetchItemDetails(String id) async {
    if (id.startsWith('ts_')) {
      final catalog = await _turkish.fetchCatalog();
      for (final it in catalog) {
        if (it.id == id) return it;
      }
      return null;
    }
    if (id.startsWith('krmzi_')) {
      return _krmzi.fetchItemDetails(id);
    }
    try {
      final response = await _dio.get('allVideoInfo/id/$id');
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        return CinemanaItem.fromJson(response.data);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Fetch episodes for a series or anime
  Future<List<CinemanaEpisode>> fetchEpisodes(String seriesId) async {
    if (seriesId.startsWith('ts_')) {
      return _turkish.fetchEpisodes(seriesId);
    }
    if (seriesId.startsWith('krmzi_')) {
      return _krmzi.fetchEpisodes(seriesId);
    }
    try {
      final response = await _dio.get('videoSeason/id/$seriesId');
      if (response.statusCode == 200 && response.data is List) {
        return (response.data as List)
            .map((item) => CinemanaEpisode.fromJson(item as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Fetch streamable video files (MP4 qualities or Krmzi/TurkishSerie direct stream)
  Future<List<CinemanaStreamFile>> fetchStreamFiles(String videoId) async {
    if (videoId.startsWith('ts_')) {
      return _turkish.fetchStreamFiles(videoId);
    }
    if (videoId.startsWith('krmzi_')) {
      return _krmzi.fetchStreamFiles(videoId);
    }
    try {
      final response = await _dio.get('transcoddedFiles/id/$videoId');
      if (response.statusCode == 200 && response.data is List) {
        return (response.data as List)
            .map((item) => CinemanaStreamFile.fromJson(item as Map<String, dynamic>))
            .where((f) => f.videoUrl.isNotEmpty)
            .toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Subtitle file links (Arabic / English) for a film or a single episode.
  Future<CinemanaSubtitleSources> fetchSubtitleSources(String videoId) async {
    try {
      final response = await _dio.get('translationFiles/id/$videoId');
      var data = response.data;
      if (data is String) data = jsonDecode(data);
      if (response.statusCode == 200 && data is Map) {
        return CinemanaSubtitleSources.fromJson(Map<String, dynamic>.from(data));
      }
    } catch (_) {}
    return const CinemanaSubtitleSources();
  }

  /// Downloads a subtitle file and reads its timed lines (empty on failure).
  Future<List<SubtitleCue>> fetchSubtitleCues(String url) async {
    try {
      final response = await _dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) return const [];
      return parseSubtitles(utf8.decode(bytes, allowMalformed: true));
    } catch (_) {
      return const [];
    }
  }

  /// Fetch all Cinemana categories
  Future<List<CinemanaCategoryItem>> fetchCategories() async {
    try {
      final response = await _dio.get('categories/lang/ar');
      if (response.statusCode == 200 && response.data is List) {
        return (response.data as List)
            .map((item) => CinemanaCategoryItem.fromJson(item as Map<String, dynamic>))
            .where((c) => c.id > 0 && c.arTitle.isNotEmpty)
            .toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Every title of [franchise] that Cinemana has, in release order - and
  /// nothing else (see [FilmFranchise.pick]).
  Future<List<CinemanaItem>> fetchFranchise(FilmFranchise franchise) async {
    final cached = _franchiseMemoryCache[franchise.id];
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    // Fast Path: Query the primary franchise search keyword first.
    // For 90%+ of franchises, this single fast request yields all or most films in < 150ms!
    final primaryQuery = franchise.queries.first;
    final primaryResults = await searchCinemanaTitles(primaryQuery, page: 0);
    final initialPicked = franchise.pick(primaryResults);

    // If we got enough items for the card (or franchise only has 1 query), cache and return immediately!
    if (initialPicked.length >= math.min(3, franchise.entries.length) || franchise.queries.length <= 1) {
      _franchiseMemoryCache[franchise.id] = initialPicked;

      // Fetch any remaining queries in background without delaying the UI
      if (franchise.queries.length > 1) {
        _fetchRemainingFranchiseInBackground(franchise, primaryResults);
      }
      return initialPicked;
    }

    // Fallback: If primary query returned too few matches, query the remaining queries with controlled concurrency
    final allResults = List<CinemanaItem>.from(primaryResults);
    final remainingJobs = [
      for (var i = 1; i < franchise.queries.length; i++)
        (franchise.queries[i], 0),
      if (franchise.deepSearch)
        for (final q in franchise.queries.take(2))
          (q, 1),
    ];

    var next = 0;
    Future<void> worker() async {
      while (next < remainingJobs.length) {
        final (q, page) = remainingJobs[next++];
        try {
          allResults.addAll(await searchCinemanaTitles(q, page: page));
        } catch (_) {}
      }
    }

    await Future.wait(List.generate(3, (_) => worker()));
    final picked = franchise.pick(allResults);
    if (picked.isNotEmpty) {
      _franchiseMemoryCache[franchise.id] = picked;
    }
    return picked;
  }

  void _fetchRemainingFranchiseInBackground(FilmFranchise franchise, List<CinemanaItem> existing) async {
    try {
      final allResults = List<CinemanaItem>.from(existing);
      final remainingJobs = [
        for (var i = 1; i < franchise.queries.length; i++)
          (franchise.queries[i], 0),
        if (franchise.deepSearch)
          for (final q in franchise.queries.take(2))
            (q, 1),
      ];

      for (final (q, page) in remainingJobs) {
        allResults.addAll(await searchCinemanaTitles(q, page: page));
      }
      final complete = franchise.pick(allResults);
      if (complete.length > (_franchiseMemoryCache[franchise.id]?.length ?? 0)) {
        _franchiseMemoryCache[franchise.id] = complete;
      }
    } catch (_) {}
  }

  /// Fetch all related movie parts / franchise sequels (e.g. Harry Potter, Batman, Spider-Man, James Bond, Anime sequels)
  Future<List<CinemanaItem>> fetchFranchiseParts(CinemanaItem item) async {
    try {
      final enTitle = item.enTitle.trim();
      final arTitle = item.arTitle.trim();
      final queries = _extractFranchiseKeywords(enTitle, arTitle);
      if (queries.isEmpty) return [];

      final Map<String, CinemanaItem> uniqueItems = {};

      for (final q in queries) {
        if (q.length < 2) continue;
        final results = await searchCinemanaTitles(q);
        for (final r in results) {
          if (r.id != item.id && !uniqueItems.containsKey(r.id)) {
            if (_isRelatedFranchiseItem(item, r, q)) {
              uniqueItems[r.id] = r;
            }
          }
        }
        if (uniqueItems.length >= 15) break;
      }

      final list = uniqueItems.values.toList();

      // Sort chronologically (by release year ascending, then title)
      list.sort((a, b) {
        final yA = int.tryParse(a.year) ?? 9999;
        final yB = int.tryParse(b.year) ?? 9999;
        if (yA != yB) return yA.compareTo(yB);
        return a.displayTitle.compareTo(b.displayTitle);
      });

      return list;
    } catch (_) {
      return [];
    }
  }

  List<String> _extractFranchiseKeywords(String en, String ar) {
    final Set<String> candidates = {};
    final combined = '$en $ar'.toLowerCase();

    final known = {
      'harry potter': ['Harry Potter', 'هاري بوتر'],
      'spider-man': ['Spider-Man', 'سبايدر مان'],
      'spiderman': ['Spider-Man', 'سبايدر مان'],
      'batman': ['Batman', 'Dark Knight', 'باتمان'],
      'dark knight': ['Dark Knight', 'Batman'],
      'james bond': ['James Bond', '007', 'جيمس بوند'],
      '007': ['James Bond', '007'],
      'john wick': ['John Wick', 'جون ويك'],
      'fast & furious': ['Fast & Furious', 'Fast and Furious', 'السرعة والغضب'],
      'fast and furious': ['Fast & Furious', 'Fast and Furious'],
      'mission: impossible': ['Mission Impossible', 'مهمة مستحيلة'],
      'mission impossible': ['Mission Impossible', 'مهمة مستحيلة'],
      'lord of the rings': ['Lord of the Rings', 'سيد الخواتم'],
      'star wars': ['Star Wars', 'حرب النجوم'],
      'transformers': ['Transformers', 'المتحولون'],
      'avengers': ['Avengers', 'المنتقمون'],
      'iron man': ['Iron Man', 'الرجل الحديدي'],
      'captain america': ['Captain America', 'كابتن أمريكا'],
      'thor': ['Thor', 'ثور'],
      'hunger games': ['Hunger Games', 'مباريات الجوع'],
      'twilight': ['Twilight', 'توايلايت'],
      'pirates of the caribbean': ['Pirates of the Caribbean', 'قراصنة الكاريبي'],
      'jurassic': ['Jurassic', 'حديقة الديناصورات'],
      'shrek': ['Shrek', 'شريك'],
      'toy story': ['Toy Story', 'حكاية لعبة'],
      'ice age': ['Ice Age', 'العصر الجليدي'],
      'kung fu panda': ['Kung Fu Panda', 'كونغ فو باندا'],
      'attack on titan': ['Attack on Titan', 'هجوم العمالقة'],
      'naruto': ['Naruto', 'ناروتو'],
      'dragon ball': ['Dragon Ball', 'دراغون بول'],
      'one piece': ['One Piece', 'ون بيس'],
      'bleach': ['Bleach', 'بليتش'],
      'demon slayer': ['Demon Slayer', 'قاتل الشياطين'],
      'jujutsu kaisen': ['Jujutsu Kaisen', 'جوجوتسو كايسن'],
      'death note': ['Death Note', 'مذكرة الموت'],
    };

    for (final entry in known.entries) {
      if (combined.contains(entry.key)) {
        candidates.addAll(entry.value);
      }
    }

    for (final title in [en, ar]) {
      if (title.contains(':')) {
        final p = title.split(':').first.trim();
        if (p.length >= 3) candidates.add(p);
      }
      if (title.contains(' - ')) {
        final p = title.split(' - ').first.trim();
        if (p.length >= 3) candidates.add(p);
      }
    }

    final numRegex = RegExp(
      r'^(.*?)\s+(\d+|[IVXLCDM]+|Part\s*\d+|Chapter\s*\d+|الجزء\s*\d+)$',
      caseSensitive: false,
    );
    final enM = numRegex.firstMatch(en);
    if (enM != null && enM.group(1)!.trim().length >= 3) {
      candidates.add(enM.group(1)!.trim());
    }
    final arM = numRegex.firstMatch(ar);
    if (arM != null && arM.group(1)!.trim().length >= 3) {
      candidates.add(arM.group(1)!.trim());
    }

    // Default fallback: if en has at least 2 words, add first 2 words
    final words = en.trim().split(RegExp(r'\s+'));
    if (words.length >= 2 && words.first.length > 2 && words.first.toLowerCase() != 'the') {
      candidates.add('${words[0]} ${words[1]}');
    }

    return candidates.toList();
  }

  bool _isRelatedFranchiseItem(
    CinemanaItem original,
    CinemanaItem candidate,
    String query,
  ) {
    if (candidate.id == original.id) return false;
    final qLower = query.toLowerCase().trim();
    final candEn = candidate.enTitle.toLowerCase();
    final candAr = candidate.arTitle.toLowerCase();

    // Exact phrase match
    if (candEn.contains(qLower) || candAr.contains(qLower)) return true;

    // Multi-word check: all significant words must match
    final qWords = qLower.split(RegExp(r'\s+')).where((w) => w.length > 2).toList();
    if (qWords.length > 1) {
      final allWordsMatch = qWords.every((w) => candEn.contains(w) || candAr.contains(w));
      if (allWordsMatch) return true;
    }

    return false;
  }
}
