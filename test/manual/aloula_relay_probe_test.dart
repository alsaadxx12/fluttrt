import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/casting/services/local_stream_server.dart';
import 'package:youtube_downloader/features/sports/data/services/aloula_service.dart';

/// Live probe (network): the whole path the phone takes for KSA Sports 1 -
/// a fresh address, the loopback relay, and the first bytes of the joined
/// stream the player would read.
void main() {
  test('ksa sports 1 through the relay', () async {
    final url = await AloulaService().streamFor(AloulaService.rowId);
    expect(url, isNotNull);
    final relay = LocalStreamServer(cacheDir: Directory.systemTemp.createTempSync('relay_'));
    final served = await relay.publish(url!, contentType: 'application/x-mpegURL', headers: AloulaService.cdnHeaders, loopback: true);
    // ignore: avoid_print
    print('served: $served');
    expect(served, isNotNull);
    final client = HttpClient();
    final res = await (await client.getUrl(Uri.parse(served!))).close();
    // ignore: avoid_print
    print('status ${res.statusCode} type ${res.headers.value('content-type')}');
    var got = 0;
    int? first;
    await for (final chunk in res) {
      first ??= chunk.isEmpty ? null : chunk.first;
      got += chunk.length;
      if (got > 3 * 1024 * 1024) break;
    }
    // ignore: avoid_print
    print('read $got bytes, first byte 0x${first?.toRadixString(16)} (0x47 is a transport-stream sync byte)');
    client.close(force: true);
    await relay.stop();
    expect(got, greaterThan(100 * 1024));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
