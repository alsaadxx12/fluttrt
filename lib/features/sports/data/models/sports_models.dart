class TeamInfo {
  final String name;
  final String? logo;

  TeamInfo({required this.name, this.logo});

  factory TeamInfo.fromJson(Map<String, dynamic> json) {
    return TeamInfo(
      name: (json['name'] ?? json['name_ar'] ?? '').toString(),
      logo: json['logo']?.toString(),
    );
  }
}

class SportMatchItem {
  final int id;
  final String? sourceId;
  final String kickoffAt;
  final String status; // scheduled, live, ended
  final int? minute;
  final TeamInfo home;
  final TeamInfo away;
  final int? homeScore;
  final int? awayScore;
  final bool hasWatch;
  final int? streamId;
  final String? league;
  final String? leagueLogo;
  final List<BroadcastChannel> broadcasters;
  final String? broadcasterName;
  final String? directUrl;

  SportMatchItem({
    required this.id,
    this.sourceId,
    required this.kickoffAt,
    required this.status,
    this.minute,
    required this.home,
    required this.away,
    this.homeScore,
    this.awayScore,
    this.hasWatch = false,
    this.streamId,
    this.league,
    this.leagueLogo,
    this.broadcasters = const [],
    this.broadcasterName,
    this.directUrl,
  });

  /// Over: the feed says finished (spelled any of the common Arabic or English ways),
  /// or the kick-off was more than ~115 minutes ago (or 105 min with scores present).
  bool get isEnded {
    final s = status.trim().toLowerCase();

    // 1. Explicitly ended if status says finished / ended
    if (s.contains('انتهت') ||
        s.contains('منتهي') ||
        s.contains('نهائي') ||
        s.contains('نهاية') ||
        s == 'ft' ||
        const {
          'ended',
          'finished',
          'ft',
          'full_time',
          'fulltime',
          'aet',
          'complete',
          'completed'
        }.contains(s)) {
      return true;
    }

    // 2. Explicitly live
    if (s.contains('مباشر') || s.contains('live') || s.contains('جاري')) {
      return false;
    }

    // 3. Time elapsed based on kickoffAt
    final ko = DateTime.tryParse(kickoffAt);
    if (ko != null) {
      final nowUtc = DateTime.now().toUtc();
      // If kickoff time is in the future, it definitely cannot have ended!
      if (ko.toUtc().isAfter(nowUtc)) {
        return false;
      }
      final sinceKickoff = nowUtc.difference(ko.toUtc());
      // Match kicked off >= 105 mins ago with scores recorded => ended
      if (sinceKickoff >= const Duration(minutes: 105) &&
          homeScore != null &&
          awayScore != null) {
        return true;
      }
      // Match kicked off >= 115 mins ago (90m + 15m break + injury time) => ended
      if (sinceKickoff >= const Duration(minutes: 115)) {
        return true;
      }
    }

    // 4. Explicitly NOT ended if marked as scheduled, not started, or upcoming
    if (s.contains('لم تبدأ') ||
        s.contains('scheduled') ||
        s.contains('not_started') ||
        s.contains('upcoming')) {
      return false;
    }

    return false;
  }

  /// In play right now.
  bool get isLive {
    if (isEnded) return false;
    final s = status.trim().toLowerCase();
    if (s.contains('لم تبدأ') ||
        s.contains('scheduled') ||
        s.contains('not_started') ||
        s.contains('upcoming')) {
      return false;
    }
    const liveWords = {
      'live',
      'in_progress',
      'inprogress',
      'playing',
      '1h',
      '2h',
      'ht',
      'et',
      'pen'
    };
    if (!liveWords.contains(s) && !s.contains('مباشر') && !s.contains('جاري')) {
      return false;
    }
    final ko = DateTime.tryParse(kickoffAt);
    if (ko != null) {
      final sinceKickoff = DateTime.now().toUtc().difference(ko.toUtc());
      if (sinceKickoff < const Duration(minutes: -10)) return false; // not started yet
      if (sinceKickoff >= const Duration(minutes: 125)) return false; // over
    }
    return true;
  }

  bool get isScheduled => !isLive && !isEnded;

  /// How long before kick-off a match opens.
  static const Duration opensBefore = Duration(minutes: 15);

  /// When the match can be opened: a quarter of an hour before kick-off.
  /// Null when the kick-off is not known.
  DateTime? get opensAt {
    final ko = DateTime.tryParse(kickoffAt);
    return ko == null ? null : ko.toLocal().subtract(opensBefore);
  }

