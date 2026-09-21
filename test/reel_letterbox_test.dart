import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:youtube_downloader/features/reels/data/reel_letterbox.dart';

/// A [width]x[height] black canvas with a colourful picture filling the
/// rows [pictureTop]..[pictureBottom) between the columns [pictureLeft]..
/// [pictureRight); the whole canvas when those are left out.
Uint8List canvas({
  required int width,
  required int height,
  int pictureTop = 0,
  int? pictureBottom,
  int pictureLeft = 0,
  int? pictureRight,
}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(0, 0, 0));
  for (var y = pictureTop; y < (pictureBottom ?? height); y++) {
    for (var x = pictureLeft; x < (pictureRight ?? width); x++) {
      // A gradient rather than a flat fill, so a row is never mistaken for
      // black because the whole picture happens to be one dark colour.
      image.setPixelRgb(x, y, x & 0xff, y & 0xff, 200);
    }
  }
  return img.encodePng(image);
}

void main() {
  group('reelBlackBandFraction', () {
    test('a 16:9 picture centred on a 9:16 canvas leaves ~0.68 of it black', () {
      // 360 wide → a 16:9 picture is 202 rows tall; 219 black above, 219 below.
      final bytes = canvas(width: 360, height: 640, pictureTop: 219, pictureBottom: 421);
      final fraction = reelBlackBandFraction(bytes)!;
      expect(fraction, closeTo(438 / 640, 0.005));
      expect(fraction >= ReelLetterbox.threshold, isTrue);
    });

    test('a picture on the middle 9/16 of the canvas scores 0.4375', () {
      // 360 rows of picture between two bands of 140.
      final bytes = canvas(width: 360, height: 640, pictureTop: 140, pictureBottom: 500);
      final fraction = reelBlackBandFraction(bytes)!;
      expect(fraction, closeTo(0.4375, 0.005));
      expect(fraction >= ReelLetterbox.threshold, isTrue);
    });

    test('a full-frame picture scores 0', () {
      expect(reelBlackBandFraction(canvas(width: 360, height: 640)), 0);
    });

    test('a thin 5% band on each side scores ~0.10, under the threshold', () {
      final bytes = canvas(width: 360, height: 640, pictureTop: 32, pictureBottom: 608);
      final fraction = reelBlackBandFraction(bytes)!;
      expect(fraction, closeTo(0.10, 0.005));
      expect(fraction < ReelLetterbox.threshold, isTrue);
    });

    test('an all-black picture scores 0, not 1', () {
      final bytes = canvas(width: 360, height: 640, pictureTop: 0, pictureBottom: 0);
      expect(reelBlackBandFraction(bytes), 0);
    });

    test('junk bytes give null', () {
      expect(reelBlackBandFraction(Uint8List.fromList(List.generate(300, (i) => (i * 31) & 0xff))), isNull);
      expect(reelBlackBandFraction(Uint8List(0)), isNull);
    });
  });

  group('ReelLetterbox.isLetterboxed', () {
    http.Response png(Uint8List bytes) => http.Response.bytes(bytes, 200, headers: {'content-type': 'image/jpeg'});

    test('letterboxed portrait thumbnail → true; only oardefault is asked for', () async {
      final asked = <String>[];
      final client = MockClient((request) async {
        asked.add(request.url.path);
        if (request.url.path == '/vi/abc/oardefault.jpg') {
          return png(canvas(width: 360, height: 640, pictureTop: 219, pictureBottom: 421));
        }
        return http.Response('', 404);
      });
      final letterbox = ReelLetterbox(client: client);
      expect(await letterbox.isLetterboxed('abc'), isTrue);
      expect(asked, ['/vi/abc/oardefault.jpg']);
      letterbox.close();
    });

    test('full-frame portrait thumbnail → false', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/vi/abc/oardefault.jpg') return png(canvas(width: 360, height: 640));
        return http.Response('', 404);
      });
      expect(await ReelLetterbox(client: client).isLetterboxed('abc'), isFalse);
    });

    test('a thin band → false', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/vi/abc/oardefault.jpg') {
          return png(canvas(width: 360, height: 640, pictureTop: 32, pictureBottom: 608));
        }
        return http.Response('', 404);
      });
      expect(await ReelLetterbox(client: client).isLetterboxed('abc'), isFalse);
    });

    test('404 for everything → null, after trying all three thumbnails in order', () async {
      final asked = <String>[];
      final client = MockClient((request) async {
        asked.add(request.url.toString());
        return http.Response('', 404);
      });
      expect(await ReelLetterbox(client: client).isLetterboxed('abc'), isNull);
      expect(asked, [
        'https://i.ytimg.com/vi/abc/oardefault.jpg',
        'https://i.ytimg.com/vi/abc/oar2.jpg',
        'https://i.ytimg.com/vi/abc/hqdefault.jpg',
      ]);
    });

    test('a 200 that is not an image is skipped like a 404', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/vi/abc/oardefault.jpg') return http.Response('<html>not found</html>', 200);
        return http.Response('', 404);
      });
      expect(await ReelLetterbox(client: client).isLetterboxed('abc'), isNull);
    });

    test('a request that throws is skipped like a 404', () async {
      final client = MockClient((request) async => throw http.ClientException('no network', request.url));
      expect(await ReelLetterbox(client: client).isLetterboxed('abc'), isNull);
    });

    test('hqdefault fallback: pillarboxed 4:3 frame whose central column is letterboxed → true', () async {
      // 480x360: the portrait column is 202 wide (139..341); inside it a
      // 16:9 picture 202x113 sits centred (rows 123..236), black elsewhere.
      final client = MockClient((request) async {
        if (request.url.path == '/vi/abc/hqdefault.jpg') {
          return png(canvas(width: 480, height: 360, pictureTop: 123, pictureBottom: 236, pictureLeft: 139, pictureRight: 341));
        }
        return http.Response('', 404);
      });
      expect(await ReelLetterbox(client: client).isLetterboxed('abc'), isTrue);
    });

    test('hqdefault fallback: pillarboxed 4:3 frame whose central column is full → false', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/vi/abc/hqdefault.jpg') {
          return png(canvas(width: 480, height: 360, pictureLeft: 139, pictureRight: 341));
        }
        return http.Response('', 404);
      });
      expect(await ReelLetterbox(client: client).isLetterboxed('abc'), isFalse);
    });

    test('a fetch slower than the timeout → null', () async {
      final client = MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return png(canvas(width: 360, height: 640, pictureTop: 219, pictureBottom: 421));
      });
      expect(await ReelLetterbox(client: client).isLetterboxed('abc', timeout: const Duration(milliseconds: 20)), isNull);
    });
  });
}
