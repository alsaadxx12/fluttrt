import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';
import 'package:youtube_downloader/features/sports/presentation/widgets/match_score_line.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../data/models/sports_models.dart';
import '../providers/sports_provider.dart';
import 'sports_player_screen.dart';
import 'league_screen.dart';
import 'leagues_screen.dart';

import '../../../home/presentation/widgets/football_showcase.dart';
import 'package:cached_network_image/cached_network_image.dart';

class SportsScreen extends ConsumerStatefulWidget {
  const SportsScreen({super.key});

  @override
  ConsumerState<SportsScreen> createState() => _SportsScreenState();
}

class _SportsScreenState extends ConsumerState<SportsScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatKickoff(String isoString) {
    if (isoString.isEmpty) return '';
    try {
      final dateTime = DateTime.parse(isoString).toLocal();
      return DateFormat('hh:mm a', 'ar').format(dateTime);
    } catch (_) {
      try {
        final dateTime = DateTime.parse(isoString).toLocal();
        return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
      } catch (_) {
        return isoString;
      }
    }
  }

  void _openPlayer(BuildContext context, SportMatchItem match, {SportsChannel? channel}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SportsPlayerScreen(
          match: match,
          directUrl: match.directUrl,
          initialSportsChannel: channel,
        ),
      ),
    );
  }

  /// The group list the streams were warmed for, so the scan does not run
  /// again on every rebuild.
  List<LeagueGroup>? _warmedGroups;

  /// The channels carrying a match, shown as their own pictures. A channel
  /// the feed gave no picture for falls back to a plain mark rather than a
  /// borrowed one, and nothing here is labelled in words.
  Widget _buildBroadcasterMarks(SportMatchItem match, bool isDark) {
    final withLogos = match.broadcasters.where((b) => b.image.isNotEmpty).toList();
    final bg = isDark ? AppPalette.of(context).cardAlt : AppPalette.of(context).cardAlt;
    final border = isDark ? AppPalette.of(context).border : AppPalette.of(context).border;

    Widget tile(Widget child) => Container(
          width: 42,
          height: 28,
          margin: const EdgeInsetsDirectional.only(end: 6),
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: border, width: 0.8),
          ),
          child: child,
        );

    if (withLogos.isEmpty) {
      return tile(const Icon(Icons.live_tv_rounded, size: 15, color: Color(0xFFFF1744)));
    }
    return SizedBox(
      height: 28,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (final b in withLogos.take(4))
            tile(CachedNetworkImage(
              imageUrl: b.image,
              fit: BoxFit.contain,
              errorWidget: (_, __, ___) =>
                  const Icon(Icons.live_tv_rounded, size: 15, color: Color(0xFFFF1744)),
            )),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedDay = ref.watch(sportsDayProvider);
    final selectedTab = ref.watch(sportsTabProvider);
    final searchQuery = ref.watch(sportsSearchQueryProvider);
    final sportsState = ref.watch(sportsNotifierProvider(selectedDay));
    final sportsNotifier = ref.read(sportsNotifierProvider(selectedDay).notifier);

    ref.listen<int>(sportsTabProvider, (previous, next) {
      if (next == 1) {
        ref.read(sportsDayProvider.notifier).state = 'today';
      }
    });

    // Resolve the streams of the matches that are live right now, before any
    // of them is tapped: the first one opened then starts with no round trip
    // of its own.
    if (!identical(sportsState.groups, _warmedGroups)) {
      _warmedGroups = sportsState.groups;
      final liveIds = <int>[
        for (final g in sportsState.groups)
          for (final m in g.matches)
            if (m.isLive && m.streamId != null) m.streamId!,
      ];
      if (liveIds.isNotEmpty) {
        ref.read(streamWarmupProvider).prefetch(liveIds);
      }
    }

    const accentColor = Color(0xFFFF1744);

    return Scaffold(
      backgroundColor: isDark ? AppPalette.of(context).bg : AppPalette.of(context).bg,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF111622) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          color: isDark ? Colors.white : Colors.black87,
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.sports_soccer_rounded,
                color: accentColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'الرياضة والمباريات',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : const Color(0xFF111115),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            color: isDark ? Colors.white70 : Colors.black54,
            tooltip: 'تحديث',
            onPressed: () => sportsNotifier.refresh(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Day & Tab Switchers Section
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF111622) : Colors.white,
              border: Border(
                bottom: BorderSide(
                  color: isDark ? const Color(0xFF1C2233) : const Color(0xFFE8EAF0),
                  width: 1,
                ),
              ),
            ),
            child: Column(
              children: [
                // Day Selector: الأمس, اليوم, الغد
                Row(
                  children: [
                    _buildDayPill(
                      label: 'أمس',
                      dayKey: 'yesterday',
                      isSelected: selectedDay == 'yesterday',
                      onTap: () => ref.read(sportsDayProvider.notifier).state = 'yesterday',
                      isDark: isDark,
                      accentColor: accentColor,
                    ),
                    const SizedBox(width: 8),
                    _buildDayPill(
                      label: 'اليوم',
                      dayKey: 'today',
                      isSelected: selectedDay == 'today',
                      onTap: () => ref.read(sportsDayProvider.notifier).state = 'today',
                      isDark: isDark,
                      accentColor: accentColor,
                    ),
                    const SizedBox(width: 8),
                    _buildDayPill(
                      label: 'غداً',
                      dayKey: 'tomorrow',
                      isSelected: selectedDay == 'tomorrow',
                      onTap: () => ref.read(sportsDayProvider.notifier).state = 'tomorrow',
                      isDark: isDark,
                      accentColor: accentColor,
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Main Section Tabs: المباريات, مباشر, القنوات, الأخبار
                Row(
                  children: [
                    _buildTabButton(
                      title: 'المباريات',
                      icon: Icons.calendar_today_rounded,
                      isSelected: selectedTab == 0,
                      onTap: () => ref.read(sportsTabProvider.notifier).state = 0,
                      isDark: isDark,
                      accentColor: accentColor,
                    ),
                    const SizedBox(width: 6),
                    _buildTabButton(
                      title: 'مباشر',
                      icon: Icons.sensors_rounded,
                      badgeCount: sportsState.liveMatches.where((m) => m.isLive).length,
                      isSelected: selectedTab == 1,
                      onTap: () {
                        ref.read(sportsDayProvider.notifier).state = 'today';
                        ref.read(sportsTabProvider.notifier).state = 1;
                      },
                      isDark: isDark,
                      accentColor: const Color(0xFFFF334B),
                    ),
                    const SizedBox(width: 6),
                    _buildTabButton(
                      title: 'القنوات',
                      icon: Icons.live_tv_rounded,
                      isSelected: selectedTab == 2,
                      onTap: () => ref.read(sportsTabProvider.notifier).state = 2,
                      isDark: isDark,
                      accentColor: accentColor,
                    ),
                    const SizedBox(width: 6),
                    _buildTabButton(
                      title: 'الأخبار',
                      icon: Icons.article_rounded,
                      isSelected: selectedTab == 3,
                      onTap: () => ref.read(sportsTabProvider.notifier).state = 3,
                      isDark: isDark,
                      accentColor: accentColor,
                    ),
                  ],
                ),

                // Search field (shown in matches and channels tabs)
                if (selectedTab != 3) ...[
                  const SizedBox(height: 10),
                  Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF192030) : const Color(0xFFEEF1F6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) {
                        ref.read(sportsSearchQueryProvider.notifier).state = val.trim();
                      },
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      decoration: InputDecoration(
                        hintText: 'ابحث عن فريقك المفضل (ريال مدريد، ليفربول...)...',
                        hintStyle: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        prefixIconColor: isDark ? Colors.white38 : Colors.black38,
                        suffixIcon: searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close_rounded, size: 16),
                                onPressed: () {
                                  _searchController.clear();
                                  ref.read(sportsSearchQueryProvider.notifier).state = '';
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Leagues strip: the day's leagues plus the way to all of them.
          if (selectedTab == 0 || selectedTab == 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 2),
              child: _buildLeaguesRow(context, sportsState, isDark),
            ),

          // Body Content
          Expanded(
            child: RefreshIndicator(
              color: accentColor,
              onRefresh: () => sportsNotifier.refresh(),
              child: _buildBodyContent(
                context,
                selectedTab,
                sportsState,
                searchQuery,
                isDark,
                accentColor,
              ),
            ),
          ),
        ],
      ),
    );
  }



  /// The competition behind a match group: one of the app's known leagues
  /// (same page the home cards open), or a plain one built from the group.
  /// Null when the group carries no 365Scores competition id.
  static FootballLeague? _leagueOf(LeagueGroup g) {
    final cid = g.cid;
    if (cid == null || cid <= 0) return null;
    for (final l in [...FootballLeague.world, ...FootballLeague.arab]) {
      if (l.id == cid) return l;
    }
    return FootballLeague(cid, g.league, '', const [Color(0xFF1B2440), Color(0xFF0B0F1A)]);
  }

  void _openLeague(BuildContext context, FootballLeague league) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => LeagueScreen(league: league)),
    );
  }

  /// A slim strip of pills: the leagues with matches on this day, and a
  /// first pill that opens the full leagues page. Tap a pill for the
  /// league's fixtures, table and streams.
  Widget _buildLeaguesRow(BuildContext context, SportsState state, bool isDark) {
    final p = AppPalette.of(context);
    final today = <FootballLeague>[];
    final seen = <int>{};
    for (final g in state.groups) {
      final l = _leagueOf(g);
      if (l != null && seen.add(l.id)) today.add(l);
    }
    final dpr = MediaQuery.of(context).devicePixelRatio;
    Widget pill({required Widget leading, required String text, required VoidCallback onTap, bool accent = false}) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 38,
          padding: const EdgeInsetsDirectional.fromSTEB(6, 0, 12, 0),
          decoration: BoxDecoration(
            color: accent ? const Color(0xFFE50914) : p.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent ? const Color(0xFFE50914) : p.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              leading,
              const SizedBox(width: 7),
              Text(text,
                  style: TextStyle(
                      color: accent ? Colors.white : p.text, fontSize: 12, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          pill(
            accent: true,
            leading: const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.emoji_events_rounded, color: Colors.white, size: 18),
            ),
            text: 'كل الدوريات',
            onTap: () => Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(builder: (_) => const LeaguesScreen()),
            ),
          ),
          for (final l in today) ...[
            const SizedBox(width: 8),
            pill(
              leading: Container(
                width: 26,
                height: 26,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: l.darkBadge ? const Color(0xFF0C1410) : Colors.white,
                  shape: BoxShape.circle,
                ),
                child: CachedNetworkImage(
                  imageUrl: l.logoUrl,
                  fit: BoxFit.contain,
                  memCacheWidth: (26 * dpr).round(),
                  errorWidget: (_, __, ___) => Icon(Icons.emoji_events_rounded, color: l.colors.last, size: 16),
                ),
              ),
              text: l.name,
              onTap: () => _openLeague(context, l),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBodyContent(
    BuildContext context,
    int selectedTab,
    SportsState state,
    String query,
    bool isDark,
    Color accentColor,
  ) {
    if (state.isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(accentColor)),
            const SizedBox(height: 14),
            Text(
              'جارٍ جلب جدول المباريات...',
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black54,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    if (state.error != null && state.groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(
              state.error!,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    if (selectedTab == 1) {
      // Live Matches tab
      final liveList = state.liveMatches.where((m) {
        if (query.isNotEmpty) {
          final q = query.toLowerCase();
          return m.home.name.toLowerCase().contains(q) ||
              m.away.name.toLowerCase().contains(q) ||
              (m.league ?? '').toLowerCase().contains(q);
        }
        return true;
      }).toList();

      if (liveList.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sensors_off_rounded, size: 48, color: isDark ? Colors.white24 : Colors.black26),
              const SizedBox(height: 12),
              Text(
                'لا توجد مباريات جارية حالياً',
                style: TextStyle(
                  color: isDark ? Colors.white60 : Colors.black54,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      }

      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        itemCount: liveList.length,
        itemBuilder: (ctx, i) {
          return _buildMatchCard(ctx, liveList[i], isDark, accentColor);
        },
      );
    }

    if (selectedTab == 2) {
      // Sports Channels tab
      return Consumer(
        builder: (context, ref, _) {
          final channelsAsync = ref.watch(sportsChannelsProvider);
          return channelsAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF1744)),
            ),
            error: (_, __) => Center(
              child: Text(
                'تعذر تحميل القنوات الرياضية',
                style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
              ),
            ),
            data: (channels) {
              final filtered = query.isEmpty
                  ? channels
                  : channels.where((c) =>
                      c.channelName.toLowerCase().contains(query.toLowerCase()) ||
                      c.categoryName.toLowerCase().contains(query.toLowerCase())).toList();

              if (filtered.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.tv_off_rounded, size: 48, color: isDark ? Colors.white24 : Colors.black26),
                      const SizedBox(height: 12),
                      Text(
                        query.isEmpty
                            ? 'لا توجد قنوات تعمل حالياً'
                            : 'لا توجد قنوات رياضية مطابقة للبحث',
                        style: TextStyle(
                          color: isDark ? Colors.white60 : Colors.black54,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return GridView.builder(
                padding: const EdgeInsets.all(14),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.05,
                ),
                itemCount: filtered.length,
                itemBuilder: (ctx, i) {
                  return _buildSportsChannelCard(ctx, filtered[i], isDark, accentColor);
                },
              );
            },
          );
        },
      );
    }

    if (selectedTab == 3) {
      // News tab
      return Consumer(
        builder: (context, ref, _) {
          final newsAsync = ref.watch(sportsNewsProvider);
          return newsAsync.when(
            loading: () => Center(
              child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(accentColor)),
            ),
            error: (_, __) => Center(
              child: Text(
                'تعذر تحميل الأخبار الرياضية',
                style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
              ),
            ),
            data: (news) {
              if (news.isEmpty) {
                return Center(
                  child: Text(
                    'لا توجد أخبار رياضية حالياً',
                    style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(14),
                itemCount: news.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (ctx, i) => _buildNewsCard(news[i], isDark),
              );
            },
          );
        },
      );
    }

    // Default: All Matches Tab grouped by League
    List<LeagueGroup> filteredGroups = state.groups;
    if (query.isNotEmpty) {
      final q = query.toLowerCase();
      filteredGroups = state.groups
          .map((g) {
            final matches = g.matches.where((m) {
              return m.home.name.toLowerCase().contains(q) ||
                  m.away.name.toLowerCase().contains(q) ||
                  g.league.toLowerCase().contains(q);
            }).toList();
            return LeagueGroup(
              leagueId: g.leagueId,
              cid: g.cid,
              league: g.league,
              logo: g.logo,
              matches: matches,
            );
          })
          .where((g) => g.matches.isNotEmpty)
          .toList();
    }

    if (filteredGroups.isEmpty) {
      // No matches on this day: the leagues stay reachable above the notice.
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        children: [
          const SizedBox(height: 40),
          Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_busy_rounded, size: 48, color: isDark ? Colors.white24 : Colors.black26),
            const SizedBox(height: 12),
            Text(
              'لا توجد مباريات مطابقة للبحث',
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.black54,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      itemCount: filteredGroups.length,
      itemBuilder: (ctx, i) {
        final group = filteredGroups[i];
        final league = _leagueOf(group);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // League Header - tap for the competition's page
            InkWell(
              onTap: league == null ? null : () => _openLeague(ctx, league),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  if (group.logo != null && group.logo!.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(
                        group.logo!,
                        width: 22,
                        height: 22,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.emoji_events_rounded,
                          size: 20,
                          color: Colors.amber,
                        ),
                      ),
                    )
                  else
                    const Icon(Icons.emoji_events_rounded, size: 20, color: Colors.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      group.league,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E2638) : const Color(0xFFE6EAF2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${group.matches.length}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ),
                  if (league != null) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_left_rounded, size: 20, color: isDark ? Colors.white54 : Colors.black45),
                  ],
                ],
              ),
              ),
            ),

            // Matches inside this league
            ...group.matches.map((m) => _buildMatchCard(ctx, m, isDark, accentColor)),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Widget _buildMatchCard(
    BuildContext context,
    SportMatchItem match,
    bool isDark,
    Color accentColor,
  ) {
    final hasStream = match.hasWatch || match.streamId != null;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  AppPalette.of(context).card,
                  const Color(0xFF101422),
                ]
              : [
                  Colors.white,
                  const Color(0xFFF7F9FD),
                ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: match.isLive
              ? const Color(0xFFFF334B).withOpacity(0.55)
              : (isDark ? AppPalette.of(context).border : const Color(0xFFE4E9F2)),
          width: match.isLive ? 1.5 : 1.0,
        ),
        boxShadow: !isDark && !match.isLive
            ? AppPalette.of(context).cardShadow
            : [
                BoxShadow(
                  color: match.isLive
                      ? const Color(0xFFFF334B).withOpacity(isDark ? 0.18 : 0.08)
                      : Colors.black.withOpacity(isDark ? 0.3 : 0.04),
                  blurRadius: match.isLive ? 14 : 8,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openPlayer(context, match),
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Column(
              children: [
                // 1. Top status header (Match Status / Time / League)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // League / Competition title if available
                    if (match.league != null && match.league!.isNotEmpty)
                      Expanded(
                        child: Row(
                          children: [
                            if (match.leagueLogo != null && match.leagueLogo!.isNotEmpty) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.network(
                                  match.leagueLogo!,
                                  width: 16,
                                  height: 16,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.emoji_events_outlined,
                                    size: 14,
                                    color: Colors.amber,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Flexible(
                              child: Text(
                                match.league!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white60 : Colors.black54,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      const Spacer(),

                    // Match Status Pill (مباشر / وقت المباراة / انتهت)
                    _buildStatusPill(match, isDark),
                  ],
                ),

                const SizedBox(height: 12),

                // 2. Main Match Row: Home Club - VS / Score - Away Club
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Home Team
                    Expanded(
                      flex: 4,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildLargeClubLogo(match.home.logo, isDark),
                          const SizedBox(height: 8),
                          Text(
                            match.home.name,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              height: 1.25,
                              color: isDark ? Colors.white : const Color(0xFF111827),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Center: Beautiful "VS" Badge & Score
                    Expanded(
                      flex: 3,
                      child: _buildCenterVsSection(match, isDark),
                    ),

                    // Away Team
                    Expanded(
                      flex: 4,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildLargeClubLogo(match.away.logo, isDark),
                          const SizedBox(height: 8),
                          Text(
                            match.away.name,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              height: 1.25,
                              color: isDark ? Colors.white : const Color(0xFF111827),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // 2.5 Broadcaster Channel Badge (إذا كانت هناك قناة ناقلة معروفة)
                // The channels carrying this match, as pictures. No names.
                if (match.broadcasters.isNotEmpty || match.displayBroadcaster.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _buildBroadcasterMarks(match, isDark),
                ],

                const SizedBox(height: 14),

                // 3. Action Button: Watch Live or Match Details
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    gradient: hasStream
                        ? const LinearGradient(
                            colors: [Color(0xFFD50000), Color(0xFFFF1744)],
                          )
                        : null,
                    color: hasStream
                        ? null
                        : (isDark ? const Color(0xFF1C2436) : const Color(0xFFEFF2F8)),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: hasStream
                        ? [
                            BoxShadow(
                              color: const Color(0xFFFF1744).withOpacity(0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        hasStream ? Icons.play_circle_fill_rounded : Icons.info_outline_rounded,
                        color: hasStream ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                        size: 17,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        hasStream ? 'مشاهدة البث المباشر والتفاصيل' : 'التفاصيل والتشكيلة والأحداث',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: hasStream ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLargeClubLogo(String? logoUrl, bool isDark) {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1D253A) : const Color(0xFFEEF2F9),
        shape: BoxShape.circle,
        border: Border.all(
          color: isDark ? const Color(0xFF2E3B59) : const Color(0xFFD6DFEF),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.35 : 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: ClipOval(
          child: logoUrl != null && logoUrl.isNotEmpty
              ? Image.network(
                  logoUrl,
                  width: 44,
                  height: 44,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.shield_rounded,
                    size: 26,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                )
              : Icon(
                  Icons.shield_rounded,
                  size: 26,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
        ),
      ),
    );
  }

  Widget _buildCenterVsSection(SportMatchItem match, bool isDark) {
    if (match.isLive) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Live Score
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFF334B).withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFFF334B).withOpacity(0.3),
                width: 1,
              ),
            ),
            child: MatchScoreLine(
              homeScore: match.homeScore,
              awayScore: match.awayScore,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Color(0xFFFF334B),
                letterSpacing: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Mini VS Badge
          _buildVsBadge(isDark, isLive: true),
        ],
      );
    }

    if (match.isEnded) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Final Score
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E263A) : const Color(0xFFE9EDF5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: MatchScoreLine(
              homeScore: match.homeScore,
              awayScore: match.awayScore,
              separator: '-',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 6),
          _buildVsBadge(isDark),
        ],
      );
    }

    // Scheduled match: The prominent beautiful VS Badge + Kickoff Time
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildVsBadge(isDark, isProminent: true),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1B2337) : const Color(0xFFEEF2F8),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _formatKickoff(match.kickoffAt),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVsBadge(bool isDark, {bool isLive = false, bool isProminent = false}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isProminent ? 14 : 9,
        vertical: isProminent ? 6 : 3,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isLive
              ? [
                  const Color(0xFFFF334B).withOpacity(0.2),
                  const Color(0xFFFF5252).withOpacity(0.08),
                ]
              : (isDark
                  ? [
                      const Color(0xFF26324D),
                      const Color(0xFF192135),
                    ]
                  : [
                      const Color(0xFFE3E9F5),
                      const Color(0xFFD4DFEE),
                    ]),
        ),
        borderRadius: BorderRadius.circular(isProminent ? 14 : 8),
        border: Border.all(
          color: isLive
              ? const Color(0xFFFF334B).withOpacity(0.4)
              : (isProminent
                  ? (isDark ? const Color(0xFFFF1744).withOpacity(0.6) : const Color(0xFFD50000).withOpacity(0.5))
                  : (isDark ? Colors.white12 : Colors.black12)),
          width: isProminent ? 1.5 : 1.0,
        ),
        boxShadow: isProminent
            ? [
                BoxShadow(
                  color: (isDark ? const Color(0xFFFF1744) : const Color(0xFFD50000)).withOpacity(isDark ? 0.2 : 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Text(
        'VS',
        style: TextStyle(
          fontSize: isProminent ? 14 : 10.5,
          fontWeight: FontWeight.w900,
          fontStyle: FontStyle.italic,
          letterSpacing: 2.0,
          color: isLive
              ? const Color(0xFFFF334B)
              : (isProminent
                  ? (isDark ? const Color(0xFFFF1744) : const Color(0xFFD50000))
                  : (isDark ? Colors.white54 : Colors.black54)),
        ),
      ),
    );
  }

  Widget _buildStatusPill(SportMatchItem match, bool isDark) {
    if (match.isLive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFFF334B).withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFFFF334B).withOpacity(0.4),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: Color(0xFFFF334B),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              match.minute != null ? "مباشر ${match.minute}'" : 'مباشر الآن',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFF334B),
              ),
            ),
          ],
        ),
      );
    }

    if (match.isEnded) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1F273B) : const Color(0xFFEBEFF6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'انتهت',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white54 : Colors.black45,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF182033) : const Color(0xFFEEF2F8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black12,
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule_rounded,
            size: 12,
            color: isDark ? Colors.white54 : Colors.black45,
          ),
          const SizedBox(width: 4),
          Text(
            _formatKickoff(match.kickoffAt),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayPill({
    required String label,
    required String dayKey,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
    required Color accentColor,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected
                ? accentColor
                : (isDark ? const Color(0xFF181F2F) : const Color(0xFFEEF1F6)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              color: isSelected
                  ? Colors.black
                  : (isDark ? Colors.white70 : Colors.black87),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabButton({
    required String title,
    required IconData icon,
    int? badgeCount,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
    required Color accentColor,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: isSelected
                ? accentColor.withOpacity(isDark ? 0.2 : 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? accentColor : (isDark ? Colors.white10 : Colors.black12),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? accentColor : (isDark ? Colors.white54 : Colors.black54),
              ),
              const SizedBox(width: 5),
              Text(
                title,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected ? accentColor : (isDark ? Colors.white70 : Colors.black87),
                ),
              ),
              if (badgeCount != null && badgeCount > 0) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF334B),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNewsCard(SportNewsItem news, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppPalette.of(context).card : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF1F263A) : const Color(0xFFE9EDF5),
        ),
        boxShadow: isDark ? null : AppPalette.of(context).cardShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (news.image != null && news.image!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                news.image!,
                width: 80,
                height: 80,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  news.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                if (news.description != null && news.description!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    news.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                if (news.date != null || news.time != null)
                  Text(
                    '${news.date ?? ''} ${news.time ?? ''}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFFF1744),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSportsChannelCard(
    BuildContext context,
    SportsChannel channel,
    bool isDark,
    Color accentColor,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppPalette.of(context).card : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppPalette.of(context).border : AppPalette.of(context).border,
          width: 1.0,
        ),
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ]
            : AppPalette.of(context).cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            final match = SportMatchItem.fromSportsChannel(channel);
            _openPlayer(context, match, channel: channel);
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  alignment: Alignment.topRight,
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: isDark ? AppPalette.of(context).cardAlt : const Color(0xFFF3F5F9),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark ? AppPalette.of(context).border : AppPalette.of(context).border,
                          width: 1,
                        ),
                      ),
                      child: channel.channelImage.isNotEmpty
                          ? Image.network(
                              channel.channelImage,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.live_tv_rounded,
                                size: 28,
                                color: Color(0xFFFF1744),
                              ),
                            )
                          : const Icon(
                              Icons.live_tv_rounded,
                              size: 28,
                              color: Color(0xFFFF1744),
                            ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF1744),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'LIVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  channel.channelName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  channel.categoryName.isNotEmpty ? channel.categoryName : 'قناة رياضية',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF1744).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFFFF1744).withOpacity(0.3),
                      width: 0.8,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.play_arrow_rounded, color: Color(0xFFFF1744), size: 14),
                      SizedBox(width: 3),
                      Text(
                        'مشاهدة الآن',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFF1744),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
