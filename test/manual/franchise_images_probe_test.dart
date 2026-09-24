import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/cinemana/data/cinemana_franchises.dart';
import 'package:youtube_downloader/features/cinemana/data/services/cinemana_service.dart';

/// Live probe (network): the pictures a franchise page asks for, saved to
/// disk so they can be looked at - the grey tiles are the ones to explain.
void main() {
  test('franchise pictures', () async {
    final out = Directory('${Directory.systemTemp.path}/fr_probe')..createSync(recursive: true);
    final client = HttpClient();
    for (final name in ['المنشار', 'أكاديمية بطلي', 'Avatar', 'أفاتار']) {
      final matches = FilmFranchise.all.where((f) => f.name == name).toList();
      if (matches.isEmpty) {
        // ignore: avoid_print
        print('== no franchise named $name');
        continue;
      }
      final films = await CinemanaService().fetchFranchise(matches.first);
      // ignore: avoid_print
      print('== $name: ${films.length} items');
      for (final f in films) {
        final card = f.imageForWidth(175 * 2.75);
        final thumb = f.imgThumbUrl ?? '';
        Future<String> fetch(String url, String tag) async {
          if (url.isEmpty) return '$tag=-';
          try {
            final req = await client.getUrl(Uri.parse(url));
            req.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (Linux; Android 14) Chrome/124.0.0.0 Mobile Safari/537.36');
            final res = await req.close();
            final bytes = <int>[];
            await for (final c in res) {
              bytes.addAll(c);
            }
            final file = File('${out.path}/${f.id}_$tag.${res.headers.value('content-type')?.split('/').last ?? 'bin'}');
            file.writeAsBytesSync(bytes);
            return '$tag=${res.statusCode}/${bytes.length}B';
          } catch (e) {
            return '$tag=ERR';
          }
        }
        // ignore: avoid_print
        print('  ${f.year} ${f.enTitle.padRight(34).substring(0, 34)} id=${f.id} ${await fetch(card, 'card')} ${await fetch(thumb, 'thumb')} sameUrl=${card == thumb}');
      }
    }
    client.close(force: true);
    // ignore: avoid_print
    print('saved under ${out.path}');
  }, timeout: const Timeout(Duration(minutes: 4)));
}
