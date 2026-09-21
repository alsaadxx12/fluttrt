import 'dart:async';
import 'dart:io';
import 'dart:math';

/// A loopback relay between the reels player and YouTube's adaptive streams.
///
/// YouTube answers 403 to any request for a video-only or audio-only stream
/// that does not carry a *bounded* `Range` header (an open `bytes=0-`, or no
/// range at all, is refused; so is a range past the end of the file), and
/// mpv's HTTP client — like every ordinary player — asks for `bytes=N-`.
/// So the player is handed a `http://127.0.0.1:<port>/<token>` URL instead;
/// this server fetches the real stream in [chunkSize] slices, each with a
/// bounded range, and streams the bytes on, honouring the player's own
/// range (a seek, the loop back to the start) so nothing else changes.
///
/// A stream whose host checks the client's identity (the iOS app's streams
/// want the app's User-Agent) is registered with the headers its byte
/// requests must carry; the relay sends them on every slice.
///
/// One server per process, started on first use on an ephemeral port; a
/// stream registered twice gets the same local URL.
class ReelStreamProxy {
  ReelStreamProxy._();
  static final ReelStreamProxy instance = ReelStreamProxy._();

  /// How much is asked of YouTube per request. Well under the 10 MB that is
  /// known to be accepted, so a slice is never refused for its size.
  static const int chunkSize = 4 << 20;

  static const Duration _upstreamTimeout = Duration(seconds: 20);

  /// Where the relay reports what it asked of YouTube and what came back;
  /// null (the default) reports nothing. For the probes.
  static void Function(String line)? log;

  final HttpClient _client = HttpClient()..idleTimeout = const Duration(seconds: 30);
  final Random _random = Random.secure();

  HttpServer? _server;
  Future<HttpServer>? _starting;
  final Map<String, Uri> _routes = {};
  final Map<Uri, String> _tokens = {};

  /// Each stream's length once a reply announced it, so later slices are
  /// bounded right on the first ask.
  final Map<Uri, int> _totals = {};

  /// The headers each stream's byte requests carry, for the streams that
  /// need any.
  final Map<Uri, Map<String, String>> _headers = {};

  /// The local URL that serves [upstream].
  ///
  /// [headers] are sent upstream on every slice (a client's User-Agent);
  /// given, they replace whatever the stream was registered with (empty
  /// clears them), and left out they keep it — so the page can register a
  /// stream the resolver already registered with its headers.
  Future<Uri> register(Uri upstream, {Map<String, String>? headers}) async {
    final server = await _ensureServer();
    final token = _tokens.putIfAbsent(upstream, () {
      final t = _newToken();
      _routes[t] = upstream;
      return t;
    });
    if (headers != null) {
      if (headers.isEmpty) {
        _headers.remove(upstream);
      } else {
        _headers[upstream] = Map.unmodifiable(headers);
      }
    }
    return Uri(scheme: 'http', host: server.address.address, port: server.port, path: '/$token');
  }

  /// The upstream a local URL stands for, or null. For tests and logging.
  Uri? upstreamOf(Uri local) => _routes[local.pathSegments.isEmpty ? '' : local.pathSegments.first];

  /// The headers the relay sends upstream for a local URL; empty when none
  /// were registered or the URL is unknown. For tests.
  Map<String, String> headersOf(Uri local) {
    final upstream = upstreamOf(local);
    return upstream == null ? const {} : _headers[upstream] ?? const {};
  }

  /// Stops the server and forgets every stream. Only for tests; the app
  /// keeps it for its lifetime.
  Future<void> close() async {
    final s = _server;
    _server = null;
    _starting = null;
    _routes.clear();
    _tokens.clear();
    _totals.clear();
    _headers.clear();
    await s?.close(force: true);
  }

  Future<HttpServer> _ensureServer() {
    final running = _server;
    if (running != null) return Future.value(running);
    return _starting ??= HttpServer.bind(InternetAddress.loopbackIPv4, 0).then((server) {
      _server = server;
      server.listen(_handle, onError: (_) {});
      return server;
    });
  }

