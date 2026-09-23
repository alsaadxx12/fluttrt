import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';
import 'package:youtube_downloader/features/sports/presentation/widgets/match_score_line.dart';
import 'package:youtube_downloader/presentation/widgets/app_search_field.dart';
import 'package:youtube_downloader/features/subscription/presentation/providers/subscription_provider.dart';
import '../../data/models/sports_models.dart';
import '../../data/match_order.dart';
import '../providers/sports_provider.dart';
import 'sports_player_screen.dart';
import 'league_screen.dart';
import '../../../../core/tv/tv_mode.dart';

import '../../../home/presentation/widgets/football_showcase.dart';
import 'package:cached_network_image/cached_network_image.dart';

class SportsScreen extends ConsumerStatefulWidget {
  const SportsScreen({super.key});

  @override
  ConsumerState<SportsScreen> createState() => _SportsScreenState();
}

class _SportsScreenState extends ConsumerState<SportsScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }
    // Verify subscription access immediately on entry
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final isUnlocked = ref.read(isSportsUnlockedProvider);
      if (!isUnlocked) {
        await ref.read(sportsSubscriptionProvider.notifier).refresh();
        if (mounted && !ref.read(isSportsUnlockedProvider)) {
          context.pushReplacement('/sports-activation');
        }
      }
    });

    // Auto refresh live matches and subscription check every 60 seconds
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) {
        final currentDay = ref.read(sportsDayProvider);
        ref.read(sportsNotifierProvider(currentDay).notifier).refresh();
        ref.read(sportsSubscriptionProvider.notifier).refresh();
      }
    });
  }


  int _calculateColumns(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    final isTv = ref.watch(tvModeProvider).valueOrNull ?? false;

    if (isTv || isDesktop) {
      if (width >= 1500) return 3;
      if (width >= 600) return 2;
      return 1;
    }

    // Mobile / Tablet / Web
    if (width >= 1200) return 3;
    if (width >= 650) return 2;
    return 1;
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String _formatKickoff(String isoString) {
    if (isoString.trim().isEmpty) return '';
    final raw = isoString.trim();
    try {
      DateTime? dateTime = DateTime.tryParse(raw);
      if (dateTime == null) {
        // Fallback for HH:MM strings with optional AM/PM or ص/م
        final match = RegExp(r'(\d{1,2}):(\d{2})\s*([a-zA-Z\u0600-\u06FF]+)?').firstMatch(raw);
        if (match != null) {
          int h = int.tryParse(match.group(1) ?? '') ?? 0;
          final m = int.tryParse(match.group(2) ?? '') ?? 0;
          final period = (match.group(3) ?? '').toLowerCase().trim();
          if (period.contains('p') || period.contains('م')) {
            if (h < 12) h += 12;
          } else if (period.contains('a') || period.contains('ص')) {
            if (h == 12) h = 0;
          }
          final now = DateTime.now();
          // Assume Mecca time (UTC+3) and convert to UTC
          dateTime = DateTime.utc(now.year, now.month, now.day, h, m).subtract(const Duration(hours: 3));
        }
      }
      if (dateTime != null) {
        final local = dateTime.toLocal();
        final h = local.hour;
        final m = local.minute.toString().padLeft(2, '0');
        final period = h >= 12 ? 'م' : 'ص';
        final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
        return '$h12:$m $period';
      }
    } catch (_) {}
    return raw;
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
    ).then((_) {
      if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
      }
    });
  }

  /// The group list the streams were warmed for, so the scan does not run
  /// again on every rebuild.
  List<LeagueGroup>? _warmedGroups;

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(isSportsUnlockedProvider, (previous, next) {
      if (!next && mounted) {
        context.pushReplacement('/sports-activation');
      }
    });

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedDay = ref.watch(sportsDayProvider);
    final selectedTab = ref.watch(sportsTabProvider);
    final searchQuery = ref.watch(sportsSearchQueryProvider);
    final sportsState = ref.watch(sportsNotifierProvider(selectedDay));
    final sportsNotifier = ref.read(sportsNotifierProvider(selectedDay).notifier);

    // Resolve the streams of the matches that are live right now, before any
    // of them is tapped: the first one opened then starts with no round trip
    // of its own.
    if (!identical(sportsState.groups, _warmedGroups)) {
      _warmedGroups = sportsState.groups;
      final liveIds = <int>[
        for (final g in sportsState.groups)
          for (final m in g.matches)
            if ((m.isLive || m.status == 'live') && m.streamId != null) m.streamId!,
      ];
      if (liveIds.isNotEmpty) {
        ref.read(streamWarmupProvider).prefetch(liveIds);
      }
    }

    final palette = AppPalette.of(context);
    const accentColor = Color(0xFFFF1744);

    return Scaffold(
      backgroundColor: palette.bg,
      body: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: palette.card,
              border: Border(
                bottom: BorderSide(
                  color: palette.border,
                  width: 1,
                ),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Search Field Only in Top Bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                    child: AppSearchField(
                      controller: _searchController,
                      hints: const ['ابحث عن مباراة', 'ابحث عن فريق', 'ابحث عن دوري'],
                      onChanged: (val) {
                        ref.read(sportsSearchQueryProvider.notifier).state = val.trim();
                      },
                      onClear: () {
                        ref.read(sportsSearchQueryProvider.notifier).state = '';
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Leagues strip: the day's leagues plus the way to all of them.
          if (selectedTab == 0 && sportsState.groups.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 2),
              child: _buildLeaguesRow(context, sportsState, isDark),
            ),

          // Body Content
          Expanded(
            child: RefreshIndicator(
              triggerMode: RefreshIndicatorTriggerMode.anywhere,
              backgroundColor: palette.card,
              color: const Color(0xFFE50914),
              strokeWidth: 2.4,
              onRefresh: () => sportsNotifier.refresh(),
              child: _buildBodyContent(
                context,
                selectedTab,
                selectedDay,
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





  /// The competition behind a match group: matched against the app's known
  /// leagues by id or Arabic name to provide official logos and icons.
  static FootballLeague _leagueOf(LeagueGroup g) {
    final cid = g.cid;
    if (cid != null && cid > 0) {
      for (final l in [...FootballLeague.world, ...FootballLeague.arab]) {
        if (l.id == cid) return l;
      }
      return FootballLeague(cid, g.league, '', const [Color(0xFF1B2440), Color(0xFF0B0F1A)]);
    }

    String norm(String s) => s
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll('ـ', '')
        .toLowerCase()
        .trim();

    final nRaw = norm(g.league);

    if (nRaw.contains('انجليز') || nRaw.contains('بريميرليج') || nRaw.contains('ممتاز')) {
      return FootballLeague.world.firstWhere((l) => l.id == 7);
    }
    if (nRaw.contains('اسبان') || nRaw.contains('لا ليغا') || nRaw.contains('لاليغا') || nRaw.contains('ليجا')) {
      return FootballLeague.world.firstWhere((l) => l.id == 11);
    }
    if (nRaw.contains('ايطال') || nRaw.contains('سيريا')) {
      return FootballLeague.world.firstWhere((l) => l.id == 17);
    }
    if (nRaw.contains('المان') || nRaw.contains('بوندسليجا') || nRaw.contains('بوندسليغا')) {
      return FootballLeague.world.firstWhere((l) => l.id == 25);
    }
    if (nRaw.contains('فرنس') || nRaw.contains('ليج 1') || nRaw.contains('ليغ 1')) {
      return FootballLeague.world.firstWhere((l) => l.id == 35);
    }
    if (nRaw.contains('ابطال اوروبا') || nRaw.contains('تشامبيونز ليج') || nRaw.contains('تشامبيونز ليغ')) {
      return FootballLeague.world.firstWhere((l) => l.id == 572);
    }
    if (nRaw.contains('ابطال اسيا')) {
      return FootballLeague.world.firstWhere((l) => l.id == 623);
    }
    if (nRaw.contains('الدوري الاوروبي') || nRaw.contains('يوروبا ليج') || nRaw.contains('يوروباليغ')) {
      return FootballLeague.world.firstWhere((l) => l.id == 573);
    }
    if (nRaw.contains('المؤتمر الاوروبي')) {
      return FootballLeague.world.firstWhere((l) => l.id == 7685);
    }
    if (nRaw.contains('سعود') || nRaw.contains('روشن')) {
      return FootballLeague.arab.firstWhere((l) => l.id == 649);
    }
    if (nRaw.contains('عراق') || nRaw.contains('نجوم العراق')) {
      return FootballLeague.arab.firstWhere((l) => l.id == 6822);
    }
    if (nRaw.contains('مصر') || nRaw.contains('نايل')) {
      return FootballLeague.arab.firstWhere((l) => l.id == 552);
    }
    if (nRaw.contains('امارات') || nRaw.contains('ادنوك')) {
      return FootballLeague.arab.firstWhere((l) => l.id == 549);
    }
    if (nRaw.contains('قطر') || nRaw.contains('نجوم قطر')) {
      return FootballLeague.arab.firstWhere((l) => l.id == 408);
    }
    if (nRaw.contains('مغرب') || nRaw.contains('البطوله الاحترافيه')) {
      return FootballLeague.arab.firstWhere((l) => l.id == 557);
    }
    if (nRaw.contains('جزائر') || nRaw.contains('الرابطه المحترفه')) {
      return FootballLeague.arab.firstWhere((l) => l.id == 560);
    }
    if (nRaw.contains('تونس')) {
      return FootballLeague.arab.firstWhere((l) => l.id == 554);
    }
    if (nRaw.contains('كويت')) {
      return FootballLeague.arab.firstWhere((l) => l.id == 5473);
    }
    if (nRaw.contains('اردن')) {
      return FootballLeague.arab.firstWhere((l) => l.id == 565);
    }
    if (nRaw.contains('برتغال')) {
      return FootballLeague.world.firstWhere((l) => l.id == 73);
    }
    if (nRaw.contains('هولندا')) {
      return FootballLeague.world.firstWhere((l) => l.id == 57);
    }
    if (nRaw.contains('ترك')) {
      return FootballLeague.world.firstWhere((l) => l.id == 78);
    }

    for (final l in [...FootballLeague.world, ...FootballLeague.arab]) {
      final nL = norm(l.name);
      if (nRaw == nL || nRaw.contains(nL) || nL.contains(nRaw)) {
        return l;
      }
    }

    var cleanLeagueName = g.league;
    if (cleanLeagueName.contains(' - ')) {
      cleanLeagueName = cleanLeagueName.split(' - ').first.trim();
    } else if (cleanLeagueName.contains(' الجولة ')) {
      cleanLeagueName = cleanLeagueName.split(' الجولة ').first.trim();
    }

    return FootballLeague(
      g.leagueId,
      cleanLeagueName,
      '',
      const [Color(0xFF1B2440), Color(0xFF0B0F1A)],
    );
  }

  void _openLeague(BuildContext context, FootballLeague league) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => LeagueScreen(league: league)),
    );
  }

  /// Horizontal leagues filter bar:
  /// - Defaults to "كل الدوريات" (selected by default with glowing accent)
  /// - Beside it are the day's active leagues with their official logos and names
  Widget _buildLeaguesRow(BuildContext context, SportsState state, bool isDark) {
    final selectedLeagueId = ref.watch(sportsLeagueFilterProvider);
    final today = <FootballLeague>[];
    final seen = <int>{};
    for (final g in state.groups) {
      final l = _leagueOf(g);
      if (seen.add(l.id)) today.add(l);
    }
    final dpr = MediaQuery.of(context).devicePixelRatio;

    Widget pill({
      required Widget leading,
      required String text,
      required VoidCallback onTap,
      VoidCallback? onLongPress,
      required bool isSelected,
    }) {
      return InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 38,
          padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 14, 0),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFE50914) : (isDark ? const Color(0xFF192032) : Colors.white),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isSelected ? const Color(0xFFE50914) : (isDark ? const Color(0xFF26324D) : const Color(0xFFE2E8F0)),
              width: 1.2,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFFE50914).withOpacity(0.32),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              leading,
              const SizedBox(width: 7),
              Text(
                text,
                style: TextStyle(
                  color: isSelected ? Colors.white : (isDark ? Colors.white : const Color(0xFF0F172A)),
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 2),
        children: [
          // 1. "كل الدوريات" Pill - Selected by default
          pill(
            isSelected: selectedLeagueId == null,
            leading: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: selectedLeagueId == null ? Colors.white.withOpacity(0.25) : const Color(0xFFE50914).withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.emoji_events_rounded,
                color: selectedLeagueId == null ? Colors.white : const Color(0xFFE50914),
                size: 16,
              ),
            ),
            text: 'كل الدوريات',
            onTap: () {
              ref.read(sportsLeagueFilterProvider.notifier).state = null;
            },
          ),

          // 2. Individual League Pills with their official logos and names
          for (final l in today) ...[
            const SizedBox(width: 8),
            pill(
              isSelected: selectedLeagueId == l.id,
              leading: Container(
                width: 26,
                height: 26,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: l.darkBadge ? const Color(0xFF0C1410) : Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: CachedNetworkImage(
                  imageUrl: l.logoUrl,
                  fit: BoxFit.contain,
                  memCacheWidth: (26 * dpr).round(),
                  placeholder: (_, __) => const SizedBox(
                    width: 14,
                    height: 14,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFFE50914)),
                    ),
                  ),
                  errorWidget: (_, __, ___) => Icon(
                    Icons.sports_soccer_rounded,
                    color: l.colors.last,
                    size: 16,
                  ),
                ),
              ),
              text: l.name,
              onTap: () {
                if (selectedLeagueId == l.id) {
                  ref.read(sportsLeagueFilterProvider.notifier).state = null;
                } else {
                  ref.read(sportsLeagueFilterProvider.notifier).state = l.id;
                }
              },
              onLongPress: () => _openLeague(context, l),
            ),
          ],
        ],
      ),
    );
  }



  /// A state with nothing to scroll (an error, an empty list) still lets the
  /// page be pulled down to refresh: it is laid out inside a scrollable that
  /// fills the viewport.
  Widget _pullable(Widget child) => LayoutBuilder(
        builder: (context, box) => ListView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          children: [SizedBox(height: box.maxHeight, child: child)],
        ),
      );

  Widget _buildBodyContent(
    BuildContext context,
    int selectedTab,
    String selectedDay,
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
      return _pullable(Center(
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
      ));
    }

    if (selectedTab == 1) {
      // Live Matches tab
      final seenLive = <String>{};
      final uniqueLive = <SportMatchItem>[];
      for (final m in state.groups.expand((g) => g.matches).where((m) => m.isLive || m.status == 'live')) {
        final key = '${m.home.name.trim().toLowerCase()}_${m.away.name.trim().toLowerCase()}';
        if (seenLive.add(key)) {
          uniqueLive.add(m);
        }
      }

      final liveList = uniqueLive.where((m) {
        if (query.isNotEmpty) {
          final q = query.toLowerCase();
          return m.home.name.toLowerCase().contains(q) ||
              m.away.name.toLowerCase().contains(q) ||
              (m.league ?? '').toLowerCase().contains(q);
        }
        return true;
      }).toList();

      if (liveList.isEmpty) {
        return _pullable(Center(
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
        ));
      }

      final columns = _calculateColumns(context);
      if (columns <= 1) {
        return ListView.builder(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          itemCount: liveList.length,
          itemBuilder: (ctx, i) {
            return _buildMatchCard(ctx, liveList[i], isDark, accentColor);
          },
        );
      }

      final rowCount = (liveList.length + columns - 1) ~/ columns;
      return ListView.builder(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        itemCount: rowCount,
        itemBuilder: (ctx, rowIndex) {
          final rowStart = rowIndex * columns;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var c = 0; c < columns; c++) ...[
                if (c > 0) const SizedBox(width: 12),
                Expanded(
                  child: (rowStart + c < liveList.length)
                      ? _buildMatchCard(ctx, liveList[rowStart + c], isDark, accentColor)
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          );
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
                return _pullable(Center(
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
                ));
              }

              final width = MediaQuery.of(context).size.width;
              final channelCols = width >= 1400 ? 5 : (width >= 1000 ? 4 : (width >= 600 ? 3 : 2));
              return GridView.builder(
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                padding: const EdgeInsets.all(14),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: channelCols,
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
                return _pullable(Center(
                  child: Text(
                    'لا توجد أخبار رياضية حالياً',
                    style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
                  ),
                ));
              }
              return ListView.separated(
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
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

    // Default: every match of the day in ONE list ordered by start time —
    // what is in play first, then kick-offs soonest-first — so a reader sees
    // at a glance what has started, instead of browsing league by league.
    // Each card names its league, so per-league headers are not needed.
    final selectedLeagueId = ref.watch(sportsLeagueFilterProvider);
    final q = query.toLowerCase();
    final seenAll = <String>{};
    final uniqueAll = <SportMatchItem>[];
    for (final g in state.groups) {
      if (selectedLeagueId != null) {
        final l = _leagueOf(g);
        if (l.id != selectedLeagueId && g.leagueId != selectedLeagueId) {
          continue;
        }
      }
      for (final m in g.matches) {
        final key = m.id > 0
            ? '${m.id}'
            : '${m.home.name.trim().toLowerCase()}_${m.away.name.trim().toLowerCase()}';
        if (!seenAll.add(key)) continue;
        if (q.isEmpty ||
            m.home.name.toLowerCase().contains(q) ||
            m.away.name.toLowerCase().contains(q) ||
            g.league.toLowerCase().contains(q) ||
            (m.league ?? '').toLowerCase().contains(q)) {
          uniqueAll.add(m);
        }
      }
    }
    final ordered = MatchOrder.dayOrder(uniqueAll, includeEnded: true);

    if (ordered.isEmpty) {
      return ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        children: [
          const SizedBox(height: 80),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sports_soccer_rounded, size: 64, color: isDark ? Colors.white24 : Colors.black26),
              const SizedBox(height: 16),
              Text(
                query.isNotEmpty
                    ? 'لا توجد مباريات مطابقة للبحث'
                    : (selectedLeagueId != null
                        ? 'لا توجد مباريات لهذا الدوري'
                        : (selectedDay == 'yesterday'
                            ? 'لا توجد مباريات للأمس'
                            : (selectedDay == 'tomorrow'
                                ? 'لا توجد مباريات للغد'
                                : 'لا توجد مباريات اليوم'))),
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black54,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (selectedLeagueId != null) ...[
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: () => ref.read(sportsLeagueFilterProvider.notifier).state = null,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('عرض كل الدوريات'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE50914),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ],
            ],
          ),
        ],
      );
    }

    final columns = _calculateColumns(context);

    // Sections: "in play now", then one per kick-off time, then ended.
    final sections = <({String title, bool live, List<SportMatchItem> matches})>[];
    if (selectedDay == 'today') {
      final live = ordered.where((m) => m.isLive).toList();
      if (live.isNotEmpty) sections.add((title: 'جارية الآن', live: true, matches: live));
    }

    final upcoming = (selectedDay == 'tomorrow')
        ? ordered
        : ((selectedDay == 'yesterday')
            ? <SportMatchItem>[]
            : ordered.where((m) => m.isScheduled).toList());
    String? currentTime;
    for (final m in upcoming) {
      final t = _formatKickoff(m.kickoffAt);
      if (t != currentTime) {
        currentTime = t;
        sections.add((title: t.isEmpty ? 'موعد غير محدد' : t, live: false, matches: <SportMatchItem>[]));
      }
      sections.last.matches.add(m);
    }

    final ended = (selectedDay == 'yesterday')
        ? ordered
        : ((selectedDay == 'tomorrow')
            ? <SportMatchItem>[]
            : ordered.where((m) => m.isEnded).toList());
    if (ended.isNotEmpty) {
      sections.add((title: 'المباريات المنتهية', live: false, matches: ended));
    }

    // Flattened into rows so the list stays lazy: a header, then card rows.
    final rows = <Widget Function(BuildContext)>[];
    // No headers: the cards run on, in play first, then by kick-off, then
    // over. Each card says for itself where it stands.
    for (final sec in sections) {
      final ms = sec.matches;
      if (columns <= 1) {
        for (final m in ms) {
          rows.add((ctx) => _buildMatchCard(ctx, m, isDark, accentColor));
        }
      } else {
        for (var startAt = 0; startAt < ms.length; startAt += columns) {
          final slice = ms.sublist(startAt, (startAt + columns).clamp(0, ms.length));
          rows.add((ctx) => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var c = 0; c < columns; c++) ...[
                    if (c > 0) const SizedBox(width: 12),
                    Expanded(
                      child: c < slice.length
                          ? _buildMatchCard(ctx, slice[c], isDark, accentColor)
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ));
        }
      }
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      itemCount: rows.length,
      itemBuilder: (ctx, i) => rows[i](ctx),
    );
  }



  Widget _buildMatchCard(
    BuildContext context,
    SportMatchItem match,
    bool isDark,
    Color accentColor,
  ) {
    final isLive = match.isLive;
    final isUpcoming = match.isScheduled;

    // Glass, like the home page's card: the page shows through a deep
    // blur and a faint white sheen, under a thin light edge - red while
    // the match is on.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAliasWithSaveLayer,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [Colors.white.withOpacity(0.14), Colors.white.withOpacity(0.05)]
              : [Colors.white.withOpacity(0.85), Colors.white.withOpacity(0.65)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isLive
              ? const Color(0xFFFF334B).withOpacity(0.55)
              : Colors.white.withOpacity(isDark ? 0.20 : 0.9),
          width: isLive ? 1.5 : 0.8,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (isUpcoming) {
              ScaffoldMessenger.of(context).removeCurrentSnackBar();
              final timeStr = _formatKickoff(match.kickoffAt);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.schedule_rounded, color: Colors.white70, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          timeStr.isNotEmpty
                              ? 'المباراة لم تبدأ بعد، سيبدأ البث المباشر في تمام الساعة $timeStr'
                              : 'المباراة لم تبدأ بعد، سيتوفر البث المباشر فور انطلاقها',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: const Color(0xFF1E2638),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  duration: const Duration(seconds: 3),
                ),
              );
              return;
            }
            _openPlayer(context, match);
          },
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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

                const SizedBox(height: 8),

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
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 34,
                            child: Center(
                              child: Text(
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
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 34,
                            child: Center(
                              child: Text(
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
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Into the match, for one in play: a round red play button and
                // nothing else. A match still to come, or over, says so in
                // its status line and needs no bar of words under it.
                if (isLive) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFD50000), Color(0xFFFF1744)],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF1744).withOpacity(0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
          ),
        ),
      );
  }

  /// The club's crest, big and on nothing: no disc, no ring.
  Widget _buildLargeClubLogo(String? logoUrl, bool isDark) {
    final fallback = Icon(Icons.shield_rounded, size: 40, color: isDark ? Colors.white38 : Colors.black38);
    return SizedBox(
      width: 84,
      height: 84,
      child: logoUrl != null && logoUrl.isNotEmpty
          ? Image.network(
              logoUrl,
              width: 84,
              height: 84,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, __, ___) => fallback,
            )
          : fallback,
    );
  }

  Widget _buildCenterVsSection(SportMatchItem match, bool isDark) {
    final kickoffTime = _formatKickoff(match.kickoffAt);

    if (match.isLive) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Live Score
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
        ],
      );
    }

    // Scheduled match: The prominent beautiful Kickoff Time + subtle VS badge
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.schedule_rounded, size: 13, color: isDark ? const Color(0xFFFFD700) : const Color(0xFFE50914)),
              const SizedBox(width: 5),
              Text(
                kickoffTime.isNotEmpty ? kickoffTime : 'لم تبدأ',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        _buildVsBadge(isDark, isProminent: true),
      ],
    );
  }

  Widget _buildVsBadge(bool isDark, {bool isLive = false, bool isProminent = false}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isProminent ? 14 : 9,
        vertical: isProminent ? 6 : 3,
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
    final kickoffTime = _formatKickoff(match.kickoffAt);

    if (match.isLive || match.status == 'live') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
              match.minute != null ? "مباشر ${match.minute}'" : 'مباشر',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFF334B),
              ),
            ),
            if (kickoffTime.isNotEmpty) ...[
              const SizedBox(width: 5),
              Text(
                '• $kickoffTime',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ],
          ],
        ),
      );
    }

    if (match.isEnded) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'انتهت',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ),
            if (kickoffTime.isNotEmpty) ...[
              const SizedBox(width: 5),
              Text(
                '• $kickoffTime',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule_rounded,
            size: 12,
            color: isDark ? Colors.white70 : const Color(0xFF475569),
          ),
          const SizedBox(width: 4),
          Text(
            kickoffTime.isNotEmpty ? kickoffTime : 'لم تبدأ بعد',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
        ],
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
                        color: isDark ? AppPalette.of(context).cardAlt : Colors.white,
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
