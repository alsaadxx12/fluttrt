import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/sports/data/services/aloula_service.dart';

/// Live probe (network): what the app hands the player for KSA Sports 1,
/// and whether that address and its first piece can be fetched plainly.
void main() {
  test('ksa sports 1 stream path', () async {
    final url = await AloulaService().streamFor(AloulaService.rowId);
    // ignore: avoid_print
    print('stream: $url');
    expect(url, isNotNull);
    final client = HttpClient();
    final r1 = await (await client.getUrl(Uri.parse(url!))).close();
    final text = await r1.transform(const SystemEncoding().decoder).join();
    // ignore: avoid_print
    print('playlist status ${r1.statusCode}, ${text.split('\n').length} lines');
    final pieces = text.split('\n').where((l) => l.isNotEmpty && !l.startsWith('#')).toList();
    final piece = Uri.parse(url).resolve(pieces.last).toString();
    // ignore: avoid_print
    print('last piece: $piece');
    final r2 = await (await client.getUrl(Uri.parse(piece))).close();
    var n = 0;
    await for (final c in r2) {
      n += c.length;
    }
    // ignore: avoid_print
    print('piece status ${r2.statusCode}, $n bytes');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
