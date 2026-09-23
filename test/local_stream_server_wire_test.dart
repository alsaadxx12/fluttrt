import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/casting/services/local_stream_server.dart';

/// The bytes on the wire, read with a raw socket rather than an http client.
///
/// A TCL set stalled for ever on a reply whose header names were in lower
/// case, and played at once when they were capitalised — measured from a PC
/// with the two replies otherwise identical. Dart's HttpServer lowercases
/// every name it sends, and an http client on this side would hide that,
/// because clients do not care. The television did.
class Wire {
  Wire._(this.status, this.headers, this.rawHeaderBlock, this.body);

  final int status;
  final Map<String, String> headers;
  final String rawHeaderBlock;
  final Uint8List body;

  static Future<Wire> fetch(String url, {String method = 'GET', String? range, int readAtMost = 1 << 20}) async {
    final uri = Uri.parse(url);
    final socket = await Socket.connect(uri.host, uri.port, timeout: const Duration(seconds: 5));
    final request = StringBuffer()
      ..write('$method ${uri.path} HTTP/1.1\r\n')
      ..write('Host: ${uri.host}:${uri.port}\r\n');
    if (range != null) request.write('Range: $range\r\n');
    request.write('\r\n');
    socket.add(ascii.encode(request.toString()));
    await socket.flush();

    final buffer = BytesBuilder(copy: false);
    await for (final chunk in socket) {
      buffer.add(chunk);
      final bytes = buffer.toBytes();
      final split = _indexOfBlankLine(bytes);
      if (split >= 0) {
        final headerBlock = ascii.decode(bytes.sublist(0, split));
        final lines = headerBlock.split('\r\n');
        final status = int.parse(lines.first.split(' ')[1]);
        final headers = <String, String>{};
        for (final line in lines.skip(1)) {
          final colon = line.indexOf(':');
          if (colon > 0) headers[line.substring(0, colon)] = line.substring(colon + 1).trim();
        }
        final bodyStart = split + 4;
        final declared = int.tryParse(headers['Content-Length'] ?? headers['content-length'] ?? '') ?? -1;
        final want = method == 'HEAD' ? 0 : (declared < 0 ? readAtMost : (declared < readAtMost ? declared : readAtMost));
        if (bytes.length - bodyStart >= want) {
          socket.destroy();
          return Wire._(status, headers, headerBlock, Uint8List.sublistView(bytes, bodyStart, bodyStart + want));
        }
      }
    }
    socket.destroy();
    throw StateError('connection closed before the reply was complete');
  }

  static int _indexOfBlankLine(Uint8List b) {
    for (var i = 0; i + 3 < b.length; i++) {
      if (b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10) return i;
    }
    return -1;
  }
}

class FakeOrigin {
  FakeOrigin._(this._server, this.body);
  final HttpServer _server;
  final List<int> body;

  static Future<FakeOrigin> start({int size = 4096}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final body = List<int>.generate(size, (i) => (i * 7) % 251);
    server.listen((request) async {
      final range = request.headers.value(HttpHeaders.rangeHeader);
      final response = request.response;
      response.headers.contentType = ContentType('video', 'mp4');
      response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      if (range != null) {
        final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range)!;
        final from = int.parse(m.group(1)!);
        final to = (m.group(2) ?? '').isEmpty ? body.length - 1 : int.parse(m.group(2)!);
        final slice = body.sublist(from, to + 1);
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $from-$to/${body.length}');
        response.headers.contentLength = slice.length;
        if (request.method != 'HEAD') response.add(slice);
      } else {
        response.headers.contentLength = body.length;
        if (request.method != 'HEAD') response.add(body);
      }
      await response.close();
    });
    return FakeOrigin._(server, body);
  }

  String get url => 'http://127.0.0.1:${_server.port}/film.mp4';
  Future<void> stop() => _server.close(force: true);
}

void main() {
  late FakeOrigin origin;
  LocalStreamServer? served;

  setUp(() async => origin = await FakeOrigin.start());
  tearDown(() async {
    await served?.stop();
    served = null;
    await origin.stop();
  });

  LocalStreamServer given() {
    HttpOverrides.global = null;
    // A cache directory of its own, thrown away after: what one test
    // fetched must not be found on disk by the next.
    final cacheDir = Directory.systemTemp.createTempSync('cineball_cast_test_');
    addTearDown(() async {
      try {
        await cacheDir.delete(recursive: true);
      } catch (_) {}
    });
    return served = LocalStreamServer(cacheDir: cacheDir);
  }

  /// The names a set matches case-sensitively; the only spelling it takes.
  const wanted = ['Content-Type', 'Content-Length', 'Accept-Ranges'];

  test('header names go out capitalised, not in lower case', () async {
    final address = await given().publish(origin.url, contentType: 'video/mp4');
    if (address == null) return;

    final wire = await Wire.fetch(address, range: 'bytes=0-');

    expect(wire.status, 206);
    for (final name in wanted) {
      expect(wire.headers.containsKey(name), isTrue,
          reason: '$name must be spelled exactly so; the set reads it by that spelling:\n${wire.rawHeaderBlock}');
      expect(wire.headers.containsKey(name.toLowerCase()), isFalse,
          reason: 'the lower-case spelling is what stalled the set:\n${wire.rawHeaderBlock}');
    }
    expect(wire.headers.containsKey('Content-Range'), isTrue);
    expect(wire.headers['Content-Range'], 'bytes 0-${origin.body.length - 1}/${origin.body.length}');
    expect(wire.headers['Content-Length'], '${origin.body.length}');
    expect(wire.body, origin.body, reason: 'and the film itself is untouched');
  });

  test('a plain GET is a 200 with the same spelling', () async {
    final address = await given().publish(origin.url, contentType: 'video/mp4');
    if (address == null) return;

    final wire = await Wire.fetch(address);
    expect(wire.status, 200);
    for (final name in wanted) {
      expect(wire.headers.containsKey(name), isTrue, reason: wire.rawHeaderBlock);
    }
    expect(wire.body, origin.body);
  });

  test('HEAD carries the same headers and no body', () async {
    final address = await given().publish(origin.url, contentType: 'video/mp4');
    if (address == null) return;

    final wire = await Wire.fetch(address, method: 'HEAD');
    expect(wire.status, 200);
    expect(wire.headers.containsKey('Content-Length'), isTrue, reason: wire.rawHeaderBlock);
    expect(wire.headers['Content-Length'], '${origin.body.length}');
    expect(wire.body, isEmpty);
  });

  test('a seek is a 206 with the exact Content-Range', () async {
    final address = await given().publish(origin.url, contentType: 'video/mp4');
    if (address == null) return;

    final wire = await Wire.fetch(address, range: 'bytes=100-199');
    expect(wire.status, 206);
    expect(wire.headers['Content-Range'], 'bytes 100-199/${origin.body.length}');
    expect(wire.headers['Content-Length'], '100');
    expect(wire.body, origin.body.sublist(100, 200));
  });
}
