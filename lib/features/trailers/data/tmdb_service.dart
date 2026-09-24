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
  /// A wide still (a 16:9 backdrop) for the title, or null.
  ///
  /// The catalogue's names are not TMDB's: «مسلسل طبيعة الحب مدبلج» is a
  /// listing, not a title. The words a listing adds are taken off first,
  /// and a series is looked for among series (a film among films) under
  /// the language the name is in. [hint] is a further name to try - the
  /// Turkish original that the catalogue leaves in its picture's file
  /// name («Doganin-Kanunu»), which TMDB knows when the Arabic dub's
  /// name means nothing to it.
  Future<String?> backdropForTitle(
    String title, {
    String? year,
    bool? series,
    String? hint,
  }) async {
    if (!TmdbConfig.isConfigured) return null;
    final q = cleanTitle(title);
    final arabic = RegExp(r'[؀-ۿ]').hasMatch(q);
    final lang = arabic ? 'ar-SA' : 'en-US';
    final tries = <Future<String?> Function()>[
      if (q.isNotEmpty && series == true)
        () => _searchBackdrop('/search/tv', q, lang, year: year, yearKey: 'first_air_date_year'),
      if (q.isNotEmpty && series == true && year != null && year.isNotEmpty)
        () => _searchBackdrop('/search/tv', q, lang),
      if (q.isNotEmpty && series == false) () => _searchBackdrop('/search/movie', q, lang, year: year, yearKey: 'year'),
      if (q.isNotEmpty) () => _searchBackdrop('/search/multi', q, lang, year: year, yearKey: 'year'),
      if (q.isNotEmpty && year != null && year.isNotEmpty) () => _searchBackdrop('/search/multi', q, lang),
    ];
    var h = cleanTitle(hint ?? '');
    // A title the region knows by its own name, which TMDB does not list
    // as a translation: the original is asked for straight away.
    final known = knownOriginals[q];
    if (known != null) {
      tries.insert(0, () => _searchBackdrop(series == false ? '/search/movie' : '/search/tv', known, 'tr-TR'));
      tries.insert(1, () => _searchBackdrop('/search/multi', known, 'en-US'));
    }
    if (h.isEmpty && arabic) {
      // A listing in two scripts («الأسيرة Esaret») carries the original
      // name in the Latin half.
      final latin = q.replaceAll(RegExp(r'[^A-Za-zÇĞİÖŞÜçğıöşü ]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (latin.length >= 4) h = latin;
    }
    if (h.isNotEmpty && h.toLowerCase() != q.toLowerCase()) {
      // The original is most often Turkish; TMDB matches an original name
      // under any language, so English is asked next for everything else.
      tries.add(() => _searchBackdrop(series == false ? '/search/movie' : '/search/tv', h, 'tr-TR'));
      tries.add(() => _searchBackdrop('/search/multi', h, 'en-US'));
    }
    for (final attempt in tries) {
      final found = await attempt();
      if (found != null) return found;
    }
    return null;
  }

  Future<String?> _searchBackdrop(
    String path,
    String query,
    String language, {
    String? year,
    String? yearKey,
  }) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        path,
        queryParameters: {
          'query': query,
          'language': language,
          if (year != null && year.isNotEmpty && yearKey != null) yearKey: year,
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
    } catch (_) {}
    return null;
  }

  /// A picture for each episode of [season] of the series called [title]:
  /// episode number to still. Empty when TMDB does not know the series,
  /// so a page can fall back to the show's own picture.
  Future<Map<int, String>> episodeStills(
    String title, {
    int season = 1,
    String? hint,
    String? year,
  }) async {
    if (!TmdbConfig.isConfigured) return const {};
    final cacheKey = '$title|$hint|$year|$season';
    final cached = _stillsCache[cacheKey];
    if (cached != null) return cached;
    final id = await _seriesId(title, hint: hint, year: year);
    final out = <int, String>{};
    if (id != null) {
      try {
        final res = await _dio.get<Map<String, dynamic>>(
          '/tv/$id/season/$season',
          queryParameters: {'language': 'ar-SA'},
        );
        final episodes = (res.data?['episodes'] as List?) ?? const [];
        for (final e in episodes.whereType<Map<String, dynamic>>()) {
          final n = e['episode_number'];
          final still = e['still_path'];
          if (n is int && still is String && still.isNotEmpty) {
            out[n] = 'https://image.tmdb.org/t/p/w400$still';
          }
        }
      } catch (_) {}
    }
    _stillsCache[cacheKey] = out;
    return out;
  }

  static final Map<String, Map<int, String>> _stillsCache = {};

  /// TMDB's id for the series called [title], found the way
  /// [backdropForTitle] finds its picture: the Arabic name, a name the
  /// region knows it by, then the original name in [hint].
  Future<int?> _seriesId(String title, {String? hint, String? year}) async {
    final q = cleanTitle(title);
    final arabic = RegExp(r'[؀-ۿ]').hasMatch(q);
    final tries = <(String, String)>[];
    final known = knownOriginals[q];
    if (known != null) tries.add((known, 'en-US'));
    if (q.isNotEmpty) tries.add((q, arabic ? 'ar-SA' : 'en-US'));
    // The first of several other names, and only its Latin half.
    var h = cleanTitle((hint ?? '').split(RegExp(r'[,/|،]')).first);
    if (arabic) {
      final latin = (h.isNotEmpty ? h : q)
          .replaceAll(RegExp(r'[^A-Za-z0-9ÇĞİÖŞÜçğıöşü ]+'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (latin.length >= 3) h = latin;
    }
    if (h.isNotEmpty && h.toLowerCase() != q.toLowerCase()) tries.add((h, 'en-US'));
    for (final (query, lang) in tries) {
      final id = await _searchSeriesId(query, lang, year: year);
      if (id != null) return id;
    }
    return null;
  }

  Future<int?> _searchSeriesId(String query, String language, {String? year}) async {
    for (final withYear in [true, false]) {
      if (withYear && (year == null || year.isEmpty)) continue;
      try {
        final res = await _dio.get<Map<String, dynamic>>(
          '/search/tv',
          queryParameters: {
            'query': query,
            'language': language,
            if (withYear) 'first_air_date_year': year,
            'include_adult': false,
          },
        );
        final results = (res.data?['results'] as List?) ?? const [];
        for (final r in results.whereType<Map<String, dynamic>>()) {
          final id = r['id'];
          if (id is int) return id;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Arabic names of series the region watches, by the original names
  /// TMDB lists them under. Only the ones TMDB's Arabic translations do
  /// not cover; the rest are found by the Arabic name itself.
  static const Map<String, String> knownOriginals = {
    'وادي الذئاب': 'Kurtlar Vadisi',
    'وادى الذئاب': 'Kurtlar Vadisi',
    'حب أبيض وأسود': 'Siyah Beyaz Aşk',
    'حب ابيض واسود': 'Siyah Beyaz Aşk',
    'حب أعمى': 'Kara Sevda',
    'حب اعمى': 'Kara Sevda',
    'عاصمة عبد الحميد': 'Payitaht Abdülhamid',
    'الأسيرة': 'Esaret',
    'الاسيرة': 'Esaret',
    'انت من احببت': 'Sevdiğim Sensin',
    'أنت من أحببت': 'Sevdiğim Sensin',
    'قيامة أرطغرل': 'Diriliş: Ertuğrul',
    'قيامة ارطغرل': 'Diriliş: Ertuğrul',
    'المؤسس عثمان': 'Kuruluş: Osman',
    'العشق الممنوع': 'Aşk-ı Memnu',
    'حريم السلطان': 'Muhteşem Yüzyıl',
    'العشق الأسود': 'Kara Sevda',
    'الحفرة': 'Çukur',
    'المتوحش': 'Yabani',
    'طائر الرفراف': 'Yalı Çapkını',
    'الطائر المبكر': 'Erkenci Kuş',
    'المدينة البعيدة': 'Uzak Şehir',
    'الغرفة الحمراء': 'Kırmızı Oda',
    'أمي': 'Anne',
    'سراج الليل': 'Gece Lambası',
  };

  /// The title as TMDB would know it: without the words a catalogue
  /// listing adds («مسلسل», «مدبلج», «Dubbed», a season or an episode,
  /// «HD»), without brackets, and tidied.
  static String cleanTitle(String title) {
    var t = title.trim();
    if (t.isEmpty) return '';
    for (final word in const [
      'مسلسل',
      'فيلم',
      'مدبلجة',
      'مدبلج',
      'مترجمة',
      'مترجم',
      'كاملة',
      'كامل',
      'للعربية',
      'بالعربي',
      'Dubbed',
      'dubbed',
      'Subbed',
      'subbed',
      'Mudblij',
      'mudblij',
      'Mublij',
      'mublij',
    ]) {
      t = t.replaceAll(word, ' ');
    }
    t = t
        .replaceAll(RegExp(r'(الموسم|الجزء|الحلقة|season|Season|episode|Episode)\s*\S*'), ' ')
        .replaceAll(RegExp(r'\b(HD|4K|1080p|720p)\b'), ' ')
        .replaceAll(RegExp(r'[\(\)\[\]\{\}|:–]+'), ' ')
        .replaceAll(RegExp(r'\s+-\s+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return t;
  }

  /// A name hidden in a picture's file name, or an empty string: the
  /// catalogue names its posters after the original («Doganin-Kanunu-2.jpg»,
  /// «Muhtemel-Ask-mublij-1.jpg»), which is a name TMDB knows. A file named
  /// by a code («Q0CCR-1.jpg», «rGUzU.jpg», a GUID) gives nothing.
  static String hintFromImageName(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) return '';
    var name = Uri.tryParse(imageUrl)?.pathSegments.lastOrNull ?? '';
    name = Uri.decodeComponent(name);
    final dot = name.lastIndexOf('.');
    if (dot > 0) name = name.substring(0, dot);
    final words = name
        .split(RegExp(r'[-_ .]+'))
        .where((w) => w.isNotEmpty)
        .where((w) => !RegExp(r'^\d+$').hasMatch(w))
        .where((w) => !RegExp(r'^m[uo]d?bl[a-z]*$', caseSensitive: false).hasMatch(w))
        .where((w) =>
            !const {'poster', 'screenshot', 'thumb', 'cover', 'scaled', 'copy', 'dubbed'}.contains(w.toLowerCase()))
        .toList();
    if (words.length < 1) return '';
    final joined = words.join(' ');
    // Letters only, with a vowel, and no long token of mixed case and digits.
    if (!RegExp(r'^[A-Za-zÇĞİÖŞÜçğıöşü ]+$').hasMatch(joined)) return '';
    if (!RegExp(r'[aeiouAEIOUıİöÖüÜ]').hasMatch(joined)) return '';
    if (words.length == 1 && (words.first.length < 5 || RegExp(r'[a-z][A-Z]').hasMatch(words.first))) return '';
    return joined;
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
