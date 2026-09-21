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



  /// Curated verified top channels across sports, news, and entertainment.
  /// The yassirtv "match=bein1" links now resolve to the direct player iframe
  /// URL via [resolveLiveStream], so ads from the surrounding page are avoided.
  /// Fetch live sports and TV channels - returns empty list
  Future<List<SportsChannel>> fetchSportsChannels() async {
    return [];
  }

  /// Robust parser that turns any date/time string from Arabic or international feeds
  /// into a standard UTC ISO-8601 string (e.g. "2026-09-21T15:00:00.000Z").
  static String parseTimeToUtcIso(String rawTime, {String day = 'today'}) {
    if (rawTime.trim().isEmpty) return '';
    final trimmed = rawTime.trim();

    // 1. If already valid ISO-8601 with year/month
    if (trimmed.contains('-') && (trimmed.contains('T') || trimmed.contains(' '))) {
      final dt = DateTime.tryParse(trimmed);
      if (dt != null) {
        return dt.toUtc().toIso8601String();
      }
    }

    // 2. Determine target date
    final now = DateTime.now();
    DateTime target = now;
    if (day == 'yesterday') {
      target = now.subtract(const Duration(days: 1));
    } else if (day == 'tomorrow') {
      target = now.add(const Duration(days: 1));
    }

    // 3. Match HH:MM with optional period (AM/PM or ص/م)
    final match = RegExp(r'(\d{1,2}):(\d{2})\s*([a-zA-Z\u0600-\u06FF]+)?').firstMatch(trimmed);
    if (match != null) {
      int h = int.tryParse(match.group(1) ?? '') ?? 0;
      final m = int.tryParse(match.group(2) ?? '') ?? 0;
      final period = (match.group(3) ?? '').toLowerCase().trim();

      if (period.contains('p') || period.contains('م')) {
        if (h < 12) h += 12;
      } else if (period.contains('a') || period.contains('ص')) {
        if (h == 12) h = 0;
      }

      // Arabic feeds (Sir TV, Yalla Shoot, Cinamana) state times in Mecca/Doha/Baghdad time (UTC+3)
      final utc = DateTime.utc(target.year, target.month, target.day, h, m).subtract(const Duration(hours: 3));
      return utc.toIso8601String();
    }

    return '';
  }

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

        final parsedKickoff = parseTimeToUtcIso(timeStr, day: 'today');
        final initialMatch = SportMatchItem(
          id: idCounter,
          kickoffAt: parsedKickoff.isNotEmpty ? parsedKickoff : now.toUtc().toIso8601String(),
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

  /// Fetch matches exclusively from the official SIR TV website (sira.website)
  Future<List<LeagueGroup>> fetchSirTvMatches({String day = 'today'}) async {
    try {
      String url = 'https://sira.website/';
      if (day == 'yesterday') {
        url = 'https://sira.website/%d9%85%d8%a8%d8%a7%d8%b1%d9%8a%d8%a7%d8%aa-%d8%a7%d9%84%d8%a3%d9%85%d8%b3-%d8%b3%d9%8a%d8%b1-%d8%aa%d9%8a%d9%81%d9%8a-%d9%86%d8%aa%d8%a7%d8%a6%d8%ac-%d8%a7%d9%84%d9%85%d8%a8%d8%a7%d8%b1%d9%8a%d8%a7/';
      } else if (day == 'tomorrow') {
        url = 'https://sira.website/%d9%85%d8%a8%d8%a7%d8%b1%d9%8a%d8%a7%d8%aa-%d8%a7%d9%84%d8%ba%d8%af-%d8%b3%d9%8a%d8%b1-%d8%aa%d9%8a%d9%81%d9%8a-%d8%ac%d8%af%d9%88%d9%84-%d8%a7%d9%84%d9%85%d8%a8%d8%a7%d8%b1%d9%8a%d8%a7%d8%aa-%d8%a7/';
      }

      final dio = createDio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          'Referer': 'https://sira.website/',
        },
      ));

      final res = await dio.get<String>(url);
      if (res.statusCode != 200 || res.data == null) return [];
      final html = res.data!;

      final matchCardRegex = RegExp(
        r'''<div[^>]*class=['"][^'"]*AY_Match[^'"]*['"][^>]*id=['"]m-(\d+)['"][^>]*>([\s\S]*?)<a\s+class=['"]hit['"][^>]*href=['"]([^'"]*)['"][^>]*>[\s\S]*?<\/a>\s*<\/div>''',
        caseSensitive: false,
      );

      final Map<String, List<SportMatchItem>> groupedByLeague = {};
      int matchOrder = 0;

      for (final match in matchCardRegex.allMatches(html)) {
        final idStr = match.group(1);
        final body = match.group(2) ?? '';
        final hitUrl = match.group(3)?.trim();
        final matchId = int.tryParse(idStr ?? '') ?? (90000 + matchOrder);
        matchOrder++;

        // Home Team (TM1)
        final tm1NameMatch = RegExp(
          r'''class=['"][^'"]*TM1[^'"]*['"][\s\S]*?class=['"][^'"]*TM_Name[^'"]*['"]>([^<]+)<\/div>''',
          caseSensitive: false,
        ).firstMatch(body);
        final tm1Name = tm1NameMatch?.group(1)?.trim() ?? '';

        final tm1LogoMatch = RegExp(
          r'''class=['"][^'"]*TM1[^'"]*['"][\s\S]*?class=['"][^'"]*TM_Logo[^'"]*['"][\s\S]*?<img[^>]*(?:data-src|src)=['"]([^'"]+)['"]''',
          caseSensitive: false,
        ).firstMatch(body);
        final tm1Logo = tm1LogoMatch?.group(1)?.trim();

        // Away Team (TM2)
        final tm2NameMatch = RegExp(
          r'''class=['"][^'"]*TM2[^'"]*['"][\s\S]*?class=['"][^'"]*TM_Name[^'"]*['"]>([^<]+)<\/div>''',
          caseSensitive: false,
        ).firstMatch(body);
        final tm2Name = tm2NameMatch?.group(1)?.trim() ?? '';

        final tm2LogoMatch = RegExp(
          r'''class=['"][^'"]*TM2[^'"]*['"][\s\S]*?class=['"][^'"]*TM_Logo[^'"]*['"][\s\S]*?<img[^>]*(?:data-src|src)=['"]([^'"]+)['"]''',
          caseSensitive: false,
        ).firstMatch(body);
        final tm2Logo = tm2LogoMatch?.group(1)?.trim();

        if (tm1Name.isEmpty && tm2Name.isEmpty) continue;

        // Kickoff Time
        final timeMatch = RegExp(
          r'''class=['"][^'"]*MT_Time[^'"]*['"]>([^<]+)<\/span>''',
          caseSensitive: false,
        ).firstMatch(body);
        final timeStr = timeMatch?.group(1)?.trim() ?? '';

        // Status text
        final statMatch = RegExp(
          r'''class=['"][^'"]*MT_Stat[^'"]*['"]>([^<]+)<\/div>''',
          caseSensitive: false,
        ).firstMatch(body);
        final statStr = statMatch?.group(1)?.trim() ?? '';

        // Goals score
        int? homeScore;
        int? awayScore;
        final scoreMatch = RegExp(
          r'''class=['"][^'"]*RS-goals[^'"]*['"]>(\d+)<\/span>\s*<span>-<\/span>\s*<span[^>]*class=['"][^'"]*RS-goals[^'"]*['"]>(\d+)<\/span>''',
          caseSensitive: false,
        ).firstMatch(body);
        if (scoreMatch != null) {
          homeScore = int.tryParse(scoreMatch.group(1) ?? '');
          awayScore = int.tryParse(scoreMatch.group(2) ?? '');
        }

        // Info chyron: channel, commentator, league
        final infoMatches = RegExp(
          r'''<li><span>([^<]+)<\/span><\/li>''',
          caseSensitive: false,
        ).allMatches(body).map((m) => m.group(1)?.trim() ?? '').toList();

        String channelName = '';
        String commentatorName = '';
        String leagueName = 'مباريات اليوم';

        if (infoMatches.isNotEmpty) {
          channelName = infoMatches[0];
          if (infoMatches.length > 1) {
            commentatorName = infoMatches[1];
          }
          if (infoMatches.length > 2) {
            leagueName = infoMatches[2];
          }
        }

        // Normalize league name (strip country prefix if present)
        if (leagueName.contains(',')) {
          final parts = leagueName.split(',');
          if (parts.length > 1 && parts[1].trim().isNotEmpty) {
            leagueName = parts[1].trim();
          }
        }

        final primaryBroadcaster = channelName.isNotEmpty && channelName != 'غير معروف'
            ? (commentatorName.isNotEmpty && commentatorName != 'غير معروف'
                ? '$channelName • $commentatorName'
                : channelName)
            : 'SIR TV';

        // Normalize status
        String status = statStr;
        if (body.contains('comming-soon') || statStr.contains('لم تبدأ')) {
          status = 'لم تبدأ بعد';
        } else if (body.contains('finished') || statStr.contains('انتهت')) {
          status = 'finished';
        } else if (body.contains('live') || statStr.contains('مباشر') || statStr.contains('جاري')) {
          status = 'live';
        }

        final parsedKickoff = parseTimeToUtcIso(timeStr, day: day);
        final item = SportMatchItem(
          id: matchId,
          kickoffAt: parsedKickoff.isNotEmpty ? parsedKickoff : DateTime.now().toUtc().toIso8601String(),
          status: status,
          home: TeamInfo(name: tm1Name, logo: tm1Logo),
          away: TeamInfo(name: tm2Name, logo: tm2Logo),
          homeScore: homeScore,
          awayScore: awayScore,
          hasWatch: true,
          league: leagueName,
          directUrl: hitUrl,
          broadcasterName: primaryBroadcaster,
          broadcasters: [
            if (hitUrl != null && hitUrl.isNotEmpty)
              BroadcastChannel(
                id: 1,
                name: primaryBroadcaster,
                image: '',
                streamUrl: hitUrl,
              ),
          ],
        );

        groupedByLeague.putIfAbsent(leagueName, () => []).add(item);
      }

      int leagueCounter = 1;
      final List<LeagueGroup> groups = [];
      for (final entry in groupedByLeague.entries) {
        groups.add(LeagueGroup(
          leagueId: leagueCounter++,
          league: entry.key,
          matches: entry.value,
        ));
      }

      return groups;
    } catch (e) {
      debugPrint('[SPORTS] fetchSirTvMatches error: $e');
      return [];
    }
  }

  Future<List<LeagueGroup>> fetchMatches({String day = 'today'}) async {
    try {
      // Unify match fetching to the EXACT source that broadcasts the streams: Kora x90 (korax90.co)
      final baseGroups = await fetchKoraX90Matches(day: day);
      if (baseGroups.isEmpty) return [];

      // Enrich with 365Scores for real-time scores / live timer if available
      List<LeagueGroup> enrichedGroups = baseGroups;
      if (day == 'yesterday' || day == 'today') {
        try {
          final scoresList = await _fetch365ScoresForDay(day);
          if (scoresList.isNotEmpty) {
            enrichedGroups = baseGroups.map((g) {
              final updatedMatches = g.matches.map((m) {
                final found = _lookup365Score(m.home.name, m.away.name, scoresList);
                if (found != null) {
                  return m.copyWith(
                    homeScore: found.homeScore,
                    awayScore: found.awayScore,
                    status: (day == 'yesterday' || found.isEnded)
                        ? 'finished'
                        : (found.isLive ? 'live' : m.status),
                  );
                }
                return m;
              }).toList();
              return LeagueGroup(
                leagueId: g.leagueId,
                cid: g.cid,
                league: g.league,
                logo: g.logo,
                matches: updatedMatches,
              );
            }).toList();
          }
        } catch (e) {
          debugPrint('[SPORTS] Enrich 365scores error: $e');
        }
      }

      if (day == 'tomorrow') {
        return enrichedGroups.map((g) => LeagueGroup(
          leagueId: g.leagueId,
          cid: g.cid,
          league: g.league,
          logo: g.logo,
          matches: g.matches.map((m) => m.copyWith(
            status: 'scheduled',
            hasWatch: false,
          )).toList(),
        )).toList();
      } else if (day == 'yesterday') {
        return enrichedGroups.map((g) => LeagueGroup(
          leagueId: g.leagueId,
          cid: g.cid,
          league: g.league,
          logo: g.logo,
          matches: g.matches.map((m) => m.copyWith(
            status: 'finished',
            hasWatch: false,
          )).toList(),
        )).toList();
      }

      return enrichedGroups;
    } catch (e) {
      debugPrint('[SPORTS] fetchMatches error: $e');
      return [];
    }
  }

  Future<List<({String home, String away, int homeScore, int awayScore, bool isLive, bool isEnded})>> _fetch365ScoresForDay(String day) async {
    try {
      final now = DateTime.now();
      DateTime target = now;
      if (day == 'yesterday') {
        target = now.subtract(const Duration(days: 1));
      } else if (day == 'tomorrow') {
        target = now.add(const Duration(days: 1));
      }
      final d = target.day.toString().padLeft(2, '0');
      final m = target.month.toString().padLeft(2, '0');
      final y = target.year.toString();
      final dateParam = '$d/$m/$y';

      final dio = createDio(BaseOptions(
        connectTimeout: const Duration(seconds: 7),
        receiveTimeout: const Duration(seconds: 7),
        headers: {'User-Agent': 'Mozilla/5.0'},
      ));

      final res = await dio.get(
        'https://webws.365scores.com/web/games/allscores/',
        queryParameters: {
          'appTypeId': 5,
          'langId': 27,
          'startDate': dateParam,
          'endDate': dateParam,
          'sports': 1,
        },
      );

      if (res.statusCode != 200 || res.data is! Map) return [];
      final games = res.data['games'] as List?;
      if (games == null || games.isEmpty) return [];

      final list = <({String home, String away, int homeScore, int awayScore, bool isLive, bool isEnded})>[];
      for (final g in games) {
        if (g is! Map) continue;
        final hComp = g['homeCompetitor'] as Map?;
        final aComp = g['awayCompetitor'] as Map?;
        if (hComp == null || aComp == null) continue;

        final hName = hComp['name']?.toString() ?? '';
        final aName = aComp['name']?.toString() ?? '';
        final hScoreNum = hComp['score'];
        final aScoreNum = aComp['score'];

        if (hName.isEmpty || aName.isEmpty || hScoreNum == null || aScoreNum == null) continue;
        final hScore = (hScoreNum as num).toInt();
        final aScore = (aScoreNum as num).toInt();

        final statusText = g['statusText']?.toString() ?? '';
        final gameTime = (g['gameTime'] as num?)?.toInt() ?? -1;
        final isEnded = statusText.contains('انتهت') || statusText.contains('نهائي') || statusText.contains('بعد') || (g['completion'] == 100);
        final isLive = gameTime > 0 && !isEnded;

        list.add((
          home: hName,
          away: aName,
          homeScore: hScore,
          awayScore: aScore,
          isLive: isLive,
          isEnded: isEnded,
        ));
      }
      return list;
    } catch (e) {
      debugPrint('[SPORTS] _fetch365ScoresForDay error: $e');
      return [];
    }
  }

  String _cleanTeamNameForMatch(String name) {
    return name
        .replaceAll(RegExp(r'^(نادي|نادى|فريق)\s+'), '')
        .replaceAll(RegExp(r'\s+(FC|CF|SC)$', caseSensitive: false), '')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .trim()
        .toLowerCase();
  }

  ({int homeScore, int awayScore, bool isLive, bool isEnded})? _lookup365Score(
    String home,
    String away,
    List<({String home, String away, int homeScore, int awayScore, bool isLive, bool isEnded})> scores,
  ) {
    final ch = _cleanTeamNameForMatch(home);
    final ca = _cleanTeamNameForMatch(away);
    if (ch.isEmpty || ca.isEmpty) return null;

    for (final s in scores) {
      final sh = _cleanTeamNameForMatch(s.home);
      final sa = _cleanTeamNameForMatch(s.away);

      final homeMatches = ch == sh || ch.contains(sh) || sh.contains(ch) ||
          (ch.length > 3 && sh.length > 3 && (ch.startsWith(sh.substring(0, 3)) || sh.startsWith(ch.substring(0, 3))));
      final awayMatches = ca == sa || ca.contains(sa) || sa.contains(ca) ||
          (ca.length > 3 && sa.length > 3 && (ca.startsWith(sa.substring(0, 3)) || sa.startsWith(ca.substring(0, 3))));

      if (homeMatches && awayMatches) {
        return (homeScore: s.homeScore, awayScore: s.awayScore, isLive: s.isLive, isEnded: s.isEnded);
      }
    }
    return null;
  }

  Future<List<SportMatchItem>> fetchLiveMatches({String day = 'today'}) async {
    if (day != 'today') return [];
    final groups = await fetchMatches(day: day);
    final all = <SportMatchItem>[];
    for (final g in groups) {
      for (final m in g.matches) {
        if (m.isLive || m.status == 'live') {
          all.add(m);
        }
      }
    }
    return all;
  }

  /// Fetch matches from Kora x90 (korax90.co)
  Future<List<LeagueGroup>> fetchKoraX90Matches({String day = 'today'}) async {
    try {
      String url = 'https://www.korax90.co/matches-today';
      if (day == 'yesterday') {
        url = 'https://www.korax90.co/matches-yesterday';
      } else if (day == 'tomorrow') {
        url = 'https://www.korax90.co/matches-tomorrow';
      }

      final dio = createDio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          'Referer': 'https://www.korax90.co/',
          'Cache-Control': 'no-cache, no-store, must-revalidate',
          'Pragma': 'no-cache',
          'Expires': '0',
        },
      ));

      final res = await dio.get<String>(url);
      if (res.statusCode != 200 || res.data == null) return [];
      final html = res.data!;

      final blocks = html.split('<div class="match-item">');
      if (blocks.length <= 1) return [];

      final Map<String, List<SportMatchItem>> groupedByLeague = {};
      final Set<String> seenMatchLinks = {};
      final Set<String> seenMatchTeams = {};
      final now = DateTime.now();
      int matchCounter = 0;

      for (int i = 1; i < blocks.length; i++) {
        final block = blocks[i];
        final linkMatch = RegExp(r'<a\s+href="([^"]+)"\s+class="match-row"', caseSensitive: false).firstMatch(block);
        if (linkMatch == null) continue;
        String link = linkMatch.group(1)?.trim() ?? '';
        if (link.isEmpty) continue;
        if (!link.startsWith('http')) {
          link = 'https://www.korax90.co${link.startsWith('/') ? '' : '/'}$link';
        }
        if (!seenMatchLinks.add(link)) continue;

        // Teams extraction
        final teamRegex = RegExp(
          r'<div class="team">[\s\S]*?<img[^>]*src="([^"]+)"[^>]*alt="([^"]*)"[\s\S]*?<div class="team-name">\s*([\s\S]*?)\s*<\/div>',
          caseSensitive: false,
        );
        final teamMatches = teamRegex.allMatches(block).toList();
        if (teamMatches.length < 2) continue;

        String fixLogo(String? raw) {
          if (raw == null || raw.isEmpty) return '';
          if (raw.startsWith('http')) return raw;
          return 'https://www.korax90.co${raw.startsWith('/') ? '' : '/'}$raw';
        }

        final homeLogo = fixLogo(teamMatches[0].group(1)?.trim());
        final homeName = teamMatches[0].group(3)?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
        final awayLogo = fixLogo(teamMatches[1].group(1)?.trim());
        final awayName = teamMatches[1].group(3)?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';

        if (homeName.isEmpty || awayName.isEmpty) continue;
        final teamKey = '${homeName.trim().toLowerCase()}_${awayName.trim().toLowerCase()}';
        if (!seenMatchTeams.add(teamKey)) continue;

        // Meta (score, time, status, league)
        final scoreMatch = RegExp(r'<div class="score-time">\s*([\s\S]*?)\s*<\/div>', caseSensitive: false).firstMatch(block);
        final scoreTime = scoreMatch?.group(1)?.trim() ?? '';

        final statusBadgeMatch = RegExp(r'<div class="status-badge([^"]*)">\s*([\s\S]*?)\s*<\/div>', caseSensitive: false).firstMatch(block);
        final badgeClass = statusBadgeMatch?.group(1)?.trim() ?? '';
        final badgeText = statusBadgeMatch?.group(2)?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';

        final dataStartMatch = RegExp(r'data-start="(\d+)"', caseSensitive: false).firstMatch(block);
        final dataStart = int.tryParse(dataStartMatch?.group(1) ?? '');

        final leagueMatch = RegExp(r'<div class="league">\s*([\s\S]*?)\s*<\/div>', caseSensitive: false).firstMatch(block);
        final rawLeague = leagueMatch?.group(1)?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? 'مباريات اليوم';

        // Parse status
        String status = 'scheduled';
        if (day == 'yesterday') {
          status = 'finished';
        } else if (day == 'tomorrow') {
          status = 'scheduled';
        } else if (badgeClass.contains('status-live') || badgeText.contains('مباشر')) {
          status = 'live';
        } else if (badgeClass.contains('status-ended') || badgeText.contains('انتهت')) {
          status = 'finished';
        } else if (badgeClass.contains('status-countdown') || badgeText.contains('يبدأ')) {
          status = 'scheduled';
        }

        // Parse goals if scoreTime has a dash
        int? homeScore;
        int? awayScore;
        if (scoreTime.contains('-')) {
          final parts = scoreTime.split('-');
          if (parts.length >= 2) {
            homeScore = int.tryParse(parts[0].trim());
            awayScore = int.tryParse(parts[1].trim());
          }
        }

        // Kickoff time
        String kickoffAt;
        if (dataStart != null && dataStart > 0) {
          kickoffAt = DateTime.fromMillisecondsSinceEpoch(dataStart * 1000, isUtc: true).toIso8601String();
        } else if (scoreTime.contains(':')) {
          kickoffAt = parseTimeToUtcIso(scoreTime, day: day);
        } else {
          var targetDate = now;
          if (day == 'yesterday') {
            targetDate = now.subtract(const Duration(days: 1));
          } else if (day == 'tomorrow') {
            targetDate = now.add(const Duration(days: 1));
          }
          kickoffAt = DateTime.utc(targetDate.year, targetDate.month, targetDate.day, 12, 0).toIso8601String();
        }

        // ID from URL suffix or counter
        final idSuffix = RegExp(r'(\d+)$').firstMatch(link)?.group(1);
        final matchId = int.tryParse(idSuffix ?? '') ?? (90000 + matchCounter);
        matchCounter++;

        // Clean league name for grouping
        String groupLeague = rawLeague;
        if (rawLeague.contains('الجولة')) {
          groupLeague = rawLeague.split('الجولة')[0].trim();
        } else if (rawLeague.contains('الأسبوع')) {
          groupLeague = rawLeague.split('الأسبوع')[0].trim();
        } else if (rawLeague.contains('-')) {
          groupLeague = rawLeague.split('-')[0].trim();
        }
        if (groupLeague.isEmpty) groupLeague = rawLeague;

        final isMatchLive = status == 'live';
        final hasWatch = isMatchLive || (link.isNotEmpty && status != 'finished');
        final item = SportMatchItem(
          id: matchId,
          kickoffAt: kickoffAt,
          status: status,
          home: TeamInfo(name: homeName, logo: homeLogo.isNotEmpty ? homeLogo : null),
          away: TeamInfo(name: awayName, logo: awayLogo.isNotEmpty ? awayLogo : null),
          homeScore: homeScore,
          awayScore: awayScore,
          hasWatch: hasWatch,
          league: rawLeague,
          directUrl: link,
          broadcasterName: 'بث Kora x90 HD',
          broadcasters: link.isNotEmpty
              ? [
                  BroadcastChannel(
                    id: matchId,
                    name: 'سيرفر البث الرئيسي HD',
                    image: '',
                    streamUrl: link,
                  ),
                ]
              : const [],
        );

        groupedByLeague.putIfAbsent(groupLeague, () => []).add(item);
      }

      int leagueCounter = 1;
      final List<LeagueGroup> groups = [];
      for (final entry in groupedByLeague.entries) {
        groups.add(LeagueGroup(
          leagueId: leagueCounter++,
          league: entry.key,
          matches: entry.value,
        ));
      }

      return groups;
    } catch (e) {
      debugPrint('[SPORTS] fetchKoraX90Matches error: $e');
      return [];
    }
  }

  /// Resolves direct stream servers for a Kora x90 match URL
  Future<List<({String name, String streamUrl, String type, String frameUrl})>> resolveKoraX90Servers(String matchUrl) async {
    try {
      final dio = createDio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          'Referer': 'https://www.korax90.co/',
        },
      ));

      final matchRes = await dio.get<String>(matchUrl);
      if (matchRes.statusCode != 200 || matchRes.data == null) return [];
      final matchHtml = matchRes.data!;

      final frameMatches = RegExp(r'data-frame="([^"]+)"', caseSensitive: false).allMatches(matchHtml);
      final frameUrls = frameMatches.map((m) => m.group(1)?.trim() ?? '').where((u) => u.startsWith('http')).toSet().toList();

      final results = <({String name, String streamUrl, String type, String frameUrl})>[];

      for (final frameUrl in frameUrls) {
        try {
          final frameDio = createDio(BaseOptions(
            connectTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 8),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 14; SmartTV; SM-A266B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              'Referer': matchUrl,
            },
          ));

          final frameRes = await frameDio.get<String>(frameUrl);
          if (frameRes.statusCode != 200 || frameRes.data == null) continue;
          final frameHtml = frameRes.data!;

          final serversMatch = RegExp(r'const\s+servers\s*=\s*(\[[^;]+\]);').firstMatch(frameHtml);
          final streamUrlMatch = RegExp(r'let\s+streamUrl\s*=\s*"([^"]+)";').firstMatch(frameHtml);

          if (serversMatch != null) {
            try {
              final jsonStr = serversMatch.group(1)!;
              final parsed = jsonDecode(jsonStr);
              if (parsed is List) {
                for (int i = 0; i < parsed.length; i++) {
                  final s = parsed[i];
                  if (s is Map && s['url'] != null) {
                    final rawUrl = s['url'].toString();
                    final rawName = s['name']?.toString().trim() ?? '';
                    final serverName = (rawName.isEmpty || rawName == 'عام' || rawName.contains('سيرفر عام'))
                        ? (i == 0 ? 'سيرفر البث الرئيسي HD' : 'سيرفر ${i + 1} HD')
                        : (rawName.startsWith('سيرفر') ? '$rawName HD' : 'سيرفر $rawName HD');
                    results.add((
                      name: serverName,
                      streamUrl: rawUrl,
                      type: s['type']?.toString() ?? (rawUrl.contains('.m3u8') ? 'hls' : 'iframe'),
                      frameUrl: frameUrl,
                    ));
                  }
                }
              }
            } catch (_) {}
          }

          if (results.isEmpty && streamUrlMatch != null) {
            final sUrl = streamUrlMatch.group(1)!.replaceAll(r'\/', '/').trim();
            if (sUrl.isNotEmpty) {
              results.add((
                name: 'السيرفر الرئيسي HD',
                streamUrl: sUrl,
                type: sUrl.contains('.m3u8') ? 'hls' : 'iframe',
                frameUrl: frameUrl,
              ));
            }
          }

          if (results.isEmpty) {
            results.add((
              name: 'مشغل البث المباشر',
              streamUrl: frameUrl,
              type: 'iframe',
              frameUrl: frameUrl,
            ));
          }
        } catch (e) {
          debugPrint('[SPORTS] resolve frame error: $e');
        }
      }

      return results;
    } catch (e) {
      debugPrint('[SPORTS] resolveKoraX90Servers error: $e');
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
      // ── Kora x90 / BoomStreaming extraction ──
      if (trimmed.contains('korax90.co')) {
        final servers = await resolveKoraX90Servers(trimmed);
        if (servers.isNotEmpty) {
          final s = servers.first;
          final isHls = s.streamUrl.contains('.m3u8');
          final res = ResolvedLiveStream(
            streamUrl: s.streamUrl,
            headers: isHls
                ? const {
                    'User-Agent': 'Mozilla/5.0 (Linux; Android 14; SmartTV; SM-A266B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                    'Referer': 'https://9.boomstreaming.com/',
                  }
                : const {
                    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
                    'Referer': 'https://www.korax90.co/',
                  },
            sourcePageUrl: s.frameUrl,
            albaplayerUrl: s.streamUrl,
          );
          _resolvedStreamsCache[trimmed] = (stream: res, timestamp: DateTime.now());
          return res;
        }
      }

      if (trimmed.contains('boomstreaming.com')) {
        // If already a direct HLS m3u8 URL with token
        if (trimmed.contains('.m3u8')) {
          final res = ResolvedLiveStream(
            streamUrl: trimmed,
            headers: const {
              'User-Agent': 'Mozilla/5.0 (Linux; Android 14; SmartTV; SM-A266B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              'Referer': 'https://9.boomstreaming.com/',
            },
            sourcePageUrl: 'https://9.boomstreaming.com/',
            albaplayerUrl: trimmed,
          );
          _resolvedStreamsCache[trimmed] = (stream: res, timestamp: DateTime.now());
          return res;
        }

        final frameDio = createDio(BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
          headers: {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 14; SmartTV; SM-A266B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Referer': 'https://www.korax90.co/',
          },
        ));
        final frameRes = await frameDio.get<String>(trimmed);
        if (frameRes.statusCode == 200 && frameRes.data != null) {
          final serversMatch = RegExp(r'const\s+servers\s*=\s*(\[[^;]+\]);').firstMatch(frameRes.data!);
          if (serversMatch != null) {
            try {
              final parsed = jsonDecode(serversMatch.group(1)!);
              if (parsed is List && parsed.isNotEmpty && parsed.first is Map) {
                final sUrl = parsed.first['url']?.toString();
                if (sUrl != null && sUrl.isNotEmpty) {
                  final res = ResolvedLiveStream(
                    streamUrl: sUrl,
                    headers: const {
                      'User-Agent': 'Mozilla/5.0 (Linux; Android 14; SmartTV; SM-A266B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                      'Referer': 'https://9.boomstreaming.com/',
                    },
                    sourcePageUrl: trimmed,
                    albaplayerUrl: sUrl,
                  );
                  _resolvedStreamsCache[trimmed] = (stream: res, timestamp: DateTime.now());
                  return res;
                }
              }
            } catch (_) {}
          }

          final streamUrlMatch = RegExp(r'let\s+streamUrl\s*=\s*"([^"]+)";').firstMatch(frameRes.data!);
          if (streamUrlMatch != null) {
            final hlsUrl = streamUrlMatch.group(1)!.replaceAll(r'\/', '/').trim();
            final res = ResolvedLiveStream(
              streamUrl: hlsUrl,
              headers: const {
                'User-Agent': 'Mozilla/5.0 (Linux; Android 14; SmartTV; SM-A266B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                'Referer': 'https://9.boomstreaming.com/',
              },
              sourcePageUrl: trimmed,
              albaplayerUrl: hlsUrl,
            );
            _resolvedStreamsCache[trimmed] = (stream: res, timestamp: DateTime.now());
            return res;
          }
        }
      }

      // If already a direct HLS or Cloudflare R2 playlist
      if (trimmed.contains('.m3u8') || trimmed.contains('.r2.dev') || trimmed.endsWith('.css') || trimmed.contains('/index.css')) {
        final isBoom = trimmed.contains('boomstreaming.com') || trimmed.contains('korax90');
        final res = ResolvedLiveStream(
          streamUrl: trimmed,
          headers: {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 14; SmartTV; SM-A266B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Referer': isBoom ? 'https://9.boomstreaming.com/' : 'https://pl.matchlivehd.com/',
          },
          sourcePageUrl: trimmed,
        );
        _resolvedStreamsCache[trimmed] = (stream: res, timestamp: DateTime.now());
        return res;
      }

      // ── YassirTV / SiirTV dedicated extraction ──
      // The yassirtv page embeds its player via a JS variable `__playerSrc`
      // pointing to a playerv5.php iframe. We extract that URL directly
      // so the WebView shows only the clean player, no surrounding ads.
      if (trimmed.contains('yassirtv.com') || trimmed.contains('siiir.tv')) {
        final yasirResolved = await _resolveYasirTvPlayer(trimmed);
        if (yasirResolved != null) {
          _resolvedStreamsCache[trimmed] = (stream: yasirResolved, timestamp: DateTime.now());
          return yasirResolved;
        }
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
        final hostMatch = RegExp(r'https:\/\/([a-zA-Z0-9.-]+)\/playerv\d*\.php').firstMatch(content);
        final keyMatch = RegExp(r'key=([a-zA-Z0-9]+)').firstMatch(content);

        if (hostMatch != null && keyMatch != null) {
          final host = hostMatch.group(1);
          final key = keyMatch.group(1);
          final directUrl = 'https://$host/playerv5.php?match=$match&key=$key';
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

  /// Extracts the direct player iframe URL from a yassirtv / siiir.tv page.
  ///
  /// The page embeds a JS variable `window.__playerSrc` pointing to a
  /// playerv5.php iframe on a subdomain of yasirtv.com. We extract that URL
  /// so the app can open the player directly — no surrounding page, no ads.
  Future<ResolvedLiveStream?> _resolveYasirTvPlayer(String pageUrl) async {
    try {
      final dio = createDio(BaseOptions(
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 12),
        responseType: ResponseType.plain,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14; SmartTV; SM-A266B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Referer': 'https://yassirtv.com/',
        },
      ));

      final res = await dio.get<String>(pageUrl);
      if (res.statusCode != 200 || res.data == null) return null;
      final html = res.data!;

      String? playerUrl;

      // Strategy 1: Extract window.__playerSrc from inline <script>.
      // e.g. window.__playerSrc = 'https://912acsss8af382.yasirtv.com/playerv5.php?match=bein1&key=...'
      final playerSrcMatch = RegExp(
        r"""window\.__playerSrc\s*=\s*['"]([^'"]+)['"]""",
      ).firstMatch(html);
      if (playerSrcMatch != null) {
        playerUrl = playerSrcMatch.group(1);
      }

      // Strategy 2: Look for an iframe whose src points to a playerv*.php
      if (playerUrl == null || playerUrl.isEmpty) {
        final iframeMatch = RegExp(
          r'''<iframe[^>]+src=["']?(https?://[^"'\s>]*playerv\d*\.php[^"'\s>]*)["']?''',
          caseSensitive: false,
        ).firstMatch(html);
        if (iframeMatch != null) {
          playerUrl = iframeMatch.group(1);
        }
      }

      // Strategy 3: Reconstruct from host + key (old _resolveDirectPlayer approach)
      if (playerUrl == null || playerUrl.isEmpty) {
        final hostMatch = RegExp(r'https://([a-zA-Z0-9.-]+)/playerv\d*\.php').firstMatch(html);
        final keyMatch = RegExp(r'key=([a-zA-Z0-9]+)').firstMatch(html);
        final matchParam = Uri.tryParse(pageUrl)?.queryParameters['match'];
        if (hostMatch != null && keyMatch != null && matchParam != null) {
          final host = hostMatch.group(1)!;
          final key = keyMatch.group(1)!;
          playerUrl = 'https://$host/playerv5.php?match=$matchParam&key=$key';
        }
      }

      if (playerUrl != null && playerUrl.isNotEmpty) {
        debugPrint('[SPORTS] YasirTV resolved player: $playerUrl');
        return ResolvedLiveStream(
          streamUrl: playerUrl,
          headers: const {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 14; SmartTV; SM-A266B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Referer': 'https://yassirtv.com/',
          },
          sourcePageUrl: pageUrl,
          albaplayerUrl: playerUrl,
        );
      }

      debugPrint('[SPORTS] YasirTV: no player URL found in page HTML');
    } catch (e) {
      debugPrint('[SPORTS] YasirTV extraction error: $e');
    }
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

  Future<String> _find365GameId(String? homeName, String? awayName) async {
    final targets = [
      if (homeName != null && homeName.isNotEmpty) homeName,
      if (awayName != null && awayName.isNotEmpty) awayName,
    ];
    if (targets.isEmpty) return '';

    final gameDio = createDio(BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 6),
      headers: {'User-Agent': 'Mozilla/5.0'},
    ));

    for (final target in targets) {
      final clean = target
          .replaceAll(RegExp(r'^(نادي|نادى|فريق)\s+'), '')
          .replaceAll(RegExp(r'\s+(FC|CF|SC)$', caseSensitive: false), '')
          .trim();
      if (clean.isEmpty) continue;

      try {
        final searchRes = await gameDio.get(
          'https://webws.365scores.com/web/search/',
          queryParameters: {'query': clean, 'appTypeId': 5, 'langId': 27},
        );
        if (searchRes.statusCode == 200 && searchRes.data is Map) {
          final comps = searchRes.data['competitors'] as List?;
          if (comps != null && comps.isNotEmpty) {
            for (final c in comps.take(3)) {
              if (c is! Map) continue;
              final cid = c['id'];
              if (cid == null) continue;

              final gRes = await gameDio.get(
                'https://webws.365scores.com/web/games/current/',
                queryParameters: {'competitors': cid, 'appTypeId': 5, 'langId': 27},
              );
              if (gRes.statusCode == 200 && gRes.data is Map) {
                final games = gRes.data['games'] as List?;
                if (games != null && games.isNotEmpty) {
                  final other = (target == homeName ? awayName : homeName) ?? '';
                  final otherClean = other
                      .replaceAll(RegExp(r'^(نادي|نادى|فريق)\s+'), '')
                      .trim()
                      .toLowerCase();

                  for (final g in games) {
                    if (g is! Map) continue;
                    final gHome = (g['homeCompetitor']?['name']?.toString() ?? '').toLowerCase();
                    final gAway = (g['awayCompetitor']?['name']?.toString() ?? '').toLowerCase();

                    if (otherClean.isNotEmpty &&
                        (gHome.contains(otherClean) ||
                         gAway.contains(otherClean) ||
                         otherClean.split(' ').any((w) => w.length > 2 && (gHome.contains(w) || gAway.contains(w))))) {
                      return g['id'].toString();
                    }
                  }
                  return games.first['id'].toString();
                }
              }
            }
          }
        }
      } catch (_) {}
    }
    return '';
  }

  Future<MatchDetailedInfo?> fetchMatchDetails(
    int matchId, {
    String? sourceId,
    String? homeName,
    String? awayName,
  }) async {
    try {
      String resolvedSourceId = sourceId ?? '';
      String? round;
      String? stadium;
      String? referee;
      String? homeCaptainName;
      String? awayCaptainName;

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

      // Fallback 2: Direct lookup on 365scores by team names
      if (resolvedSourceId.isEmpty && (homeName != null || awayName != null)) {
        resolvedSourceId = await _find365GameId(homeName, awayName);
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
          if (starters.length < 11 && subs.isNotEmpty) {
            final needed = 11 - starters.length;
            final count = needed.clamp(0, subs.length);
            for (var i = 0; i < count; i++) {
              final p = subs[i];
              final line = (i == 0 && starters.isEmpty) ? 1 : (i <= 4 ? 2 : (i <= 7 ? 3 : 4));
              final fieldSide = 15.0 + (i % 4) * 25.0;
              starters.add(PlayerLineupItem(
                id: p.id,
                athleteId: p.athleteId,
                name: p.name,
                shortName: p.shortName,
                jerseyNumber: p.jerseyNumber ?? (i + 1),
                position: p.position ?? (line == 1 ? 'حارس مرمى' : (line == 2 ? 'مدافع' : (line == 3 ? 'وسط' : 'مهاجم'))),
                isStarter: true,
                line: p.line > 0 ? p.line : line,
                fieldSide: p.fieldSide > 0 ? p.fieldSide : fieldSide,
                rating: p.rating,
                popularityRank: p.popularityRank,
              ));
            }
            subs.removeRange(0, count);
          }

          final coach = homeCompetitor['coach'] is Map ? homeCompetitor['coach']['name']?.toString() : null;
          homeLineup = TeamLineup(
            teamName: homeName,
            formation: formation ?? '4-3-3',
            coach: coach,
            starters: starters,
            substitutes: subs,
          );
        } else if (game['members'] is List) {
          // Fallback: Populate squad members for home team from game members
          final squad = <PlayerLineupItem>[];
          for (final m in game['members']) {
            if (m is Map && (m['competitorId'] == homeId || m['competitorId']?.toString() == homeId?.toString())) {
              squad.add(parseMember(m));
            }
          }
          final starters = squad.take(11).toList();
          final subs = squad.skip(11).toList();
          for (var i = 0; i < starters.length; i++) {
            final p = starters[i];
            final line = (i == 0) ? 1 : (i <= 4 ? 2 : (i <= 7 ? 3 : 4));
            final fieldSide = 15.0 + (i % 4) * 25.0;
            starters[i] = PlayerLineupItem(
              id: p.id,
              athleteId: p.athleteId,
              name: p.name,
              shortName: p.shortName,
              jerseyNumber: p.jerseyNumber ?? (i + 1),
              position: p.position ?? (line == 1 ? 'حارس مرمى' : (line == 2 ? 'مدافع' : (line == 3 ? 'وسط' : 'مهاجم'))),
              isStarter: true,
              line: p.line > 0 ? p.line : line,
              fieldSide: p.fieldSide > 0 ? p.fieldSide : fieldSide,
              rating: p.rating,
              popularityRank: p.popularityRank,
            );
          }
          if (starters.isNotEmpty || subs.isNotEmpty) {
            homeLineup = TeamLineup(
              teamName: homeName,
              formation: '4-3-3',
              coach: null,
              starters: starters,
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

          if (starters.length < 11 && subs.isNotEmpty) {
            final needed = 11 - starters.length;
            final count = needed.clamp(0, subs.length);
            for (var i = 0; i < count; i++) {
              final p = subs[i];
              final line = (i == 0 && starters.isEmpty) ? 1 : (i <= 4 ? 2 : (i <= 7 ? 3 : 4));
              final fieldSide = 15.0 + (i % 4) * 25.0;
              starters.add(PlayerLineupItem(
                id: p.id,
                athleteId: p.athleteId,
                name: p.name,
                shortName: p.shortName,
                jerseyNumber: p.jerseyNumber ?? (i + 1),
                position: p.position ?? (line == 1 ? 'حارس مرمى' : (line == 2 ? 'مدافع' : (line == 3 ? 'وسط' : 'مهاجم'))),
                isStarter: true,
                line: p.line > 0 ? p.line : line,
                fieldSide: p.fieldSide > 0 ? p.fieldSide : fieldSide,
                rating: p.rating,
                popularityRank: p.popularityRank,
              ));
            }
            subs.removeRange(0, count);
          }

          final coach = awayCompetitor['coach'] is Map ? awayCompetitor['coach']['name']?.toString() : null;
          awayLineup = TeamLineup(
            teamName: awayName,
            formation: formation ?? '4-2-3-1',
            coach: coach,
            starters: starters,
            substitutes: subs,
          );
        } else if (game['members'] is List) {
          // Fallback: Populate squad members for away team from game members
          final squad = <PlayerLineupItem>[];
          for (final m in game['members']) {
            if (m is Map && (m['competitorId'] == awayId || m['competitorId']?.toString() == awayId?.toString())) {
              squad.add(parseMember(m));
            }
          }
          final starters = squad.take(11).toList();
          final subs = squad.skip(11).toList();
          for (var i = 0; i < starters.length; i++) {
            final p = starters[i];
            final line = (i == 0) ? 1 : (i <= 4 ? 2 : (i <= 7 ? 3 : 4));
            final fieldSide = 15.0 + (i % 4) * 25.0;
            starters[i] = PlayerLineupItem(
              id: p.id,
              athleteId: p.athleteId,
              name: p.name,
              shortName: p.shortName,
              jerseyNumber: p.jerseyNumber ?? (i + 1),
              position: p.position ?? (line == 1 ? 'حارس مرمى' : (line == 2 ? 'مدافع' : (line == 3 ? 'وسط' : 'مهاجم'))),
              isStarter: true,
              line: p.line > 0 ? p.line : line,
              fieldSide: p.fieldSide > 0 ? p.fieldSide : fieldSide,
              rating: p.rating,
              popularityRank: p.popularityRank,
            );
          }
          if (starters.isNotEmpty || subs.isNotEmpty) {
            awayLineup = TeamLineup(
              teamName: awayName,
              formation: '4-2-3-1',
              coach: null,
              starters: starters,
              substitutes: subs,
            );
          }
        }

        // Designate Captains with gold (C) mark
        if (homeLineup != null && homeLineup.starters.isNotEmpty) {
          final startersList = List<PlayerLineupItem>.from(homeLineup.starters);
          final capIdx = startersList.indexWhere((p) => p.popularityRank == 1 || p.jerseyNumber == 4 || p.jerseyNumber == 8 || p.jerseyNumber == 10);
          final idx = capIdx >= 0 ? capIdx : (startersList.length > 3 ? 3 : 0);
          final p = startersList[idx];
          startersList[idx] = PlayerLineupItem(
            id: p.id,
            athleteId: p.athleteId,
            name: p.name,
            shortName: p.shortName,
            jerseyNumber: p.jerseyNumber,
            position: p.position,
            isStarter: p.isStarter,
            line: p.line,
            fieldSide: p.fieldSide,
            rating: p.rating,
            popularityRank: p.popularityRank,
            isCaptain: true,
          );
          homeCaptainName = p.name;
          homeLineup = TeamLineup(
            teamName: homeLineup.teamName,
            formation: homeLineup.formation ?? '4-3-3',
            coach: homeLineup.coach,
            starters: startersList,
            substitutes: homeLineup.substitutes,
          );
        }

        if (awayLineup != null && awayLineup.starters.isNotEmpty) {
          final startersList = List<PlayerLineupItem>.from(awayLineup.starters);
          final capIdx = startersList.indexWhere((p) => p.popularityRank == 1 || p.jerseyNumber == 4 || p.jerseyNumber == 8 || p.jerseyNumber == 10);
          final idx = capIdx >= 0 ? capIdx : (startersList.length > 3 ? 3 : 0);
          final p = startersList[idx];
          startersList[idx] = PlayerLineupItem(
            id: p.id,
            athleteId: p.athleteId,
            name: p.name,
            shortName: p.shortName,
            jerseyNumber: p.jerseyNumber,
            position: p.position,
            isStarter: p.isStarter,
            line: p.line,
            fieldSide: p.fieldSide,
            rating: p.rating,
            popularityRank: p.popularityRank,
            isCaptain: true,
          );
          awayCaptainName = p.name;
          awayLineup = TeamLineup(
            teamName: awayLineup.teamName,
            formation: awayLineup.formation ?? '4-2-3-1',
            coach: awayLineup.coach,
            starters: startersList,
            substitutes: awayLineup.substitutes,
          );
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
        homeCaptain: homeCaptainName,
        awayCaptain: awayCaptainName,
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

