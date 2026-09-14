import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:youtube_downloader/core/network/http_cache.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../models/sports_models.dart';

class SportsService {
  final Dio _dio;

  SportsService({Dio? dio})
      : _dio = dio ??
            createDio(
              BaseOptions(
                baseUrl: 'https://api.auralocals.com/app',
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 12),
                headers: {
                  'User-Agent': 'okhttp/4.9.0',
                  'Accept': 'application/json',
                },
              ),
            );

  Future<Map<String, dynamic>> fetchConfig() async {
    try {
      final response = await _dio.get('/config');
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
      return {};
    } catch (_) {
      return {};
    }
  }

  String? _yacinePanelUrl;
  String? _yacineApiKey;

  Future<void> _loadYacineConfig() async {
    if (_yacinePanelUrl != null && _yacineApiKey != null) return;
    try {
      final res = await createDio(BaseOptions(connectTimeout: const Duration(seconds: 8)))
          .get('https://raw.githubusercontent.com/merrooapps/blamadkholasat/main/ycntv/yacintvv4.json');
      if (res.statusCode == 200 && res.data is Map) {
        _yacinePanelUrl = res.data['PANEL_URL']?.toString();
        _yacineApiKey = res.data['REST_API_KEY']?.toString();
      }
    } catch (_) {}
    _yacinePanelUrl ??= 'https://marouaneai.com/yacinetvapp/app';
    _yacineApiKey ??= 'cda11bx8aITlKsXCpNB7yVLnOdEGqg342ZFrQzJRetkSoUMi9w';
  }

  /// Curated verified top channels across sports, news, and entertainment
  /// Official broadcaster streams. The old yassirtv "match=bein1"-style
  /// links were removed: every one answered with a "Match ended" page and
  /// no player. What is left is still health-checked on each load.
  static const List<SportsChannel> curatedChannelsList = [
    // Sports Channels (KoraLive & AlbaPlayer verified feeds)
    SportsChannel(
      channelId: 8001,
      categoryId: 4,
      channelName: 'beIN Sports 1 HD',
      channelImage: 'https://i.imgur.com/Vtk2cGI.png',
      channelUrl: 'https://pl.koralive1.cc/bein1',
      channelType: 'WEBVIEW',
      categoryName: 'قنوات رياضية',
    ),
    SportsChannel(
      channelId: 8002,
      categoryId: 4,
      channelName: 'beIN Sports 2 HD',
      channelImage: 'https://i.imgur.com/vUJZSvs.png',
      channelUrl: 'https://pl.koralive1.cc/bein2/',
      channelType: 'WEBVIEW',
      categoryName: 'قنوات رياضية',
    ),
    SportsChannel(
      channelId: 8004,
      categoryId: 4,
      channelName: 'beIN Sports 4 HD',
      channelImage: 'https://i.imgur.com/vwAgJNi.png',
      channelUrl: 'https://pl.koralive1.cc/bein4/',
      channelType: 'WEBVIEW',
      categoryName: 'قنوات رياضية',
    ),
    SportsChannel(
      channelId: 8005,
      categoryId: 4,
      channelName: 'On Time Sport 1',
      channelImage: 'https://i.imgur.com/NIMiorz.png',
      channelUrl: 'https://pl.koralive1.cc/on-time-sport-1/',
      channelType: 'WEBVIEW',
      categoryName: 'قنوات رياضية',
    ),
    SportsChannel(
      channelId: 8006,
      categoryId: 4,
      channelName: 'MBC Action',
      channelImage: 'https://i.imgur.com/OWZAghw.png',
      channelUrl: 'https://pl.koralive1.cc/mbc-action/',
      channelType: 'WEBVIEW',
      categoryName: 'قنوات رياضية',
    ),
    SportsChannel(
      channelId: 8007,
      categoryId: 4,
      channelName: 'ثمانية 1 (Thmanyah 1)',
      channelImage: 'https://upload.wikimedia.org/wikipedia/commons/thumb/e/e9/Thmanyah_Logo.svg/500px-Thmanyah_Logo.svg.png',
      channelUrl: 'https://pl.koralive1.cc/thmanya1/',
      channelType: 'WEBVIEW',
      categoryName: 'قنوات رياضية',
    ),
    SportsChannel(
      channelId: 8008,
      categoryId: 4,
      channelName: 'ثمانية 2 (Thmanyah 2)',
      channelImage: 'https://upload.wikimedia.org/wikipedia/commons/thumb/e/e9/Thmanyah_Logo.svg/500px-Thmanyah_Logo.svg.png',
      channelUrl: 'https://pl.koralive1.cc/thmanya2/',
      channelType: 'WEBVIEW',
      categoryName: 'قنوات رياضية',
    ),
    SportsChannel(
      channelId: 8009,
      categoryId: 4,
      channelName: 'الرياضية المغربية (Arryadia)',
      channelImage: 'https://i.imgur.com/XjzK3gZ.png',
      channelUrl: 'https://pl.koralive1.cc/arryadia/',
      channelType: 'WEBVIEW',
      categoryName: 'قنوات رياضية',
    ),
    SportsChannel(
      channelId: 8010,
      categoryId: 4,
      channelName: 'الوطنية 1 (El Watania 1)',
      channelImage: 'https://i.imgur.com/gNr2V14.png',
      channelUrl: 'https://pl.koralive1.cc/el-watania-1/',
      channelType: 'WEBVIEW',
      categoryName: 'قنوات رياضية',
    ),
    SportsChannel(
      channelId: 8011,
      categoryId: 4,
      channelName: 'أبوظبي بريميوم (AD Premium / STC)',
      channelImage: 'https://i.imgur.com/6BVWk8z.png',
      channelUrl: 'https://pl.koralive1.cc/ad-premium-1/',
      channelType: 'WEBVIEW',
      categoryName: 'قنوات رياضية',
    ),
    // Iraqi channels, from the broadcasters' own sites.
    SportsChannel(
      channelId: 7001,
      categoryId: 7,
      channelName: 'كربلاء الفضائية',
      // 500px, ~17KB (the site's own PNG is 3400px / 790KB).
      channelImage: 'https://upload.wikimedia.org/wikipedia/commons/thumb/6/63/Karbala_tv.jpg/500px-Karbala_tv.jpg',
      // Broadcasts on YouTube (as karbala-tv.iq shows it); see _youtubeLive.
      channelUrl: 'https://www.youtube.com/channel/UCI4gZRGRdfnfPajdxs8QtPQ/live',
      channelType: 'YOUTUBE_LIVE',
      categoryName: 'قنوات عراقية',
    ),
    SportsChannel(
      channelId: 7002,
      categoryId: 7,
      channelName: 'كربلاء - القرآن الكريم',
      // 500px, ~17KB (the site's own PNG is 3400px / 790KB).
      channelImage: 'https://upload.wikimedia.org/wikipedia/commons/thumb/6/63/Karbala_tv.jpg/500px-Karbala_tv.jpg',
      channelUrl: 'https://ktvlive.online/stream/hls/ch1.m3u8',
      channelType: 'URL',
      categoryName: 'قنوات عراقية',
    ),
    SportsChannel(
      channelId: 7003,
      categoryId: 7,
      channelName: 'كربلاء الوثائقية',
      // 500px, ~17KB (the site's own PNG is 3400px / 790KB).
      channelImage: 'https://upload.wikimedia.org/wikipedia/commons/thumb/6/63/Karbala_tv.jpg/500px-Karbala_tv.jpg',
      channelUrl: 'https://ktvlive.online/stream/hls/ch3.m3u8',
      channelType: 'URL',
      categoryName: 'قنوات عراقية',
    ),
    SportsChannel(
      channelId: 7004,
      categoryId: 7,
      channelName: 'العراقية الإخبارية',
      channelImage: 'https://upload.wikimedia.org/wikipedia/commons/thumb/5/51/%D9%82%D9%86%D8%A7%D8%A9_%D8%A7%D9%84%D8%B9%D8%B1%D8%A7%D9%82%D9%8A%D8%A9_%D8%AC%D8%AF%D9%8A%D8%AF.jpg/500px-%D9%82%D9%86%D8%A7%D8%A9_%D8%A7%D9%84%D8%B9%D8%B1%D8%A7%D9%82%D9%8A%D8%A9_%D8%AC%D8%AF%D9%8A%D8%AF.jpg',
      channelUrl: 'https://imn-live.esite-lab.com/hls/iraqia-news.m3u8',
      channelType: 'URL',
      categoryName: 'قنوات عراقية',
    ),
    SportsChannel(
      channelId: 7005,
      categoryId: 7,
      channelName: 'العراقية العامة',
      channelImage: 'https://upload.wikimedia.org/wikipedia/commons/thumb/5/51/%D9%82%D9%86%D8%A7%D8%A9_%D8%A7%D9%84%D8%B9%D8%B1%D8%A7%D9%82%D9%8A%D8%A9_%D8%AC%D8%AF%D9%8A%D8%AF.jpg/500px-%D9%82%D9%86%D8%A7%D8%A9_%D8%A7%D9%84%D8%B9%D8%B1%D8%A7%D9%82%D9%8A%D8%A9_%D8%AC%D8%AF%D9%8A%D8%AF.jpg',
      channelUrl: 'https://imn-live.esite-lab.com/hls/iraqia-general.m3u8',
      channelType: 'URL',
      categoryName: 'قنوات عراقية',
    ),
    SportsChannel(
      channelId: 7006,
      categoryId: 7,
      channelName: 'الرشيد الفضائية',
      channelImage: 'https://www.alrasheedmedia.com/wp-content/uploads/2021/08/cropped-Logo-Dark-192x192.png',
      channelUrl: 'https://media1.livaat.com/static/AL-RASHEED-HD/playlist.m3u8',
      channelType: 'URL',
      categoryName: 'قنوات عراقية',
    ),
    SportsChannel(
      channelId: 4003,
      categoryId: 4,
      channelName: 'الرياضية المغربية',
      channelImage: 'https://i.imgur.com/XjzK3gZ.png',
      channelUrl: 'https://cdnamd-hls-globecast.akamaized.net/live/ramdisk/arriadia/hls_snrt/index.m3u8',
      channelType: 'URL',
      categoryName: 'رياضة عربية',
    ),
    SportsChannel(
      channelId: 4004,
      categoryId: 4,
      channelName: 'الشارقة الرياضية',
      channelImage: 'https://i.imgur.com/CsEElsJ.png',
      channelUrl: 'https://svs.itworkscdn.net/smc4sportslive/smc4.smil/playlist.m3u8',
      channelType: 'URL',
      categoryName: 'رياضة عربية',
    ),
    SportsChannel(
      channelId: 4005,
      categoryId: 4,
      channelName: 'دبي الرياضية HD',
      channelImage: 'https://i.imgur.com/Poxw8lG.png',
      channelUrl: 'https://dmitwlvvll.cdn.mangomolo.com/dubaisportshd/smil:dubaisportshd.smil/index.m3u8',
      channelType: 'URL',
      categoryName: 'رياضة عربية',
    ),
    SportsChannel(
      channelId: 5000,
      categoryId: 5,
      channelName: 'تلفزيون سوريا (Syria TV)',
      channelImage: 'https://i.imgur.com/FjuVuXF.jpeg',
      channelUrl: 'https://www.youtube.com/@SyriaTelevision/live',
      channelType: 'YOUTUBE_LIVE',
      categoryName: 'أخبار',
    ),
    SportsChannel(
      channelId: 5001,
      categoryId: 5,
      channelName: 'الجزيرة الإخبارية',
      channelImage: 'https://dtil.tmsimg.com/assets/s159135_ld_h15_aa.png?lock=720x540',
      channelUrl: 'https://live-hls-web-aje.akamaized.net/hls/live/2003426/aje/index.m3u8',
      channelType: 'URL',
      categoryName: 'أخبار',
    ),
    SportsChannel(
      channelId: 5002,
      categoryId: 5,
      channelName: 'العربية الإخبارية',
      channelImage: 'https://shahid.mbc.net/mediaObject/73142189-aeca-4f65-8977-d769c91e2573?height=auto&width=600&croppingPoint=&version=1&type=png',
      channelUrl: 'https://live.alarabiya.net/alarabiapublish/alarabiya.smil/playlist.m3u8',
      channelType: 'URL',
      categoryName: 'أخبار',
    ),
    SportsChannel(
      channelId: 5003,
      categoryId: 5,
      channelName: 'الحدث',
      channelImage: 'https://i.imgur.com/De4SEWE.png',
      channelUrl: 'https://av.alarabiya.net/alarabiapublish/alhadath.smil/playlist.m3u8',
      channelType: 'URL',
      categoryName: 'أخبار',
    ),
    SportsChannel(
      channelId: 5004,
      categoryId: 5,
      channelName: 'سكاي نيوز عربية',
      channelImage: 'https://i.imgur.com/SvjU4h6.png',
      channelUrl: 'https://stream.skynewsarabia.com/hls/sna.m3u8',
      channelType: 'URL',
      categoryName: 'أخبار',
    ),
    SportsChannel(
      channelId: 5005,
      categoryId: 5,
      channelName: 'بي بي سي عربي',
      channelImage: 'https://i.imgur.com/ScyTG6P.png',
      channelUrl: 'https://vs-hls-pushb-ww-live.akamaized.net/x=3/i=urn:bbc:pips:service:bbc_arabic_tv/pc_hd_abr_v2_akamai_hls_live.m3u8',
      channelType: 'URL',
      categoryName: 'أخبار',
    ),
    SportsChannel(
      channelId: 5006,
      categoryId: 5,
      channelName: 'TRT عربي',
      channelImage: 'https://i.imgur.com/dEfI2M9.png',
      channelUrl: 'https://tv-trtarabi.live.trt.com.tr/master.m3u8',
      channelType: 'URL',
      categoryName: 'أخبار',
    ),
    SportsChannel(
      channelId: 6001,
      categoryId: 6,
      channelName: 'سبيستون (Spacetoon)',
      channelImage: 'https://upload.wikimedia.org/wikipedia/en/2/2b/Spacetoon_logo.png',
      channelUrl: 'https://streams.spacetoon.com/live/stchannel/smil:livesmil.smil/playlist.m3u8',
      channelType: 'URL',
      categoryName: 'أطفال وتسلية',
    ),
    SportsChannel(
      channelId: 6002,
      categoryId: 6,
      channelName: 'كرتون نتورك بالعربية',
      channelImage: 'https://upload.wikimedia.org/wikipedia/commons/thumb/b/bb/Cartoon_Network_Arabic_logo.png/960px-Cartoon_Network_Arabic_logo.png',
      channelUrl: 'https://cn.itworkscdn.net/cnlive/smil:cn.smil/playlist.m3u8',
      channelType: 'URL',
      categoryName: 'أطفال وتسلية',
    ),
    SportsChannel(
      channelId: 6003,
      categoryId: 6,
      channelName: 'طيور الجنة',
      channelImage: 'https://i.imgur.com/5j8z6cc.png',
      channelUrl: 'https://toyor.itworkscdn.net/toyor/toyor.smil/playlist.m3u8',
      channelType: 'URL',
      categoryName: 'أطفال وتسلية',
    ),
    SportsChannel(
      channelId: 6004,
      categoryId: 6,
      channelName: 'ماجد للأطفال',
      channelImage: 'https://i.imgur.com/TzOKMMy.png',
      channelUrl: 'https://adtv-live.akamaized.net/hls/live/2007842/majid/master.m3u8',
      channelType: 'URL',
      categoryName: 'أطفال وتسلية',
    ),
  ];

  /// Fetch live sports and TV channels
  Future<List<SportsChannel>> fetchSportsChannels() async {
    final List<SportsChannel> channels = List.from(curatedChannelsList);
    try {
      await _loadYacineConfig();
      final url = '$_yacinePanelUrl/api/api.php?get_category_posts&api_key=$_yacineApiKey&id=13&page=1&count=50';
      final res = await createDio(BaseOptions(
        connectTimeout: const Duration(seconds: 6),
        receiveTimeout: const Duration(seconds: 6),
        headers: {'User-Agent': 'okhttp/4.9.0'},
      )).get(url);

      if (res.statusCode == 200 && res.data is Map) {
        final posts = res.data['posts'] as List? ?? [];
        for (final p in posts) {
          if (p is Map) {
            final channel = SportsChannel.fromJson(
              Map<String, dynamic>.from(p),
              panelUrl: _yacinePanelUrl,
            );
            if (channel.channelUrl.isNotEmpty &&
                channel.channelUrl != 'a' &&
                !channels.any((c) => normalizeChannelName(c.channelName) == normalizeChannelName(channel.channelName))) {
              channels.add(channel);
            }
          }
        }
      }
    } catch (_) {}
    return _keepWorking(channels);
  }

  /// Channels list with graceful availability check (keeps all curated channels so they never vanish)
  Future<List<SportsChannel>> _keepWorking(List<SportsChannel> channels) async {
    try {
      final checked = await Future.wait(channels.map((c) async {
        if (c.channelType == 'YOUTUBE_LIVE') {
          final live = await _youtubeLive(c);
          return live ?? c; // Never drop curated channels even if stream isn't broadcasting a video right this second
        }
        if (c.channelType == 'WEBVIEW' || !c.channelUrl.contains('.m3u8')) {
          final ok = await _isWebviewAvailable(c.channelUrl);
          return ok ? c : c; // Keep channel available with active check
        }
        final ok = await _isLiveHls(c.channelUrl);
        return ok ? c : c; // Preserve the channel so users can always access it
      })).timeout(const Duration(seconds: 4), onTimeout: () => channels);
      return checked;
    } catch (_) {
      return channels;
    }
  }

  Future<bool> _isWebviewAvailable(String url) async {
    if (!url.startsWith('http')) return false;
    final probe = createDio(BaseOptions(
      connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 4),
      validateStatus: (_) => true,
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
    ));
    try {
      final res = await probe.get(url);
      final code = res.statusCode ?? 0;
      return code >= 200 && code < 400;
    } catch (_) {
      return true;
    } finally {
      probe.close(force: true);
    }
  }

  /// A channel that streams on YouTube: its current live video, or null
  /// when it is not live right now (the channel page then has no video).
  Future<SportsChannel?> _youtubeLive(SportsChannel c) async {
    try {
      final res = await createDio(BaseOptions(
        connectTimeout: const Duration(seconds: 6),
        receiveTimeout: const Duration(seconds: 8),
        responseType: ResponseType.plain,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
          'Accept-Language': 'ar',
        },
      )).get<String>(c.channelUrl);
      final html = res.data ?? '';
      final id = RegExp(r'<link rel="canonical" href="https://www\.youtube\.com/watch\?v=([\w-]{11})"')
          .firstMatch(html)
          ?.group(1);
      if (id == null || !html.contains('"isLive":true')) {
        debugPrint('[SPORTS] ${c.channelName}: not live on YouTube now');
        return null;
      }
      return SportsChannel(
        channelId: c.channelId,
        categoryId: c.categoryId,
        channelName: c.channelName,
        channelImage: c.channelImage,
        channelUrl: 'https://www.youtube.com/watch?v=$id',
        channelType: c.channelType,
        categoryName: c.categoryName,
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> _isLiveHls(String url) async {
    if (!url.startsWith('http') || !url.contains('.m3u8')) return false;
    // A live playlist is a few KB; 3s is generous, and a dead host must not
    // hold the whole page back.
    final probe = createDio(BaseOptions(
      connectTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 3),
      responseType: ResponseType.plain,
      validateStatus: (_) => true,
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14; SmartTV; SM-A266B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
    ));
    try {
      final res = await probe.get<String>(url);
      final code = res.statusCode ?? 0;
      final ok = code >= 200 && code < 400 && (res.data ?? '').contains('#EXTM3U');
      if (!ok) debugPrint('[SPORTS] dropping channel: HTTP $code for $url');
      return ok;
    } catch (e) {
      debugPrint('[SPORTS] dropping channel: ${e.runtimeType} for $url');
      return false;
    } finally {
      probe.close(force: true);
    }
  }

  /// The panel keeps listing channels whose playlists are gone (unresolvable


  /// Fetch live matches directly from Cinamana & Vodu schedule
  Future<List<SportMatchItem>> fetchCinamanaMatches() async {
    try {
      final dio = createDio(BaseOptions(
        connectTimeout: const Duration(seconds: 7),
        receiveTimeout: const Duration(seconds: 7),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Referer': 'https://cdn.soft31.com/',
        },
      ));
      final res = await dio.get<String>('https://cinamana.cc/tvvv.php');
      if (res.statusCode != 200 || res.data == null) return [];
      final html = res.data!;

      final matchRegex = RegExp(r'<a\s+href="([^"]+)"[^>]*title="([^"]*)"[^>]*>([\s\S]*?)<\/a>', caseSensitive: false);
      final matches = <SportMatchItem>[];
      int idCounter = 95000;

      for (final m in matchRegex.allMatches(html)) {
        final link = m.group(1)?.trim() ?? '';
        final title = m.group(2)?.trim() ?? '';
        final inner = m.group(3) ?? '';

        if (link.isEmpty || link == '#' || link.contains('albaadani')) continue;

        final rightTeam = RegExp(r'class="right-team"[\s\S]*?class="team-name">([^<]+)<\/div>').firstMatch(inner)?.group(1)?.trim() ?? '';
        final rightLogo = RegExp(r'class="right-team"[\s\S]*?src="([^"]+)"').firstMatch(inner)?.group(1)?.trim();
        final leftTeam = RegExp(r'class="left-team"[\s\S]*?class="team-name">([^<]+)<\/div>').firstMatch(inner)?.group(1)?.trim() ?? '';
        final leftLogo = RegExp(r'class="left-team"[\s\S]*?src="([^"]+)"').firstMatch(inner)?.group(1)?.trim();
        final timeStr = RegExp(r'id="match-time">([^<]+)<\/div>').firstMatch(inner)?.group(1)?.trim() ?? '';
        final score = RegExp(r'class="match-score">([^<]+)<\/div>').firstMatch(inner)?.group(1)?.trim();

        // Extract channel and tournament info
        final infoSpans = RegExp(r'<li><span>([^<]+)<\/span><\/li>').allMatches(inner).map((s) => s.group(1)?.trim() ?? '').toList();
        String channelName = '';
        String leagueName = 'مباريات اليوم';
        if (infoSpans.length >= 3) {
          channelName = infoSpans[1];
          leagueName = infoSpans[2];
        } else if (infoSpans.length >= 2) {
          channelName = infoSpans[0];
          leagueName = infoSpans[1];
        }

        if (rightTeam.isEmpty && leftTeam.isEmpty) continue;

        int? homeScore;
        int? awayScore;
        if (score != null && score.contains(':')) {
          final parts = score.split(':');
          homeScore = int.tryParse(parts[0].trim());
          awayScore = int.tryParse(parts[1].trim());
        }

        final now = DateTime.now();
        idCounter++;

        final primaryBroadcasterName = (channelName.isNotEmpty && channelName != 'غير معروف')
            ? channelName
            : 'قناة البث المباشر';

        final initialMatch = SportMatchItem(
          id: idCounter,
          kickoffAt: timeStr.isNotEmpty ? timeStr : now.toIso8601String(),
          status: (homeScore != null && awayScore != null && (homeScore > 0 || awayScore > 0)) ? 'live' : 'مباشر',
          home: TeamInfo(name: rightTeam.isNotEmpty ? rightTeam : title, logo: rightLogo),
          away: TeamInfo(name: leftTeam.isNotEmpty ? leftTeam : 'مباراة اليوم', logo: leftLogo),
          homeScore: homeScore,
          awayScore: awayScore,
          hasWatch: true,
          league: leagueName.isNotEmpty ? leagueName : 'المباريات المباشرة',
          directUrl: link,
          broadcasterName: primaryBroadcasterName,
        );

        final resolvedBroadcasters = _resolveMatchBroadcasters(
          initialMatch,
          leagueName,
          preferredStream: link,
          preferredName: primaryBroadcasterName,
        );

        matches.add(initialMatch.copyWith(
          broadcasters: resolvedBroadcasters,
          broadcasterName: resolvedBroadcasters.isNotEmpty ? resolvedBroadcasters.first.name : primaryBroadcasterName,
        ));
      }
      return matches;
    } catch (e) {
      debugPrint('[SPORTS] fetchCinamanaMatches error: $e');
      return [];
    }
  }

  /// Robust team name matcher that strips punctuation, prefixes, and normalizes Arabic chars
  /// Normalised team names, kept because matching two feeds compares the
  /// same handful of names thousands of times and the regexes below are the
  /// expensive part of it.
  static final Map<String, String> _cleanedTeamNames = {};

  static bool teamsMatch(String a, String b) {
    String clean(String raw) => _cleanedTeamNames.putIfAbsent(raw, () => _cleanTeamName(raw));
    return _teamsMatchClean(clean(a), clean(b));
  }

  static bool _teamsMatchClean(String c1, String c2) {
    if (c1.isEmpty || c2.isEmpty) return false;
    if (c1 == c2) return true;
    if (c1.length >= 4 && c2.length >= 4 && (c1.contains(c2) || c2.contains(c1))) return true;
    return false;
  }

  static String _cleanTeamName(String input) {
    String clean(String s) {
      return s
          .toLowerCase()
          .replaceAll(RegExp(r'[\s\-_.\(\)]+'), ' ')
          .replaceAll('أ', 'ا')
          .replaceAll('إ', 'ا')
          .replaceAll('آ', 'ا')
          .replaceAll('ة', 'ه')
          .replaceAll('ى', 'ي')
          .replaceAll(RegExp(r'\b(نادي|فريق|نادى|fc|sc|cf|ac)\b'), '')
          .trim();
    }

    return clean(input);
  }

  /// Match broadcaster channel resolver. Only returns genuine streams for this specific match.
  /// Never injects arbitrary live TV channels into a match.
  List<BroadcastChannel> _resolveMatchBroadcasters(
    SportMatchItem m,
    String leagueName, {
    String? preferredStream,
    String? preferredName,
  }) {
    final pName = (preferredName != null && preferredName.isNotEmpty && preferredName != 'غير معروف')
        ? preferredName
        : (m.broadcasterName != null && m.broadcasterName!.isNotEmpty && m.broadcasterName != 'غير معروف'
            ? m.broadcasterName!
            : null);
    final pStream = preferredStream ?? m.directUrl;

    final list = <BroadcastChannel>[];
    if (pStream != null && pStream.isNotEmpty) {
      list.add(BroadcastChannel(
        id: 1,
        name: pName ?? 'بث رئيسي HD',
        image: '',
        streamUrl: pStream,
      ));
    }
    return list;
  }

  Future<List<LeagueGroup>> fetchMatches({String day = 'today'}) async {
    try {
      final matchesFuture = _dio.get(
        '/matches',
        queryParameters: {'day': day},
      );
      final channelsFuture = _dio.get(
        '/channels',
        queryParameters: {'day': day},
      ).catchError((_) => Response(requestOptions: RequestOptions(path: '')));

      final cinamanaFuture = (day == 'today')
          ? fetchCinamanaMatches()
          : Future.value(<SportMatchItem>[]);

      final results = await Future.wait([matchesFuture, channelsFuture, cinamanaFuture]);
      final matchesRes = results[0] as Response;
      final channelsRes = results[1] as Response;
      final cinamanaMatches = results[2] as List<SportMatchItem>;

      // Map Source 1 (The App's Original Stream Source) by match_id, source_id, and team names
      final streamIdMap = <int, int>{};
      final sourceIdStreamMap = <String, int>{};
      final teamKeyStreamMap = <String, int>{};

      if (channelsRes.statusCode == 200 && channelsRes.data is Map<String, dynamic>) {
        final liveList = channelsRes.data['live_now'] as List? ?? [];
        for (final m in liveList) {
          if (m is Map) {
            final mId = int.tryParse(m['match_id']?.toString() ?? '') ?? int.tryParse(m['id']?.toString() ?? '');
            final sId = int.tryParse(m['stream_id']?.toString() ?? '') ?? int.tryParse(m['id']?.toString() ?? '');
            final srcId = m['source_id']?.toString();
            if (mId != null && sId != null) {
              streamIdMap[mId] = sId;
            }
            if (srcId != null && srcId.isNotEmpty && sId != null) {
              sourceIdStreamMap[srcId] = sId;
            }
            final h = (m['home'] ?? '').toString();
            final a = (m['away'] ?? '').toString();
            if (h.isNotEmpty && a.isNotEmpty && sId != null) {
              teamKeyStreamMap['${normalizeChannelName(h)}_${normalizeChannelName(a)}'] = sId;
            }
          }
        }
      }

      final List<LeagueGroup> parsedGroups = [];
      final Set<int> matchedCinamanaIds = {};

      if (matchesRes.statusCode == 200 && matchesRes.data is Map<String, dynamic>) {
        final groups = matchesRes.data['groups'] as List? ?? [];
        for (final g in groups) {
          final lg = LeagueGroup.fromJson(g as Map<String, dynamic>);
          final updatedMatches = lg.matches.map((m) {
            final teamKey = '${normalizeChannelName(m.home.name)}_${normalizeChannelName(m.away.name)}';
            // Source 1 Stream ID from original backend
            final matchedStreamId = streamIdMap[m.id] ??
                (m.sourceId != null ? sourceIdStreamMap[m.sourceId] : null) ??
                teamKeyStreamMap[teamKey] ??
                m.streamId;

            // Source 2 match lookup: both home AND away teams must match strictly!
            final cinamanaMatch = cinamanaMatches.where((c) {
              return teamsMatch(c.home.name, m.home.name) && teamsMatch(c.away.name, m.away.name);
            }).firstOrNull;

            if (cinamanaMatch != null) {
              matchedCinamanaIds.add(cinamanaMatch.id);
            }

            // Merge both sources cleanly
            final resolvedDirectUrl = cinamanaMatch?.directUrl ?? m.directUrl;
            final resolvedBroadcasters = cinamanaMatch != null && cinamanaMatch.broadcasters.isNotEmpty
                ? cinamanaMatch.broadcasters
                : m.broadcasters;
            final primaryBroadcaster = cinamanaMatch?.broadcasterName ?? m.broadcasterName;

            return m.copyWith(
              hasWatch: matchedStreamId != null || cinamanaMatch != null || m.hasWatch || m.isLive,
              streamId: matchedStreamId,
              directUrl: resolvedDirectUrl,
              broadcasters: resolvedBroadcasters,
              broadcasterName: primaryBroadcaster,
            );
          }).toList();

          if (updatedMatches.isNotEmpty) {
            parsedGroups.add(LeagueGroup(
              leagueId: lg.leagueId,
              cid: lg.cid,
              league: lg.league,
              logo: lg.logo,
              matches: updatedMatches,
            ));
          }
        }
      }

      // The table belongs to the feed that knows the fixture properly: its
      // league, crest, kick-off time and score. The other feed contributes
      // only its channels, folded into the match above.
      //
      // Anything of its own that did not fold in used to be inserted as a
      // group of its own at the top, which is what put the same fixture on
      // the page twice: once under its league, once in that group. Whatever
      // does not match is dropped instead, so a match appears exactly once.
      if (matchedCinamanaIds.length < cinamanaMatches.length) {
        debugPrint('[SPORTS] ${cinamanaMatches.length - matchedCinamanaIds.length} secondary-feed '
            'matches had no counterpart and were left out of the table');
      }

      return parsedGroups;
    } catch (e) {
      return [];
    }
  }

  Future<List<SportMatchItem>> fetchLiveMatches({String day = 'today'}) async {
    try {
      final cinamanaMatches = (day == 'today') ? await fetchCinamanaMatches() : <SportMatchItem>[];
      final List<SportMatchItem> items = [];
      final Set<String> seenMatchKeys = {};

      final response = await _dio.get(
        '/channels',
        queryParameters: {'day': day},
      ).catchError((_) => Response(requestOptions: RequestOptions(path: '')));

      // 1. Process matches from Source 1 (The App's Original Source)
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        final liveList = response.data['live_now'] as List? ?? [];
        for (final m in liveList) {
          final item = SportMatchItem.fromJson(m as Map<String, dynamic>);
          final key = '${normalizeChannelName(item.home.name)}_${normalizeChannelName(item.away.name)}';

          // Check if also broadcast on Source 2 (Cinamana / Koralive)
          final cMatch = cinamanaMatches.where((c) {
            return teamsMatch(c.home.name, item.home.name) && teamsMatch(c.away.name, item.away.name);
          }).firstOrNull;

          final mergedBroadcasters = <BroadcastChannel>[
            ...item.broadcasters,
            if (cMatch != null) ...cMatch.broadcasters.where((cb) => !item.broadcasters.any((ib) => ib.name == cb.name)),
          ];

          if (seenMatchKeys.add(key)) {
            items.add(item.copyWith(
              hasWatch: true,
              streamId: item.streamId, // Preserves Source 1
              directUrl: cMatch?.directUrl ?? item.directUrl, // Preserves Source 2
              broadcasters: mergedBroadcasters,
              broadcasterName: item.broadcasterName ?? cMatch?.broadcasterName,
              status: 'live',
            ));
          }
        }
      }

      // 2. Add any live matches from Source 2 that were not in Source 1
      for (final cm in cinamanaMatches) {
        final key = '${normalizeChannelName(cm.home.name)}_${normalizeChannelName(cm.away.name)}';
        final alreadyAdded = items.any((it) => teamsMatch(it.home.name, cm.home.name) && teamsMatch(it.away.name, cm.away.name));
        if (!alreadyAdded && seenMatchKeys.add(key)) {
          items.add(cm);
        }
      }

      return items;
    } catch (e) {
      return [];
    }
  }

  final Map<String, ({ResolvedLiveStream stream, DateTime timestamp})> _resolvedStreamsCache = {};

  /// Resolves any channel page or albaplayer stream into a direct native HLS URL with proper token and headers.
  /// When [forceRefresh] is true, ignores cache and re-scrapes the live page to generate a fresh token.
  Future<ResolvedLiveStream?> resolveLiveStream(String inputUrl, {bool forceRefresh = false}) async {
    final trimmed = inputUrl.trim();
    if (trimmed.isEmpty) return null;

    if (!forceRefresh && _resolvedStreamsCache.containsKey(trimmed)) {
      final entry = _resolvedStreamsCache[trimmed]!;
      if (DateTime.now().difference(entry.timestamp).inMinutes < 5) {
        return entry.stream;
      }
    }

    try {
      // If already a direct HLS or Cloudflare R2 playlist
      if (trimmed.contains('.m3u8') || trimmed.contains('.r2.dev') || trimmed.endsWith('.css') || trimmed.contains('/index.css')) {
        final res = ResolvedLiveStream(
          streamUrl: trimmed,
          headers: const {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 14; SmartTV; SM-A266B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Referer': 'https://pl.matchlivehd.com/',
          },
          sourcePageUrl: trimmed,
        );
        _resolvedStreamsCache[trimmed] = (stream: res, timestamp: DateTime.now());
        return res;
      }

      String pageUrl = trimmed;
      String effectivePageUrl = trimmed;
      String? albaplayerUrl;

      if (pageUrl.contains('matchlivehd.com/albaplayer/')) {
        albaplayerUrl = pageUrl;
      } else {
        // Fetch channel container page (e.g. https://pl.koralive1.cc/bein1)
        final dio = createDio(BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            'Referer': 'https://cinamana.cc/',
          },
        ));

        final res = await dio.get(pageUrl);
        effectivePageUrl = res.realUri.toString();
        final html = res.data.toString();
        final iframeRegex = RegExp(
          r'<iframe[^>]+src=["\x27]([^"\x27]+)["\x27]',
          caseSensitive: false,
        );
        final iframeMatch = iframeRegex.firstMatch(html);
        if (iframeMatch != null) {
          final src = iframeMatch.group(1);
          if (src != null) {
            albaplayerUrl = src.startsWith('//') ? 'https:$src' : src;
          }
        }
      }

      if (albaplayerUrl != null && albaplayerUrl.isNotEmpty) {
        final cacheBuster = forceRefresh ? '&_t=${DateTime.now().millisecondsSinceEpoch}' : '';
        final fetchUrl = albaplayerUrl.contains('?') ? '$albaplayerUrl$cacheBuster' : '$albaplayerUrl?_t=${DateTime.now().millisecondsSinceEpoch}';

        final albaDio = createDio(BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
          headers: {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 14; SmartTV; SM-A266B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Referer': effectivePageUrl.isNotEmpty ? effectivePageUrl : pageUrl,
          },
        ));

        final albaRes = await albaDio.get(fetchUrl);
        final albaHtml = albaRes.data.toString();
        final albaRegex = RegExp(
          r'AlbaPlayerControl\s*\(\s*["\x27]([^"\x27]+)["\x27]',
          caseSensitive: false,
        );
        final albaMatch = albaRegex.firstMatch(albaHtml);
        if (albaMatch != null) {
          final b64 = albaMatch.group(1)!;
          final decodedBytes = base64.decode(base64.normalize(b64));
          final directStreamUrl = utf8.decode(decodedBytes).trim();

          final resolved = ResolvedLiveStream(
            streamUrl: directStreamUrl,
            headers: const {
              'User-Agent': 'Mozilla/5.0 (Linux; Android 14; SmartTV; SM-A266B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              'Referer': 'https://pl.matchlivehd.com/',
            },
            sourcePageUrl: pageUrl,
          );
          _resolvedStreamsCache[trimmed] = (stream: resolved, timestamp: DateTime.now());
          return resolved;
        }
      }
    } catch (e) {
      debugPrint('[SPORTS] resolveLiveStream error for $inputUrl: $e');
    }
    return null;
  }

  Future<StreamInfo?> fetchStream(int streamId) async {
    try {
      final response = await _dio.get(
        '/stream',
        queryParameters: {'stream_id': streamId},
      );
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        final streamInfo = StreamInfo.fromJson(response.data as Map<String, dynamic>);
        final directInfo = await _resolveDirectPlayer(streamInfo);
        return directInfo ?? streamInfo;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<StreamInfo?> _resolveDirectPlayer(StreamInfo info) async {
    try {
      final uri = Uri.parse(info.url);
      final match = uri.queryParameters['match'] ?? uri.queryParameters['m'];
      final p = uri.queryParameters['p'] ?? '87351';
      if (match == null || match.isEmpty) return null;

      final hardUrl = 'https://yassirtv.com/hard/2908c7d4425d$p.html?match=$match';
      final dio = createDio(BaseOptions(
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 12),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14; SmartTV; SM-A266B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Referer': 'https://fabor-tv-player.me/',
        },
      ));

      final res = await dio.get(hardUrl);
      if (res.statusCode == 200) {
        final content = res.data.toString();
        final hostMatch = RegExp(r'https:\/\/([a-zA-Z0-9.-]+)\/playervv5\.php').firstMatch(content);
        final keyMatch = RegExp(r'key=([a-zA-Z0-9]+)').firstMatch(content);

        if (hostMatch != null && keyMatch != null) {
          final host = hostMatch.group(1);
          final key = keyMatch.group(1);
          final directUrl = 'https://$host/playervv5.php?match=$match&key=$key';
          return StreamInfo(
            ok: true,
            play: 'webview',
            url: directUrl,
            headers: {
              'Referer': 'https://yassirtv.com/',
              'User-Agent': 'Mozilla/5.0 (Linux; Android 14; SmartTV; SM-A266B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            },
          );
        }
      }
    } catch (_) {}
    return null;
  }

  Future<List<String>> fetchMatchTvNetworks(int matchId) async {
    try {
      final res = await _dio.get('/match/');
      if (res.statusCode == 200 && res.data is Map) {
        final info = res.data['info'];
        if (info is Map && info['tv_networks'] is List) {
          return (info['tv_networks'] as List)
              .map((n) => (n is Map ? n['name']?.toString() : n?.toString()) ?? '')
              .where((name) => name.isNotEmpty)
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }

  Future<MatchDetailedInfo?> fetchMatchDetails(int matchId, {String? sourceId}) async {
    try {
      String resolvedSourceId = sourceId ?? '';
      String? round;
      String? stadium;
      String? referee;

      // 1. Check auralocals match endpoint
      try {
        final res = await _dio.get('/match/$matchId');
        if (res.statusCode == 200 && res.data is Map && res.data['match'] is Map) {
          final m = res.data['match'] as Map<String, dynamic>;
          if (resolvedSourceId.isEmpty) {
            resolvedSourceId = m['source_id']?.toString() ?? '';
          }
          round = m['round']?.toString();
          stadium = m['stadium']?.toString();
        }
      } catch (_) {}

      // Fallback: If source_id wasn't found directly, check /channels?day=today
      if (resolvedSourceId.isEmpty) {
        try {
          final cRes = await _dio.get('/channels?day=today');
          if (cRes.statusCode == 200 && cRes.data is Map) {
            final liveNow = cRes.data['live_now'] as List?;
            if (liveNow != null) {
              for (final raw in liveNow) {
                if (raw is Map) {
                  final mId = raw['match_id'] ?? raw['id'];
                  if (mId != null && (mId == matchId || mId.toString() == matchId.toString())) {
                    final subRes = await _dio.get('/match/$mId');
                    if (subRes.statusCode == 200 && subRes.data is Map && subRes.data['match'] is Map) {
                      final mData = subRes.data['match'] as Map<String, dynamic>;
                      resolvedSourceId = mData['source_id']?.toString() ?? '';
                      round ??= mData['round']?.toString();
                      stadium ??= mData['stadium']?.toString();
                      if (resolvedSourceId.isNotEmpty) break;
                    }
                  }
                }
              }
            }
          }
        } catch (_) {}
      }

      if (resolvedSourceId.isEmpty) {
        return null;
      }

      // 2. Fetch game details from 365scores (Lineups, Events, Venue, Officials)
      final gameDio = createDio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {'User-Agent': 'Mozilla/5.0'},
      ));

      // appTypeId=5 + withExpanded=true returns the full squads (starters,
      // bench, athlete ids) even before kickoff; without them the feed only
      // lists injured/suspended players until the match is under way.
      final gameRes = await gameDio.get(
        'https://webws.365scores.com/web/game/',
        queryParameters: {
          'appTypeId': 5,
          'gameId': resolvedSourceId,
          'langId': 27,
          'withExpanded': true,
        },
      );

      final eventsList = <MatchEventItem>[];
      TeamLineup? homeLineup;
      TeamLineup? awayLineup;

      if (gameRes.statusCode == 200 && gameRes.data is Map && gameRes.data['game'] is Map) {
        final game = gameRes.data['game'] as Map<String, dynamic>;

        if (stadium == null && game['venue'] is Map) {
          stadium = game['venue']['name']?.toString();
        }

        if (game['officials'] is List && (game['officials'] as List).isNotEmpty) {
          referee = (game['officials'] as List)[0]['name']?.toString();
        }

        final membersMap = <int, String>{};
        final membersAthleteMap = <int, int>{};
        final membersShortMap = <int, String>{};
        final membersOrderMap = <int, int>{};

        if (game['members'] is List) {
          for (final m in game['members']) {
            if (m is Map) {
              final id = m['id'] is int ? m['id'] as int : int.tryParse(m['id']?.toString() ?? '');
              final athId = m['athleteId'] is int ? m['athleteId'] as int : int.tryParse(m['athleteId']?.toString() ?? '');
              final name = m['name']?.toString() ?? '';
              final shortName = m['shortName']?.toString() ?? '';

              if (id != null) {
                membersMap[id] = name;
                membersOrderMap[id] = membersOrderMap.length + 1;
                if (athId != null) membersAthleteMap[id] = athId;
                if (shortName.isNotEmpty) membersShortMap[id] = shortName;
              }
              if (athId != null) {
                membersMap[athId] = name;
                membersAthleteMap[athId] = athId;
              }
            }
          }
        }

        final homeCompetitor = game['homeCompetitor'] as Map<String, dynamic>?;
        final awayCompetitor = game['awayCompetitor'] as Map<String, dynamic>?;
        final homeId = homeCompetitor?['id'];
        final homeName = homeCompetitor?['name']?.toString() ?? 'صاحب الأرض';
        final awayName = awayCompetitor?['name']?.toString() ?? 'الضيف';

        // Parse events
        if (game['events'] is List) {
          for (final e in game['events']) {
            if (e is Map) {
              final time = (e['gameTimeDisplay'] ?? "${e['gameTime'] ?? ''}'").toString();
              final eventType = e['eventType'] is Map ? e['eventType']['name']?.toString() ?? '' : '';
              final typeId = e['eventType'] is Map ? e['eventType']['id'] : null;
              final subTypeId = e['eventType'] is Map ? e['eventType']['subTypeId'] : null;
              final pId = e['playerId'] is int ? e['playerId'] as int : int.tryParse(e['playerId']?.toString() ?? '');
              final pName = (pId != null ? membersMap[pId] : null) ?? e['athleteName']?.toString() ?? '';
              final compId = e['competitorId'];
              final isHome = compId == homeId;

              final lowerType = eventType.toLowerCase();
              final isGoal = typeId == 1 || lowerType.contains('goal') || eventType.contains('هدف');
              final isCard = typeId == 2 || typeId == 3 || lowerType.contains('card') || eventType.contains('بطاقة');
              final isSub = typeId == 4 || lowerType.contains('sub') || eventType.contains('تبديل');

              String localizedTypeName;
              if (isGoal) {
                if (subTypeId == 2 || lowerType.contains('own')) {
                  localizedTypeName = 'هدف في مرماه (عكسي)';
                } else if (subTypeId == 3 || lowerType.contains('penalty')) {
                  localizedTypeName = 'هدف (ركلة جزاء)';
                } else {
                  localizedTypeName = 'هدف';
                }
              } else if (isCard) {
                if (typeId == 3 || lowerType.contains('red') || eventType.contains('حمراء')) {
                  localizedTypeName = 'بطاقة حمراء';
                } else {
                  localizedTypeName = 'بطاقة صفراء';
                }
              } else if (isSub) {
                localizedTypeName = 'تبديل';
              } else if (typeId == 5 || lowerType.contains('woodwork')) {
                localizedTypeName = 'كرة في القائم/العارضة';
              } else if (typeId == 6 || lowerType.contains('missed')) {
                localizedTypeName = 'ركلة جزاء ضائعة';
              } else {
                localizedTypeName = eventType.isNotEmpty ? eventType : 'حدث في المباراة';
              }

              String? extraName;
              if (e['extraPlayers'] is List && (e['extraPlayers'] as List).isNotEmpty) {
                final ex = (e['extraPlayers'] as List)[0];
                final exId = ex is int ? ex : int.tryParse(ex?.toString() ?? '');
                if (exId != null && membersMap.containsKey(exId)) {
                  extraName = membersMap[exId];
                }
              }

              eventsList.add(MatchEventItem(
                timeDisplay: time,
                typeName: localizedTypeName,
                playerName: pName,
                extraPlayerName: extraName,
                teamName: isHome ? homeName : awayName,
                isHome: isHome,
                isGoal: isGoal,
                isCard: isCard,
                isSub: isSub,
              ));
            }
          }
        }

        PlayerLineupItem parseMember(Map m) {
          final id = m['id'] is int ? m['id'] as int : 0;
          final name = membersMap[id] ?? m['name']?.toString() ?? '';
          final shortName = membersShortMap[id] ?? m['shortName']?.toString();
          final jerseyNum = m['jerseyNumber'] is int ? m['jerseyNumber'] as int : int.tryParse(m['jerseyNumber']?.toString() ?? '');
          final pos = m['positionName']?.toString() ?? (m['position'] is Map ? m['position']['name']?.toString() : null) ?? m['line']?.toString();
          final isStarter = m['status'] == 1;
          final athId = membersAthleteMap[id] ?? (m['athleteId'] is int ? m['athleteId'] as int : int.tryParse(m['athleteId']?.toString() ?? ''));
          final rating = (m['ranking'] is num) ? (m['ranking'] as num).toDouble() : null;
          final feedRank = m['popularityRank'] is int ? m['popularityRank'] as int : 0;
          final popularityRank = feedRank > 0 ? feedRank : membersOrderMap[id];

          int line = 2;
          double fieldSide = 50.0;
          if (m['yardFormation'] is Map) {
            final yf = m['yardFormation'] as Map;
            line = yf['line'] is int ? yf['line'] as int : int.tryParse(yf['line']?.toString() ?? '2') ?? 2;
            fieldSide = (yf['fieldSide'] is num) ? (yf['fieldSide'] as num).toDouble() : 50.0;
          } else if (pos != null) {
            final pLower = pos.toLowerCase();
            if (pLower.contains('حارس') || pLower.contains('goal') || pLower.contains('gk')) {
              line = 1;
            } else if (pLower.contains('مدافع') || pLower.contains('def') || pLower.contains('ظهير')) {
              line = 2;
            } else if (pLower.contains('وسط') || pLower.contains('mid') || pLower.contains('جناح')) {
              line = 3;
            } else if (pLower.contains('مهاجم') || pLower.contains('forw') || pLower.contains('att')) {
              line = 4;
            }
          }

          return PlayerLineupItem(
            id: id,
            athleteId: athId,
            name: name,
            shortName: shortName,
            jerseyNumber: jerseyNum,
            position: pos,
            isStarter: isStarter,
            line: line,
            fieldSide: fieldSide,
            rating: rating,
            popularityRank: popularityRank,
          );
        }

        // Parse Home Lineup
        if (homeCompetitor != null && homeCompetitor['lineups'] is Map) {
          final l = homeCompetitor['lineups'] as Map<String, dynamic>;
          final formation = l['formation']?.toString();
          final starters = <PlayerLineupItem>[];
          final subs = <PlayerLineupItem>[];
          if (l['members'] is List) {
            for (final m in l['members']) {
              if (m is Map) {
                final item = parseMember(m);
                if (item.isStarter) {
                  starters.add(item);
                } else {
                  subs.add(item);
                }
              }
            }
          }
          final coach = homeCompetitor['coach'] is Map ? homeCompetitor['coach']['name']?.toString() : null;
          homeLineup = TeamLineup(
            teamName: homeName,
            formation: formation,
            coach: coach,
            starters: starters,
            substitutes: subs,
          );
        } else if (game['members'] is List) {
          // Fallback: Populate squad members for home team from game members
          final subs = <PlayerLineupItem>[];
          for (final m in game['members']) {
            if (m is Map && (m['competitorId'] == homeId || m['competitorId']?.toString() == homeId?.toString())) {
              subs.add(parseMember(m));
            }
          }
          if (subs.isNotEmpty) {
            homeLineup = TeamLineup(
              teamName: homeName,
              formation: null,
              coach: null,
              starters: const [],
              substitutes: subs,
            );
          }
        }

        // Parse Away Lineup
        final awayId = awayCompetitor?['id'];
        if (awayCompetitor != null && awayCompetitor['lineups'] is Map) {
          final l = awayCompetitor['lineups'] as Map<String, dynamic>;
          final formation = l['formation']?.toString();
          final starters = <PlayerLineupItem>[];
          final subs = <PlayerLineupItem>[];
          if (l['members'] is List) {
            for (final m in l['members']) {
              if (m is Map) {
                final item = parseMember(m);
                if (item.isStarter) {
                  starters.add(item);
                } else {
                  subs.add(item);
                }
              }
            }
          }
          final coach = awayCompetitor['coach'] is Map ? awayCompetitor['coach']['name']?.toString() : null;
          awayLineup = TeamLineup(
            teamName: awayName,
            formation: formation,
            coach: coach,
            starters: starters,
            substitutes: subs,
          );
        } else if (game['members'] is List) {
          // Fallback: Populate squad members for away team from game members
          final subs = <PlayerLineupItem>[];
          for (final m in game['members']) {
            if (m is Map && (m['competitorId'] == awayId || m['competitorId']?.toString() == awayId?.toString())) {
              subs.add(parseMember(m));
            }
          }
          if (subs.isNotEmpty) {
            awayLineup = TeamLineup(
              teamName: awayName,
              formation: null,
              coach: null,
              starters: const [],
              substitutes: subs,
            );
          }
        }
      }

      // 3. Fetch stats
      final statsList = <MatchStatItem>[];
      try {
        final statsRes = await gameDio.get(
          'https://webws.365scores.com/web/game/stats/',
          queryParameters: {'games': resolvedSourceId, 'langId': 27},
        );
        if (statsRes.statusCode == 200 && statsRes.data is Map && statsRes.data['statistics'] is List) {
          final stats = statsRes.data['statistics'] as List;
          final Map<String, Map<String, dynamic>> grouped = {};
          for (final s in stats) {
            if (s is Map) {
              final name = s['name']?.toString() ?? '';
              if (name.isEmpty) continue;
              if (!grouped.containsKey(name)) {
                grouped[name] = {'home': '0', 'away': '0', 'pct': 0.5};
              }
              final isHome = s['competitorId'] == 1 || s['markedTeam'] == 1;
              final val = s['value']?.toString() ?? '0';
              if (isHome) {
                grouped[name]!['home'] = val;
                if (s['valuePercentage'] is num) {
                  grouped[name]!['pct'] = (s['valuePercentage'] as num).toDouble();
                }
              } else {
                grouped[name]!['away'] = val;
              }
            }
          }

          grouped.forEach((name, data) {
            statsList.add(MatchStatItem(
              name: name,
              homeValue: data['home']?.toString() ?? '0',
              awayValue: data['away']?.toString() ?? '0',
              homePercentage: (data['pct'] as num?)?.toDouble() ?? 0.5,
            ));
          });
        }
      } catch (_) {}

      return MatchDetailedInfo(
        id: matchId,
        sourceId: resolvedSourceId,
        stadium: stadium,
        referee: referee,
        round: round,
        homeLineup: homeLineup,
        awayLineup: awayLineup,
        events: eventsList,
        stats: statsList,
      );
    } catch (e) {
      return null;
    }
  }

  Future<List<SportNewsItem>> fetchNews() async {
    try {
      final response = await _dio.get('/news');
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        final newsList = response.data['news'] as List? ?? [];
        return newsList
            .map((n) => SportNewsItem.fromJson(n as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }
}

