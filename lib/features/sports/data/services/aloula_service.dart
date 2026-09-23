import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../../../casting/services/local_stream_server.dart';
import 'alkass_service.dart';

/// KSA Sports 1 («الرياضية 1»), from the Saudi Broadcasting Authority's
/// own platform, aloula.sba.sa.
///
/// The site runs on Faulio: one call lists the channels, another hands a
/// channel's stream - an HLS address on Akamai carrying a token that lasts
/// about two minutes. Only the first playlist needs it: the renditions it
/// names carry a day-long token of their own. So the address is fetched
/// the moment a channel is opened, and the sharpest rendition is handed
/// over directly, so the picture is 1080p from the first second rather
/// than climbing to it.
class AloulaService {
  AloulaService({Dio? dio}) : _dio = dio ?? Dio();

  static const String api = 'https://aloula.faulio.com/api';

  /// The channel's id on the platform, and how the site names it.
  static const int sports1Id = 9;
  static const String sports1Name = 'riyadiya1';

  /// A stable id for the row, well clear of Alkass's own numbers.
  static const int rowId = 900000 + sports1Id;

  static const String logo =
      'https://aloula.faulio.com/storage/mediagallery/36/f0/fullhd_7b5a1c62d4c0785dff72d85e41ade22b9478258b.png';

  static const String pageUrl = 'https://aloula.sba.sa/live/$sports1Name';

  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
    'Origin': 'https://aloula.sba.sa',
    'Referer': 'https://aloula.sba.sa/',
    'Accept': 'application/json',
  };

  final Dio _dio;

  /// The channel as the row shows it. The address is left empty: it is
  /// fetched when the channel is opened, since the one the platform hands
  /// out lasts only minutes.
  AlkassChannel sports1() => const AlkassChannel(
        id: rowId,
        title: 'الرياضية 1',
        webname: sports1Name,
        logo: logo,
        streamUrl: '',
        isPremium: false,
        sorting: 50,
        page: pageUrl,
        // The address comes with opening; there is none to check yet.
        alwaysFree: true,
      );

  /// A fresh address for the channel, the sharpest rendition of it: null
  /// when the platform gives none.
  Future<String?> streamFor(int id) async {
    final channel = id == rowId ? sports1Id : id;
    try {
      final res = await _dio.get<dynamic>(
        '$api/v1.1/channels/$channel/player/live',
        options: Options(
          responseType: ResponseType.json,
          receiveTimeout: const Duration(seconds: 12),
          headers: _headers,
        ),
      );
      final data = res.data;
      final streams = data is Map ? data['streams'] : null;
      final hls = streams is Map ? streams['hls']?.toString() : null;
      if (hls == null || hls.isEmpty) {
        debugPrint('[aloula] no hls address for channel $channel');
        return null;
      }
      final chosen = await sharpest(hls) ?? hls;
      debugPrint('[aloula] channel $channel -> ${chosen.split("?").first}');
      // Said in the log, so a set or a phone that cannot play it can be
      // told apart from an address that never answered.
      unawaited(_check(chosen));
      return chosen;
    } catch (e) {
      debugPrint('[aloula] stream: $e');
      return null;
    }
  }

  /// Fetches [url] once and logs how it answered.
  Future<void> _check(String url) async {
    try {
      final res = await _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 12),
          headers: _headers,
          validateStatus: (_) => true,
        ),
      );
      final body = res.data ?? '';
      final first = body.startsWith('#EXTM3U') ? 'a playlist' : body.replaceAll(RegExp('<[^>]*>'), ' ').trim();
      debugPrint('[aloula] check: ${res.statusCode}, ${body.length} chars, '
          '${first.length > 80 ? first.substring(0, 80) : first}');
    } catch (e) {
      debugPrint('[aloula] check: $e');
    }
  }

  /// The address of the sharpest rendition in the master playlist at
  /// [master], when the renditions carry a token of their own and so can
  /// be fetched without the master's; null otherwise, and the master is
  /// used as it is.
  Future<String?> sharpest(String master) async {
    try {
      final res = await _dio.get<String>(
        master,
        options:
            Options(responseType: ResponseType.plain, receiveTimeout: const Duration(seconds: 12), headers: _headers),
      );
      final picked = pickSharpest(res.data ?? '', master);
      if (picked == null) debugPrint('[aloula] master lists no tokenised rendition; the master goes as it is');
      return picked;
    } catch (e) {
      debugPrint('[aloula] master: $e');
      return null;
    }
  }

  /// The rendition with the most bandwidth in [text], resolved against
  /// [master]; null when the playlist lists none, or when the one found
  /// carries no token of its own.
  static String? pickSharpest(String text, String master) {
    final lines = text.split('\n').map((l) => l.trim()).toList();
    String? best;
    var bestBandwidth = -1;
    for (var i = 0; i < lines.length - 1; i++) {
      if (!lines[i].startsWith('#EXT-X-STREAM-INF:')) continue;
      final m = RegExp(r'BANDWIDTH=(\d+)').firstMatch(lines[i]);
      final bandwidth = int.tryParse(m?.group(1) ?? '') ?? 0;
      var j = i + 1;
      while (j < lines.length && (lines[j].isEmpty || lines[j].startsWith('#'))) {
        j++;
      }
      if (j >= lines.length) break;
      if (bandwidth > bestBandwidth) {
        bestBandwidth = bandwidth;
        best = lines[j];
      }
    }
    if (best == null) return null;
    // Resolved by hand: Uri.resolve would rewrite the token's «%2f» as
    // «%2F», and Akamai, which signed the exact text, answers 403.
    final absolute = LocalStreamServer.resolveAgainst(master, best);
    // Without a token of its own the rendition needs the master's, which
    // is about to run out; the master is the safer address then.
    if (!absolute.contains('hdntl=') && !absolute.contains('hdnts=')) return null;
    return absolute;
  }
}
