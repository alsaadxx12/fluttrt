import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

/// A disk-backed cache for JSON GET requests, so the app keeps working offline
/// and every screen comes back at once.
///
/// It sits on every [Dio] built through [createDio] and does four things:
///  * serves any cached answer younger than a day at once (cache first, no
///    network wait),
///  * when that answer is older than ten minutes, refreshes it in the
///    background so the next visit gets current data without a spinner,
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

  /// A cached answer younger than this is still served at once; once it is
  /// older than [_freshFor] a background revalidation refreshes it as well.
  /// Anything older goes to the network first (the disk copy stays the
  /// offline fallback).
  static const Duration _maxAge = Duration(hours: 24);

  /// Bodies larger than this are not cached (guards against media payloads).
  static const int _maxBodyChars = 4 * 1024 * 1024;

  /// Cached text larger than this is decoded on a background isolate; smaller
  /// entries decode faster inline than an isolate round-trip costs.
  static const int _inlineDecodeChars = 64 * 1024;

  final Map<String, _Entry> _mem = {};

  /// Keys with a background revalidation in flight, so a stale entry hit
  /// repeatedly triggers one network request, not one per hit.
  final Set<String> _revalidating = {};
  Directory? _dir;

  /// Milliseconds since the epoch. Tests replace it to age entries without
  /// waiting.
  @visibleForTesting
  int Function() now = () => DateTime.now().millisecondsSinceEpoch;

  /// Builds the [Dio] that carries a background revalidation: a fresh one, so
  /// the caller's cancel token and other interceptors do not apply. Tests
  /// replace it to fake the network.
  @visibleForTesting
  Dio Function() newDio = Dio.new;

  /// Entries stored before this instant are no longer served as fresh: a
  /// pull-to-refresh calls [markStale] so the next request for every URL
  /// goes to the network. The disk copy still remains the offline fallback.
  int _staleBefore = 0;
  void markStale() => _staleBefore = now();
  bool _fresh(_Entry e, int t) => e.at >= _staleBefore && t - e.at < _freshFor.inMilliseconds;
  bool _usable(_Entry e, int t) => e.at >= _staleBefore && t - e.at < _maxAge.inMilliseconds;
  bool _isRevalidation(RequestOptions o) => o.extra['revalidate'] == true;
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

  /// When the in-memory entry for [uri] was stored (ms since the epoch), or
  /// null when there is none.
  @visibleForTesting
  int? storedAt(Uri uri) => _mem[_hash(uri.toString())]?.at;

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
    // A background revalidation must reach the network, never the cache.
    if (!_cacheable(options) || _isRevalidation(options)) return handler.next(options);
    final key = _key(options);
    final t = now();

    final mem = _mem[key];
    if (mem != null && _usable(mem, t)) return _serve(options, handler, key, mem, t);
    final disk = mem ?? await _read(key);
    if (disk != null) {
      _mem[key] = disk;
      if (_usable(disk, t)) return _serve(options, handler, key, disk, t);
    }
    handler.next(options);
  }

  /// Answers [options] from [e] at once and, when [e] is past [_freshFor],
  /// refreshes it in the background for the next visit.
  void _serve(RequestOptions options, RequestInterceptorHandler handler, String key, _Entry e, int t) {
    // false: a cached answer must not run onResponse, which would re-write
    // the entry and reset its age on every hit.
    handler.resolve(_response(options, e), false);
    if (!_fresh(e, t)) unawaited(_revalidate(key, options));
  }

  /// Fetches [options] again on a fresh [Dio]; the answer lands in the cache
  /// through [onResponse]. One request per key at a time; a failure is
  /// ignored — the cached copy stays in place and a later hit tries again.
  Future<void> _revalidate(String key, RequestOptions options) async {
    if (!_revalidating.add(key)) return;
    try {
      // copyWith keeps the caller's token when handed null, so clear it (and
      // the caller's progress callbacks) on the copy instead.
      final request = options.copyWith(extra: {...options.extra, 'revalidate': true})
        ..cancelToken = null
        ..onReceiveProgress = null
        ..onSendProgress = null;
      await (newDio()..interceptors.add(this)).fetch<dynamic>(request);
    } catch (_) {
      // Swallowed on purpose: nobody is waiting on a background refresh.
    } finally {
      _revalidating.remove(key);
    }
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final o = response.requestOptions;
    final data = response.data;
    // A cached answer is never written back: that would reset its age.
    if (_cacheable(o) &&
        response.extra['fromCache'] != true &&
        response.statusCode == 200 &&
        (data is Map || data is List)) {
      _store(_key(o), response.statusCode!, '${response.headers.value(Headers.contentTypeHeader)}', data);
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final o = err.requestOptions;
    // A failed revalidation needs no replay: the caller already has the copy.
    if (_cacheable(o) && !_isRevalidation(o)) {
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
    final entry = _Entry(now(), statusCode, contentType, body);
    _mem[key] = entry;
    try {
      final encoded = await _encode({'at': entry.at, 'sc': statusCode, 'ct': contentType, 'b': body});
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
      final text = await f.readAsString();
      final map = (text.length > _inlineDecodeChars ? await _decode(text) : jsonDecode(text)) as Map<String, dynamic>;
      return _Entry(map['at'] as int, map['sc'] as int? ?? 200, map['ct'] as String?, map['b']);
    } catch (_) {
      return null;
    }
  }

  // JSON work for a large listing is real CPU time; both run on a background
  // isolate. Static so the closures capture only their argument, never
  // `this` (whose pending futures could not be sent to another isolate).
  static Future<String> _encode(Map<String, Object?> record) => Isolate.run(() => jsonEncode(record));
  static Future<dynamic> _decode(String text) => Isolate.run(() => jsonDecode(text));
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
