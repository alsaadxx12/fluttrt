import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';

import '../../cinemana/data/cinemana_subtitles.dart';
import 'viu_models.dart';

/// A page of a category: the free shows found in it, and whether Viu has
/// more entries after this page.
class ViuPage {
  final List<ViuShow> shows;
  final bool hasMore;
  final int nextOffset;
  const ViuPage(this.shows, this.hasMore, this.nextOffset);
}

/// Talks to Viu's public web API the way viu.com does for a visitor who is
/// not signed in: a guest token, then catalogue and playback requests.
/// Only what Viu gives every visitor for free is used - episodes marked for
/// subscribers are left out.
class ViuService {
  static const _gateway = 'https://api-gateway-global.viu.com/api';
  static const _ua =
      'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  // Viu MENA (Iraq), Arabic.
  static const _region = {
    'platform_flag_label': 'web',
    'platformFlagLabel': 'web',
    'area_id': '1004',
    'areaId': '1004',
    'language_flag_id': '6',
    'languageFlagId': '6',
    'countryCode': 'IQ',
    'ut': '0',
  };

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _gateway,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 25),
      headers: const {
        'User-Agent': _ua,
        'Referer': 'https://www.viu.com/',
        'Origin': 'https://www.viu.com',
      },
    ),
  );

  final String _deviceId = _uuidV4();
  Future<String>? _token;
  final Map<String, Future<List<ViuEpisode>>> _episodes = {};

  // ------------------------------------------------------------ plumbing

  Future<String> _getToken({bool refresh = false}) {
    if (refresh || _token == null) {
      _token = _requestToken();
      // A failed request must not be cached.
      _token!.catchError((Object _) {
        _token = null;
        return '';
      });
    }
    return _token!;
  }

  Future<String> _requestToken() async {
    final r = await _dio.post('/auth/token', data: {
      'countryCode': 'IQ',
      'platform': 'browser',
      'platformFlagLabel': 'web',
      'language': 'ar',
      'uuid': _deviceId,
      'carrierId': '0',
    });
    final data = r.data is String ? jsonDecode(r.data as String) : r.data;
    final token = data is Map ? data['token'] : null;
    if (token is! String || token.isEmpty) throw const ViuException('تعذّر الاتصال بـ Viu');
    return token;
  }

  Future<Map<String, dynamic>> _get(String path, Map<String, dynamic> params) async {
    for (var attempt = 0;; attempt++) {
      final token = await _getToken(refresh: attempt > 0);
      try {
        final r = await _dio.get(
          path,
          queryParameters: params,
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
        final data = r.data is String ? jsonDecode(r.data as String) : r.data;
        if (data is! Map) throw const ViuException('رد غير متوقع من Viu');
        return Map<String, dynamic>.from(data);
      } on DioException catch (e) {
        final code = e.response?.statusCode;
        // An expired guest token: get a fresh one once.
        if (attempt == 0 && (code == 401 || code == 403)) continue;
        rethrow;
      }
    }
  }

  Future<Map<String, dynamic>> _mobile(String route, [Map<String, dynamic> params = const {}]) =>
      _get('/mobile', {..._region, 'r': route, ...params});

  static Map<String, dynamic> _data(Map<String, dynamic> json) {
    final d = json['data'];
    return d is Map ? Map<String, dynamic>.from(d) : const {};
  }

  // ----------------------------------------------------------- catalogue

  /// Every episode of a series, oldest first (cached for the session).
  Future<List<ViuEpisode>> fetchEpisodes(String seriesId) {
    return _episodes.putIfAbsent(seriesId, () async {
      final json = await _mobile('/vod/product-list', {'series_id': seriesId, 'size': '-1', 'sort': 'asc'});
      final list = _data(json)['product_list'];
      final eps = (list is List ? list : const [])
          .whereType<Map>()
          .map((e) => ViuEpisode.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.productId.isNotEmpty && e.ccsProductId.isNotEmpty)
          .toList()
        ..sort((a, b) => a.number.compareTo(b.number));
      return eps;
    }).catchError((Object e) {
      _episodes.remove(seriesId); // retry next time
      throw e;
    });
  }

  /// Free episodes only.
  Future<List<ViuEpisode>> fetchFreeEpisodes(String seriesId) async =>
      (await fetchEpisodes(seriesId)).where((e) => e.isFree).toList();

  Future<List<ViuShow>> _categoryEntries(String categoryId, int offset, int length) async {
    final json = await _mobile('/category/series', {
      'category_id': categoryId,
      'length': '$length',
      'offset': '$offset',
    });
    final list = _data(json)['series'];
    return (list is List ? list : const [])
        .whereType<Map>()
        .map((e) => ViuShow.fromSeries(Map<String, dynamic>.from(e)))
        .where((s) => s.seriesId.isNotEmpty && !s.isTrailer)
        .toList();
  }

  /// Series with at least one free episode, from [offset] on, until [want]
  /// are found or the category ends. Viu lists newest first and its newest
  /// titles are often for subscribers only, so it may take a few pages.
  ///
  /// The list shows the access of each series' latest episode: free there
  /// means free. Otherwise the episodes are checked (and stay cached for
  /// playback).
  Future<ViuPage> fetchFreeShows(
    String categoryId, {
    int offset = 0,
    int want = 18,
    int pageSize = 30,
    int maxPages = 5,
  }) async {
    final shows = <ViuShow>[];
    var at = offset;
    var more = true;
    for (var page = 0; page < maxPages && more && shows.length < want; page++) {
      final entries = await _categoryEntries(categoryId, at, pageSize);
      more = entries.length >= pageSize;
      at += pageSize;

      final keep = List<bool>.filled(entries.length, false);
      var next = 0;
      Future<void> worker() async {
        while (next < entries.length) {
          final i = next++;
          if (entries[i].userLevel == 0) {
            keep[i] = true;
            continue;
          }
          try {
            keep[i] = (await fetchEpisodes(entries[i].seriesId)).any((e) => e.isFree);
          } catch (_) {}
        }
      }

      await Future.wait(List.generate(6, (_) => worker()));
      for (var i = 0; i < entries.length; i++) {
        if (keep[i]) shows.add(entries[i]);
      }
    }
    return ViuPage(shows, more, at);
  }

  /// Free films: those in the films category plus free films Viu features
  /// on its home page.
  Future<List<ViuShow>> fetchFreeMovies() async {
    final results = await Future.wait([
      _categoryEntries(ViuCategory.movies.id, 0, 300).catchError((Object _) => <ViuShow>[]),
      _homeGridMovies().catchError((Object _) => <ViuShow>[]),
    ]);
    final seen = <String>{};
    return [
      for (final m in [...results[0], ...results[1]])
        if (m.userLevel == 0 && seen.add(m.seriesId)) m,
    ];
  }

  Future<List<ViuShow>> _homeGridMovies() async {
    final grids = _data(await _mobile('/home/index'))['grid'];
    return [
      for (final g in (grids is List ? grids : const []).whereType<Map>())
        for (final p in (g['product'] is List ? g['product'] as List : const []).whereType<Map>())
          if ('${p['is_movie']}' == '1') ViuShow.fromGridProduct(Map<String, dynamic>.from(p)),
    ].where((s) => s.seriesId.isNotEmpty).toList();
  }

  // ------------------------------------------------------------ playback

  /// Stream addresses and Arabic subtitles for a free episode.
  Future<ViuPlayback> fetchPlayback(ViuEpisode episode) async {
    if (!episode.isFree) throw const ViuException('هذه الحلقة متاحة للمشتركين فقط');

    final detail = _data(await _mobile('/vod/detail', {'product_id': episode.productId, 'os_flag_id': '1'}));
    final current = detail['current_product'];
    final cur = current is Map ? Map<String, dynamic>.from(current) : const <String, dynamic>{};
    if ('${cur['user_level'] ?? 0}' != '0') throw const ViuException('هذه الحلقة متاحة للمشتركين فقط');
    final ccs = '${cur['ccs_product_id'] ?? episode.ccsProductId}';

    String? arabicSubs;
    final subs = cur['subtitle'];
    if (subs is List) {
      for (final s in subs.whereType<Map>()) {
        final url = '${s['url'] ?? s['subtitle_url'] ?? ''}';
        if ('${s['code']}' == 'ar' && url.startsWith('http')) arabicSubs = url;
      }
    }

    final play = await _get('/playback/distribute', {
      'ccs_product_id': ccs,
      'platform_flag_label': 'web',
      'language_flag_id': '6',
      'ui_language': 'ar',
      'area_id': '1004',
      'os_flag_id': '1',
      'countryCode': 'IQ',
    });
    final stream = _data(play)['stream'];
    if (stream is! Map) throw const ViuException('البث غير متاح لهذه الحلقة الآن');
    if ('${stream['is_drm']}'.toLowerCase() == 'y') {
      throw const ViuException('هذه الحلقة محمية ولا يمكن تشغيلها هنا');
    }

    final qualities = <ViuQuality>[];
    final urls = stream['url'] is Map ? stream['url'] as Map : (stream['url2'] is Map ? stream['url2'] as Map : const {});
    urls.forEach((k, v) {
      final label = '$k'.replaceFirst('s', '');
      if (v is String && v.startsWith('http')) qualities.add(ViuQuality(label, v));
    });
    int px(ViuQuality q) => int.tryParse(q.label.replaceAll(RegExp(r'\D'), '')) ?? 0;
    qualities.sort((a, b) => px(a).compareTo(px(b)));
    if (qualities.isEmpty) throw const ViuException('البث غير متاح لهذه الحلقة الآن');

    return ViuPlayback(qualities: qualities, arabicSubtitleUrl: arabicSubs);
  }

  Future<List<SubtitleCue>> fetchSubtitleCues(String url) async {
    try {
      final r = await _dio.get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
      final bytes = r.data;
      if (bytes == null || bytes.isEmpty) return const [];
      return parseSubtitles(utf8.decode(bytes, allowMalformed: true));
    } catch (_) {
      return const [];
    }
  }
}

String _uuidV4() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
