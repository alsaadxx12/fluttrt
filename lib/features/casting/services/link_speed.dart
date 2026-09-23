import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// How fast the internet is right now, measured rather than assumed.
///
/// The quality a film is sent in used to be a fixed choice, and on a link
/// that is 6 Mbit/s one evening and 1.5 the next a fixed choice is wrong
/// half the time: too sharp and the set stalls every minute, too soft and
/// the evening the link was good is wasted. So before a film is sent, a
/// couple of megabytes of it are pulled down against the clock, and the
/// ceiling is set from what arrived.
///
/// The sample is the film's own address, not a speed-test server: what
/// matters is how fast *this* CDN reaches *this* phone, redirect and all.
class LinkSpeed {
  LinkSpeed._();

  /// How much is pulled down for the measurement, at most.
  static const int _sampleBytes = 1536 * 1024;

  /// How long the measurement may take. On a slow link the sample is not
  /// finished by then, and what did arrive is answer enough.
  static const Duration _sampleFor = Duration(seconds: 3);

  /// Below this much the answer is noise, not a measurement.
  static const int _enough = 48 * 1024;

  /// A measurement is believed for this long: the next episode does not
  /// need another.
  static const Duration _remember = Duration(seconds: 90);

  static double? _last;
  static DateTime? _lastAt;

  /// Bytes per second the link carried, or null when it could not be
  /// measured — in which case the caller keeps its own ceiling.
  static Future<double?> measure(String url, {HttpClient? client}) async {
    final remembered = _last;
    if (remembered != null &&
        _lastAt != null &&
        DateTime.now().difference(_lastAt!) < _remember) {
      return remembered;
    }
    final speed = await _sample(url, client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 6)));
    if (speed != null) {
      _last = speed;
      _lastAt = DateTime.now();
    }
    return speed;
  }

  /// Forgets the last measurement — for a test, or a network that changed.
  @visibleForTesting
  static void forget() {
    _last = null;
    _lastAt = null;
  }

  static Future<double?> _sample(String url, HttpClient client) async {
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.followRedirects = true;
      request.maxRedirects = 5;
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-${_sampleBytes - 1}');
      final response = await request.close().timeout(_sampleFor);
      if (response.statusCode >= 400) return null;

      // Timed from the first byte, not from the request: the redirect and
      // the handshake are latency, and latency is not bandwidth.
      var received = 0;
      DateTime? first;
      final done = Completer<void>();
      late final StreamSubscription<List<int>> sub;
      sub = response.listen(
        (chunk) {
          first ??= DateTime.now();
          received += chunk.length;
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        onError: (Object _) {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );
      await done.future.timeout(_sampleFor, onTimeout: () {});
      await sub.cancel();

      final start = first;
      if (start == null || received < _enough) return null;
      // A sample that arrived faster than the clock can tell is a link
      // fast enough for anything; it is not a reason to say nothing.
      final seconds = DateTime.now().difference(start).inMicroseconds / 1e6;
      return received / (seconds < 0.05 ? 0.05 : seconds);
    } catch (e) {
      debugPrint('[cast] link speed: $e');
      return null;
    }
  }

  /// The tallest picture a link of [bytesPerSecond] carries comfortably.
  ///
  /// The catalogue's 1080p files run at roughly 1.5–3 Mbit/s and its 720p
  /// at about half that. The phone pulls the film down and pushes it back
  /// out over the same wifi, so the link is asked for about twice the
  /// bitrate before a quality is chosen — headroom for the prefetch to
  /// stay ahead, and for the evening rush.
  static int ceilingFor(double bytesPerSecond) {
    final kbps = bytesPerSecond * 8 / 1000;
    if (kbps >= 4500) return 1080;
    if (kbps >= 2200) return 720;
    return 480;
  }

  /// «2.1 Mbit/s», for the remote.
  static String describe(double bytesPerSecond) {
    final mbps = bytesPerSecond * 8 / 1e6;
    return mbps >= 10
        ? '${mbps.round()} Mbit/s'
        : '${mbps.toStringAsFixed(1)} Mbit/s';
  }
}
