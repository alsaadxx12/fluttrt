import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/sports/data/services/aloula_service.dart';

/// Live probe (network): which way of asking, from dart:io's HttpClient,
/// Akamai in front of KSA Sports 1 accepts.
void main() {
  test('httpclient variants', () async {
    final url = await AloulaService().streamFor(AloulaService.rowId);
    expect(url, isNotNull);
    const ua = 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';
    Future<String> go(String label, void Function(HttpClient c, HttpClientRequest r) tweak) async {
      final c = HttpClient();
      try {
        final r = await c.getUrl(Uri.parse(url!));
        tweak(c, r);
        final res = await r.close();
        await res.drain<void>();
        return '$label -> ${res.statusCode}';
      } catch (e) {
        return '$label -> $e';
      } finally {
        c.close(force: true);
      }
    }
    Future<void> tryWith(String label, Map<String, String> h) async {
      // ignore: avoid_print
      print(await go(label, (c, r) => h.forEach(r.headers.set)));
    }
    await tryWith('UA only', {'User-Agent': ua});
    await tryWith('UA + Referer', {'User-Agent': ua, 'Referer': 'https://aloula.sba.sa/'});
    await tryWith('UA + Origin', {'User-Agent': ua, 'Origin': 'https://aloula.sba.sa'});
    await tryWith('UA + Accept json', {'User-Agent': ua, 'Accept': 'application/json'});
    await tryWith('UA + Accept */*', {'User-Agent': ua, 'Accept': '*/*'});
    await tryWith('UA + Origin + Referer + Accept json', {'User-Agent': ua, 'Origin': 'https://aloula.sba.sa', 'Referer': 'https://aloula.sba.sa/', 'Accept': 'application/json'});
    await tryWith('Accept json only', {'Accept': 'application/json'});
    final c2 = HttpClient()..userAgent = ua;
    final r2 = await c2.getUrl(Uri.parse(url!));
    final res2 = await r2.close();
    await res2.drain<void>();
    // ignore: avoid_print
    print('client.userAgent -> ${res2.statusCode}');
    // ignore: avoid_print
    print('uri as dart sends it: ${Uri.parse(url).toString().substring(0, 140)}');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