  /// Whether the match can be opened now: one in play or over always, one
  /// still to come only from a quarter of an hour before kick-off. A match
  /// whose kick-off is not known is not kept out.
  bool get canOpen {
    if (isLive || isEnded) return true;
    final at = opensAt;
    return at == null || !DateTime.now().isBefore(at);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SportMatchItem &&
          runtimeType == other.runtimeType &&
          ((id > 0 && id == other.id) ||
              (home.name.trim().toLowerCase() == other.home.name.trim().toLowerCase() &&
                  away.name.trim().toLowerCase() == other.away.name.trim().toLowerCase()));

  @override
  int get hashCode => id > 0
      ? id.hashCode
      : Object.hash(home.name.trim().toLowerCase(), away.name.trim().toLowerCase());

  String get displayBroadcaster {
    if (broadcasterName != null && broadcasterName!.isNotEmpty) {
      return broadcasterName!;
    }
    if (broadcasters.isNotEmpty) {
      return broadcasters.map((b) => b.name).join(' • ');
    }
    return '';
  }

  SportMatchItem copyWith({
    int? id,
    String? sourceId,
    String? kickoffAt,
    String? status,
    int? minute,
    TeamInfo? home,
    TeamInfo? away,
    int? homeScore,
    int? awayScore,
    bool? hasWatch,
    int? streamId,
    String? league,
    String? leagueLogo,
    List<BroadcastChannel>? broadcasters,
    String? broadcasterName,
    String? directUrl,
  }) {
    return SportMatchItem(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      kickoffAt: kickoffAt ?? this.kickoffAt,
      status: status ?? this.status,
      minute: minute ?? this.minute,
      home: home ?? this.home,
      away: away ?? this.away,
      homeScore: homeScore ?? this.homeScore,
      awayScore: awayScore ?? this.awayScore,
      hasWatch: hasWatch ?? this.hasWatch,
      streamId: streamId ?? this.streamId,
      league: league ?? this.league,
      leagueLogo: leagueLogo ?? this.leagueLogo,
      broadcasters: broadcasters ?? this.broadcasters,
      broadcasterName: broadcasterName ?? this.broadcasterName,
      directUrl: directUrl ?? this.directUrl,
    );
  }

  factory SportMatchItem.fromJson(Map<String, dynamic> json, {String? defaultLeague, String? defaultLeagueLogo}) {
    // Handle home team
    TeamInfo homeTeam;
    if (json['home'] is Map<String, dynamic>) {
      homeTeam = TeamInfo.fromJson(json['home'] as Map<String, dynamic>);
    } else {
      homeTeam = TeamInfo(
        name: (json['home'] ?? '').toString(),
        logo: json['home_logo']?.toString(),
      );
    }

    // Handle away team
    TeamInfo awayTeam;
    if (json['away'] is Map<String, dynamic>) {
      awayTeam = TeamInfo.fromJson(json['away'] as Map<String, dynamic>);
    } else {
      awayTeam = TeamInfo(
        name: (json['away'] ?? '').toString(),
        logo: json['away_logo']?.toString(),
      );
    }

    int? parseInt(dynamic val) {
      if (val == null) return null;
      if (val is int) return val;
      return int.tryParse(val.toString());
    }

    final hasWatchVal = json['has_watch'];
    final bool isWatchable = hasWatchVal == true ||
        hasWatchVal == 1 ||
        hasWatchVal == '1' ||
        hasWatchVal == 'true' ||
        json['stream_id'] != null;

    final broadcastersRaw = json['broadcasters'] ?? json['tv_stations'] ?? json['channels'];
    final broadcastersList = <BroadcastChannel>[];
    if (broadcastersRaw is List) {
      for (final b in broadcastersRaw) {
        if (b is Map) {
          broadcastersList.add(BroadcastChannel.fromJson(Map<String, dynamic>.from(b)));
        } else if (b is String && b.isNotEmpty) {
          broadcastersList.add(BroadcastChannel(id: 0, name: b, image: ''));
        }
      }
    }
    final singleBroadcaster = json['broadcaster_name']?.toString() ??
        json['channel']?.toString() ??
        json['channel_name']?.toString() ??
        (broadcastersList.isNotEmpty ? broadcastersList.first.name : null);

    return SportMatchItem(
      id: parseInt(json['match_id']) ?? parseInt(json['id']) ?? 0,
      sourceId: json['source_id']?.toString(),
      kickoffAt: (json['kickoff_at'] ?? '').toString(),
      status: (json['status'] ?? 'scheduled').toString(),
      minute: parseInt(json['minute']),
      home: homeTeam,
      away: awayTeam,
      homeScore: parseInt(json['home_score']),
      awayScore: parseInt(json['away_score']),
      hasWatch: isWatchable,
      streamId: parseInt(json['stream_id']),
      league: json['league']?.toString() ?? defaultLeague,
      leagueLogo: json['league_logo']?.toString() ?? defaultLeagueLogo,
      broadcasters: broadcastersList,
      broadcasterName: singleBroadcaster,
      directUrl: json['direct_url']?.toString() ?? json['url']?.toString(),
    );
  }

  factory SportMatchItem.fromSportsChannel(SportsChannel channel) {
    return SportMatchItem(
      id: channel.channelId,
      sourceId: channel.channelId.toString(),
      kickoffAt: DateTime.now().toIso8601String(),
      status: 'مباشر',
      home: TeamInfo(name: channel.channelName, logo: channel.channelImage),
      away: TeamInfo(name: channel.categoryName, logo: channel.channelImage),
      hasWatch: true,
      league: channel.categoryName,
      leagueLogo: channel.channelImage,
      directUrl: channel.channelUrl,
      broadcasters: [
        BroadcastChannel(
          id: channel.channelId,
          name: channel.channelName,
          image: channel.channelImage,
          streamUrl: channel.channelUrl,
        ),
      ],
      broadcasterName: channel.channelName,
    );
  }
}

class LeagueGroup {
  final int leagueId;
  final int? cid;
  final String league;
  final String? logo;
  final List<SportMatchItem> matches;

