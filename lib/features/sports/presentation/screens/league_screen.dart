import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_palette.dart';
import '../../../home/presentation/widgets/football_showcase.dart';
import '../../data/models/sports_models.dart';
import '../../data/services/league_service.dart';
import '../providers/sports_provider.dart';
import 'sports_player_screen.dart';

final leagueServiceProvider = Provider<LeagueService>((ref) => LeagueService());

final leagueFixturesProvider = FutureProvider.family<List<LeagueFixture>, int>(
  (ref, id) => ref.watch(leagueServiceProvider).fetchFixtures(id),
);

final leagueStandingsProvider = FutureProvider.family<List<LeagueTable>, int>(
  (ref, id) => ref.watch(leagueServiceProvider).fetchStandings(id),
);

/// One competition: its fixtures (with a play button on the ones the app can
/// stream) and its table.
class LeagueScreen extends ConsumerStatefulWidget {
  final FootballLeague league;
  const LeagueScreen({super.key, required this.league});

  @override
  ConsumerState<LeagueScreen> createState() => _LeagueScreenState();
}

class _LeagueScreenState extends ConsumerState<LeagueScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// The app's own matches of this competition (yesterday / today /
  /// tomorrow), by 365Scores game id - these are the ones with a stream.
  Map<String, SportMatchItem> _streamable() {
    final out = <String, SportMatchItem>{};
    for (final day in const ['yesterday', 'today', 'tomorrow']) {
      final state = ref.watch(sportsNotifierProvider(day));
      for (final g in state.groups) {
        if (g.cid != widget.league.id) continue;
        for (final m in g.matches) {
          if (m.sourceId != null) out[m.sourceId!] = m;
        }
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final league = widget.league;

    return Scaffold(
      backgroundColor: p.bg,
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            expandedHeight: 190,
            pinned: true,
            backgroundColor: league.colors.first,
            foregroundColor: Colors.white,
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            title: Text(league.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: league.colors,
                  ),
                ),
                child: SafeArea(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 44),
                      child: Container(
                        width: 96,
                        height: 96,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: league.darkBadge ? const Color(0xFF0C1410) : Colors.white,
                          borderRadius: BorderRadius.circular(26),
                        ),
                        child: CachedNetworkImage(imageUrl: league.logoUrl, memCacheWidth: 160, fit: BoxFit.contain),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            bottom: TabBar(
              controller: _tabs,
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
              tabs: const [
                Tab(text: 'المباريات'),
                Tab(text: 'الترتيب'),
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabs,
          children: [
            _FixturesTab(league: league, streamable: _streamable()),
            _StandingsTab(league: league),
          ],
        ),
      ),
    );
  }
}

class _FixturesTab extends ConsumerWidget {
  final FootballLeague league;
  final Map<String, SportMatchItem> streamable;
  const _FixturesTab({required this.league, required this.streamable});

