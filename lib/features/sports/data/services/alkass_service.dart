import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// One of Alkass's channels, as its own site lists them.
class AlkassChannel {
  const AlkassChannel({
    required this.id,
    required this.title,
    required this.webname,
    required this.logo,
    required this.streamUrl,
    required this.isPremium,
    required this.sorting,
    this.page,
    this.alwaysFree = false,
  });

  final int id;

  /// «Alkass 1», «shoof1».
  final String title;

  /// The short name the site addresses the channel by: «one», «shoof1».
  final String webname;

  /// The channel's mark, white on transparent.
  final String logo;

  /// The HLS address, carrying a token that runs out (see [expiresAt]).
  final String streamUrl;

  /// Needs a Shoof Premium subscription on their side: the address given
  /// is a «blocked» clip, not the channel.
  final bool isPremium;

  final int sorting;

  /// The page the channel is opened at, when it is not one of Alkass's:
  /// what tells the player where to ask for a fresh address.
  final String? page;

  /// Free without an address in hand: one whose address is fetched only
  /// on opening, because the one the platform hands out lasts minutes.
  final bool alwaysFree;

  bool get isFree => alwaysFree || (!isPremium && streamUrl.isNotEmpty);

  /// When the address stops working, as the token in it says; null when
  /// the address carries no token.
  DateTime? get expiresAt => AlkassService.expiryOf(streamUrl);

  /// The address the site opens the channel at.
  String get pageUrl => page ?? 'https://shoof.alkass.net/live-tv?ch=$webname';

  /// The name shown on a card: «الكأس 1», «شوف 1», «الرياضية 1».
  String get arabicTitle {
    if (page != null) return title.replaceFirst(RegExp(r'^قناة\s+'), '').trim();
    final m = RegExp(r'^Alkass\s+(\d+)$', caseSensitive: false).firstMatch(title.trim());
    if (m != null) return 'الكأس ${m.group(1)}';
    final s = RegExp(r'^shoof\s*(\d+)$', caseSensitive: false).firstMatch(title.trim());
    if (s != null) return 'شوف ${s.group(1)}';
    return title;
  }
}

/// Alkass's free channels, from the same endpoint its site uses.
///
/// The site (shoof.alkass.net) reads its channel list from one JSON answer
/// that carries a tokenised HLS address per channel; the token lasts a
/// quarter of an hour, but only the first playlist needs it - the pieces
/// carry a day-long token of their own - so a stream started in time keeps
/// going. Premium channels come back with a «blocked» clip in place of an
/// address and are left out here.
class AlkassService {
  AlkassService({Dio? dio}) : _dio = dio ?? Dio();

  static const String endpoint = 'https://shoofapi.alkass.net/Shoof/live.php';

  /// No app-wide cache: an address older than its token is no address.
  final Dio _dio;

  List<AlkassChannel>? _last;
  DateTime? _lastAt;

  /// The free channels, in the site's order. A list fetched within the
  /// last few minutes is reused: its tokens are still good.
  Future<List<AlkassChannel>> fetchFree({bool fresh = false}) async {
    final last = _last;
    final lastAt = _lastAt;
    if (!fresh && last != null && lastAt != null && DateTime.now().difference(lastAt) < const Duration(minutes: 5)) {
      return last;
    }
    try {
      final res = await _dio.get<dynamic>(
        endpoint,
        options: Options(
          responseType: ResponseType.json,
          receiveTimeout: const Duration(seconds: 12),
          sendTimeout: const Duration(seconds: 12),
          headers: const {
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
            'Referer': 'https://shoof.alkass.net/',
            'Origin': 'https://shoof.alkass.net',
          },
        ),
      );
      final data = res.data;
      final channels = parse(data is List ? data : const []);
      _last = channels;
      _lastAt = DateTime.now();
      debugPrint('[alkass] ${channels.length} free channels');
      return channels;
    } catch (e) {
      debugPrint('[alkass] channels: $e');
      // Whatever was fetched before is better than nothing, tokens or not.
      return last ?? const [];
    }
  }

  /// A fresh address for the channel with [id], for the moment it is
  /// opened; null when the channel is not offered free right now.
  Future<String?> streamFor(int id) async {
    for (final c in await fetchFree(fresh: true)) {
      if (c.id == id) return c.streamUrl;
    }
    return null;
  }

  /// The free channels in [json], in the site's order.
  static List<AlkassChannel> parse(List<dynamic> json) {
    final out = <AlkassChannel>[];
    for (final row in json) {
      if (row is! Map) continue;
      final premium = row['is_premium'];
      final isPremium = premium is num ? premium != 0 : (premium?.toString() ?? '0') != '0';
      final url = (row['body'] ?? '').toString().trim();
      final channel = AlkassChannel(
        id: (row['id'] as num?)?.toInt() ?? 0,
        title: (row['title'] ?? '').toString().trim(),
        webname: (row['webname'] ?? '').toString().trim(),
        logo: (row['image'] ?? '').toString().trim(),
        // A premium channel's «address» is a clip saying so; not a stream.
        streamUrl: isPremium || !url.contains('.m3u8') ? '' : url,
        isPremium: isPremium,
        sorting: (row['Sorting'] as num?)?.toInt() ?? 999,
      );
      // «Shoof» is the site's own promotional channel, not one of the
      // Alkass channels; the site keeps it out of its guide, and so does
      // the row.
      if (channel.webname.toLowerCase().startsWith('shoof')) continue;
      if (channel.isFree && channel.id > 0) out.add(channel);
    }
    out.sort((a, b) => a.sorting.compareTo(b.sorting));
    return out;
  }

  /// When the token in [url] runs out (`exp=<unix seconds>`), or null.
  static DateTime? expiryOf(String url) {
    final m = RegExp(r'exp=(\d{9,11})').firstMatch(url);
    if (m == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(int.parse(m.group(1)!) * 1000, isUtc: true);
  }
}
