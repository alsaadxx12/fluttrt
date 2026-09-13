import 'dart:async';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Resolves a trailer's playable stream URL, and caches it.
///
/// The slow part of starting a trailer is not the video itself but resolving
/// its stream from YouTube: that round trip costs a second or two. This caches
/// the resolved URL per video, and can resolve a batch ahead of time
/// (prewarm) so that by the time a card is tapped its URL is already in hand
/// and playback starts at once.
///
/// Resolved URLs are time-limited by YouTube (a few hours), so cache entries
/// expire well within that window.
class TrailerStreamResolver {
  TrailerStreamResolver._();
  static final TrailerStreamResolver instance = TrailerStreamResolver._();

  static const _ttl = Duration(hours: 3);

  final Map<String, _Entry> _cache = {};
  final Map<String, Future<Uri?>> _inflight = {};

  /// A fresh cached URL for [videoId], or null.
  Uri? cached(String videoId) {
    final e = _cache[videoId];
    if (e == null) return null;
    if (DateTime.now().difference(e.at) > _ttl) {
      _cache.remove(videoId);
      return null;
    }
    return e.url;
  }

  /// The stream URL for [videoId], resolving and caching it if needed.
  /// Concurrent calls for the same id share one resolution.
  Future<Uri?> resolve(String videoId) {
    final hit = cached(videoId);
    if (hit != null) return Future.value(hit);
    return _inflight.putIfAbsent(videoId, () => _resolve(videoId))
      ..whenComplete(() => _inflight.remove(videoId));
  }

  Future<Uri?> _resolve(String videoId) async {
    final yt = YoutubeExplode();
    try {
      StreamManifest manifest;
      try {
        manifest = await yt.videos.streamsClient
            .getManifest(videoId, requireWatchPage: false)
            .timeout(const Duration(seconds: 12));
      } on TimeoutException {
        manifest = await yt.videos.streamsClient.getManifest(videoId);
      }
      final muxed = manifest.muxed;
      if (muxed.isEmpty) return null;
      // The highest-resolution muxed stream available (a single stream that
      // already carries audio, so it plays as-is). We select the absolute highest
      // resolution (height and width) and highest bitrate available.
      final list = muxed.toList()
        ..sort((a, b) {
          final byHeight = b.videoResolution.height.compareTo(a.videoResolution.height);
          if (byHeight != 0) return byHeight;
          final byWidth = b.videoResolution.width.compareTo(a.videoResolution.width);
          if (byWidth != 0) return byWidth;
          return b.bitrate.compareTo(a.bitrate);
        });
      final stream = list.first;
      _cache[videoId] = _Entry(stream.url, DateTime.now());
      return stream.url;
    } catch (_) {
      return null;
    } finally {
      yt.close();
    }
  }

  /// Resolve several trailers ahead of time, a few at a time, ignoring
  /// failures. Ones already cached or already resolving are skipped.
  Future<void> prewarm(Iterable<String> videoIds, {int concurrency = 2}) async {
    final todo = videoIds
        .where((id) => id.isNotEmpty && cached(id) == null && !_inflight.containsKey(id))
        .toList();
    for (var i = 0; i < todo.length; i += concurrency) {
      final batch = todo.skip(i).take(concurrency).map(resolve);
      await Future.wait(batch);
    }
  }
}

class _Entry {
  final Uri url;
  final DateTime at;
  const _Entry(this.url, this.at);
}