  static String _clock(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  static String _date(DateTime t) => '${t.day}/${t.month}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final async = ref.watch(leagueFixturesProvider(league.id));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFE50914))),
      error: (_, __) => _message(p, 'تعذّر تحميل المباريات'),
      data: (fixtures) {
        if (fixtures.isEmpty) return _message(p, 'لا توجد مباريات قريبة في هذه البطولة');
        final past = fixtures.where((f) => f.isEnded).toList();
        final coming = fixtures.where((f) => !f.isEnded).toList();
        Widget heading(String text, {bool live = false}) => Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
              child: Row(
                children: [
                  if (live) ...[
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFFF2A4A), shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                  ],
                  Text(text, style: TextStyle(color: p.text, fontSize: 14, fontWeight: FontWeight.w900)),
                ],
              ),
            );
        Widget round(String name) => name.isEmpty
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
                child: Text(name, style: TextStyle(color: p.textMuted, fontSize: 12, fontWeight: FontWeight.w800)),
              );
        List<Widget> section(List<LeagueFixture> list) {
          final out = <Widget>[];
          String? lastRound;
          for (final f in list) {
            if (f.roundName != lastRound) {
              out.add(round(f.roundName));
              lastRound = f.roundName;
            }
            out.add(_FixtureRow(data: FixtureRowData(fixture: f, match: streamable['${f.id}'], leagueName: league.name)));
          }
          return out;
        }
        final hasLive = coming.any((f) => f.isLive);
        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
          children: [
            if (coming.isNotEmpty) ...[
              heading(hasLive ? 'الآن والقادمة' : 'المباريات القادمة', live: hasLive),
              ...section(coming),
            ],
            if (past.isNotEmpty) ...[
              heading('النتائج الأخيرة'),
              ...section(past.reversed.toList()),
            ],
            if (coming.isEmpty && past.isEmpty) _message(p, 'لا توجد مباريات قريبة في هذه البطولة'),
          ],
        );
      },
    );
  }

  static Widget _message(AppPalette p, String text) =>
      Center(child: Text(text, style: TextStyle(color: p.textMuted, fontSize: 13.5)));
}

class _FixtureRow extends StatelessWidget {
  final FixtureRowData data;
  const _FixtureRow({required this.data});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final f = data.fixture;
    final live = f.isLive || (data.match?.isLive ?? false);
    final centre = live || f.isEnded ? '${f.homeScore ?? 0} - ${f.awayScore ?? 0}' : _FixturesTab._clock(f.startTime);
    final sub = live
        ? (f.statusText.isNotEmpty ? f.statusText : 'مباشر')
        : (f.isEnded ? 'انتهت' : _FixturesTab._date(f.startTime));
    final watchable = data.playable;
    return InkWell(
      onTap: watchable == null
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SportsPlayerScreen(match: watchable))),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: live ? const Color(0xFFFF2A4A).withOpacity(0.7) : p.border, width: live ? 1.2 : 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: _team(f.home, p, alignEnd: true)),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      centre,
                      style: TextStyle(
                        color: live ? const Color(0xFFFF2A4A) : p.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(sub,
                        style: TextStyle(
                            color: live ? const Color(0xFFFF2A4A) : p.textFaint, fontSize: 10.5, fontWeight: FontWeight.w700)),
                  ],
                ),
                Expanded(child: _team(f.away, p, alignEnd: false)),
              ],
            ),
            // Live: a full "watch now" button. Coming with a stream: a small one.
            if (live && watchable != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 38,
                child: FilledButton.icon(
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => SportsPlayerScreen(match: watchable))),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE50914),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 22),
                  label: const Text('شاهد الآن', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900)),
                ),
              ),
            ] else if (watchable != null) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.play_circle_fill_rounded, color: Color(0xFFE50914), size: 18),
                  const SizedBox(width: 5),
                  Text('متاح للمشاهدة',
                      style: TextStyle(color: p.textMuted, fontSize: 11, fontWeight: FontWeight.w800)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _team(LeagueTeam t, AppPalette p, {required bool alignEnd}) {
    final crest = CachedNetworkImage(
      memCacheWidth: 128,
      imageUrl: t.crestUrl,
      width: 34,
      height: 34,
      fit: BoxFit.contain,
      errorWidget: (_, __, ___) => Icon(Icons.shield_rounded, color: p.textFaint, size: 28),
    );
    final name = Expanded(
      child: Text(
        t.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: alignEnd ? TextAlign.end : TextAlign.start,
        style: TextStyle(color: p.text, fontSize: 12.5, fontWeight: FontWeight.w800),
      ),
    );
    return Row(children: alignEnd ? [name, const SizedBox(width: 8), crest] : [crest, const SizedBox(width: 8), name]);
  }
}

/// A fixture plus the app's own record of it, and what can be played.
class FixtureRowData {
  final LeagueFixture fixture;
  final SportMatchItem? match;
  final String leagueName;
  const FixtureRowData({required this.fixture, this.match, required this.leagueName});

