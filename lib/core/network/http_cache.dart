import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

/// A disk-backed cache for JSON GET requests, so the app keeps working offline.
///
/// It sits on every [Dio] built through [createDio] and does three things:
///  * serves a recently cached answer at once (fast path, no network wait),
///  * saves every fresh JSON GET response to disk, and
///  * on any network failure, replays the last saved response for that URL.
///
/// So once a screen has been visited online, its films, series, trailers and
/// everything else it loaded come back with no connection at all. Only true
/// media playback (a trailer's video stream, a film's download) still needs a
/// connection; the browsing data does not.
class HttpCache extends Interceptor {
  HttpCache._();
  static final HttpCache instance = HttpCache._();

  /// A cached answer younger than this is served without touching the network.
  static const Duration _freshFor = Duration(minutes: 10);

  /// Bodies larger than this are not cached (guards against media payloads).
  static const int _maxBodyChars = 4 * 1024 * 1024;

  final Map<String, _Entry> _mem = {};
  Directory? _dir;
  Future<Directory>? _dirFuture;

  Future<Directory> _cacheDir() {
    if (_dir != null) return Future.value(_dir!);
    return _dirFuture ??= () async {
      final base = await getApplicationSupportDirectory();
      final d = Directory('${base.path}/http_cache');
      if (!await d.exists()) await d.create(recursive: true);
      _dir = d;
      return d;
    }();
  }

  bool _cacheable(RequestOptions o) =>
      o.method.toUpperCase() == 'GET' && o.responseType == ResponseType.json;

  String _key(RequestOptions o) => _hash(o.uri.toString());

  /// 64-bit FNV-1a, as hex — a short, stable file name for a URL.
  static String _hash(String s) {
    var h = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    for (final c in utf8.encode(s)) {
      h = (h ^ c) * prime; // 64-bit wraparound is intended
    }
    return (h & 0x7fffffffffffffff).toRadixString(16);
  }

  Response<dynamic> _response(RequestOptions o, _Entry e) => Response<dynamic>(
        requestOptions: o,
        data: e.body,
        statusCode: e.statusCode,
        headers: Headers.fromMap({
          Headers.contentTypeHeader: [e.contentType ?? 'application/json'],
          'x-from-cache': ['1'],
        }),
        extra: {'fromCache': true},
      );

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (!_cacheable(options)) return handler.next(options);
    final key = _key(options);
    final now = DateTime.now().millisecondsSinceEpoch;

    final mem = _mem[key];
    if (mem != null && now - mem.at < _freshFor.inMilliseconds) {
      return handler.resolve(_response(options, mem), true);
    }
    final disk = mem ?? await _read(key);
    if (disk != null) {
      _mem[key] = disk;
      if (now - disk.at < _freshFor.inMilliseconds) {
        return handler.resolve(_response(options, disk), true);
      }
    }
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final o = response.requestOptions;
    final data = response.data;
    if (_cacheable(o) &&
        response.statusCode == 200 &&
        (data is Map || data is List)) {
      _store(_key(o), response.statusCode!, '${response.headers.value(Headers.contentTypeHeader)}', data);
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final o = err.requestOptions;
    if (_cacheable(o)) {
      final key = _key(o);
      final cached = _mem[key] ?? await _read(key);
      if (cached != null) {
        _mem[key] = cached;
        return handler.resolve(_response(o, cached));
      }
    }
    handler.next(err);
  }

  Future<void> _store(String key, int statusCode, String contentType, dynamic body) async {
    final entry = _Entry(DateTime.now().millisecondsSinceEpoch, statusCode, contentType, body);
    _mem[key] = entry;
    try {
      final encoded = jsonEncode({'at': entry.at, 'sc': statusCode, 'ct': contentType, 'b': body});
      if (encoded.length > _maxBodyChars) return;
      final dir = await _cacheDir();
      await File('${dir.path}/$key.json').writeAsString(encoded, flush: false);
    } catch (_) {
      // A cache write failure must never break a real request.
    }
  }

  Future<_Entry?> _read(String key) async {
    try {
      final dir = await _cacheDir();
      final f = File('${dir.path}/$key.json');
      if (!await f.exists()) return null;
      final map = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return _Entry(map['at'] as int, map['sc'] as int? ?? 200, map['ct'] as String?, map['b']);
    } catch (_) {
      return null;
    }
  }
}

class _Entry {
  final int at;
  final int statusCode;
  final String? contentType;
  final dynamic body;
  _Entry(this.at, this.statusCode, this.contentType, this.body);
}

/// A [Dio] that caches JSON GET responses to disk for offline use. Use this
/// everywhere instead of `Dio(...)` so browsing keeps working without a
/// connection.
Dio createDio([BaseOptions? options]) {
  final dio = options == null ? Dio() : Dio(options);
  dio.interceptors.add(HttpCache.instance);
  return dio;
}
