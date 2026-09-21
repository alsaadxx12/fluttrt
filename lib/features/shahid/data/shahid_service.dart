import 'package:dio/dio.dart';
import 'package:youtube_downloader/core/network/http_cache.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'shahid_models.dart';

/// Row ids from Shahid's public home and category pages (visible to guests).
class ShahidRows {
  ShahidRows._();

  // Free sections (AVOD)
  static const freeTrendsSeries =
      'Main/LEVANT/free/LEV-Free-Trends-RecentContent-Series-All-AVOD';
  static const freeArabicSeries =
      'Main/LEVANT/free/LEV-Free-Trends-RecentContent-Series-Dialect-All-All-PAN~Guest';
  static const freeEgyptianSeries =
      'Main/LEVANT/free/LEV-Free-Trends-RecentContent-Series-Dialect-All-All-Egyptian';
  static const freeGulfSeries =
      'Main/LEVANT/free/LEV-Free-Trends-RecentContent-Series-Dialect-All-All-Gulf~Guest';
  static const freeTurkishSeries =
      'Main/LEVANT/free/LEV-Free-Trends-RecentContent-Series-Dialect-All-All-Turkish~Guest';
  static const freeTvShows =
      'Main/LEVANT/free/LEV-Free-Trends-RecentContent-All-All-TVShows';
  static const freeWhatsOnTv =
      'Main/LEVANT/free/LEV-Free-Editorial-WhatsonTv-TV-AVOD~Guest';

  // Series section
  static const seriesArabic =
      'Main/LEVANT/series/LEV-Series-Trends-RecentContent-Series-Dialect-All-All-PAN~Guest';
  static const seriesGulf =
      'Main/LEVANT/series/LEV-Series-Trends-RecentContent-Series-Dialect-All-All-Gulf~Guest';
  static const seriesEgyptian =
      'Main/LEVANT/series/LEV-Series-Trends-RecentContent-Series-Dialect-All-All-Egyptian~Guest';
  static const seriesTurkish =
      'Main/LEVANT/series/LEV-Series-Trends-RecentContent-Series-Dialect-All-All-Turkish~Guest';

  // Home section
  static const gulfSeries =
      'Main/LEVANT/home/LEV-Home-Trends-RecentContent-Series-Dialect-All-All-Gulf~Guest';
  static const newOnShahid = 'Main/LEVANT/home/LEV-Home-Trends-RecentContent-All-All~Guest';
  static const arabicSeries =
      'Main/LEVANT/home/LEV-Home-Trends-RecentContent-Series-Dialect-All-All-PAN~Guest';
  static const spiderMan = 'Main/LEVANT/home/LEV-Home-Editorial-SpiderMan-Movies-All~Guest';
  static const turkishSeries =
      'Main/LEVANT/home/LEV-Home-Trends-RecentContent-Series-Dialect-All-All-Turkish~Guest';
  static const egyptianSeries =
      'Main/LEVANT/home/LEV-Home-Trends-RecentContent-Series-Dialect-All-All-Egyptian~Guest';

  static const liveTv = 'Main/LEVANT/home/LEV-Home-Hybrid-EditorialPersonalized-LiveTV-All-All~Guest';
  static const fastChannels = 'Main/LEVANT/home/LEV-Home-Editorial-FastStream-All-All~Guest';
}

/// Reads Shahid's public editorial API - the same guest endpoints the
/// shahid.mbc.net home page calls for its rows. Metadata only.
class ShahidService {
  final Dio _dio;