  /// What to hand the player: the app's match when it has one; for a match
  /// that is live right now, one built from the fixture (the player then
  /// looks the stream up by the same 365Scores id and the team names).
  SportMatchItem? get playable {
    final m = match;
    if (m != null && (m.hasWatch || m.isLive || m.streamId != null)) return m;
    if (fixture.isLive) {
      return m ??
          SportMatchItem(
            id: fixture.id,
            sourceId: '${fixture.id}',
            kickoffAt: fixture.startTime.toIso8601String(),
            status: 'live',
            home: TeamInfo(name: fixture.home.name, logo: fixture.home.crestUrl),
            away: TeamInfo(name: fixture.away.name, logo: fixture.away.crestUrl),
            homeScore: fixture.homeScore,
            awayScore: fixture.awayScore,
            hasWatch: true,
            league: leagueName,
          );
    }
    return null;
  }
}

class _StandingsTab extends ConsumerWidget {
  final FootballLeague league;
  const _StandingsTab({required this.league});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final async = ref.watch(leagueStandingsProvider(league.id));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFE50914))),
      error: (_, __) => Center(child: Text('تعذّر تحميل الترتيب', style: TextStyle(color: p.textMuted))),
      data: (tables) {
        if (tables.isEmpty) {
          return Center(child: Text('لا يوجد جدول ترتيب لهذه البطولة', style: TextStyle(color: p.textMuted)));
        }
        const head = TextStyle(fontSize: 11, fontWeight: FontWeight.w800);
        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
          children: [
            for (final t in tables) ...[
              if (tables.length > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
                  child: Text(t.name, style: TextStyle(color: p.text, fontSize: 14, fontWeight: FontWeight.w900)),
                ),
              Container(
                decoration: BoxDecoration(
                  color: p.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: p.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Container(
                      color: p.cardAlt,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Row(
                        children: [
                          SizedBox(width: 24, child: Text('#', style: head.copyWith(color: p.textMuted))),
                          Expanded(child: Text('الفريق', style: head.copyWith(color: p.textMuted))),
                          for (final h in const ['ل', 'ف', 'ت', 'خ', '+/-'])
                            SizedBox(width: 30, child: Text(h, textAlign: TextAlign.center, style: head.copyWith(color: p.textMuted))),
                          SizedBox(width: 34, child: Text('ن', textAlign: TextAlign.center, style: head.copyWith(color: p.text))),
                        ],
                      ),
                    ),
                    for (final r in t.rows) _row(r, p),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
          ],
        );
      },
    );
  }

  Widget _row(LeagueRow r, AppPalette p) {
    final cell = TextStyle(color: p.textMuted, fontSize: 12, fontWeight: FontWeight.w700);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: p.border))),
      child: Row(
        children: [
          SizedBox(width: 24, child: Text('${r.position}', style: TextStyle(color: p.text, fontSize: 12, fontWeight: FontWeight.w900))),
          CachedNetworkImage(
            memCacheWidth: 96,
            imageUrl: r.team.crestUrl,
            width: 22,
            height: 22,
            fit: BoxFit.contain,
            errorWidget: (_, __, ___) => Icon(Icons.shield_rounded, color: p.textFaint, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(r.team.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.text, fontSize: 12.5, fontWeight: FontWeight.w800)),
          ),
          for (final v in [r.played, r.won, r.drawn, r.lost])
            SizedBox(width: 30, child: Text('$v', textAlign: TextAlign.center, style: cell)),
          SizedBox(
            width: 30,
            child: Text('${r.goalDifference > 0 ? '+' : ''}${r.goalDifference}', textAlign: TextAlign.center, style: cell),
          ),
          SizedBox(
            width: 34,
            child: Text('${r.points}', textAlign: TextAlign.center,
                style: TextStyle(color: p.text, fontSize: 13, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}
