import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/sports_models.dart';
import 'sports_service.dart';

/// Everything that makes a stream start sooner without making the network
/// itself faster.
///
/// Tapping a match used to cost up to four serial round trips before the
/// first video byte: list the live matches, resolve the stream, resolve the
/// direct player, then let the WebView do DNS, TLS and the page itself. This
/// removes the waits that are not the network's fault:
///
///  * a resolved stream is remembered for a few minutes, so going back into
///    a match is instant instead of repeating the whole chain;
///  * the streams of the matches on screen are resolved in the background
///    before anything is tapped;
///  * the connection to the stream host is opened in advance, so the player's
///    first request skips DNS and the TLS handshake.
class StreamWarmup {
  StreamWarmup(this._service);

  final SportsService _service;

  /// A live stream url is signed and short-lived; a few minutes is long
  /// enough to help and short enough never to hand out a dead one.
  static const ttl = Duration(minutes: 4);

  /// How many of the matches on screen to resolve ahead of the tap. Kept
  /// small: this is speculative work on someone's mobile data.
  static const prefetchLimit = 3;

  final Map<int, _Entry> _cache = {};
  final Set<int> _inFlight = {};
  final Set<String> _preconnected = {};

  /// A stream resolved earlier and still fresh, or null.
  StreamInfo? cached(int streamId) {
    final e = _cache[streamId];
    if (e == null) return null;
    if (DateTime.now().difference(e.at) > ttl) {
      _cache.remove(streamId);
      return null;
    }
    return e.info;
  }

  void remember(int streamId, StreamInfo info) {
    _cache[streamId] = _Entry(info, DateTime.now());
    preconnect(info.url);
  }

  /// Resolves a stream, using the cache when it can. Concurrent callers for
  /// the same id share one request instead of racing.
  Future<StreamInfo?> resolve(int streamId) async {
    final hit = cached(streamId);
    if (hit != null) return hit;
    if (_inFlight.contains(streamId)) return null;
    _inFlight.add(streamId);
    try {
      final info = await _service.fetchStream(streamId);
      if (info != null && info.ok && info.url.isNotEmpty) {
        remember(streamId, info);
        return info;
      }
      return info;
    } finally {
      _inFlight.remove(streamId);
    }
  }

  /// Resolve the streams of matches the user can see, so the one they tap is
  /// already waiting. Errors are ignored: this is a head start, not a step.
  Future<void> prefetch(Iterable<int> streamIds) async {
    final ids = streamIds.take(prefetchLimit).where((id) => cached(id) == null).toList();
    for (final id in ids) {
      unawaited(resolve(id).catchError((_) => null));
    }
  }

  /// Open the connection to a host before it is needed. On a weak mobile
  /// link the DNS lookup and TLS handshake alone can cost most of a second.
  Future<void> preconnect(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority) return;
    final key = '${uri.scheme}://${uri.host}';
    if (!_preconnected.add(key)) return;
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 4)
        ..idleTimeout = const Duration(seconds: 30)
        ..userAgent = 'okhttp/4.9.0';
      final req = await client.headUrl(uri).timeout(const Duration(seconds: 4));
      final res = await req.close().timeout(const Duration(seconds: 4));
      await res.drain<void>();
      // The socket stays in the pool for the real request that follows.
    } catch (e) {
      // A host that refuses HEAD still had its DNS and TLS warmed.
      debugPrint('[WARMUP] preconnect $key: $e');
    }
  }

  void clear() {
    _cache.clear();
    _preconnected.clear();
  }
}

class _Entry {
  final StreamInfo info;
  final DateTime at;
  const _Entry(this.info, this.at);
}