  LeagueGroup({
    required this.leagueId,
    this.cid,
    required this.league,
    this.logo,
    required this.matches,
  });

  factory LeagueGroup.fromJson(Map<String, dynamic> json) {
    final leagueName = (json['league'] ?? json['league_ar'] ?? json['league_en'] ?? '').toString();
    final leagueLogo = json['logo']?.toString();

    final matchesList = (json['matches'] as List? ?? [])
        .map((m) => SportMatchItem.fromJson(
              m as Map<String, dynamic>,
              defaultLeague: leagueName,
              defaultLeagueLogo: leagueLogo,
            ))
        .toList();

    return LeagueGroup(
      leagueId: json['league_id'] is int
          ? json['league_id']
          : int.tryParse(json['league_id']?.toString() ?? '0') ?? 0,
      cid: json['cid'] is int ? json['cid'] : int.tryParse(json['cid']?.toString() ?? '0'),
      league: leagueName,
      logo: leagueLogo,
      matches: matchesList,
    );
  }
}

class StreamInfo {
  final bool ok;
  final String play;
  final String url;
  final Map<String, String> headers;

  StreamInfo({
    required this.ok,
    required this.play,
    required this.url,
    required this.headers,
  });

  factory StreamInfo.fromJson(Map<String, dynamic> json) {
    final headersMap = <String, String>{};
    if (json['headers'] is Map) {
      (json['headers'] as Map).forEach((k, v) {
        headersMap[k.toString()] = v.toString();
      });
    }

    return StreamInfo(
      ok: json['ok'] == true,
      play: (json['play'] ?? 'webview').toString(),
      url: (json['url'] ?? '').toString(),
      headers: headersMap,
    );
  }
}

class SportNewsItem {
  final int id;
  final String title;
  final String? image;
  final String? time;
  final String? date;
  final String? description;
  final String? url;

  SportNewsItem({
    required this.id,
    required this.title,
    this.image,
    this.time,
    this.date,
    this.description,
    this.url,
  });

  factory SportNewsItem.fromJson(Map<String, dynamic> json) {
    return SportNewsItem(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      title: (json['title'] ?? json['title_ar'] ?? '').toString(),
      image: json['image']?.toString() ?? json['img']?.toString(),
      time: json['time']?.toString(),
      date: json['date']?.toString(),
      description: json['description']?.toString(),
      url: json['url']?.toString(),
    );
  }
}

class MatchEventItem {
  final String timeDisplay;
  final String typeName;
  final String playerName;
  final String? extraPlayerName;
  final String teamName;
  final bool isHome;
  final bool isGoal;
  final bool isCard;
  final bool isSub;

  MatchEventItem({
    required this.timeDisplay,
    required this.typeName,
    required this.playerName,
    this.extraPlayerName,
    required this.teamName,
    required this.isHome,
    required this.isGoal,
    required this.isCard,
    required this.isSub,
  });
}

class PlayerLineupItem {
  final int id;
  final int? athleteId;
  final String name;
  final String? shortName;
  final int? jerseyNumber;
  final String? position;
  final bool isStarter;
  final int line;
  final double fieldSide;
  final double? rating;
  // Position in the 365scores game-level `members` list, which leads with a
  // squad's headline players. Neither source flags a captain, so this order is
  // the best available "face" of a team (lower = more notable).
  final int? popularityRank;
  final bool isCaptain;