  ShahidService({Dio? dio})
      : _dio = dio ??
            createDio(
              BaseOptions(
                baseUrl: 'https://api3.shahid.net/proxy/v2.1',
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 15),
                headers: {
                  'User-Agent':
                      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
                  'Accept': 'application/json',
                  'Origin': 'https://shahid.mbc.net',
                  'Referer': 'https://shahid.mbc.net/',
                },
              ),
            );

  static const _country = 'IQ';

  /// One page of a row. The API rejects page sizes under 10 with a 404.
  Future<({List<ShahidItem> items, bool hasMore})> _page(
    String rowId, {
    required int page,
    required int pageSize,
  }) async {
    final request =
        '{"displayedItems":0,"id":"$rowId","itemsRequestedStatic":true,"pageNumber":$page,"pageSize":$pageSize}';
    final res = await _dio.get(
      '/editorial/carousel',
      queryParameters: {'request': request, 'country': _country},
    );
    final data = res.data;
    if (data is! Map) return (items: const <ShahidItem>[], hasMore: false);
    final isFreeRow = rowId.contains('/free/');
    final items = (data['editorialItems'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => e['item'] is Map ? e['item'] as Map : e)
        .map((m) {
          final it = ShahidItem.fromJson(Map<String, dynamic>.from(m));
          return isFreeRow ? it.copyWith(isFree: true) : it;
        })
        .where((i) => i.id != 0 && i.title.isNotEmpty && i.pageUrl.isNotEmpty)
        .toList();
    return (items: items, hasMore: data['hasMore'] == true);
  }

  Future<List<ShahidItem>> fetchRow(String rowId, {int pageSize = 15}) async {
    try {
      return (await _page(rowId, page: 0, pageSize: pageSize)).items;
    } catch (e) {
      debugPrint('[SHAHID] row failed ($rowId): $e');
      return const [];
    }
  }

  /// Paged fetching for catalog screens
  Future<({List<ShahidItem> items, bool hasMore})> fetchPagedRow(
    String rowId, {
    required int page,
    int pageSize = 20,
  }) async {
    try {
      return await _page(rowId, page: page, pageSize: pageSize.clamp(10, 50));
    } catch (e) {
      debugPrint('[SHAHID] paged row failed ($rowId p$page): $e');
      return (items: const <ShahidItem>[], hasMore: false);
    }
  }

  /// Free Arabic Series (مسلسلات عربية مجانية)
  Future<List<ShahidItem>> fetchFreeArabicSeries({int pageSize = 20}) async {
    final pan = await fetchRow(ShahidRows.freeArabicSeries, pageSize: pageSize);
    if (pan.isNotEmpty) return pan;
    return fetchRow(ShahidRows.seriesArabic, pageSize: pageSize);
  }

  /// All Free Series (جميع المسلسلات المجانية من شاهد)
  Future<List<ShahidItem>> fetchFreeAllSeries({int pageSize = 20}) async {
    return fetchRow(ShahidRows.freeTrendsSeries, pageSize: pageSize);
  }

  /// Collects all unique free series across multiple dialect rows
  Future<List<ShahidItem>> fetchAllFreeCatalog() async {
    final rows = [
      ShahidRows.freeTrendsSeries,
      ShahidRows.freeArabicSeries,
      ShahidRows.freeEgyptianSeries,
      ShahidRows.freeGulfSeries,
      ShahidRows.freeTurkishSeries,
      ShahidRows.freeTvShows,
    ];

    final results = await Future.wait(rows.map((r) => fetchRow(r, pageSize: 20)));
    final byId = <int, ShahidItem>{};
    for (final list in results) {
      for (final item in list) {
        byId.putIfAbsent(item.id, () => item.copyWith(isFree: true));
      }
    }
    return byId.values.toList();
  }

  /// The HLS address Shahid hands its own player for a channel - only when
  /// it is an unencrypted HLS stream. DRM-protected (DASH/Widevine) streams
  /// return null and are left alone.
  Future<String?> fetchStreamUrl(int channelId) async {
    try {
      final res = await _dio.get(
        '/playout/new/url/$channelId',
        queryParameters: {'country': _country},
      );
      final playout = res.data is Map ? (res.data as Map)['playout'] : null;
      if (playout is! Map) return null;
      if (playout['drm'] == true) return null;
      final url = playout['url']?.toString() ?? '';
      return url.contains('.m3u8') ? url : null;
    } catch (e) {
      debugPrint('[SHAHID] playout failed ($channelId): $e');
      return null;
    }
  }

  /// Every live channel Shahid lists: the main live row (paged) plus the
  /// round-the-clock FAST channels, de-duplicated.
  Future<List<ShahidItem>> fetchLiveChannels() async {
    final byId = <int, ShahidItem>{};
    Future<void> collect(String rowId) async {
      for (var page = 0; page < 5; page++) {
        try {
          final r = await _page(rowId, page: page, pageSize: 30);
          for (final item in r.items.where((i) => i.isLive)) {
            byId.putIfAbsent(item.id, () => item);
          }
          if (!r.hasMore || r.items.isEmpty) break;
        } catch (e) {
          debugPrint('[SHAHID] live row failed ($rowId p$page): $e');
          break;
        }
      }
    }

    await collect(ShahidRows.liveTv);
    await collect(ShahidRows.fastChannels);

    // Only channels Shahid gives away free (AVOD) - subscription channels are
    // not played here - and of those only the ones with an open HLS stream,
    // checked in parallel so a dead or encrypted channel never shows a card.
    final free = byId.values.where((c) => c.isFree).toList();
    final streams = await Future.wait(free.map((c) => fetchStreamUrl(c.id)));
    return [
      for (var i = 0; i < free.length; i++)
        if (streams[i] != null) free[i].copyWith(streamUrl: streams[i]),
    ];
  }
}
