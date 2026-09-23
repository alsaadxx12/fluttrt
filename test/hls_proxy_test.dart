import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/casting/services/local_stream_server.dart';

/// A live channel is an HLS playlist. A television handed the playlist as
/// it is would resolve the pieces against the phone and get nothing, or go
/// to a CDN that wants https and a Referer; so every piece is rewritten to
/// an address on the phone, which fetches the real one.
void main() {
  group('rewriting a playlist', () {
    String piece(String absolute) => 'http://phone:1/p/tok?u=${Uri.encodeQueryComponent(absolute)}';

    test('relative pieces are resolved against the playlist and pointed at the phone', () {
      const text = '#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXTINF:6.0,\nseg1.ts\n#EXTINF:6.0,\n../other/seg2.ts\n';
      final out = LocalStreamServer.rewritePlaylist(text, 'https://cdn.example.com/live/ch/index.m3u8', piece);
      final lines = out.trim().split('\n');
      expect(lines[3], piece('https://cdn.example.com/live/ch/seg1.ts'));
      expect(lines[5], piece('https://cdn.example.com/live/other/seg2.ts'));
      expect(lines[0], '#EXTM3U', reason: 'tags are kept as they are');
    });

    test('absolute pieces and URI attributes are rewritten too', () {
      const text = '#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\n#EXT-X-MAP:URI="https://x.example.com/init.mp4"\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=1\nhttps://cdn.example.com/hd.m3u8\n';
      final out = LocalStreamServer.rewritePlaylist(text, 'https://cdn.example.com/a/b.m3u8', piece);
      expect(out, contains('URI="${piece('https://cdn.example.com/a/key.bin')}"'));
      expect(out, contains('URI="${piece('https://x.example.com/init.mp4')}"'));
      expect(out, contains(piece('https://cdn.example.com/hd.m3u8')));
    });

    test('a stream is a playlist by its type or its name', () {
      expect(LocalStreamServer.isPlaylist('application/x-mpegURL', 'https://a/b'), isTrue);
      expect(LocalStreamServer.isPlaylist(null, 'https://a/live.m3u8?token=1'), isTrue);
      expect(LocalStreamServer.isPlaylist('video/mp4', 'https://a/film.mp4'), isFalse);
    });
  });

  group('serving a playlist', () {
    late HttpServer origin;
    LocalStreamServer? served;

    setUp(() async {
      HttpOverrides.global = null;
      origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      origin.listen((request) async {
        final path = request.uri.path;
        final response = request.response;
        if (path.endsWith('.m3u8')) {
          response.headers.contentType = ContentType('application', 'vnd.apple.mpegurl');
          response.write('#EXTM3U\n#EXTINF:4.0,\nseg-0.ts\n#EXTINF:4.0,\nseg-1.ts\n');
        } else {
          response.headers.contentType = ContentType('video', 'mp2t');
          response.add(List<int>.filled(1500, path.endsWith('0.ts') ? 7 : 9));
        }
        await response.close();
      });
    });

    tearDown(() async {
      await served?.stop();
      await origin.close(force: true);
    });

    test('the set gets the playlist with pieces on the phone, and the pieces themselves', () async {
      final server = served = LocalStreamServer(cacheDir: Directory.systemTemp.createTempSync('hls_'));
      final address = await server.publish(
        'http://127.0.0.1:${origin.port}/live/ch.m3u8',
        contentType: 'application/x-mpegURL',
      );
      if (address == null) return;
      expect(address, endsWith('.m3u8'));

      final client = HttpClient();
      final list = await (await client.getUrl(Uri.parse(address))).close();
      expect(list.headers.value('content-type'), 'application/vnd.apple.mpegurl');
      final text = await utf8.decoder.bind(list).join();
      final pieces = text.split('\n').where((l) => l.isNotEmpty && !l.startsWith('#')).toList();
      expect(pieces, hasLength(2));
      expect(pieces.first, startsWith(address.substring(0, address.indexOf('/s/'))),
          reason: 'every piece is on the phone, not on the origin');
      expect(pieces.first, contains('/p/'));

      // And a piece, fetched through the phone, is the origin's bytes.
      final seg = await (await client.getUrl(Uri.parse(pieces.first))).close();
      expect(seg.statusCode, 200);
      expect(seg.headers.value('content-type'), 'video/mp2t');
      final bytes = await seg.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      expect(bytes.length, 1500);
      expect(bytes.first, 7);
    });
  });
}
