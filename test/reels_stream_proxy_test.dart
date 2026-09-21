import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/reels/data/reel_stream_proxy.dart';

/// A stand-in for YouTube's stream host: it refuses every request without a
/// bounded `Range` (403), one that runs past the end (403), and records the
/// ranges it was asked for.
class _Upstream {
  _Upstream(this.size) : bytes = Uint8List.fromList(List.generate(size, (i) => (i * 7 + 3) & 0xff));

  final int size;
  final Uint8List bytes;
  final List<(int, int)> asked = [];
  late final HttpServer server;

  Future<Uri> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final res = req.response;
      final range = parseRange(req.headers.value(HttpHeaders.rangeHeader));
      if (range == null || range.$2 == null || range.$2! >= size) {
        res.statusCode = HttpStatus.forbidden;
        await res.close();
        return;
      }
      final (start, end) = (range.$1, range.$2!);
      asked.add((start, end));
      res.statusCode = HttpStatus.partialContent;
      res.headers.contentType = ContentType('video', 'mp4');
      res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$size');
      res.headers.contentLength = end - start + 1;
      res.add(bytes.sublist(start, end + 1));
      await res.close();
    });
    return Uri(scheme: 'http', host: server.address.address, port: server.port, path: '/videoplayback', queryParameters: {'itag': '137', 'clen': '$size'});
  }

  Future<void> stop() => server.close(force: true);
}

Future<(HttpClientResponse, Uint8List)> _get(Uri url, {String? range, String method = 'GET'}) async {
  final client = HttpClient();
  try {
    final req = await client.openUrl(method, url);
    if (range != null) req.headers.set(HttpHeaders.rangeHeader, range);
    final res = await req.close();
    final builder = BytesBuilder(copy: false);
    await for (final chunk in res) {
      builder.add(chunk);
    }
    return (res, builder.takeBytes());
  } finally {
    client.close(force: true);
  }
}

void main() {
  group('range headers', () {
    test('parseRange reads open and bounded byte ranges, and nothing else', () {
      expect(parseRange(null), isNull);
      expect(parseRange('bytes=0-'), (0, null));
      expect(parseRange('bytes=10-19'), (10, 19));
      expect(parseRange(' bytes = 5 - '), (5, null));
      expect(parseRange('bytes=-500'), isNull, reason: 'a suffix range is not served');
      expect(parseRange('bytes=9-3'), isNull);
      expect(parseRange('items=0-1'), isNull);
    });

    test('parseContentRange reads start, end and total', () {
      expect(parseContentRange('bytes 0-1023/40094756'), (0, 1023, 40094756));
      expect(parseContentRange('bytes */100'), isNull);
      expect(parseContentRange(null), isNull);
    });
  });

  group('ReelStreamProxy', () {
    // Three chunks and a bit, so a whole read needs four bounded slices.
    const size = ReelStreamProxy.chunkSize * 3 + 12345;
    late _Upstream upstream;
    late Uri upstreamUrl;
    final proxy = ReelStreamProxy.instance;

    setUp(() async {
      upstream = _Upstream(size);
      upstreamUrl = await upstream.start();
    });

    tearDown(() async {
      await upstream.stop();
      await proxy.close();
    });

    test('an open range from the player comes back whole, fetched in bounded slices', () async {
      final local = await proxy.register(upstreamUrl);
      expect(local.host, '127.0.0.1');
      expect(proxy.upstreamOf(local), upstreamUrl);

      final (res, body) = await _get(local, range: 'bytes=0-');
      expect(res.statusCode, HttpStatus.partialContent);
      expect(res.headers.value(HttpHeaders.contentRangeHeader), 'bytes 0-${size - 1}/$size');
      expect(res.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
      expect(res.headers.contentType?.mimeType, 'video/mp4');
      expect(body.length, size);
      expect(body, upstream.bytes);

      expect(upstream.asked.length, 4);
      for (final (start, end) in upstream.asked) {
        expect(end - start + 1, lessThanOrEqualTo(ReelStreamProxy.chunkSize));
        expect(end, lessThan(size));
      }
      expect(upstream.asked.first, (0, ReelStreamProxy.chunkSize - 1));
      expect(upstream.asked.last.$2, size - 1);
    });

    test('a seek (bytes=N-) and a bounded ask (bytes=N-M) are honoured exactly', () async {
      final local = await proxy.register(upstreamUrl);
      const from = ReelStreamProxy.chunkSize + 777;

      final (tail, tailBody) = await _get(local, range: 'bytes=$from-');
      expect(tail.statusCode, HttpStatus.partialContent);
      expect(tail.headers.value(HttpHeaders.contentRangeHeader), 'bytes $from-${size - 1}/$size');
      expect(tailBody, upstream.bytes.sublist(from));
      expect(upstream.asked.first.$1, from, reason: 'the first slice starts where the player asked');

      upstream.asked.clear();
      final (part, partBody) = await _get(local, range: 'bytes=100-199');
      expect(part.statusCode, HttpStatus.partialContent);
      expect(part.headers.value(HttpHeaders.contentRangeHeader), 'bytes 100-199/$size');
      expect(part.headers.contentLength, 100);
      expect(partBody, upstream.bytes.sublist(100, 200));
      expect(upstream.asked, [(100, 199)], reason: 'no more is fetched than was asked');
    });

    test('no range at all is the whole file with a 200; HEAD carries the headers only', () async {
      final local = await proxy.register(upstreamUrl);
      final (res, body) = await _get(local);
      expect(res.statusCode, HttpStatus.ok);
      expect(res.headers.contentLength, size);
      expect(body, upstream.bytes);

      final (head, headBody) = await _get(local, method: 'HEAD', range: 'bytes=0-');
      expect(head.statusCode, HttpStatus.partialContent);
      expect(head.headers.contentLength, size);
      expect(headBody, isEmpty);
    });

    test('past the end is 416, an unknown token 404, and the same stream keeps its URL', () async {
      final local = await proxy.register(upstreamUrl);
      expect(await proxy.register(upstreamUrl), local);
      final other = await proxy.register(upstreamUrl.replace(queryParameters: {'itag': '140', 'clen': '$size'}));
      expect(other, isNot(local));

      final (past, _) = await _get(local, range: 'bytes=$size-');
      expect(past.statusCode, HttpStatus.requestedRangeNotSatisfiable);

      final (missing, _) = await _get(local.replace(path: '/nosuchtoken'));
      expect(missing.statusCode, HttpStatus.notFound);
    });

    test('the file length comes from the upstream when the URL carries no clen', () async {
      final bare = upstreamUrl.replace(queryParameters: {'itag': '137'});
      final local = await proxy.register(bare);
      final (res, body) = await _get(local, range: 'bytes=${size - 10}-');
      expect(res.statusCode, HttpStatus.partialContent);
      expect(body, upstream.bytes.sublist(size - 10));
      // The last slice was cut to the end the first reply announced.
      expect(upstream.asked.every((r) => r.$2 < size), isTrue);
    });
  });
}
