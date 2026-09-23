import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/casting/services/local_stream_server.dart';

/// A live channel is an HLS playlist: a text file naming the pieces of the
/// stream. A television handed the playlist read it once and stopped when
/// its pieces ran out, so the phone follows the playlist itself and hands
/// the set the pieces laid end to end, as one stream with no end.
void main() {
  group('reading a playlist', () {
    test('pieces are resolved against the playlist, with their durations and sequence', () {
      const text = '#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXT-X-MEDIA-SEQUENCE:41\n'
          '#EXTINF:6.0,\nseg41.ts\n#EXTINF:5.5,\n../other/seg42.ts\n';
      final list = LocalStreamServer.parsePlaylist(text, 'https://cdn.example.com/live/ch/index.m3u8');
      expect(list.sequence, 41);
      expect(list.target, 6.0);
      expect(list.ended, isFalse);
      expect(list.pieces.map((p) => p.url),
          ['https://cdn.example.com/live/ch/seg41.ts', 'https://cdn.example.com/live/other/seg42.ts']);
      expect(list.pieces.map((p) => p.duration), [6.0, 5.5]);
    });

    test('a master playlist names the variant with the most bandwidth', () {
      const text = '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360\nsd.m3u8\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1280x720\nhttps://x.example.com/hd.m3u8\n';
      final list = LocalStreamServer.parsePlaylist(text, 'https://cdn.example.com/a/b.m3u8');
      expect(list.variant, 'https://x.example.com/hd.m3u8');
      expect(list.pieces, isEmpty);
    });

    test('an init segment, an end and encryption are all noticed', () {
      const text = '#EXTM3U\n#EXT-X-MAP:URI="init.mp4"\n#EXT-X-KEY:METHOD=AES-128,URI="k"\n'
          '#EXTINF:4,\na.m4s\n#EXT-X-ENDLIST\n';
      final list = LocalStreamServer.parsePlaylist(text, 'https://cdn.example.com/a/b.m3u8');
      expect(list.init, 'https://cdn.example.com/a/init.mp4');
      expect(list.ended, isTrue);
      expect(list.encrypted, isTrue);
    });

    test('the first pieces sent leave the set about eight seconds in hand, no more', () {
      List<LivePiece> pieces(double seconds, int count) =>
          List.generate(count, (i) => LivePiece('https://a/$i.ts', seconds));
      expect(LocalStreamServer.liveStart(pieces(10, 7)), 6, reason: 'one ten-second piece');
      expect(LocalStreamServer.liveStart(pieces(4, 6)), 4, reason: 'two four-second pieces');
      expect(LocalStreamServer.liveStart(pieces(2, 8)), 4, reason: 'four two-second pieces');
      expect(LocalStreamServer.liveStart(pieces(30, 5)), 4, reason: 'one long piece is enough');
      expect(LocalStreamServer.liveStart(pieces(10, 1)), 0);
    });

    test('the wall-clock time of each piece is carried forward from the one given', () {
      const text = '#EXTM3U\n#EXT-X-PROGRAM-DATE-TIME:2026-09-23T14:00:00.000Z\n'
          '#EXTINF:10,\na.ts\n#EXTINF:10,\nb.ts\n';
      final list = LocalStreamServer.parsePlaylist(text, 'https://cdn.example.com/a/b.m3u8');
      expect(list.pieces[0].at, DateTime.utc(2026, 9, 23, 14, 0, 0));
      expect(list.pieces[1].at, DateTime.utc(2026, 9, 23, 14, 0, 10));
    });

    test('pieces under a signed path keep the percent-encoding of the path', () {
      const base = 'https://cdn/live/ch/hdntl=exp=9~acl=%2flive%2f*~hmac=y/chunks.m3u8';
      final list = LocalStreamServer.parsePlaylist('#EXTM3U\n#EXTINF:6,\npiece.ts\n', base);
      expect(list.pieces.single.url, 'https://cdn/live/ch/hdntl=exp=9~acl=%2flive%2f*~hmac=y/piece.ts');
      expect(LocalStreamServer.resolveAgainst(base, '/root.ts'), 'https://cdn/root.ts');
      expect(LocalStreamServer.resolveAgainst(base, 'https://x/y.ts'), 'https://x/y.ts');
      expect(LocalStreamServer.resolveAgainst('https://cdn/a/b/c.m3u8', '../d.ts'), 'https://cdn/a/d.ts');
    });

    test('a stream is a playlist by its type or its name', () {
      expect(LocalStreamServer.isPlaylist('application/x-mpegURL', 'https://a/b'), isTrue);
      expect(LocalStreamServer.isPlaylist(null, 'https://a/live.m3u8?token=1'), isTrue);
      expect(LocalStreamServer.isPlaylist('video/mp4', 'https://a/film.mp4'), isFalse);
    });
  });

  group('rewriting a playlist (the fallback for encrypted channels)', () {
    String piece(String absolute) => 'http://phone:1/p/tok?u=${Uri.encodeQueryComponent(absolute)}';

    test('relative and absolute pieces, and URI attributes, are pointed at the phone', () {
      const text = '#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\n#EXTINF:6.0,\nseg1.ts\n'
          '#EXTINF:6.0,\nhttps://x.example.com/seg2.ts\n';
      final out = LocalStreamServer.rewritePlaylist(text, 'https://cdn.example.com/a/b.m3u8', piece);
      expect(out, contains('URI="${piece('https://cdn.example.com/a/key.bin')}"'));
      expect(out, contains(piece('https://cdn.example.com/a/seg1.ts')));
      expect(out, contains(piece('https://x.example.com/seg2.ts')));
      expect(out.split('\n').first, '#EXTM3U', reason: 'tags are kept as they are');
    });
  });

  group('serving a live channel', () {
    late HttpServer origin;
    LocalStreamServer? served;
    var fetches = 0;

    /// A piece is 1000 bytes: a transport-stream sync byte, then its number.
    List<int> pieceBytes(int n) => [0x47, ...List<int>.filled(999, n)];

    setUp(() async {
      HttpOverrides.global = null;
      fetches = 0;
      origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      origin.listen((request) async {
        final path = request.uri.path;
        final response = request.response;
        if (path.endsWith('ended.m3u8')) {
          response.headers.contentType = ContentType('application', 'vnd.apple.mpegurl');
          response.write('#EXTM3U\n#EXTINF:4.0,\nseg-1.ts\n#EXTINF:4.0,\nseg-2.ts\n#EXT-X-ENDLIST\n');
        } else if (path.endsWith('rolling.m3u8')) {
          // Each reading moves the window on by one piece; the third
          // reading says the channel has ended.
          final k = fetches++;
          response.headers.contentType = ContentType('application', 'vnd.apple.mpegurl');
          final lines = ['#EXTM3U', '#EXT-X-TARGETDURATION:4', '#EXT-X-MEDIA-SEQUENCE:$k'];
          for (var n = k; n < k + 4; n++) {
            lines.addAll(['#EXTINF:4.0,', 'seg-$n.ts']);
          }
          if (k >= 2) lines.add('#EXT-X-ENDLIST');
          response.write('${lines.join('\n')}\n');
        } else {
          final n = int.parse(RegExp(r'seg-(\d+)').firstMatch(path)!.group(1)!);
          response.headers.contentType = ContentType('video', 'mp2t');
          response.add(pieceBytes(n));
        }
        await response.close();
      });
    });

    tearDown(() async {
      await served?.stop();
      await origin.close(force: true);
    });

    Future<(HttpClientResponse, List<int>)> fetch(String address) async {
      final response = await (await HttpClient().getUrl(Uri.parse(address))).close();
      final bytes = await response.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      return (response, bytes);
    }

    test('the set is handed one mpeg-ts stream made of the pieces, not the playlist', () async {
      final server = served = LocalStreamServer(cacheDir: Directory.systemTemp.createTempSync('hls_'));
      final address = await server.publish(
        'http://127.0.0.1:${origin.port}/live/ended.m3u8',
        contentType: 'application/x-mpegURL',
      );
      if (address == null) return;
      expect(address, endsWith('.ts'));
      expect(server.lastMime, 'video/mpeg');
      expect(server.lastFeatures, LocalStreamServer.liveFeatures);

      final (response, bytes) = await fetch(address);
      expect(response.statusCode, 200);
      expect(response.headers.value('content-type'), 'video/mpeg');
      expect(response.headers.value('contentFeatures.dlna.org'), LocalStreamServer.liveFeatures);
      expect(bytes.length, 2000);
      expect(bytes[1], 1, reason: 'the first piece first');
      expect(bytes[1001], 2);
    });

    test('a channel that keeps going is followed: new pieces, each once, in order', () async {
      final server = served = LocalStreamServer(cacheDir: Directory.systemTemp.createTempSync('hls_'));
      final address = await server.publish(
        'http://127.0.0.1:${origin.port}/live/rolling.m3u8',
        contentType: 'application/x-mpegURL',
      );
      if (address == null) return;
      fetches = 0;

      final (_, bytes) = await fetch(address);
      // First reading: pieces 0..3, joined two from the end: 2, 3.
      // Second: 1..4, only 4 is new. Third: 2..5 and the end: 5.
      final order = [for (var i = 1; i < bytes.length; i += 1000) bytes[i]];
      expect(order, [2, 3, 4, 5]);
    });
  });
}