  String? get photoUrl => athleteId != null && athleteId! > 0
      ? 'https://imagecache.365scores.com/image/upload/f_png,w_80,h_80,c_limit,q_auto:eco,dpr_2/athletes/$athleteId'
      : null;

  PlayerLineupItem({
    required this.id,
    this.athleteId,
    required this.name,
    this.shortName,
    this.jerseyNumber,
    this.position,
    required this.isStarter,
    this.line = 2,
    this.fieldSide = 50.0,
    this.rating,
    this.popularityRank,
    this.isCaptain = false,
  });
}

class TeamLineup {
  final String teamName;
  final String? formation;
  final String? coach;
  final List<PlayerLineupItem> starters;
  final List<PlayerLineupItem> substitutes;

  TeamLineup({
    required this.teamName,
    this.formation,
    this.coach,
    required this.starters,
    required this.substitutes,
  });
}

class MatchStatItem {
  final String name;
  final String homeValue;
  final String awayValue;
  final double homePercentage;

  MatchStatItem({
    required this.name,
    required this.homeValue,
    required this.awayValue,
    required this.homePercentage,
  });
}

class MatchDetailedInfo {
  final int id;
  final String? sourceId;
  final String? stadium;
  final String? referee;
  final String? round;
  final String? homeCaptain;
  final String? awayCaptain;
  final TeamLineup? homeLineup;
  final TeamLineup? awayLineup;
  final List<MatchEventItem> events;
  final List<MatchStatItem> stats;

  MatchDetailedInfo({
    required this.id,
    this.sourceId,
    this.stadium,
    this.referee,
    this.round,
    this.homeCaptain,
    this.awayCaptain,
    this.homeLineup,
    this.awayLineup,
    required this.events,
    required this.stats,
  });
}

class BroadcastChannel {
  final int id;
  final String name;
  final String image;
  final String? streamUrl;

  const BroadcastChannel({
    required this.id,
    required this.name,
    required this.image,
    this.streamUrl,
  });

  factory BroadcastChannel.fromJson(Map<String, dynamic> json) {
    return BroadcastChannel(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      name: json['name']?.toString() ?? '',
      image: json['image_path']?.toString() ?? json['image']?.toString() ?? '',
      streamUrl: json['stream_url']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'image_path': image,
    'stream_url': streamUrl,
  };
}

class SportsChannel {
  final int channelId;
  final int categoryId;
  final String channelName;
  final String channelImage;
  final String channelUrl;
  final String channelType;
  final String categoryName;
  final String userAgent;

  const SportsChannel({
    required this.channelId,
    required this.categoryId,
    required this.channelName,
    required this.channelImage,
    required this.channelUrl,
    required this.channelType,
    required this.categoryName,
    this.userAgent = 'default',
  });

  factory SportsChannel.fromJson(Map<String, dynamic> json, {String? panelUrl}) {
    String img = json['channel_image']?.toString() ?? '';
    if (img.isNotEmpty && !img.startsWith('http') && panelUrl != null && panelUrl.isNotEmpty) {
      img = '$panelUrl/upload/$img';
    }
    return SportsChannel(
      channelId: int.tryParse(json['channel_id']?.toString() ?? '') ?? 0,
      categoryId: int.tryParse(json['category_id']?.toString() ?? '') ?? 13,
      channelName: json['channel_name']?.toString() ?? '',
      channelImage: img,
      channelUrl: json['channel_url']?.toString() ?? '',
      channelType: json['channel_type']?.toString() ?? 'URL',
      categoryName: json['category_name']?.toString() ?? 'ARABIC SPORTS',
      userAgent: json['user_agent']?.toString() ?? 'default',
    );
  }
}

/// Normalizes channel names for reliable comparison and matching
String normalizeChannelName(String value) {
  return value
      .toLowerCase()
      .replaceAll('hd', '')
      .replaceAll('4k', '')
      .replaceAll('sd', '')
      .replaceAll('tv', '')
      .replaceAll(' ', '')
      .replaceAll('-', '')
      .replaceAll('_', '')
      .replaceAll('sport', '')
      .replaceAll('sports', '')
      .trim();
}

class ResolvedLiveStream {
  final String streamUrl;
  final Map<String, String> headers;
  final String? sourcePageUrl;
  final String? albaplayerUrl;
  final List<String> alternativeStreamUrls;

  const ResolvedLiveStream({
    required this.streamUrl,
    this.headers = const {},
    this.sourcePageUrl,
    this.albaplayerUrl,
    this.alternativeStreamUrls = const [],
  });
}

