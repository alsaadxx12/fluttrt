import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/cinemana/data/cinemana_franchises.dart';
import 'package:youtube_downloader/features/cinemana/data/services/cinemana_service.dart';

/// Live probe (network): the pictures a franchise page asks for, and how
/// each answers - the grey tiles on the Saw page are the ones to explain.
void main() {
  test('saw franchise pictures', () async {
    final franchise = FilmFranchise.all.firstWhere((f) => f.name == 'المنشار');
    final films = await CinemanaService().fetchFranchise(franchise);
    final client = HttpClient();
    for (final f in films) {
      final card = f.imageForWidth(175 * 2.75);
      String status;
      try {
        final req = await client.getUrl(Uri.parse(card));
        req.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (Linux; Android 14) Chrome/124.0.0.0 Mobile Safari/537.36');
        final res = await req.close();
        var n = 0;
        await for (final c in res) {
          n += c.length;
        }
        status = '${res.statusCode} ${res.headers.value('content-type')} $n bytes';
      } catch (e) {
        status = 'ERR $e';
      }
      // ignore: avoid_print
      print('${f.year} ${f.enTitle.padRight(28)} medium=${f.imgMediumUrl != null} full=${f.imgUrl != null} thumb=${f.imgThumbUrl != null} card=${card.split('/').last.substring(0, card.split('/').last.length.clamp(0, 40))} -> $status');
    }
    client.close(force: true);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
