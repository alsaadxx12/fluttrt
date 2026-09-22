import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'mp4_faststart.dart';

/// A small http server on the phone, so a television can fetch what it
/// cannot fetch for itself.
///
/// DLNA was built for plain http on a local network, and it shows. A smart
/// television's built-in player will usually not do TLS at all, and most of
/// them will not follow a redirect — while the catalogue serves `https` and
/// answers with a 302 to whichever CDN node is nearest. A set handed that
/// address opens its player, fails quietly and drops straight back out,
/// which is exactly what happens.
///
/// So the phone stands in the middle: it takes the address the television
/// was going to be given, hands the set a plain `http://<phone>:<port>/…`
/// instead, and fetches the real stream itself. TLS, redirects and any
/// headers the source insists on are all dealt with on this side, where
/// there is a modern http client to do it.
///
/// Range requests pass through untouched, so seeking still works, and the
/// body is piped rather than held — a film is never in memory.
class LocalStreamServer {
  HttpServer? _server;

  /// What each token stands for. Small: one entry per thing being cast.
  final Map<String, _Source> _sources = <String, _Source>{};

  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..idleTimeout = const Duration(seconds: 30);

  final Random _random = Random.secure();

  /// True while the server is up.
  bool get isRunning => _server != null;

  /// Publishes [url] on the local network and returns the address to give
  /// the television.
  ///
  /// [headers] are sent upstream, not handed to the set — that is the whole
  /// point for a source that demands a Referer.
  Future<String?> publish(
    String url, {
    Map<String, String>? headers,
    String? contentType,
  }) async {
    final server = await _ensureStarted();
    if (server == null) return null;

    final host = await _lanAddress();
    if (host == null) {
      debugPrint('[cast] no local address to serve from');
      return null;
    }

    // A token rather than the url in a query string: the address ends up in
    // the television's memory, its logs, and sometimes on its screen, and a
    // signed url has no business in any of those.
    final token = List<int>.generate(16, (_) => _random.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    // And an extension on the end of it, which matters more than it should.
    //
    // A TCL set was given `/s/<token>` and never fetched it at all — no
    // request, no error, a black screen. The same set, the same server and
    // the same file at `/probe.mp4` was fetched at once. It decides whether
    // to try from the name of the file, before it opens a connection. Every
    // player that guesses from the url is doing the same thing.
    final suffix = extensionFor(contentType, url);

    final source = _Source(url, headers ?? const {});
    // Worked out now rather than when the set comes knocking: it costs a
    // few megabytes and a moment, and doing it while the television waits
    // on its first request risks the set giving up first.
    source.layout = await _planFastStart(source);

    _sources[token] = source;
    _lastToken = token;
    _fetched.remove(token);
    debugPrint('[cast] serving on http://$host:${server.port}/s/$token$suffix');
    return 'http://$host:${server.port}/s/$token$suffix';
  }

  /// The file extension to put on the end of a served address.
  ///
  /// From the content type when there is one, and from the source url when
  /// there is not. Defaults to `.mp4`, because a wrong guess is better than
  /// none: a set that cannot play what arrives says so, and a set given no
  /// extension says nothing at all.
  @visibleForTesting
  static String extensionFor(String? contentType, String url) {
    final type = (contentType ?? '').toLowerCase();
    if (type.contains('mpegurl')) return '.m3u8';
    if (type.contains('matroska')) return '.mkv';
    if (type.contains('webm')) return '.webm';
    if (type.contains('mp4')) return '.mp4';

    final path = (Uri.tryParse(url)?.path ?? '').toLowerCase();
    for (final known in const ['.m3u8', '.mkv', '.webm', '.mp4', '.mov', '.avi']) {
      if (path.endsWith(known)) return known;
    }
    return '.mp4';
  }

  /// Rearranges a film so its index comes first, when it needs it.
  ///
  /// Returns null for anything already in the right order, anything that is
  /// not an mp4, and anything the source will not serve ranges of — in
  /// every one of those cases the file is passed through as it is.
  Future<Mp4Layout?> _planFastStart(_Source source) async {
    var total = 0;

    Future<Uint8List?> range(int start, int endInclusive) async {
      try {
        final request = await _client.getUrl(Uri.parse(source.url));
        request.followRedirects = true;
        request.maxRedirects = 5;
        source.headers.forEach(request.headers.set);
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$endInclusive');
        final response =
            await request.close().timeout(const Duration(seconds: 20));
        if (response.statusCode >= 400) return null;
        if (total == 0) {
          final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
          if (contentRange != null && contentRange.contains('/')) {
            total = int.tryParse(contentRange.split('/').last) ?? 0;
          }
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
        }
        return Uint8List.fromList(bytes);
      } catch (e) {
        debugPrint('[cast] range read: $e');
        return null;
      }
    }

    try {
      final probe = await range(0, 1023);
      if (probe == null || total <= 0) return null;
      final layout = await Mp4FastStart.plan(fetch: range, totalSize: total);
      if (layout != null) {
        debugPrint('[cast] index moved to the front '
            '(${layout.header.length} bytes ahead of ${layout.dataLength})');
      }
      return layout;
    } catch (e) {
      debugPrint('[cast] faststart: $e');
      return null;
    }
  }

  String? _lastToken;
  final Set<String> _fetched = <String>{};

  /// Whether the television has actually come and asked for what it was
  /// last given.
  ///
  /// A set that never turns up here is a set that could not reach the
  /// phone — a different fault entirely from one that fetched the film and
  /// could not play it, and the only way to tell them apart from this side.
  bool get wasFetched {
    final token = _lastToken;
    return token != null && _fetched.contains(token);
  }

  /// Forgets everything published so far.
  ///
  /// Called when casting stops: an address that outlives the film it was for
  /// is an open door onto a signed url.
  void clear() => _sources.clear();

  Future<HttpServer?> _ensureStarted() async {
    final existing = _server;
    if (existing != null) return existing;
    try {
      final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      server.listen(_handle, onError: (Object e) => debugPrint('[cast] serve: $e'));
      _server = server;
      return server;
    } catch (e) {
      debugPrint('[cast] could not start the local server: $e');
      return null;
    }
  }

  /// The phone's address on the wifi it shares with the television.
  ///
  /// Picking the first private address is not good enough on a phone. A
  /// mobile data interface usually carries a carrier address in 10.x, which
  /// is private as well — so whichever interface the system lists first
  /// decides what the set is told, and an address on the cellular network
  /// is one the television can never reach. It connects to nothing and
  /// shows black.
  ///
  /// So the wifi interface is asked for by name, then the ranges a home
  /// router actually hands out, and 10.x only if there is nothing else.
  static Future<String?> _lanAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      return pickLanAddress({
        for (final i in interfaces) i.name: [for (final a in i.addresses) a.address],
      });
    } catch (e) {
      debugPrint('[cast] interfaces: $e');
      return null;
    }
  }

  /// Chooses which of the phone's addresses to hand the television.
  ///
  /// Exposed for testing because getting this wrong is invisible until a
  /// television somewhere shows a black screen.
  @visibleForTesting
  static String? pickLanAddress(Map<String, List<String>> interfaces) {
    String? homeRange;
    String? anyPrivate;
    String? anything;

    for (final entry in interfaces.entries) {
      final wifi = _looksLikeWifi(entry.key);
      for (final address in entry.value) {
        anything ??= address;
        if (!_isPrivate(address)) continue;
        anyPrivate ??= address;
        // wlan0 named outright beats any guess made from the number.
        if (wifi) return address;
        homeRange ??= _isHomeRange(address) ? address : null;
      }
    }
    return homeRange ?? anyPrivate ?? anything;
  }

  static bool _looksLikeWifi(String name) {
    final n = name.toLowerCase();
    // wlan0 on Android, en0 on iOS, wl* on desktop linux.
    return n.startsWith('wlan') || n.startsWith('wl') || n.startsWith('en');
  }

  /// The ranges a home router hands out. Carrier networks use 10.x, so it
  /// is deliberately not one of them.
  static bool _isHomeRange(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    if (a == null || b == null) return false;
    if (a == 192 && b == 168) return true;
    return a == 172 && b >= 16 && b <= 31;
  }

  @visibleForTesting
  static bool isPrivateAddress(String ip) => _isPrivate(ip);

  static bool _isPrivate(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    if (a == null || b == null) return false;
    if (a == 10) return true;
    if (a == 192 && b == 168) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    return false;
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.pathSegments;
    // The extension is for the set's benefit, not ours; the token is what
    // identifies the stream.
    final token = path.length == 2 && path.first == 's'
        ? path[1].split('.').first
        : null;
    final source = token == null ? null : _sources[token];

    if (source == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    _fetched.add(token!);
    debugPrint('[cast] the television asked for '
        '${request.method} ${request.uri.path} '
        'range=${request.headers.value(HttpHeaders.rangeHeader) ?? "-"}');

    try {
      await _relay(request, source);
    } catch (e) {
      debugPrint('[cast] relay: $e');
      try {
        request.response.statusCode = HttpStatus.badGateway;
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _relay(HttpRequest request, _Source source) async {
    final layout = source.layout;
    if (layout != null) return _relayRearranged(request, source, layout);

    // A television almost always asks what it is about to fetch before
    // fetching it, and some refuse to play at all if that first answer is
    // unhelpful.
    final head = request.method == 'HEAD';

    final upstream = await _client.openUrl(
      head ? 'HEAD' : 'GET',
      Uri.parse(source.url),
    );
    upstream.followRedirects = true;
    upstream.maxRedirects = 5;
    source.headers.forEach(upstream.headers.set);

    // Seeking on the set is a Range request; it has to reach the CDN or the
    // set gets the whole film back and gives up.
    final range = request.headers.value(HttpHeaders.rangeHeader);
    if (range != null) upstream.headers.set(HttpHeaders.rangeHeader, range);

    final response = await upstream.close().timeout(const Duration(seconds: 20));

    final out = request.response;
    out.statusCode = response.statusCode;
    for (final name in const [
      HttpHeaders.contentTypeHeader,
      HttpHeaders.contentLengthHeader,
      HttpHeaders.contentRangeHeader,
      HttpHeaders.acceptRangesHeader,
    ]) {
      final value = response.headers.value(name);
      if (value != null) out.headers.set(name, value);
    }
    // Said plainly even when the origin forgot to: without it some sets will
    // not offer a scrubber at all.
    if (response.headers.value(HttpHeaders.acceptRangesHeader) == null) {
      out.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    }

    if (head) {
      await out.close();
      return;
    }

    // Piped, not collected: a film would not fit in memory and does not
    // need to.
    await response.pipe(out);
  }

  /// Serves the film as `ftyp | moov | mdat`, which is not how it is stored.
  ///
  /// The first few megabytes — the header — are held in memory and sent
  /// from there; everything after them is the original file from a byte
  /// offset, streamed through untouched. A range that straddles the two is
  /// served from both in turn, which is what a set does when it seeks.
  Future<void> _relayRearranged(
    HttpRequest request, _Source source, Mp4Layout layout) async {
    final total = layout.length;
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);

    var from = 0;
    var to = total - 1;
    if (rangeHeader != null) {
      final match = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(rangeHeader);
      if (match != null) {
        final startText = match.group(1) ?? '';
        final endText = match.group(2) ?? '';
        if (startText.isEmpty && endText.isNotEmpty) {
          // A suffix range: the last n bytes. Players use it to find an
          // index at the end — which is no longer where it is, but the
          // request still has to be answered correctly.
          from = (total - int.parse(endText)).clamp(0, total - 1);
        } else {
          from = int.tryParse(startText) ?? 0;
          if (endText.isNotEmpty) to = int.tryParse(endText) ?? to;
        }
      }
    }
    if (from > to || from >= total) {
      request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
      await request.response.close();
      return;
    }
    to = to.clamp(from, total - 1);
    final length = to - from + 1;

    final out = request.response;
    out.headers.set(HttpHeaders.contentTypeHeader, 'video/mp4');
    out.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    out.headers.contentLength = length;
    if (rangeHeader != null) {
      out.statusCode = HttpStatus.partialContent;
      out.headers.set(HttpHeaders.contentRangeHeader, 'bytes $from-$to/$total');
    } else {
      out.statusCode = HttpStatus.ok;
    }

    if (request.method == 'HEAD') {
      await out.close();
      return;
    }

    // The part that falls inside the rewritten header.
    final headerLength = layout.header.length;
    if (from < headerLength) {
      final until = (to + 1).clamp(0, headerLength);
      out.add(Uint8List.sublistView(layout.header, from, until));
    }

    // And the part that comes from the original file.
    if (to >= headerLength) {
      final dataFrom = (from - headerLength).clamp(0, layout.dataLength);
      final dataTo = (to - headerLength).clamp(0, layout.dataLength - 1);
      final sourceFrom = layout.sourceDataStart + dataFrom;
      final sourceTo = layout.sourceDataStart + dataTo;

      final upstream = await _client.getUrl(Uri.parse(source.url));
      upstream.followRedirects = true;
      upstream.maxRedirects = 5;
      source.headers.forEach(upstream.headers.set);
      upstream.headers.set(HttpHeaders.rangeHeader, 'bytes=$sourceFrom-$sourceTo');

      final response = await upstream.close().timeout(const Duration(seconds: 20));
      await response.pipe(out);
      return;
    }

    await out.close();
  }

  Future<void> stop() async {
    _sources.clear();
    final server = _server;
    _server = null;
    if (server != null) {
      try {
        await server.close(force: true);
      } catch (_) {}
    }
    _client.close(force: true);
  }

  /// The port the server settled on, for tests.
  @visibleForTesting
  int? get port => _server?.port;
}

class _Source {
  _Source(this.url, this.headers);

  final String url;
  final Map<String, String> headers;

  /// Set when the file has to be served in a different order than it is
  /// stored in; null when it can simply be passed through.
  Mp4Layout? layout;
}
