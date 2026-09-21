import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';
import '../models/asia2tv_models.dart';

class Asia2TvService {
  static const String baseUrl = 'https://ww1.asia2tv.pw';

  static const Map<String, String> defaultHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': '$baseUrl/',
    'Accept-Language': 'ar,en-US;q=0.9,en;q=0.8',
  };

  final http.Client _client;

  Asia2TvService({http.Client? client}) : _client = client ?? http.Client();

  void dispose() {
    _client.close();
  }

  // ===========================================================================
  // 1. Listings & Categories
  // ===========================================================================

  /// Fetches latest episodes from category/new-episodes/
  Future<List<Asia2TvItem>> fetchLatestEpisodes({int page = 1}) async {
    return fetchCategory(Asia2TvCategory.newEpisodes, page: page);
  }

  /// Fetches items from a specific category
  Future<List<Asia2TvItem>> fetchCategory(Asia2TvCategory category, {int page = 1}) async {
    final String url;
    if (page <= 1) {
      url = '$baseUrl/${category.path}';
    } else {
      url = '$baseUrl/${category.path}page/$page/';
    }
    return _fetchAndParseList(url, defaultCategory: category.label);
  }

  /// Searches the Asian drama catalogue
  Future<List<Asia2TvItem>> search(String query, {int page = 1}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return const [];
    final encoded = Uri.encodeQueryComponent(cleanQuery);
    final String url;
    if (page <= 1) {
      url = '$baseUrl/?s=$encoded';
    } else {
      url = '$baseUrl/page/$page/?s=$encoded';
    }
    return _fetchAndParseList(url);
  }

  /// Whether [item] is worth showing.
  ///
  /// A listing page carries entries whose poster never resolved and entries
  /// with no link to open. Both render as an empty grey card that does
  /// nothing when tapped, so they are dropped here - at the one point every
  /// listing passes through - rather than in each row.
  static bool isPlayable(Asia2TvItem item) =>
      item.posterUrl.trim().isNotEmpty &&
      item.url.trim().isNotEmpty &&
      item.title.trim().isNotEmpty;

  /// Internal parser for category / search listing pages
  Future<List<Asia2TvItem>> _fetchAndParseList(String url, {String? defaultCategory}) async {
    try {
      final response = await _client
          .get(Uri.parse(url), headers: defaultHeaders)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint('[asian-catalogue] HTTP error ${response.statusCode} for $url');
        return const [];
      }

      final html = response.body;
      return parseListHtml(html, defaultCategory: defaultCategory);
    } catch (e, st) {
      debugPrint('[asian-catalogue] Error fetching list from $url: $e\n$st');
      return const [];
    }
  }

  /// Pure parser helper for listing HTML
  List<Asia2TvItem> parseListHtml(String html, {String? defaultCategory}) {
    final List<Asia2TvItem> items = [];
    final seenUrls = <String>{};

    // Each post is inside <div class="box-item">
    final blockRegex = RegExp(r'<div class="box-item">([\s\S]*?)(?=<div class="box-item">|$)', caseSensitive: false);
    final matches = blockRegex.allMatches(html);

    for (final match in matches) {
      final block = match.group(1) ?? '';

      // URL and Title
      final titleMatch = RegExp(r'<h3><a\s+href="([^"]+)"[^>]*>([\s\S]*?)</a></h3>', caseSensitive: false).firstMatch(block) ??
          RegExp(r'<a\s+href="([^"]+)"[^>]*title="([^"]+)"', caseSensitive: false).firstMatch(block);
      if (titleMatch == null) continue;

      final postUrl = titleMatch.group(1)?.trim() ?? '';
      if (postUrl.isEmpty || seenUrls.contains(postUrl)) continue;
      seenUrls.add(postUrl);

      final rawTitle = titleMatch.group(2) ?? '';
      final title = _cleanText(rawTitle);
      if (title.isEmpty) continue;

      // Image
      final imgMatch = RegExp(r'<img[^>]+(?:src|data-src)=["\x27]([^"\x27]+)["\x27]', caseSensitive: false).firstMatch(block);
      final posterUrl = imgMatch?.group(1)?.trim() ?? '';

      // Year
      final yearMatch = RegExp(r'<div class="post-date">([^<]+)</div>', caseSensitive: false).firstMatch(block);
      final year = yearMatch?.group(1)?.trim();

      // Episode number if this is an episode post
      final isEp = title.contains('الحلقة') || postUrl.contains('الحلقة') || defaultCategory == 'الحلقات الجديدة';
      int? epNumber;
      if (isEp) {
        final epNumMatch = RegExp(r'الحلقة\s*(\d+)', caseSensitive: false).firstMatch(title);
        if (epNumMatch != null) {
          epNumber = int.tryParse(epNumMatch.group(1)!);
        }
      }

      final isMovie = title.contains('فيلم') || postUrl.contains('فيلم') || defaultCategory == 'أفلام آسيوية';

      final id = _extractSlug(postUrl);

      items.add(Asia2TvItem(
        id: id,
        title: title,
        url: postUrl,
        posterUrl: posterUrl,
        year: year,
        category: defaultCategory,
        isMovie: isMovie,
        isEpisode: isEp,
        episodeNumber: epNumber,
      ));
    }

    // Only what can actually be shown and opened leaves the parser.
    return items.where(isPlayable).toList();
  }

  // ===========================================================================
  // 2. Drama & Movie Details
  // ===========================================================================

  /// Fetches drama/movie details and episode list
  Future<Asia2TvItemDetails> fetchDramaDetails(String dramaUrl) async {
    try {
      final response = await _client
          .get(Uri.parse(dramaUrl), headers: defaultHeaders)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception('HTTP status ${response.statusCode}');
      }

      return parseDetailsHtml(dramaUrl, response.body);
    } catch (e, st) {
      debugPrint('[asian-catalogue] Error fetching drama details for $dramaUrl: $e\n$st');
      rethrow;
    }
  }

  /// Parses drama details HTML
  Asia2TvItemDetails parseDetailsHtml(String dramaUrl, String html) {
    // Title
    final titleMatch = RegExp(r'<h1><span class="title">([^<]+)</span>', caseSensitive: false).firstMatch(html) ??
        RegExp(r'<h1>([^<]+)</h1>', caseSensitive: false).firstMatch(html);
    final title = _cleanText(titleMatch?.group(1) ?? '');

    // Poster
    final posterMatch = RegExp(r'<div class="singlepost-poster"[^>]*>[\s\S]*?<img[^>]+src=["\x27]([^"\x27]+)["\x27]', caseSensitive: false).firstMatch(html) ??
        RegExp(r'<img[^>]+class="[^"]*attachment-post-thumbnail[^"]*"[^>]+src=["\x27]([^"\x27]+)["\x27]', caseSensitive: false).firstMatch(html) ??
        RegExp(r'<img[^>]+src=["\x27]([^"\x27]+)["\x27][^>]+class="[^"]*attachment-post-thumbnail[^"]*"', caseSensitive: false).firstMatch(html);
    final posterUrl = posterMatch?.group(1)?.trim() ?? '';

    // Metadata
    final countryMatch = RegExp(r'<span>البلد المنتج:</span>\s*(?:<a[^>]*>)?([^<]+)', caseSensitive: false).firstMatch(html);
    final country = countryMatch?.group(1)?.trim();

    final dateMatch = RegExp(r'<span>موعد البث:</span>([^<]+)', caseSensitive: false).firstMatch(html);
    final date = dateMatch?.group(1)?.trim();
    final yearMatch = RegExp(r'\b(20\d\d|19\d\d)\b').firstMatch(date ?? '');
    final year = yearMatch?.group(1);

    final otherNamesMatch = RegExp(r'<span>يعرف ايضا بـ:</span>([^<]+)', caseSensitive: false).firstMatch(html);
    final otherNames = otherNamesMatch?.group(1)?.trim();

    // Story
    final storyMatch = RegExp(r'<div class="getcontent">([\s\S]*?)</div>', caseSensitive: false).firstMatch(html);
    final rawStory = storyMatch?.group(1) ?? '';
    final story = _cleanText(rawStory);

    // Genre
    final genreMatch = RegExp(r'<div class="box-tags">([\s\S]*?)</div>', caseSensitive: false).firstMatch(html);
    String? genre;
    if (genreMatch != null) {
      final tags = RegExp(r'<a[^>]*>([^<]+)</a>', caseSensitive: false)
          .allMatches(genreMatch.group(1)!)
          .map((m) => m.group(1)!.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (tags.isNotEmpty) {
        genre = tags.join(' • ');
      }
    }

    final isMovie = title.contains('فيلم') || dramaUrl.contains('فيلم');

    // Episodes
    final episodes = <Asia2TvEpisode>[];
    final seenEpUrls = <String>{};

    final epMatch = RegExp(r'<div class="loop-episode">([\s\S]*?)(?:</div>\s*</div>|$)', caseSensitive: false).firstMatch(html);
    final loopBlock = epMatch?.group(1) ?? html;

    final epLinkRegex = RegExp(r'<a\s+href="([^"]+)"[^>]*>[\s\S]*?<div class="titlepisode">([\s\S]*?)</div>', caseSensitive: false);
    for (final m in epLinkRegex.allMatches(loopBlock)) {
      final epUrl = m.group(1)?.trim() ?? '';
      if (epUrl.isEmpty || seenEpUrls.contains(epUrl)) continue;
      seenEpUrls.add(epUrl);

      final epTitle = _cleanText(m.group(2) ?? '');
      int epNum = episodes.length + 1;
      final numM = RegExp(r'(?:الحلقة|Episode)\s*(\d+)', caseSensitive: false).firstMatch(epTitle) ??
          RegExp(r'-(\d+)/?$', caseSensitive: false).firstMatch(epUrl);
      if (numM != null) {
        epNum = int.tryParse(numM.group(1)!) ?? epNum;
      }

      episodes.add(Asia2TvEpisode(
        number: epNum,
        title: epTitle.isNotEmpty ? epTitle : 'الحلقة $epNum',
        url: epUrl,
      ));
    }

    // Sort episodes ascending (1 to N)
    episodes.sort((a, b) => a.number.compareTo(b.number));

    final item = Asia2TvItem(
      id: _extractSlug(dramaUrl),
      title: title.isNotEmpty ? title : 'عمل آسيوي',
      url: dramaUrl,
      posterUrl: posterUrl,
      year: year,
      isMovie: isMovie,
      story: story,
      country: country,
      genre: genre,
      otherNames: otherNames,
    );

    return Asia2TvItemDetails(item: item, episodes: episodes);
  }

  // ===========================================================================
  // 3. Ad-Free Stream & Server Resolution (Auto Highest Quality)
  // ===========================================================================

  /// Resolves video playback for an episode or movie page.
  /// Automatically picks the highest available resolution (1080p Full HD -> 720p)
  /// and ensures completely ad-free streaming.
  Future<Asia2TvPlayback> resolveEpisodePlayback(String watchUrl) async {
    try {
      final response = await _client
          .get(Uri.parse(watchUrl), headers: defaultHeaders)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception('Failed to load episode page (${response.statusCode})');
      }

      final html = response.body;

      // Extract servers
      final serverRegex = RegExp(
        r'<li[^>]*class=["\x27]serverslist\s+([^"\x27]*)["\x27][^>]*data-server=["\x27]([^"\x27]+)["\x27][^>]*>([\s\S]*?)</li>',
        caseSensitive: false,
      );

      final servers = <Asia2TvServer>[];
      for (final m in serverRegex.allMatches(html)) {
        final cls = m.group(1)?.trim() ?? '';
        final serverUrl = m.group(2)?.trim() ?? '';
        final name = _cleanText(m.group(3) ?? '');
        if (serverUrl.isNotEmpty) {
          servers.add(Asia2TvServer(
            name: name.isNotEmpty ? name : cls,
            serverUrl: serverUrl,
            serverClass: cls,
          ));
        }
      }

      // If no servers found in standard format, search for iframes or fallback
      if (servers.isEmpty) {
        final iframeRegex = RegExp(r'<iframe[^>]+src=["\x27]([^"\x27]+)["\x27]', caseSensitive: false);
        for (final m in iframeRegex.allMatches(html)) {
          final sUrl = m.group(1)?.trim() ?? '';
          if (sUrl.startsWith('http')) {
            servers.add(Asia2TvServer(name: 'سيرفر رئيسي', serverUrl: sUrl, serverClass: 'default'));
          }
        }
      }

      // Try resolving direct streams from preferred servers:
      // 1. Vidmoly (Master m3u8 -> 1080p)
      // 2. Ok.ru (1080p full / 720p hd)
      // 3. Fallback server
      final streams = <CinemanaStreamFile>[];
      String activeServer = 'تلقائي';

      // 1. Look for Vidmoly
      final vidmolyServer = servers.firstWhere(
        (s) => s.name.toLowerCase().contains('vidmoly') || s.serverClass.toLowerCase().contains('vidmoly'),
        orElse: () => const Asia2TvServer(name: '', serverUrl: '', serverClass: ''),
      );
      if (vidmolyServer.serverUrl.isNotEmpty) {
        try {
          final vmStreams = await _resolveVidmoly(vidmolyServer.serverUrl);
          if (vmStreams.isNotEmpty) {
            streams.addAll(vmStreams);
            activeServer = 'Vidmoly';
          }
        } catch (e) {
          debugPrint('[asian-catalogue] Vidmoly resolution error: $e');
        }
      }

      // 2. Look for Ok.ru (if streams still empty or to provide extra high quality options)
      final okruServer = servers.firstWhere(
        (s) => s.name.toLowerCase().contains('ok') || s.serverClass.toLowerCase().contains('ok'),
        orElse: () => const Asia2TvServer(name: '', serverUrl: '', serverClass: ''),
      );
      if (okruServer.serverUrl.isNotEmpty) {
        try {
          final okStreams = await _resolveOkru(okruServer.serverUrl);
          if (okStreams.isNotEmpty) {
            if (streams.isEmpty) {
              streams.addAll(okStreams);
              activeServer = 'Ok.ru';
            } else {
              // Append Okru streams with server tag
              for (final s in okStreams) {
                if (!streams.any((x) => x.resolution == s.resolution)) {
                  streams.add(s);
                }
              }
            }
          }
        } catch (e) {
          debugPrint('[asian-catalogue] Ok.ru resolution error: $e');
        }
      }

      // Sort all streams in descending resolution order (1080p > 720p > 480p)
      streams.sort((a, b) => _resolutionToInt(b.resolution).compareTo(_resolutionToInt(a.resolution)));

      final defaultUrl = streams.isNotEmpty ? streams.first.videoUrl : null;
      final highestRes = streams.isNotEmpty ? streams.first.resolution : null;

      return Asia2TvPlayback(
        streams: streams,
        servers: servers,
        activeServerName: activeServer,
        defaultStreamUrl: defaultUrl,
        highestResolution: highestRes,
      );
    } catch (e, st) {
      debugPrint('[asian-catalogue] Error resolving playback for $watchUrl: $e\n$st');
      rethrow;
    }
  }

  /// Resolves Vidmoly direct master m3u8 and its resolution variants
  Future<List<CinemanaStreamFile>> _resolveVidmoly(String embedUrl) async {
    final res = await _client.get(
      Uri.parse(embedUrl),
      headers: {
        'User-Agent': defaultHeaders['User-Agent']!,
        'Referer': 'https://vidmoly.org/',
      },
    ).timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) return const [];
    final html = res.body;

    final m3u8Match = RegExp(r'file\s*:\s*["\x27](https?://[^"\x27]+\.m3u8[^"\x27]*)["\x27]', caseSensitive: false).firstMatch(html) ??
        RegExp(r'(https?://[^\s"\x27<>]+\.m3u8[^\s"\x27<>]*)', caseSensitive: false).firstMatch(html);
    if (m3u8Match == null) return const [];

    final masterUrl = m3u8Match.group(1)!;

    // Fetch master m3u8 playlist to extract 1080p, 720p, etc.
    try {
      final playlistRes = await _client.get(
        Uri.parse(masterUrl),
        headers: {
          'User-Agent': defaultHeaders['User-Agent']!,
          'Referer': 'https://vidmoly.org/',
        },
      ).timeout(const Duration(seconds: 10));

      if (playlistRes.statusCode == 200) {
        final lines = const LineSplitter().convert(playlistRes.body);
        final variants = <CinemanaStreamFile>[];

        for (var i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.startsWith('#EXT-X-STREAM-INF:')) {
            final resMatch = RegExp(r'RESOLUTION=\d+x(\d+)', caseSensitive: false).firstMatch(line);
            final height = resMatch != null ? int.tryParse(resMatch.group(1)!) ?? 0 : 0;
            if (i + 1 < lines.length) {
              var streamUrl = lines[i + 1].trim();
              if (!streamUrl.startsWith('http')) {
                // relative URL
                final uri = Uri.parse(masterUrl);
                streamUrl = uri.resolve(streamUrl).toString();
              }
              final label = height > 0 ? '${height}p' : 'Auto';
              variants.add(CinemanaStreamFile(
                name: 'Vidmoly $label',
                resolution: label,
                container: 'hls',
                videoUrl: streamUrl,
              ));
            }
          }
        }

        if (variants.isNotEmpty) {
          variants.sort((a, b) => _resolutionToInt(b.resolution).compareTo(_resolutionToInt(a.resolution)));
          return variants;
        }
      }
    } catch (_) {}

    // Fallback: master playlist itself
    return [
      CinemanaStreamFile(
        name: 'Vidmoly 1080p (تلقائي)',
        resolution: '1080p',
        container: 'hls',
        videoUrl: masterUrl,
      ),
    ];
  }

  /// Resolves Ok.ru direct stream links (full 1080p, hd 720p, etc.)
  Future<List<CinemanaStreamFile>> _resolveOkru(String embedUrl) async {
    final res = await _client.get(
      Uri.parse(embedUrl),
      headers: {
        'User-Agent': defaultHeaders['User-Agent']!,
        'Referer': 'https://ok.ru/',
      },
    ).timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) return const [];
    final html = res.body;

    final optsMatch = RegExp(r'data-options="([^"]+)"', caseSensitive: false).firstMatch(html);
    if (optsMatch == null) return const [];

    final rawJson = _unescapeHtml(optsMatch.group(1)!);
    final data = json.decode(rawJson) as Map<String, dynamic>;
    final flashvars = data['flashvars'] as Map<String, dynamic>? ?? {};

    var metadata = flashvars['metadata'];
    if (metadata is String) {
      metadata = json.decode(metadata);
    }
    if (metadata is! Map<String, dynamic>) return const [];

    final videos = metadata['videos'] as List<dynamic>? ?? [];
    final streams = <CinemanaStreamFile>[];

    // Map Ok.ru names to resolution labels
    const qualityMap = {
      'full': '1080p',
      'hd': '720p',
      'sd': '480p',
      'low': '360p',
      'lowest': '240p',
      'mobile': '144p',
    };

    for (final v in videos) {
      if (v is Map) {
        final qName = v['name']?.toString().toLowerCase() ?? '';
        final vUrl = v['url']?.toString() ?? '';
        if (vUrl.isNotEmpty) {
          final resLabel = qualityMap[qName] ?? '720p';
          streams.add(CinemanaStreamFile(
            name: 'Okru $resLabel',
            resolution: resLabel,
            container: 'mp4',
            videoUrl: vUrl,
          ));
        }
      }
    }

    final hlsMaster = metadata['hlsMasterPlaylistUrl']?.toString() ?? metadata['hlsManifestUrl']?.toString();
    if (hlsMaster != null && hlsMaster.isNotEmpty) {
      streams.add(CinemanaStreamFile(
        name: 'Okru HLS Master',
        resolution: '1080p',
        container: 'hls',
        videoUrl: hlsMaster,
      ));
    }

    streams.sort((a, b) => _resolutionToInt(b.resolution).compareTo(_resolutionToInt(a.resolution)));
    return streams;
  }

  // ===========================================================================
  // 4. Utility Helpers
  // ===========================================================================

  static int _resolutionToInt(String res) {
    final digits = res.replaceAll(RegExp(r'\D'), '');
    return int.tryParse(digits) ?? 0;
  }

  static String _cleanText(String text) {
    var cleaned = text
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#038;', '&')
        .replaceAll('&#8211;', '-')
        .replaceAll('&#8217;', "'");
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _unescapeHtml(String text) {
    return text
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&#039;', "'");
  }

  static String _extractSlug(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    return segments.isNotEmpty ? segments.last : url;
  }
}

class Asia2TvItemDetails {
  final Asia2TvItem item;
  final List<Asia2TvEpisode> episodes;

  const Asia2TvItemDetails({
    required this.item,
    required this.episodes,
  });
}
