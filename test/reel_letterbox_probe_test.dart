/// LIVE probe: hits i.ytimg.com for real thumbnails, so it is excluded from
/// the ordinary test run (`*_probe_test.dart`) and only makes sense with a
/// network. It checks [ReelLetterbox] against three real shorts and prints
/// the measured band fraction of each, so a disagreement can be read off the
/// numbers rather than guessed at.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:youtube_downloader/features/reels/data/reel_letterbox.dart';

/// The thumbnail names [ReelLetterbox] tries, in its order.
const _names = ['oardefault.jpg', 'oar2.jpg', 'hqdefault.jpg'];

/// Fetches the first thumbnail of [videoId] that answers with an image and
/// prints its size and band fraction — the same number the module measures
/// for a portrait frame — so the probe's output explains its own verdict.
Future<void> report(http.Client client, String videoId) async {
  for (final name in _names) {
    final uri = Uri.https('i.ytimg.com', '/vi/$videoId/$name');
    final response = await client.get(uri);
    if (response.statusCode != 200) {
      // ignore: avoid_print
      print('$videoId $name -> HTTP ${response.statusCode}');
      continue;
    }
    final bytes = response.bodyBytes;
    final image = img.decodeImage(bytes);
    if (image == null) {
      // ignore: avoid_print
      print('$videoId $name -> 200 but undecodable (${bytes.length} bytes)');
      continue;
    }
    final fraction = reelBlackBandFraction(Uint8List.fromList(bytes));
    // ignore: avoid_print
    print('$videoId $name -> ${image.width}x${image.height}, '
        'full-width band fraction ${fraction?.toStringAsFixed(4)}');
    return;
  }
}

void main() {
  late http.Client client;
  late ReelLetterbox letterbox;

  setUp(() {
    client = http.Client();
    letterbox = ReelLetterbox(client: client);
  });
  tearDown(() {
    letterbox.close();
    client.close();
  });

  test('a letterboxed short is caught, full-frame ones are not', () async {
    // «اسطنبول راسا على عقب» trailer: a 16:9 trailer posted as a short.
    const letterboxed = '-fzylQYZakI';
    const fullFrame = ['ShuDSDd95Rk', 'KowSadqCx2A'];

    for (final id in [letterboxed, ...fullFrame]) {
      await report(client, id);
    }

    expect(await letterbox.isLetterboxed(letterboxed), isTrue, reason: letterboxed);
    for (final id in fullFrame) {
      expect(await letterbox.isLetterboxed(id), isFalse, reason: id);
    }
  }, timeout: const Timeout(Duration(seconds: 90)));
}
