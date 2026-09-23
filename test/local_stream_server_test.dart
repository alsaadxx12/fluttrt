import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/casting/services/local_stream_server.dart';
import 'package:youtube_downloader/features/casting/services/source_cache.dart';

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

  /// How many of the next requests are dropped on the floor — the socket
  /// closed without a reply, the way a flaky link drops one.
  int dropNext = 0;

  static Future<FakeOrigin> start({
    int size = 4096,
    String contentType = 'video/mp4',
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final body = List<int>.generate(size, (i) => i % 251);
    final origin = FakeOrigin._(server, body);

    server.listen((request) async {
      origin.methods.add(request.method);
      origin.ranges.add(request.headers.value(HttpHeaders.rangeHeader));
      origin.referers.add(request.headers.value('referer'));

      if (origin.dropNext > 0) {
        origin.dropNext--;
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.destroy();
        return;
      }

      final range = request.headers.value(HttpHeaders.rangeHeader);
      final response = request.response;
      final type = contentType.split('/');
      response.headers.contentType = ContentType(type.first, type.last);
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

  test('seeking reaches the origin for the stretch around the seek, not the whole film', () async {
    // Two megabytes: four chunks of the phone's copy.
    final big = await FakeOrigin.start(size: 2 * 1024 * 1024);
    addTearDown(big.stop);

    final server = given();
    final address = await server.publish(big.url);
    if (address == null) return;
    big.ranges.clear();

    const from = 1000000;
    const to = 1000099;
    final response = await ask(address, range: 'bytes=$from-$to');
    final bytes = await response.fold<List<int>>(<int>[], (a, b) => a..addAll(b));

    expect(response.statusCode, HttpStatus.partialContent);
    expect(response.headers.value(HttpHeaders.contentRangeHeader),
        'bytes $from-$to/${big.body.length}');
    expect(bytes, big.body.sublist(from, to + 1));
    // The chunk the seek landed in was fetched - and only chunks: a set
    // that seeks must never be handed the whole rest of the film.
    expect(big.ranges, contains('bytes=${SourceCache.chunk}-${2 * SourceCache.chunk - 1}'));
    for (final range in big.ranges.whereType<String>()) {
      final m = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range)!;
      expect(int.parse(m.group(2)!) - int.parse(m.group(1)!) + 1,
          lessThanOrEqualTo(SourceCache.chunk * 4));
    }
  });

  test('a HEAD probe is answered without a body', () async {
    final server = given();
    final address = await server.publish(origin.url);
    if (address == null) return;

    final response = await ask(address, head: true);
    final bytes = await response.fold<List<int>>(<int>[], (a, b) => a..addAll(b));

    expect(response.statusCode, 200);
    expect(bytes, isEmpty);
    // The length was learnt while the film was published, so the probe is
    // answered from the phone: nothing goes upstream for it, least of all
    // the film itself.
    expect(origin.methods, isNot(contains('HEAD')));
    expect(origin.methods.last, 'GET',
        reason: 'the last thing the origin saw was the planning read');
    expect(response.headers.value(HttpHeaders.contentLengthHeader), '${origin.body.length}');
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

  test('a set that hangs up mid-film does not take the server down', () async {
    // A television closes a connection it is done with, abruptly, several
    // times a film: it reads the index, hangs up, and asks again from the
    // start of the data a second later. Seen on a TCL set against the PC.
    // The second request has to be answered, or the screen stays black.
    final big = await FakeOrigin.start(size: 2 * 1024 * 1024);
    addTearDown(big.stop);

    final server = given();
    final address = await server.publish(big.url, contentType: 'video/mp4');
    if (address == null) return;

    // Read a little, then slam the door.
    final client = HttpClient();
    final first = await (await client.getUrl(Uri.parse(address))).close();
    await first.first;
    await first.detachSocket().then((socket) => socket.destroy());

    // The next request, a moment later, from the middle.
    final again = await ask(address, range: 'bytes=1048576-1048675');
    final bytes = await again.fold<List<int>>(<int>[], (a, b) => a..addAll(b));

    expect(again.statusCode, HttpStatus.partialContent);
    expect(bytes.length, 100);
    expect(bytes, big.body.sublist(1048576, 1048676));
  });

  test('only private addresses count as the local network', () {
    expect(LocalStreamServer.isPrivateAddress('192.168.0.14'), isTrue);
    expect(LocalStreamServer.isPrivateAddress('10.0.0.3'), isTrue);
    expect(LocalStreamServer.isPrivateAddress('172.20.1.1'), isTrue);
    expect(LocalStreamServer.isPrivateAddress('172.32.1.1'), isFalse);
    expect(LocalStreamServer.isPrivateAddress('8.8.8.8'), isFalse);
    expect(LocalStreamServer.isPrivateAddress('not an address'), isFalse);
  });

  group('what a Samsung or LG set reads before it plays', () {
    test('every reply carries the DLNA headers the set asks for', () async {
      final server = given();
      final address = await server.publish(origin.url, contentType: 'video/mp4');
      if (address == null) return;

      for (final head in [true, false]) {
        final response = await ask(address, head: head);
        expect(response.headers.value('transfermode.dlna.org'), 'Streaming');
        expect(response.headers.value('contentfeatures.dlna.org'),
            LocalStreamServer.dlnaFeatures);
        expect(response.headers.value('content-type'), 'video/mp4');
        expect(response.headers.value('server'), contains('DLNADOC'));
        expect(response.headers.value('date'), isNotNull);
        await response.drain<void>();
      }
    });

    test('a HEAD is answered from the phone once the length is known', () async {
      final server = given();
      final address = await server.publish(origin.url, contentType: 'video/mp4');
      if (address == null) return;
      origin.methods.clear();

      final response = await ask(address, head: true);
      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers.value('content-length'), '${origin.body.length}');
      await response.drain<void>();

      // The question never reached the CDN: a Samsung gives a server about
      // three seconds to answer it, and a redirect and a TLS handshake
      // away is longer than that on a slow link.
      expect(origin.methods, isNot(contains('HEAD')));
      expect(server.lastLength, origin.body.length);
    });

    test('a HEAD with a range is answered with the range', () async {
      final server = given();
      final address = await server.publish(origin.url, contentType: 'video/mp4');
      if (address == null) return;

      final response = await ask(address, head: true, range: 'bytes=100-199');
      expect(response.statusCode, HttpStatus.partialContent);
      expect(response.headers.value('content-length'), '100');
      expect(response.headers.value('content-range'), 'bytes 100-199/${origin.body.length}');
      await response.drain<void>();
    });

    test('the set is told what the stream is, whatever the CDN says', () async {
      final vague = await FakeOrigin.start(contentType: 'application/octet-stream');
      addTearDown(vague.stop);

      final server = given();
      final address = await server.publish(vague.url, contentType: 'video/mp4');
      if (address == null) return;

      final response = await ask(address);
      // octet-stream is a file the set was never told about, and a Samsung
      // refuses it before reading a byte.
      expect(response.headers.value('content-type'), 'video/mp4');
      await response.drain<void>();
    });
  });

  group('a link that drops the odd request', () {
    test('a request the CDN dropped is asked again, and the film arrives whole', () async {
      final server = given();
      final address = await server.publish(origin.url, contentType: 'video/mp4');
      if (address == null) return;

      origin.dropNext = 1;
      final response = await ask(address);
      final bytes = await response.fold<List<int>>(<int>[], (a, b) => a..addAll(b));

      expect(bytes, origin.body, reason: 'the second try served the whole film');
      expect(origin.methods.where((m) => m == 'GET').length, greaterThanOrEqualTo(2));
    });

    test('a dropped read while planning does not lose the plan', () async {
      final film = File('test/fixtures/tiny_tail.mp4').readAsBytesSync();
      final flaky = await FakeOrigin.serving(film);
      addTearDown(flaky.stop);
      flaky.dropNext = 2;

      final server = given();
      final address = await server.publish(flaky.url, contentType: 'video/mp4');
      if (address == null) return;

      // The index is at the end of this file; had the first read been given
      // up on, the film would have gone as it is and the set would have
      // read the whole of it to find the index. Rearranged, the index is
      // in the first few kilobytes.
      final head = await ask(address, head: true);
      expect(head.headers.value('content-length'), '${server.lastLength}');
      await head.drain<void>();
      final front = await ask(address, range: 'bytes=0-4095');
      final bytes = await front.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      expect(latin1.decode(bytes, allowInvalid: true), contains('moov'));
    });
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
  group('a film with a subtitle', () {
    /// ffmpeg's tiny film: H.264 with B-frames, AAC, index last.
    final film = File('test/fixtures/tiny_tail.mp4').readAsBytesSync();
    const srt = '1\n00:00:00,500 --> 00:00:01,200\nمرحبا\n\n'
        '2\n00:00:01,400 --> 00:00:02,000\nسطر ثانٍ\n';

    Future<Uint8List> fetch(String url, {String? range}) async {
      final response = await ask(url, range: range);
      final bytes = await response.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      return Uint8List.fromList(bytes);
    }

    test('is served as an mkv, and says so in the address', () async {
      final origin = await FakeOrigin.serving(film);
      addTearDown(origin.stop);

      final server = given();
      final address = await server.publish(origin.url, contentType: 'video/mp4', subtitle: srt);
      if (address == null) return;

      // A television's player shows no sidecar subtitle at all; it shows a
      // subtitle track inside a Matroska file. So that is what it gets.
      expect(address, endsWith('.mkv'));
    });

    test('the mkv begins with its magic and is exactly as long as promised', () async {
      final origin = await FakeOrigin.serving(film);
      addTearDown(origin.stop);

      final server = given();
      final address = await server.publish(origin.url, subtitle: srt);
      if (address == null) return;

      final head = await ask(address, head: true);
      expect(head.headers.value('content-type'), 'video/x-matroska');
      final promised = int.parse(head.headers.value('content-length')!);

      final whole = await fetch(address);
      expect(whole.length, promised);
      expect(whole.sublist(0, 4), [0x1A, 0x45, 0xDF, 0xA3]);
      expect(whole.length, greaterThan(film.length - 3000),
          reason: 'every frame of the film is in there');
    });

    test('a seek is answered with the same bytes a full read gives', () async {
      final origin = await FakeOrigin.serving(film);
      addTearDown(origin.stop);

      final server = given();
      final address = await server.publish(origin.url, subtitle: srt);
      if (address == null) return;

      final whole = await fetch(address);
      final from = whole.length ~/ 2;
      final response = await ask(address, range: 'bytes=$from-${from + 4095}');
      expect(response.statusCode, HttpStatus.partialContent);
      expect(response.headers.value('content-range'), 'bytes $from-${from + 4095}/${whole.length}');
      final part = await response.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      expect(part, whole.sublist(from, from + 4096));

      // And the tail, which is how a set reads an index it expects at the end.
      final tail = await fetch(address, range: 'bytes=${whole.length - 100}-');
      expect(tail, whole.sublist(whole.length - 100));
    });

    test('ffmpeg reads the served file back with its subtitle', () async {
      final origin = await FakeOrigin.serving(film);
      addTearDown(origin.stop);

      final server = given();
      final address = await server.publish(origin.url, subtitle: srt);
      if (address == null) return;

      final whole = await fetch(address);
      final dir = await Directory.systemTemp.createTemp('cineball-served');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}${Platform.pathSeparator}served.mkv';
      await File(path).writeAsBytes(whole);

      final ProcessResult probe;
      try {
        probe = await Process.run('ffprobe', [
          '-v', 'error', '-show_entries', 'stream=codec_type', '-of', 'csv=p=0', path,
        ]);
      } on ProcessException {
        markTestSkipped('ffprobe is not installed here');
        return;
      }
      expect((probe.stdout as String).trim().split(RegExp(r'\r?\n')),
          ['video', 'audio', 'subtitle']);
    });

    test('a seek into a film the phone already holds never goes to the origin', () async {
      // A noisier film - 640 KB, two chunks of the phone's copy.
      final big = File('test/fixtures/noisy_tail.mp4').readAsBytesSync();
      final origin = await FakeOrigin.serving(big);
      addTearDown(origin.stop);

      final server = given();
      final address = await server.publish(origin.url, subtitle: srt);
      if (address == null) return;
      final head = await ask(address, head: true);
      final length = int.parse(head.headers.value('content-length')!);
      // The set watches the film through once; the phone keeps it.
      await fetch(address);
      origin.ranges.clear();

      // The set seeks: one request, from a third of the way in, to the end.
      final part = await fetch(address, range: 'bytes=${length ~/ 3}-');
      expect(part.length, length - length ~/ 3);

      // Answered from the phone's copy, whole: a seek that used to be a
      // trip to the internet is a read from storage.
      expect(origin.ranges, isEmpty);
      final whole = await fetch(address);
      expect(part, whole.sublist(length ~/ 3));
    });

    test('the same stretch asked for again does not go back to the origin', () async {
      final origin = await FakeOrigin.serving(film);
      addTearDown(origin.stop);

      final server = given();
      final address = await server.publish(origin.url, subtitle: srt);
      if (address == null) return;
      final whole = await fetch(address);
      final from = whole.length ~/ 2;

      final once = await fetch(address, range: 'bytes=$from-');
      final asked = origin.ranges.length;
      final again = await fetch(address, range: 'bytes=${from + 12}-');
      expect(origin.ranges.length, asked,
          reason: 'a set re-reads what it just read; the answer is remembered');
      expect(again, once.sublist(12));
    });

    test('without a subtitle the film stays an mp4, index first', () async {
      final origin = await FakeOrigin.serving(film);
      addTearDown(origin.stop);

      final server = given();
      final address = await server.publish(origin.url, contentType: 'video/mp4');
      if (address == null) return;

      expect(address, endsWith('.mp4'));
      final whole = await fetch(address);
      expect(String.fromCharCodes(whole, 4, 8), 'ftyp');
      expect(String.fromCharCodes(whole, 36, 40), 'moov');
    });

    test('a subtitle with nothing in it changes nothing', () async {
      final origin = await FakeOrigin.serving(film);
      addTearDown(origin.stop);

      final server = given();
      final address = await server.publish(origin.url, subtitle: 'not a subtitle at all');
      if (address == null) return;
      expect(address, endsWith('.mp4'));
    });
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
