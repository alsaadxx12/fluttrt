import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:youtube_downloader/core/network/http_cache.dart';
import 'qitv_models.dart';

/// Talks to Qi TV's public APIs to fetch live channels, showcase content,
/// and exclusive Iraqi works.
///
/// Two API bases:
///   - api-prod.qi.tv    → channels, plans, banners (the app API)
///   - api-landing.qi.tv → showcase, exclusive works, categories (landing page)
class QiTvService {
  static const _apiProd = 'https://api-prod.qi.tv';
  static const _apiLanding = 'https://api-landing.qi.tv';

  final Dio _prod = createDio(BaseOptions(
    baseUrl: _apiProd,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 25),
    headers: const {
      'Accept': 'application/json',
      'accept-language': 'ar',
    },
  ));

  final Dio _landing = createDio(BaseOptions(
    baseUrl: _apiLanding,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 25),
    headers: const {
      'Accept': 'application/json',
      'accept-language': 'ar',
    },
  ));

  List<T> _parseList<T>(Response r, T Function(Map<String, dynamic>) parse) {
    final body = r.data is String ? jsonDecode(r.data as String) : r.data;
    final data = body is Map ? body['data'] : null;
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => parse(Map<String, dynamic>.from(e)))
        .toList();
  }

  // ------------------------------------------------------------ prod API

  /// Every channel Qi TV offers, with stream URLs and plan info.
  Future<List<QiChannel>> fetchChannels() async {
    final r = await _prod.get('/api/channels');
    return _parseList(r, QiChannel.fromJson);
  }

  /// Only the channels that are active and on the Free plan.
  Future<List<QiChannel>> fetchFreeActiveChannels() async {
    final all = await fetchChannels();
    return all.where((ch) => ch.active && ch.isFree).toList();
  }

  // --------------------------------------------------------- landing API

  /// The showcase items (Top 10 - movies and series on the landing page).
  Future<List<QiShowcase>> fetchShowcase() async {
    final r = await _landing.get('/api/client/showcase-contents');
    return _parseList(r, QiShowcase.fromJson);
  }

  /// The exclusive Iraqi original works (Qi Originals).
  Future<List<QiExclusiveWork>> fetchExclusiveWorks() async {
    final r = await _landing.get('/api/client/exclusive-works');
    return _parseList(r, QiExclusiveWork.fromJson);
  }
}