  String _newToken() {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return String.fromCharCodes(List.generate(24, (_) => alphabet.codeUnitAt(_random.nextInt(alphabet.length))));
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      final token = req.uri.pathSegments.isEmpty ? '' : req.uri.pathSegments.first;
      final upstream = _routes[token];
      if (upstream == null || (req.method != 'GET' && req.method != 'HEAD')) {
        res.statusCode = upstream == null ? HttpStatus.notFound : HttpStatus.methodNotAllowed;
        await res.close();
        return;
      }
      final asked = parseRange(req.headers.value(HttpHeaders.rangeHeader));
      final start = asked?.$1 ?? 0;
      final known = _knownTotal(upstream);
      if (known != null && start >= known) {
        res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$known');
        await res.close();
        return;
      }

      // The first slice tells the file's length (Content-Range's total) and
      // its type; its bytes are streamed like every later one.
      final first = await _fetch(upstream, start, _sliceEnd(start, asked?.$2, upstream));
      if (first == null) {
        res.statusCode = HttpStatus.badGateway;
        await res.close();
        return;
      }
      final total = first.total;
      final last = min(asked?.$2 ?? (total - 1), total - 1);
      if (start >= total || last < start) {
        await first.response.drain<void>();
        res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
        await res.close();
        return;
      }
      res.statusCode = asked == null ? HttpStatus.ok : HttpStatus.partialContent;
      res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      res.headers.contentType = first.contentType;
      res.headers.contentLength = last - start + 1;
      if (asked != null) res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$last/$total');
      if (req.method == 'HEAD') {
        await first.response.drain<void>();
        await res.close();
        return;
      }

      var pos = start;
      var slice = first;
      while (true) {
        await res.addStream(_upTo(slice.response, last - pos + 1));
        pos = min(slice.end, last) + 1;
        if (pos > last) break;
        final next = await _fetch(upstream, pos, _sliceEnd(pos, last, upstream));
        if (next == null) {
          log?.call('$token: gave up at $pos of ${last + 1}');
          break;
        }
        slice = next;
      }
      await res.close();
    } catch (e) {
      // The player went away (a swipe, a teardown) or YouTube did: nothing
      // to answer any more.
      log?.call('${req.uri.path}: $e');
      try {
        await res.close();
      } catch (_) {}
    }
  }

  /// The last byte of the slice starting at [start]: a whole chunk, cut to
  /// [wanted] (the player's own end, if any) and to the file's length when
  /// it is known — from an earlier reply, or the `clen` YouTube puts in the
  /// URL — so no slice runs past the end.
  int _sliceEnd(int start, int? wanted, Uri upstream) {
    var end = start + chunkSize - 1;
    if (wanted != null) end = min(end, wanted);
    final total = _knownTotal(upstream);
    if (total != null) end = min(end, total - 1);
    return max(end, start);
  }

  /// The stream's length when known: from an earlier reply, else from the
  /// `clen` YouTube puts in the URL. Null otherwise.
  int? _knownTotal(Uri upstream) {
    final total = _totals[upstream] ?? int.tryParse(upstream.queryParameters['clen'] ?? '');
    return total != null && total > 0 ? total : null;
  }

  /// One bounded slice from YouTube; null when it failed. A refused ask is
  /// tried once more: for a single byte when the file's length was not yet
  /// known (the ask may have run past the end, and one byte tells the
  /// length), else the same slice again, for a passing failure. A slice
  /// YouTube refuses outright is given up on — the relay never crawls a
  /// byte at a time.
  Future<_Slice?> _fetch(Uri upstream, int start, int end) async {
    final retry = _knownTotal(upstream) == null ? start : end;
    for (final last in [end, retry]) {
      try {
        final req = await _client.getUrl(upstream).timeout(_upstreamTimeout);
        _headers[upstream]?.forEach(req.headers.set);
        req.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$last');
        final res = await req.close().timeout(_upstreamTimeout);
        final range = parseContentRange(res.headers.value(HttpHeaders.contentRangeHeader));
        log?.call('${upstream.queryParameters['itag'] ?? upstream.path}: bytes=$start-$last -> ${res.statusCode} '
            '${res.headers.value(HttpHeaders.contentRangeHeader) ?? ''} len=${res.contentLength}');
        if (res.statusCode == HttpStatus.partialContent && range != null) {
          _totals[upstream] = range.$3;
          return _Slice(res, range.$2, range.$3, res.headers.contentType ?? ContentType.binary);
        }
        // Whole file in one go (a server ignoring the range): still usable.
        if (res.statusCode == HttpStatus.ok && start == 0 && res.contentLength > 0) {
          _totals[upstream] = res.contentLength;
          return _Slice(res, res.contentLength - 1, res.contentLength, res.headers.contentType ?? ContentType.binary);
        }
        await res.drain<void>();
      } catch (e) {
        log?.call('${upstream.queryParameters['itag'] ?? upstream.path}: bytes=$start-$last threw $e');
      }
    }
    return null;
  }
}

/// The first [count] bytes of [source]; the rest is left unread.
Stream<List<int>> _upTo(Stream<List<int>> source, int count) async* {
  var left = count;
  if (left <= 0) return;
  await for (final chunk in source) {
    if (chunk.length < left) {
      left -= chunk.length;
      yield chunk;
    } else {
      yield chunk.length == left ? chunk : chunk.sublist(0, left);
      return;
    }
  }
}

/// A slice of the file as YouTube sent it: the body, its last byte's
/// offset, the file's total length and its type.
class _Slice {
  const _Slice(this.response, this.end, this.total, this.contentType);

  final HttpClientResponse response;
  final int end;
  final int total;
  final ContentType contentType;
}

/// `bytes=start-end` or `bytes=start-` as (start, end?); null when there is
/// no usable range (absent, another unit, a suffix range).
(int, int?)? parseRange(String? header) {
  if (header == null) return null;
  final m = RegExp(r'^\s*bytes\s*=\s*(\d+)\s*-\s*(\d*)\s*$').firstMatch(header);
  if (m == null) return null;
  final start = int.parse(m.group(1)!);
  final end = m.group(2)!.isEmpty ? null : int.parse(m.group(2)!);
  if (end != null && end < start) return null;
  return (start, end);
}

/// `bytes start-end/total` as (start, end, total); null when malformed.
(int, int, int)? parseContentRange(String? header) {
  if (header == null) return null;
  final m = RegExp(r'^\s*bytes\s+(\d+)-(\d+)/(\d+)\s*$').firstMatch(header);
  if (m == null) return null;
  return (int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
}
