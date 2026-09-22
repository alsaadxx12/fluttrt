import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/casting/services/local_stream_server.dart';

/// Stands in for the catalogue's CDN: serves a known body, honours Range,
/// and records what it was asked for — including the headers, which is how
/// the Referer a live source insists on is checked.
class FakeOrigin {
  FakeOrigin._(this._server, this.body);

  final HttpServer _server;
  final List<int> body;
  final List<String> methods = <String>[];
  final List<String?> ranges = <String?>[];
  final List<String?> referers = <String?>[];

  static Future<FakeOrigin> start({int size = 4096}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final body = List<int>.generate(size, (i) => i % 251);
    final origin = FakeOrigin._(server, body);

    server.listen((request) async {
      origin.methods.add(request.method);
      origin.ranges.add(request.headers.value(HttpHeaders.rangeHeader));
      origin.referers.add(request.headers.value('referer'));

      final range = request.headers.value(HttpHeaders.rangeHeader);
      final response = request.response;
      response.headers.contentType = ContentType('video', 'mp4');
      response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');

      if (range != null) {
        final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range);
        final from = int.parse(match!.group(1)!);
        final to = (match.group(2) ?? '').isEmpty
            ? body.length - 1
            : int.parse(match.group(2)!);
        final slice = body.sublist(from, to + 1);
        response.statusCode = HttpStatus.partialContent;
        response.headers
            .set(HttpHeaders.contentRangeHeader, 'bytes $from-$to/${body.length}');
        response.headers.contentLength = slice.length;
        if (request.method != 'HEAD') response.add(slice);
      } else {
        response.headers.contentLength = body.length;
        if (request.method != 'HEAD') response.add(body);
      }
      await response.close();
    });

    return origin;
  }

  /// An origin that serves exactly these bytes.
  static Future<FakeOrigin> serving(List<int> body) async {
    final origin = await FakeOrigin.start(size: 0);
    origin.body
      ..clear()
      ..addAll(body);
    return origin;
  }

  String get url => 'http://127.0.0.1:${_server.port}/film.mp4';

  Future<void> stop() => _server.close(force: true);
}

