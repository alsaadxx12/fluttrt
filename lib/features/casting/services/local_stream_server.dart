import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'mkv_remux.dart';
import 'mp4_faststart.dart';
import 'mp4_tracks.dart';
import 'source_cache.dart';

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
///
/// What the phone fetches it keeps, on storage, in a [SourceCache]: a seek
/// back is answered from the file, a film watched again needs no internet,
/// and while the set plays the phone fetches ahead of it on its own.
class LocalStreamServer {
  LocalStreamServer({Directory? cacheDir}) : _cacheDir = cacheDir;

  HttpServer? _server;

  Directory? _cacheDir;
  bool _pruned = false;

  /// Where films are kept between viewings.
  ///
  /// The app's temporary directory, which the system may clear when space
  /// is short — the right place for something that is only ever a copy.
  /// A test passes a directory of its own.
  Future<Directory?> _cacheDirectory() async {
    var dir = _cacheDir;
    if (dir == null) {
      try {
        final base = await getTemporaryDirectory();
        dir = Directory('${base.path}${Platform.pathSeparator}cineball_cast_cache');
      } catch (_) {
        // Off the phone — a test, a desktop — there is no plugin to ask.
        dir = Directory(
            '${Directory.systemTemp.path}${Platform.pathSeparator}cineball_cast_cache');
      }
      _cacheDir = dir;
    }
    if (!_pruned) {
      _pruned = true;
      await SourceCache.prune(dir);
    }
    return dir;
  }

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
  ///
  /// [subtitle] is SubRip text. When it is given and the source is an mp4
  /// whose codecs Matroska can carry, the set is served an `.mkv` with the
  /// subtitle as a track of its own — the one form of subtitle a television's
  /// DLNA player has been seen to show. The returned address ends in `.mkv`
  /// when that happened and `.mp4` when it did not.
  ///
  /// [subtitleFuture] is the same thing still on its way: it is waited for
  /// only once the film's index has been read, so the seconds the subtitle
  /// takes to download are spent alongside the index rather than before it.
  Future<String?> publish(
    String url, {
    Map<String, String>? headers,
    String? contentType,
    String? subtitle,
    Future<String?>? subtitleFuture,
    MkvFill fill = MkvFill.keep,
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
    var suffix = extensionFor(contentType, url);

    final source = _Source(url, headers ?? const {});
    // What the set is told the stream is, whatever the CDN says about it.
    // A CDN that answers `application/octet-stream` - some do - is a set
    // (a Samsung, for one) that refuses the film before reading a byte.
    source.mime = contentType ??
        switch (suffix) {
          '.m3u8' => 'application/x-mpegURL',
          '.mkv' => 'video/x-matroska',
          '.webm' => 'video/webm',
          _ => 'video/mp4',
        };
    // Worked out now rather than when the set comes knocking: it costs a
    // few megabytes and a moment, and doing it while the television waits
    // on its first request risks the set giving up first.
    if (suffix == '.mp4' || suffix == '.mov') {
      await _plan(source, subtitle, subtitleFuture, fill);
      if (source.mkv != null) suffix = '.mkv';
    }

    _sources[token] = source;
    _lastToken = token;
    _fetched.remove(token);
    debugPrint('[cast] serving on http://$host:${server.port}/s/$token$suffix');
    return 'http://$host:${server.port}/s/$token$suffix';
  }

  /// How long the last published stream is, in bytes - or null when the
  /// source never said.
  ///
  /// Goes into the `<res size="…">` the set is handed with the address: a
  /// Samsung reads it before it reads anything else, and some LG sets show
  /// no scrubber without it.
  int? get lastLength {
    final source = _lastToken == null ? null : _sources[_lastToken];
    if (source == null) return null;
    return source.mkv?.length ?? source.layout?.length ??
        (source.total > 0 ? source.total : null);
  }

  /// True when the whole of the last published film is on the phone.
  bool get isComplete {
    final source = _lastToken == null ? null : _sources[_lastToken];
    return source?.cache?.isComplete ?? false;
  }

  /// The DLNA features every stream here is served with.
  ///
  /// OP=01: byte ranges, which is what seeking is. CI=0: not transcoded.
  /// The flags say it can be played as it arrives and read in any order.
  /// Written once, because the same string has to appear in the
  /// `protocolInfo` the set is given and in the `contentFeatures.dlna.org`
  /// header it reads back when it fetches - and a set that compares the two
  /// (Samsung does) refuses the film if they differ.
  static const String dlnaFeatures =
      'DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000';

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

  /// Decides how the film is served: remuxed with its subtitle, rearranged
  /// so its index comes first, or passed through as it is.
  ///
  /// Anything that is not an mp4, or that the source will not serve ranges
  /// of, is passed through.
  Future<void> _plan(
    _Source source,
    String? subtitle,
    Future<String?>? subtitleFuture,
    MkvFill fill,
  ) async {
    var total = 0;

    // Read straight from the CDN, exactly as much as asked, and not kept.
    // The index is megabytes at the far end of the file and the set never
    // asks for those bytes - the mkv is built from what they say, not
    // from them - so keeping them would round every read up to half a
    // megabyte and store what nobody will read. On a slow link that was
    // seconds before the set was even told the address.
    Future<Uint8List?> range(int start, int endInclusive) async {
      // Three goes, not one: a link that drops a request now and then is
      // the ordinary case on a slow connection, and one dropped read here
      // used to mean a film served as it is, index at the end, or without
      // its subtitle - with nothing to say why.
      for (var attempt = 1; attempt <= _attempts; attempt++) {
        try {
          final response = await _openUpstream(source, range: 'bytes=$start-$endInclusive');
          if (response.statusCode >= 400) return null;
          if (total == 0) {
            final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
            if (contentRange != null && contentRange.contains('/')) {
              total = int.tryParse(contentRange.split('/').last) ?? 0;
            }
          }
          final builder = BytesBuilder(copy: false);
          await for (final chunk in response) {
            builder.add(chunk);
          }
          return builder.takeBytes();
        } catch (e) {
          debugPrint('[cast] range read ($attempt/$_attempts): $e');
          if (attempt == _attempts) return null;
          await Future<void>.delayed(_pause * attempt);
        }
      }
      return null;
    }

    try {
      final probe = await range(0, 1023);
      if (probe == null || total <= 0) return;
      // Known from here on, so the set's first question - how long is it -
      // is answered from the phone at once rather than from the CDN in its
      // own time.
      source.total = total;
      await _openCache(source);
      // The first half megabyte is what the set asks for first, whatever
      // else it does; fetched now, alongside the index, it is there the
      // moment the set comes for it.
      _warmFront(source);
      final file = await Mp4FastStart.read(fetch: range, totalSize: total);
      if (file == null) return;

      final text = subtitle ?? (subtitleFuture == null ? null : await subtitleFuture);
      final cues = text == null ? const <SrtCue>[] : SrtCue.parse(text);
      if (cues.isNotEmpty) {
        final movie = Mp4Movie.parse(file.moov);
        final mkv = movie == null
            ? null
            : MkvRemux.plan(movie: movie, cues: cues, fill: fill);
        if (mkv != null) {
          source.mkv = mkv;
          debugPrint('[cast] remuxed as mkv: ${mkv.clusterCount} clusters, '
              '${mkv.subtitleCount} subtitle lines, ${mkv.length} bytes');
          return;
        }
        debugPrint('[cast] could not remux; serving the mp4 without its subtitle');
      }

      if (file.indexFirst) return;
      final layout = Mp4FastStart.planFor(file);
      if (layout != null) {
        debugPrint('[cast] index moved to the front '
            '(${layout.header.length} bytes ahead of ${layout.dataLength})');
      }
      source.layout = layout;
    } catch (e) {
      debugPrint('[cast] planning: $e');
    }
  }

  /// How many times a request to the CDN is tried before it is given up on.
  static const int _attempts = 3;

  /// The wait before a second try; doubled and tripled for the ones after.
  static const Duration _pause = Duration(milliseconds: 700);

  /// Starts the first chunk of [source] on its way into the cache, and
  /// does not wait for it.
  void _warmFront(_Source source) {
    final cache = source.cache;
    if (cache == null || source.total <= 0) return;
    unawaited(_readSource(source, 0, min(SourceCache.chunk, source.total) - 1, planning: true)
        .then<void>((_) {}, onError: (Object e) => debugPrint('[cast] warming the front: $e')));
  }

  /// Gives [source] a file on the phone to fill in, when there is
  /// somewhere to put it.
  Future<void> _openCache(_Source source) async {
    if (source.cache != null || source.total <= 0) return;
    final dir = await _cacheDirectory();
    if (dir == null) return;
    source.cache = await SourceCache.open(dir, source.url, source.total);
  }

  /// `from`..`to` of the source: from the phone's copy where it has one,
  /// from the CDN where it does not — and kept, either way.
  ///
  Future<Uint8List> _readSource(
    _Source source,
    int from,
    int to, {
    bool Function()? abandoned,
    bool planning = false,
  }) async {
    final cache = source.cache;
    bool never() => false;
    if (cache == null) {
      return _fetchRange(source, from, to, abandoned ?? never);
    }
    return cache.read(
      from,
      to,
      (a, b) => _fetchRange(source, a, b, abandoned ?? never),
      abandoned: abandoned,
      planning: planning,
    );
  }

  /// Starts fetching the rest of [source] ahead of the set.
  ///
  /// Only once the set has actually come for the film: a film the set
  /// never fetches - the wrong network, a refused address - is not one to
  /// spend a metered connection on.
  void _prefetch(_Source source) {
    final cache = source.cache;
    if (cache == null) return;
    cache.prefetch((a, b) => _fetchRange(source, a, b, () => false));
  }

  /// Opens a request to the source, following its redirect, trying again
  /// when the connection cannot be made or the CDN answers with a server
  /// error.
  ///
  /// The redirect the catalogue answers with is remembered, so every window
  /// after the first is one round trip rather than two - which on a slow
  /// link is the difference between a seek the set waits for and one it
  /// gives up on. A 4xx is not retried: the CDN has made up its mind.
  Future<HttpClientResponse> _openUpstream(
    _Source source, {
    String method = 'GET',
    String? range,
    bool Function()? abandoned,
  }) async {
    Object? last;
    for (var attempt = 1; attempt <= _attempts; attempt++) {
      if (abandoned?.call() ?? false) throw const _Abandoned();
      try {
        final request = await _client.openUrl(
          method,
          source.resolved ?? Uri.parse(source.url),
        );
        request.followRedirects = true;
        request.maxRedirects = 5;
        source.headers.forEach(request.headers.set);
        if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
        final response = await request.close().timeout(const Duration(seconds: 20));
        if (response.redirects.isNotEmpty) {
          source.resolved = response.redirects.last.location;
        }
        if (response.statusCode >= 500 && attempt < _attempts) {
          await response.drain<void>().catchError((Object _) {});
          throw HttpException('cdn said ${response.statusCode}');
        }
        return response;
      } on _Abandoned {
        rethrow;
      } catch (e) {
        last = e;
        // A remembered CDN node that has stopped answering is forgotten,
        // and the next try starts from the catalogue again.
        source.resolved = null;
        debugPrint('[cast] upstream $method ($attempt/$_attempts): $e');
        if (attempt < _attempts) await Future<void>.delayed(_pause * attempt);
      }
    }
    throw last is Exception ? last : HttpException('$last');
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
  void clear() {
    for (final source in _sources.values) {
      unawaited(source.cache?.close());
    }
    _sources.clear();
  }

  Future<HttpServer?> _ensureStarted() async {
    final existing = _server;
    if (existing != null) return existing;
    try {
      final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      server.listen(
        _handle,
        onError: (Object e) => debugPrint('[cast] serve: $e'),
        // One connection reset by the set is one connection; the server
        // stays up for the next request, which is usually a second later.
        cancelOnError: false,
      );
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
      await _replyEmpty(request, HttpStatus.notFound);
      return;
    }

    _fetched.add(token!);
    debugPrint('[cast] the television asked for '
        '${request.method} ${request.uri.path} '
        'range=${request.headers.value(HttpHeaders.rangeHeader) ?? "-"}');
    if (request.method != 'HEAD') _prefetch(source);

    try {
      await _relay(request, source);
    } catch (e) {
      debugPrint('[cast] relay: $e');
      try {
        await _replyEmpty(request, HttpStatus.badGateway);
      } catch (_) {}
    }
  }

  // ------------------------------------------------------------- the wire
  //
  // Every reply here is written onto the socket by hand, status line and
  // headers included, instead of through HttpResponse. HttpResponse spells
  // every header name in lower case, and a TCL set, handed
  // `content-length: ...`, read nothing and sat in TRANSITIONING for ever;
  // handed `Content-Length: ...` and otherwise the same bytes, it played
  // within four seconds. Measured, not guessed: the two replies were served
  // from the same PC a minute apart. Its http client matches names by
  // exact spelling, and nothing in HttpResponse lets that spelling through,
  // so the reply is composed here where it can be.

  static String _reason(int status) => switch (status) {
        200 => 'OK',
        206 => 'Partial Content',
        404 => 'Not Found',
        416 => 'Requested Range Not Satisfiable',
        502 => 'Bad Gateway',
        _ => 'OK',
      };

  /// Takes the socket over and writes the status line and [headers].
  ///
  /// [headers] is written in the order and spelling given. `Connection:
  /// close` is added, because from here the connection is this method's
  /// to end, and a set opens a fresh one for every request anyway.
  static Future<Socket> _open(
    HttpRequest request,
    int status,
    Map<String, String> headers,
  ) async {
    final socket = await request.response.detachSocket(writeHeaders: false);
    // A detached socket reports a write that failed after the set hung up
    // through its `done` future as well as through the write itself. The
    // write is caught where it happens; this catches the second report,
    // which otherwise surfaces as an unhandled error in the server's zone
    // and, in a test, fails the run.
    unawaited(socket.done.then<void>((_) {}, onError: (Object e) {
      debugPrint('[cast] socket closed with $e');
    }));
    final head = StringBuffer('HTTP/1.1 $status ${_reason(status)}\r\n');
    headers.forEach((name, value) => head.write('$name: $value\r\n'));
    // Who is serving and when. Neither is read by a TCL set; both are
    // looked for by a Samsung, which wants a server that says it speaks
    // DLNA before it takes a film from it.
    head.write('Server: Android/1.0 UPnP/1.0 DLNADOC/1.50 CineBall/1.0\r\n');
    head.write('Date: ${HttpDate.format(DateTime.now().toUtc())}\r\n');
    head.write('Connection: close\r\n\r\n');
    socket.add(ascii.encode(head.toString()));
    await socket.flush();
    return socket;
  }

  /// The headers every reply carrying the film starts with.
  ///
  /// `transferMode.dlna.org` and `contentFeatures.dlna.org` are what a DLNA
  /// player asks for (it sends `getcontentFeatures.dlna.org: 1`), and a
  /// Samsung or LG set given a reply without them treats the file as one
  /// it was never told about and refuses it - the "cannot play this
  /// content" on the screen with the phone none the wiser.
  static Map<String, String> _mediaHeaders(String mime) => {
        'Content-Type': mime,
        'Accept-Ranges': 'bytes',
        'transferMode.dlna.org': 'Streaming',
        'contentFeatures.dlna.org': dlnaFeatures,
      };

  static Future<void> _replyEmpty(HttpRequest request, int status) async {
    final socket = await _open(request, status, {'Content-Length': '0'});
    await socket.close();
  }

  /// Streams [body] to [socket], counting, and says how it went.
  static Future<String> _pump(
    Stream<List<int>> body,
    Socket socket,
    void Function(int) count,
  ) async {
    try {
      await for (final piece in body) {
        socket.add(piece);
        count(piece.length);
      }
      await socket.flush();
      await socket.close();
      return 'done';
    } catch (e) {
      // A set closes a connection it is done with, abruptly, several times
      // a film - not a fault, but worth a word when nothing plays.
      socket.destroy();
      return e.runtimeType.toString();
    }
  }

  Future<void> _relay(HttpRequest request, _Source source) async {
    final mkv = source.mkv;
    if (mkv != null) return _relayMkv(request, source, mkv);
    final layout = source.layout;
    if (layout != null) return _relayRearranged(request, source, layout);

    // A television almost always asks what it is about to fetch before
    // fetching it, and some refuse to play at all if that first answer is
    // unhelpful.
    final head = request.method == 'HEAD';
    final range = request.headers.value(HttpHeaders.rangeHeader);
    final mime = source.mime ?? 'video/mp4';

    // When the length is already known the question is answered here, now.
    // Going to the CDN for it is a redirect and a TLS handshake away, and a
    // Samsung gives a server about three seconds to say how long the film
    // is before it decides the film is not there.
    if (head && source.total > 0) {
      final bounds = _bounds(range, source.total);
      if (bounds == null) {
        final socket = await _open(request, HttpStatus.requestedRangeNotSatisfiable, {
          'Content-Range': 'bytes */${source.total}',
          'Content-Length': '0',
        });
        await socket.close();
        return;
      }
      final (from, to) = bounds;
      final socket = await _open(
        request,
        range != null ? HttpStatus.partialContent : HttpStatus.ok,
        {
          ..._mediaHeaders(mime),
          'Content-Length': '${to - from + 1}',
          if (range != null) 'Content-Range': 'bytes $from-$to/${source.total}',
        },
      );
      await socket.close();
      return;
    }

    // A film of known length is served in windows, through the phone's
    // copy of it, like the rearranged and remuxed ones: what the set has
    // already had is not fetched twice, and what it is about to ask for is
    // usually here before it asks.
    if (!head && source.total > 0) {
      final bounds = _bounds(range, source.total);
      if (bounds == null) {
        final socket = await _open(request, HttpStatus.requestedRangeNotSatisfiable, {
          'Content-Range': 'bytes */${source.total}',
          'Content-Length': '0',
        });
        await socket.close();
        return;
      }
      final (from, to) = bounds;
      final status = range != null ? HttpStatus.partialContent : HttpStatus.ok;
      final socket = await _open(request, status, {
        ..._mediaHeaders(mime),
        'Content-Length': '${to - from + 1}',
        if (range != null) 'Content-Range': 'bytes $from-$to/${source.total}',
      });
      await _sendWindows(
        socket,
        from,
        to,
        (a, b, abandoned) => _readSource(source, a, b, abandoned: abandoned),
        log: 'range=${range ?? "-"} status=$status',
      );
      return;
    }

    // Seeking on the set is a Range request; it has to reach the CDN or the
    // set gets the whole film back and gives up.
    final response = await _openUpstream(
      source,
      method: head ? 'HEAD' : 'GET',
      range: range,
    );

    final headers = _mediaHeaders(mime);
    void carry(String wire, String name) {
      final value = response.headers.value(name);
      if (value != null) headers[wire] = value;
    }
    carry('Content-Length', HttpHeaders.contentLengthHeader);
    carry('Content-Range', HttpHeaders.contentRangeHeader);

    final socket = await _open(request, response.statusCode, headers);
    if (head) {
      await socket.close();
      return;
    }

    final started = DateTime.now();
    var sent = 0;
    final outcome = await _pump(response, socket, (n) => sent += n);
    final seconds = DateTime.now().difference(started).inMilliseconds / 1000;
    debugPrint('[cast] served range=${range ?? "-"} status=${response.statusCode} '
        'sent=${(sent / 1e6).toStringAsFixed(2)}MB in ${seconds.toStringAsFixed(1)}s -> $outcome');
  }

  /// Reads a Range header against a file of [total] bytes.
  ///
  /// Returns the inclusive bounds, or null when the range starts past the
  /// end — the one case that is answered with 416 rather than a body.
  static (int, int)? _bounds(String? rangeHeader, int total) {
    var from = 0;
    var to = total - 1;
    if (rangeHeader != null) {
      final match = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(rangeHeader);
      if (match != null) {
        final startText = match.group(1) ?? '';
        final endText = match.group(2) ?? '';
        if (startText.isEmpty && endText.isNotEmpty) {
          // A suffix range: the last n bytes. Players use it to find an
          // index at the end - which is no longer where it is, but the
          // request still has to be answered correctly.
          from = (total - int.parse(endText)).clamp(0, total - 1);
        } else {
          from = int.tryParse(startText) ?? 0;
          if (endText.isNotEmpty) to = int.tryParse(endText) ?? to;
        }
      }
    }
    if (from > to || from >= total) return null;
    return (from, to.clamp(from, total - 1));
  }

  /// How much of a remuxed file is assembled in memory at a time, at most.
  static const int _window = 4 * 1024 * 1024;

  /// The first window of a request is this small, and each one after it
  /// twice the last, up to [_window].
  ///
  /// A set that has just been told to seek opens a connection and waits
  /// for the first byte; nothing reaches it until a whole window has been
  /// fetched from the CDN and put together. Four megabytes over a phone's
  /// link is seconds, and a TCL set gives up on a seek in about that -
  /// "يتعذر العرض" on the screen and the film gone. A quarter of a megabyte
  /// is a moment, and by the time it is played the next window is there.
  static const int _firstWindow = 256 * 1024;

  /// How many assembled windows are kept, per film.
  ///
  /// After a seek the set asks for the same stretch several times over -
  /// once to look, once to check, once from twelve bytes further on - and
  /// each time from a fresh connection. The second and third answers come
  /// from here rather than from the CDN again.
  static const int _remembered = 4;

  /// Two source ranges closer than this are fetched as one.
  static const int _gap = 512 * 1024;

  /// Serves the film inside a Matroska container, assembled as it goes.
  ///
  /// The plan says which bytes come from here and which from the source,
  /// but the source's bytes are interleaved by the encoder in chunks of a
  /// second or so while the container wants them frame by frame — so the
  /// requested stretch is served in windows: the source ranges of one
  /// window are fetched (coalesced, since they nearly abut), the window is
  /// put together in memory, sent, and the next one is already on its way.
  Future<void> _relayMkv(HttpRequest request, _Source source, MkvLayout mkv) async {
    final total = mkv.length;
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    final bounds = _bounds(rangeHeader, total);
    if (bounds == null) {
      final socket = await _open(request, HttpStatus.requestedRangeNotSatisfiable, {
        'Content-Range': 'bytes */$total',
        'Content-Length': '0',
      });
      await socket.close();
      return;
    }
    final (from, to) = bounds;
    final status = rangeHeader != null ? HttpStatus.partialContent : HttpStatus.ok;
    final socket = await _open(request, status, {
      ..._mediaHeaders('video/x-matroska'),
      'Content-Length': '${to - from + 1}',
      if (rangeHeader != null) 'Content-Range': 'bytes $from-$to/$total',
    });
    if (request.method == 'HEAD') {
      await socket.close();
      return;
    }

    await _sendWindows(
      socket,
      from,
      to,
      (a, b, abandoned) => _assemble(source, mkv, a, b, abandoned),
      log: 'range=${rangeHeader ?? "-"} status=$status',
    );
  }

  /// Writes `from`..`to` of a film to [socket] in windows, each fetched
  /// while the one before it is being sent.
  ///
  /// The first window is small and each after it twice the last, up to
  /// [_window]: a set that has just seeked is waiting for the first byte,
  /// and a quarter of a megabyte reaches it in a moment where four would
  /// not. [read] may return fewer bytes than asked for - never none - and
  /// the next window starts after what it returned.
  Future<void> _sendWindows(
    Socket socket,
    int from,
    int to,
    Future<Uint8List> Function(int from, int to, bool Function() abandoned) read, {
    required String log,
  }) async {
    var closed = false;
    unawaited(socket.done.then<void>((_) => closed = true, onError: (Object _) => closed = true));

    final started = DateTime.now();
    var sent = 0;
    var outcome = 'done';
    var at = from;
    var window = _firstWindow;
    Future<Uint8List>? next;
    try {
      next = read(at, min(to, at + window - 1), () => closed);
      while (at <= to) {
        final bytes = await next!;
        next = null;
        at += bytes.length;
        window = min(window * 2, _window);
        if (at <= to) {
          // Fetched while this window is being written.
          next = read(at, min(to, at + window - 1), () => closed);
        }
        if (closed) {
          outcome = 'set hung up';
          break;
        }
        socket.add(bytes);
        if (sent == 0) {
          // The number that decides how long the set shows black: how
          // long its first request waited for its first byte.
          final wait = DateTime.now().difference(started).inMilliseconds;
          debugPrint('[cast] first ${bytes.length ~/ 1024} KB of $log '
              'out after ${wait}ms');
        }
        sent += bytes.length;
        await socket.flush();
      }
      if (!closed) await socket.close();
    } on _Abandoned {
      outcome = 'set hung up';
      socket.destroy();
    } catch (e) {
      outcome = e.runtimeType.toString();
      socket.destroy();
    } finally {
      // A window still on its way when the set hung up, or the server was
      // stopped, has nobody waiting for it; its failure is not news.
      final orphan = next;
      if (orphan != null) {
        unawaited(orphan.then<void>((_) {}, onError: (Object _) {}));
      }
    }
    final seconds = DateTime.now().difference(started).inMilliseconds / 1000;
    debugPrint('[cast] served $log '
        'sent=${(sent / 1e6).toStringAsFixed(2)}MB in ${seconds.toStringAsFixed(1)}s -> $outcome');
  }

  /// Output bytes [from]..[to] of a remuxed file, put together in memory.
  ///
  /// May return fewer bytes than asked for - never none - when the start
  /// of the stretch is still remembered from a moment ago. [abandoned] is
  /// asked between fetches and mid-fetch; once it says so the CDN is left
  /// alone, since nobody is waiting for the answer any more.
  Future<Uint8List> _assemble(
    _Source source,
    MkvLayout mkv,
    int from,
    int to,
    bool Function() abandoned,
  ) async {
    for (final (start, bytes) in source.recent) {
      if (from >= start && from < start + bytes.length) {
        final end = min(to, start + bytes.length - 1);
        return Uint8List.sublistView(bytes, from - start, end - start + 1);
      }
    }

    final assembled = await _assembleFresh(source, mkv, from, to, abandoned);
    source.recent.add((from, assembled));
    if (source.recent.length > _remembered) source.recent.removeAt(0);
    return assembled;
  }

  Future<Uint8List> _assembleFresh(
    _Source source,
    MkvLayout mkv,
    int from,
    int to,
    bool Function() abandoned,
  ) async {
    final pieces = mkv.pieces(from, to).toList();

    // Every source range this window needs, in file order, run together
    // where the space between them is cheaper to read than to skip.
    final wanted = pieces
        .where((p) => p.fromSource)
        .map((p) => (p.sourceOffset, p.sourceOffset + p.length - 1))
        .toList()
      ..sort((a, b) => a.$1.compareTo(b.$1));
    final runs = <(int, int)>[];
    for (final r in wanted) {
      if (runs.isNotEmpty && r.$1 <= runs.last.$2 + _gap) {
        if (r.$2 > runs.last.$2) runs[runs.length - 1] = (runs.last.$1, r.$2);
      } else {
        runs.add(r);
      }
    }
    final fetched = <(int, Uint8List)>[];
    for (final run in runs) {
      if (abandoned()) throw const _Abandoned();
      fetched.add((run.$1, await _readSource(source, run.$1, run.$2, abandoned: abandoned)));
    }

    final out = Uint8List(to - from + 1);
    for (final piece in pieces) {
      final at = piece.outputOffset - from;
      final literal = piece.literal;
      if (literal != null) {
        out.setRange(at, at + piece.length, literal);
        continue;
      }
      final run = fetched.firstWhere((f) =>
          piece.sourceOffset >= f.$1 &&
          piece.sourceOffset + piece.length <= f.$1 + f.$2.length);
      out.setRange(at, at + piece.length, run.$2, piece.sourceOffset - run.$1);
    }
    return out;
  }

  /// One range of the source, read whole.
  Future<Uint8List> _fetchRange(
    _Source source,
    int from,
    int to,
    bool Function() abandoned,
  ) async {
    final response = await _openUpstream(
      source,
      range: 'bytes=$from-$to',
      abandoned: abandoned,
    );
    if (response.statusCode >= 400) {
      throw HttpException('cdn said ${response.statusCode}');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      if (abandoned()) {
        // Leaving the loop cancels the subscription and with it the
        // transfer; the exception says why to whoever asked.
        throw const _Abandoned();
      }
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    if (bytes.length != to - from + 1) {
      throw HttpException('cdn sent ${bytes.length} of ${to - from + 1} bytes');
    }
    return bytes;
  }

  /// Serves the film as `ftyp | moov | mdat`, which is not how it is stored.
  ///
  /// The first few megabytes - the header - are held in memory and sent
  /// from there; everything after them is the original file from a byte
  /// offset, streamed through untouched. A range that straddles the two is
  /// served from both in turn, which is what a set does when it seeks.
  Future<void> _relayRearranged(
    HttpRequest request, _Source source, Mp4Layout layout) async {
    final total = layout.length;
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    final bounds = _bounds(rangeHeader, total);
    if (bounds == null) {
      final socket = await _open(request, HttpStatus.requestedRangeNotSatisfiable, {
        'Content-Range': 'bytes */$total',
        'Content-Length': '0',
      });
      await socket.close();
      return;
    }
    final (from, to) = bounds;
    final length = to - from + 1;
    final status = rangeHeader != null ? HttpStatus.partialContent : HttpStatus.ok;

    final headers = <String, String>{
      ..._mediaHeaders('video/mp4'),
      'Content-Length': '$length',
      if (rangeHeader != null) 'Content-Range': 'bytes $from-$to/$total',
    };
    final socket = await _open(request, status, headers);

    if (request.method == 'HEAD') {
      await socket.close();
      return;
    }

    final started = DateTime.now();
    var sent = 0;
    try {
      // The part that falls inside the rewritten header.
      final headerLength = layout.header.length;
      if (from < headerLength) {
        final until = (to + 1).clamp(0, headerLength);
        final chunk = Uint8List.sublistView(layout.header, from, until);
        socket.add(chunk);
        sent += chunk.length;
        // Pushed out now, before the CDN is even contacted. The set reads
        // the whole index before it decides anything, and opening the
        // upstream connection first - a redirect and a TLS handshake away -
        // left it waiting on an empty socket for the one thing it needed.
        await socket.flush();
      }
    } catch (e) {
      debugPrint('[cast] served range=${rangeHeader ?? "-"} status=$status '
          'sent=${(sent / 1e6).toStringAsFixed(2)}MB in '
          '${(DateTime.now().difference(started).inMilliseconds / 1000).toStringAsFixed(1)}s '
          '-> ${e.runtimeType}');
      socket.destroy();
      return;
    }

    // And the part that comes from the original file, window by window,
    // through the phone's copy of it.
    if (to < layout.header.length) {
      await socket.close();
      return;
    }
    final dataFrom = (from - layout.header.length).clamp(0, layout.dataLength);
    final dataTo = (to - layout.header.length).clamp(0, layout.dataLength - 1);
    final shift = layout.sourceDataStart;
    await _sendWindows(
      socket,
      shift + dataFrom,
      shift + dataTo,
      (a, b, abandoned) => _readSource(source, a, b, abandoned: abandoned),
      log: 'range=${rangeHeader ?? "-"} status=$status',
    );
  }

  Future<void> stop() async {
    clear();
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

  /// What the set is told the stream is.
  String? mime;

  /// How long the source is, once it has said; zero until then.
  int total = 0;

  /// Set when the file has to be served in a different order than it is
  /// stored in; null when it can simply be passed through.
  Mp4Layout? layout;

  /// Set when the film is served inside a Matroska container with its
  /// subtitle as a track; takes precedence over [layout].
  MkvLayout? mkv;

  /// Where the source's redirect led, once followed.
  Uri? resolved;

  /// The phone's copy of the film, filling in; null when there is nowhere
  /// to keep one.
  SourceCache? cache;

  /// The last few windows put together for the set, oldest first.
  final List<(int, Uint8List)> recent = <(int, Uint8List)>[];
}

/// Thrown inside a transfer nobody is waiting for any more.
class _Abandoned implements Exception {
  const _Abandoned();
}