void main() {
  late FakeOrigin origin;
  LocalStreamServer? served;

  setUp(() async {
    origin = await FakeOrigin.start();
  });

  tearDown(() async {
    await served?.stop();
    served = null;
    await origin.stop();
  });

  /// flutter_test answers every request with 400 and reinstates that between
  /// setUp and the body, so both the clearing and the server that holds the
  /// client belong in here.
  LocalStreamServer given() {
    HttpOverrides.global = null;
    return served = LocalStreamServer();
  }

  /// Fetches through the phone's server the way a television would.
  Future<HttpClientResponse> ask(String url, {String? range, bool head = false}) async {
    final client = HttpClient();
    final request = await client.openUrl(head ? 'HEAD' : 'GET', Uri.parse(url));
    if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
    return request.close();
  }

  test('publishes an address on the local network, not a loopback one', () async {
    final server = given();
    final address = await server.publish(origin.url);

    // On a machine with no network at all there is nothing to publish from,
    // and saying so is better than handing out an address that cannot work.
    if (address == null) return;

    expect(address, startsWith('http://'));
    expect(address, isNot(contains('127.0.0.1')));
    expect(address, isNot(contains('localhost')));
    expect(address, contains(':${server.port}/s/'));
  });

  test('the address carries a token, never the real url', () async {
    final server = given();
    final address = await server.publish(
      'https://cdn.example.com/film.mp4?Signature=secret&Expires=99',
    );
    if (address == null) return;

    expect(address, isNot(contains('cdn.example.com')));
    expect(address, isNot(contains('Signature')));
    expect(address, isNot(contains('secret')));
  });

  test('a television fetching the address gets the film', () async {
    final server = given();
    final address = await server.publish(origin.url);
    if (address == null) return;

    final response = await ask(address);
    final bytes = await response.fold<List<int>>(<int>[], (a, b) => a..addAll(b));

    expect(response.statusCode, 200);
    expect(response.headers.contentType.toString(), startsWith('video/mp4'));
    expect(bytes, origin.body, reason: 'byte for byte, not a re-encode');
  });

  test('seeking passes the range through to the origin', () async {
    final server = given();
    final address = await server.publish(origin.url);
    if (address == null) return;

    final response = await ask(address, range: 'bytes=100-199');
    final bytes = await response.fold<List<int>>(<int>[], (a, b) => a..addAll(b));

    expect(response.statusCode, HttpStatus.partialContent);
    expect(response.headers.value(HttpHeaders.contentRangeHeader),
        'bytes 100-199/${origin.body.length}');
    expect(bytes, origin.body.sublist(100, 200));
    expect(origin.ranges.last, 'bytes=100-199',
        reason: 'the range has to reach the cdn or the set gets the whole film');
  });

  test('a HEAD probe is answered without a body', () async {
    final server = given();
    final address = await server.publish(origin.url);
    if (address == null) return;

    final response = await ask(address, head: true);
    final bytes = await response.fold<List<int>>(<int>[], (a, b) => a..addAll(b));

    expect(response.statusCode, 200);
    expect(bytes, isEmpty);
    expect(origin.methods.last, 'HEAD',
        reason: 'the probe should not pull the film down behind it');
    expect(response.headers.value(HttpHeaders.acceptRangesHeader), 'bytes',
        reason: 'without this some sets show no scrubber');
  });

  test('headers the source insists on are sent upstream, not to the set', () async {
    final server = given();
    final address = await server.publish(
      origin.url,
      headers: {'Referer': 'https://9.boomstreaming.com/'},
    );
    if (address == null) return;

    await ask(address);

    expect(origin.referers.last, 'https://9.boomstreaming.com/');
    expect(address, isNot(contains('boomstreaming')));
  });

  test('an address is dead once casting stops', () async {
    final server = given();
    final address = await server.publish(origin.url);
    if (address == null) return;

    server.clear();
    final response = await ask(address);

    expect(response.statusCode, HttpStatus.notFound,
        reason: 'an address that outlives its film is a signed url left out');
  });

  group('which address the television is told', () {
    test('the wifi interface wins, even when mobile data is up first', () {
      // rmnet_data0 is the mobile interface on Android and its carrier
      // address is private too, so «first private address» picked it and
      // the set was sent somewhere it could never reach.
      expect(
        LocalStreamServer.pickLanAddress({
          'rmnet_data0': ['10.115.22.7'],
          'wlan0': ['192.168.0.14'],
        }),
        '192.168.0.14',
      );
    });

    test('an unnamed interface is judged by its range instead', () {
      expect(
        LocalStreamServer.pickLanAddress({
          'unknown0': ['10.115.22.7'],
          'unknown1': ['192.168.1.5'],
        }),
        '192.168.1.5',
      );
    });

    test('10.x is taken only when there is nothing else', () {
      expect(
        LocalStreamServer.pickLanAddress({'rmnet_data0': ['10.115.22.7']}),
        '10.115.22.7',
      );
    });

    test('nothing at all is nothing, not a guess', () {
      expect(LocalStreamServer.pickLanAddress({}), isNull);
      expect(LocalStreamServer.pickLanAddress({'eth0': []}), isNull);
    });
  });

  test('it knows whether the television ever came for the film', () async {
    final server = given();
    final address = await server.publish(origin.url);
    if (address == null) return;

    expect(server.wasFetched, isFalse, reason: 'nothing has asked yet');
    await ask(address);
    expect(server.wasFetched, isTrue);
  });

  group('a film whose index is at the end', () {
    /// An origin serving a file shaped like the catalogue's: ftyp, free,
    /// mdat, and the index last.
    Future<FakeOrigin> awkward() async {
      final ftyp = _box('ftyp', List<int>.filled(24, 0));
      final free = _box('free', const []);
      final media = List<int>.generate(2048, (i) => (i * 7) % 251);
      final mdat = _box('mdat', media);
      final dataStart = ftyp.length + free.length + 8;

      final stco = _stco([dataStart, dataStart + 1024]);
      final moov = _box('moov',
          _box('trak', _box('mdia', _box('minf', _box('stbl', stco)))));

      return FakeOrigin.serving([...ftyp, ...free, ...mdat, ...moov]);
    }

    test('the set is served the index first, and the film entire', () async {
      final origin = await awkward();
      addTearDown(origin.stop);

      final server = given();
      final address = await server.publish(origin.url);
      if (address == null) return;

      final response = await ask(address);
      final bytes = await response.fold<List<int>>(<int>[], (a, b) => a..addAll(b));

      expect(String.fromCharCodes(bytes.sublist(4, 8)), 'ftyp');
      expect(String.fromCharCodes(bytes.sublist(36, 40)), 'moov',
          reason: 'the index has to come before the film, or the set shows black');

      // The media survives the move byte for byte.
      final mdatAt = bytes.length - 2048;
      expect(bytes.sublist(mdatAt),
          List<int>.generate(2048, (i) => (i * 7) % 251));
    });

    test('a seek into the middle is answered from the right place', () async {
      final origin = await awkward();
      addTearDown(origin.stop);

      final server = given();
      final address = await server.publish(origin.url);
      if (address == null) return;

      final whole = await (await ask(address))
          .fold<List<int>>(<int>[], (a, b) => a..addAll(b));

      // A range that straddles the rewritten header and the original file.
      final from = whole.length - 2048 - 16;
      final response = await ask(address, range: 'bytes=$from-${from + 63}');
      final part = await response.fold<List<int>>(<int>[], (a, b) => a..addAll(b));

      expect(response.statusCode, HttpStatus.partialContent);
      expect(part, whole.sublist(from, from + 64),
          reason: 'a seek must land on the same bytes a full read would');
    });
  });

  group('the extension on the end of the address', () {
    test('a served address ends in a file extension', () async {
      final server = given();
      final address = await server.publish(origin.url, contentType: 'video/mp4');
      if (address == null) return;

      // A TCL set given `/s/<token>` never fetched it — no request at all,
      // just a black screen. The same set fetched `/probe.mp4` from the
      // same server at once. It decides whether to try from the file name.
      expect(address, endsWith('.mp4'));
    });

    test('and the stream is still served at that address', () async {
      final server = given();
      final address = await server.publish(origin.url, contentType: 'video/mp4');
      if (address == null) return;

      final response = await ask(address);
      final bytes = await response.fold<List<int>>(<int>[], (a, b) => a..addAll(b));

      expect(response.statusCode, 200);
      expect(bytes, origin.body,
          reason: 'the extension is decoration; the token is what matters');
    });

    test('the kind of stream decides which one', () {
      expect(LocalStreamServer.extensionFor('video/mp4', ''), '.mp4');
      expect(LocalStreamServer.extensionFor('application/x-mpegURL', ''), '.m3u8');
      expect(LocalStreamServer.extensionFor('video/x-matroska', ''), '.mkv');
    });

    test('without a content type it reads the source url', () {
      expect(
        LocalStreamServer.extensionFor(null, 'https://cdn.example.com/a/live.m3u8?t=1'),
        '.m3u8',
      );
      expect(
        LocalStreamServer.extensionFor(null, 'https://cdn.example.com/film.mkv'),
        '.mkv',
      );
    });

    test('and falls back to mp4 rather than to nothing', () {
      // A wrong guess is answered by the set; no guess is answered by
      // silence.
      expect(LocalStreamServer.extensionFor(null, 'https://cdn.example.com/x?a=1'), '.mp4');
      expect(LocalStreamServer.extensionFor('', ''), '.mp4');
    });
  });

  test('only private addresses count as the local network', () {
    expect(LocalStreamServer.isPrivateAddress('192.168.0.14'), isTrue);
    expect(LocalStreamServer.isPrivateAddress('10.0.0.3'), isTrue);
    expect(LocalStreamServer.isPrivateAddress('172.20.1.1'), isTrue);
    expect(LocalStreamServer.isPrivateAddress('172.32.1.1'), isFalse);
    expect(LocalStreamServer.isPrivateAddress('8.8.8.8'), isFalse);
    expect(LocalStreamServer.isPrivateAddress('not an address'), isFalse);
  });

  test('a body of the right size comes through whole', () async {
    final big = await FakeOrigin.start(size: 512 * 1024);
    addTearDown(big.stop);

    final server = given();
    final address = await server.publish(big.url);
    if (address == null) return;

    final response = await ask(address);
    final bytes = await response.fold<List<int>>(<int>[], (a, b) => a..addAll(b));

    expect(bytes.length, 512 * 1024, reason: 'piped, not truncated');
    expect(utf8.encode('').length, 0); // keeps the convert import honest
  });
}

/// A box: four bytes of size, four of type, then the payload.
List<int> _box(String type, List<int> payload) {
  final out = Uint8List(8 + payload.length);
  ByteData.view(out.buffer).setUint32(0, out.length);
  out.setRange(4, 8, type.codeUnits);
  out.setRange(8, out.length, payload);
  return out;
}

/// `stco`: version and flags, how many chunks, then where each one is.
List<int> _stco(List<int> offsets) {
  final body = ByteData(8 + offsets.length * 4);
  body.setUint32(4, offsets.length);
  for (var i = 0; i < offsets.length; i++) {
    body.setUint32(8 + i * 4, offsets[i]);
  }
  return _box('stco', body.buffer.asUint8List());
}
