import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';
import 'package:youtube_downloader/core/network/image_cache.dart';
import 'package:youtube_downloader/presentation/widgets/glass.dart';
import 'package:youtube_downloader/presentation/widgets/section_title.dart';

import '../../../home/presentation/widgets/football_showcase.dart' show FootballLeague;
import '../../data/models/sports_models.dart';
import '../../data/services/league_service.dart';
import '../../data/services/tournament_service.dart';
import '../providers/sports_provider.dart';
import 'league_screen.dart' show FixtureRowData, leagueFixturesProvider;
import 'sports_player_screen.dart';

/// The sports display face (see pubspec): competition names, tabs, ranks
/// and scores are set in it.
const kSportFont = 'Changa';

final tournamentServiceProvider = Provider<TournamentService>((ref) => TournamentService());

final tournamentStandingsProvider = FutureProvider.family<TournamentStandings, int>(
  (ref, id) => ref.watch(tournamentServiceProvider).fetchStandings(id),
);

final tournamentScorersProvider = FutureProvider.family<List<TopScorer>, int>((ref, id) async {
  final scorers = await ref.watch(tournamentServiceProvider).fetchTopScorers(id);
  // While a match is being played its goals keep coming: look again in a
  // minute.
  if (scorers.any((s) => s.live)) {
    final timer = Timer(const Duration(minutes: 1), ref.invalidateSelf);
    ref.onDispose(timer.cancel);
  }
  return scorers;
});

/// Every competition the app knows, the Gulf Cup first: what the row at
/// the top of the page swipes through.
final List<Tournament> kTournaments = () {
  Tournament fromLeague(FootballLeague l) => Tournament(
        id: l.id,
        name: l.name,
        logoUrl: l.logoUrl,
        accent: l.colors.last.value,
        accent2: l.colors.first.value,
        darkBadge: l.darkBadge,
      );
  final out = <Tournament>[Tournament.gulfCup];
  for (final l in [...FootballLeague.arab, ...FootballLeague.world]) {
    if (out.every((t) => t.id != l.id)) out.add(fromLeague(l));
  }
  return out;
}();

/// «البطولات»: a row of competitions to swipe through at the top, and
/// under it the one in the middle - its group tables or league table with
/// who goes through, its fixtures and results by round, and its scorers,
/// all on the app's glass.
class TournamentScreen extends ConsumerStatefulWidget {
  const TournamentScreen({super.key});

  @override
  ConsumerState<TournamentScreen> createState() => _TournamentScreenState();
}

class _TournamentScreenState extends ConsumerState<TournamentScreen> {
  int _tab = 0;
  int _index = 0;

  static const _tabs = ['الترتيب', 'المباريات', 'الهدافون'];

  Tournament get _current => kTournaments[_index];

  /// The app's own matches of this competition (yesterday / today /
  /// tomorrow), by 365Scores game id: the ones with a stream.
  Map<String, SportMatchItem> _streamable() {
    final out = <String, SportMatchItem>{};
    for (final day in const ['yesterday', 'today', 'tomorrow']) {
      final state = ref.watch(sportsNotifierProvider(day));
      for (final g in state.groups) {
        if (g.cid != _current.id) continue;
        for (final m in g.matches) {
          if (m.sourceId != null) out[m.sourceId!] = m;
        }
      }
    }
    return out;
  }

  Future<void> _refresh() async {
    final id = _current.id;
    ref.invalidate(tournamentStandingsProvider(id));
    ref.invalidate(leagueFixturesProvider(id));
    ref.invalidate(tournamentScorersProvider(id));
    await Future.wait([
      ref
          .read(tournamentStandingsProvider(id).future)
          .catchError((_) => const TournamentStandings(groups: [], stage: '', destination: '')),
      ref.read(leagueFixturesProvider(id).future).catchError((_) => <LeagueFixture>[]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final t = _current;
    final standings = ref.watch(tournamentStandingsProvider(t.id));
    final stage = standings.valueOrNull?.stage ?? '';

    // The banner runs up under the status bar, whose icons stay light
    // over the competition's colours.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: p.bg,
        body: RefreshIndicator(
          color: AppColors.primary,
          backgroundColor: p.card,
          edgeOffset: MediaQuery.of(context).padding.top,
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TournamentPicker(
                      tournaments: kTournaments,
                      index: _index,
                      onChanged: (i) => setState(() => _index = i),
                    ),
                    if (stage.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Center(child: _Chip(icon: Icons.flag_rounded, text: stage, accent: true)),
                    ],
                    const SizedBox(height: 14),
                    _Tabs(labels: _tabs, index: _tab, onChanged: (i) => setState(() => _tab = i)),
                    const SizedBox(height: 14),
                  ],
                ),
              ),
              if (_tab == 0) _StandingsSliver(tournament: t, standings: standings),
              if (_tab == 1) _FixturesSliver(tournament: t, streamable: _streamable()),
              if (_tab == 2) _ScorersSliver(tournament: t),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- the row of competitions

/// The competitions as full-width banners, swiped through; the one on
/// screen is the page's. No frame: the banner runs edge to edge.
class _TournamentPicker extends StatefulWidget {
  const _TournamentPicker({required this.tournaments, required this.index, required this.onChanged});

  final List<Tournament> tournaments;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  State<_TournamentPicker> createState() => _TournamentPickerState();
}

class _TournamentPickerState extends State<_TournamentPicker> {
  late final PageController _pages = PageController(initialPage: widget.index);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The banner's own height, plus the status bar it runs under.
    final inset = MediaQuery.of(context).padding.top;
    return SizedBox(
      height: 232 + inset,
      child: PageView.builder(
        controller: _pages,
        itemCount: widget.tournaments.length,
        onPageChanged: widget.onChanged,
        itemBuilder: (context, i) => _TournamentBanner(
          tournament: widget.tournaments[i],
          position: '${i + 1} / ${widget.tournaments.length}',
        ),
      ),
    );
  }
}

/// A wide banner of the competition's own colours, its emblem large on
/// the start side and its name on the other, with a wash of light behind
/// the emblem.
class _TournamentBanner extends StatelessWidget {
  const _TournamentBanner({required this.tournament, required this.position});

  final Tournament tournament;
  final String position;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).padding.top;
    final light = Color(tournament.accent);
    final dark = Color(tournament.accent2 ?? tournament.accent).withOpacity(1);
    final deep = Color.lerp(dark, Colors.black, 0.45)!;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [deep, dark, Color.lerp(dark, light, 0.6)!],
          stops: const [0, 0.42, 1],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // A wash of the brand's light behind the emblem.
          PositionedDirectional(
            start: -60,
            top: inset - 80,
            child: Container(
              width: 360,
              height: 360,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [light.withOpacity(0.7), light.withOpacity(0.0)]),
              ),
            ),
          ),
          // Shade gathering at the far end and the foot, so the name and
          // the counter sit on something darker.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: AlignmentDirectional.centerStart,
                end: AlignmentDirectional.centerEnd,
                colors: [Colors.transparent, Colors.black.withOpacity(0.28)],
                stops: const [0.45, 1],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.white.withOpacity(0.12), Colors.transparent, Colors.black.withOpacity(0.30)],
                stops: const [0, 0.35, 1],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(22, inset + 18, 22, 26),
            child: Row(
              children: [
                // The emblem, large, on a pool of shadow.
                SizedBox(
                  width: 160,
                  height: 160,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 150,
                        height: 150,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 40, spreadRadius: -6),
                          ],
                        ),
                      ),
                      CachedNetworkImage(
                        imageUrl: tournament.logoUrl,
                        cacheManager: appImageCache,
                        memCacheWidth: 480,
                        width: 156,
                        height: 156,
                        fit: BoxFit.contain,
                        errorWidget: (_, __, ___) =>
                            const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 84),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        tournament.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: kSportFont,
                          color: Colors.white,
                          fontSize: 27,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                          shadows: [Shadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 2))],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.22),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withOpacity(0.18), width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.swipe_rounded, color: Colors.white.withOpacity(0.85), size: 13),
                            const SizedBox(width: 6),
                            Text(
                              position,
                              style: const TextStyle(
                                  fontFamily: kSportFont,
                                  color: Colors.white,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  height: 1.2),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text, this.accent = false});

  final IconData icon;
  final String text;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: accent ? AppColors.primary.withOpacity(0.14) : p.glassFill(),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent ? AppColors.primary.withOpacity(0.4) : p.glassFillEdge(), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: accent ? AppColors.primary : p.textMuted),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(
                  fontFamily: kSportFont,
                  color: accent ? AppColors.primary : p.text,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  height: 1.2)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- tabs

/// Glass segmented tabs, like the catalogue's.
class _Tabs extends StatelessWidget {
  const _Tabs({required this.labels, required this.index, required this.onChanged});

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: p.glassFill(),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: p.glassFillEdge(), width: 0.8),
        ),
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: i == index ? p.glassFill(selected: true) : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: kSportFont,
                        color: i == index ? p.text : p.onGlassMuted,
                        fontSize: 14,
                        fontWeight: i == index ? FontWeight.w800 : FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- standings

class _StandingsSliver extends StatelessWidget {
  const _StandingsSliver({required this.tournament, required this.standings});

  final Tournament tournament;
  final AsyncValue<TournamentStandings> standings;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return standings.when(
      loading: () => const SliverToBoxAdapter(child: _Loading()),
      error: (_, __) => SliverToBoxAdapter(child: _Message('تعذّر تحميل الترتيب', p)),
      data: (s) {
        if (s.groups.isEmpty) return SliverToBoxAdapter(child: _Message('لا يوجد جدول ترتيب بعد', p));
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.builder(
            itemCount: s.groups.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _GroupTable(group: s.groups[i]),
            ),
          ),
        );
      },
    );
  }
}

class _GroupTable extends StatelessWidget {
  const _GroupTable({required this.group});

  final TournamentGroup group;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final head = TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: p.textMuted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (group.name.isNotEmpty) ...[
          SectionTitle(group.name, padding: EdgeInsets.zero, fontFamily: kSportFont),
          const SizedBox(height: 10),
        ],
        GlassPanel(
          radius: 16,
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
                child: Row(
                  children: [
                    SizedBox(width: 22, child: Text('#', style: head)),
                    Expanded(child: Text('الفريق', style: head)),
                    for (final h in const ['ل', 'ف', 'ت', 'خ', '+/-'])
                      SizedBox(width: 28, child: Text(h, textAlign: TextAlign.center, style: head)),
                    SizedBox(
                        width: 34,
                        child: Text('نقاط', textAlign: TextAlign.center, style: head.copyWith(color: p.text))),
                  ],
                ),
              ),
              for (final r in group.rows) _GroupRow(row: r),
            ],
          ),
        ),
      ],
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.row});

  final TournamentRow row;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final r = row;
    final cell = TextStyle(color: p.textMuted, fontSize: 12, fontWeight: FontWeight.w700);
    const green = Color(0xFF22C55E);
    return Container(
      margin: const EdgeInsets.only(top: 3),
      padding: const EdgeInsetsDirectional.only(start: 6, end: 2),
      decoration: BoxDecoration(
        color: r.qualifies ? green.withOpacity(p.isDark ? 0.10 : 0.12) : p.glassFill().withOpacity(0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          // A green mark on the rows that go through.
          Container(
            width: 3,
            height: 30,
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: r.qualifies ? green : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 9),
          SizedBox(
            width: 22,
            child: Text('${r.position}', style: TextStyle(color: p.text, fontSize: 12.5, fontWeight: FontWeight.w900)),
          ),
          CachedNetworkImage(
            imageUrl: r.team.crestUrl,
            cacheManager: appImageCache,
            memCacheWidth: 96,
            width: 24,
            height: 24,
            fit: BoxFit.contain,
            errorWidget: (_, __, ___) => Icon(Icons.shield_rounded, color: p.textFaint, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  r.team.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.text, fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
                if (r.form.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      for (final f in r.form.take(5))
                        Container(
                          width: 7,
                          height: 7,
                          margin: const EdgeInsetsDirectional.only(end: 3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: f == 1 ? green : (f == 2 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444)),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          for (final v in [r.played, r.won, r.drawn, r.lost])
            SizedBox(width: 28, child: Text('$v', textAlign: TextAlign.center, style: cell)),
          SizedBox(
            width: 28,
            child: Text(
              '${r.goalDifference > 0 ? '+' : ''}${r.goalDifference}',
              textAlign: TextAlign.center,
              style: cell,
            ),
          ),
          SizedBox(
            width: 34,
            child: Text(
              '${r.points}',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.text, fontSize: 14, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- fixtures

class _FixturesSliver extends ConsumerWidget {
  const _FixturesSliver({required this.tournament, required this.streamable});

  final Tournament tournament;
  final Map<String, SportMatchItem> streamable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final async = ref.watch(leagueFixturesProvider(tournament.id));
    return async.when(
      loading: () => const SliverToBoxAdapter(child: _Loading()),
      error: (_, __) => SliverToBoxAdapter(child: _Message('تعذّر تحميل المباريات', p)),
      data: (fixtures) {
        if (fixtures.isEmpty) return SliverToBoxAdapter(child: _Message('لا توجد مباريات قريبة', p));
        final coming = fixtures.where((f) => !f.isEnded).toList();
        final past = fixtures.where((f) => f.isEnded).toList().reversed.toList();
        final items = <Widget>[];
        void section(String title, List<LeagueFixture> list, {bool live = false}) {
          if (list.isEmpty) return;
          items.add(Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SectionTitle(
              title,
              padding: EdgeInsets.zero,
              fontFamily: kSportFont,
              leading: live
                  ? Container(
                      width: 9,
                      height: 9,
                      margin: const EdgeInsetsDirectional.only(end: 9),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFFF2A4A),
                        boxShadow: [BoxShadow(color: Color(0xFFFF2A4A), blurRadius: 8, spreadRadius: 2)],
                      ),
                    )
                  : null,
            ),
          ));
          String? lastRound;
          for (final f in list) {
            if (f.roundName != lastRound && f.roundName.isNotEmpty) {
              items.add(Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
                child:
                    Text(f.roundName, style: TextStyle(color: p.textMuted, fontSize: 12, fontWeight: FontWeight.w800)),
              ));
              lastRound = f.roundName;
            }
            items.add(_FixtureCard(
              data: FixtureRowData(fixture: f, match: streamable['${f.id}'], leagueName: tournament.name),
            ));
          }
          items.add(const SizedBox(height: 8));
        }

        final hasLive = coming.any((f) => f.isLive);
        section(hasLive ? 'الآن والقادمة' : 'المباريات القادمة', coming, live: hasLive);
        section('النتائج', past);
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.list(children: items),
        );
      },
    );
  }
}

class _FixtureCard extends StatelessWidget {
  const _FixtureCard({required this.data});

  final FixtureRowData data;

  static String _clock(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  static String _date(DateTime t) => '${t.day}/${t.month}';

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final f = data.fixture;
    final live = f.isLive || (data.match?.isLive ?? false);
    final centre = live || f.isEnded ? '${f.homeScore ?? 0} - ${f.awayScore ?? 0}' : _clock(f.startTime);
    final sub = live ? (f.statusText.isNotEmpty ? f.statusText : 'مباشر') : (f.isEnded ? 'انتهت' : _date(f.startTime));
    final watchable = data.playable;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassPanel(
        radius: 16,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: watchable == null
              ? null
              : () =>
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => SportsPlayerScreen(match: watchable))),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: _Team(team: f.home, alignEnd: true)),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        centre,
                        style: TextStyle(
                          fontFamily: kSportFont,
                          color: live ? const Color(0xFFFF2A4A) : p.text,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: live ? const Color(0xFFFF2A4A).withOpacity(0.14) : p.glassFill(),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: live ? const Color(0xFFFF2A4A).withOpacity(0.5) : p.glassFillEdge(), width: 0.8),
                        ),
                        child: Text(
                          sub,
                          style: TextStyle(
                            fontFamily: kSportFont,
                            color: live ? const Color(0xFFFF2A4A) : p.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Expanded(child: _Team(team: f.away, alignEnd: false)),
                ],
              ),
              if (watchable != null) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(live ? Icons.play_circle_fill_rounded : Icons.play_circle_outline_rounded,
                        color: AppColors.primary, size: 18),
                    const SizedBox(width: 5),
                    Text(
                      live ? 'شاهد الآن' : 'متاحة للمشاهدة',
                      style: const TextStyle(
                          fontFamily: kSportFont,
                          color: AppColors.primary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          height: 1.2),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Team extends StatelessWidget {
  const _Team({required this.team, required this.alignEnd});

  final LeagueTeam team;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final crest = CachedNetworkImage(
      imageUrl: team.crestUrl,
      cacheManager: appImageCache,
      memCacheWidth: 128,
      width: 38,
      height: 38,
      fit: BoxFit.contain,
      errorWidget: (_, __, ___) => Icon(Icons.shield_rounded, color: p.textFaint, size: 30),
    );
    final name = Expanded(
      child: Text(
        team.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: alignEnd ? TextAlign.end : TextAlign.start,
        style: TextStyle(fontFamily: kSportFont, color: p.text, fontSize: 14, fontWeight: FontWeight.w700, height: 1.2),
      ),
    );
    return Row(children: alignEnd ? [name, const SizedBox(width: 8), crest] : [crest, const SizedBox(width: 8), name]);
  }
}

// ---------------------------------------------------------------- scorers

class _ScorersSliver extends ConsumerWidget {
  const _ScorersSliver({required this.tournament});

  final Tournament tournament;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final async = ref.watch(tournamentScorersProvider(tournament.id));
    return async.when(
      loading: () => const SliverToBoxAdapter(child: _Loading()),
      error: (_, __) => SliverToBoxAdapter(child: _Message('تعذّر تحميل الهدافين', p)),
      data: (scorers) {
        if (scorers.isEmpty) return SliverToBoxAdapter(child: _Message('لا أهداف بعد', p));
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.list(children: [
            // The race to the top scorer's cup, then the list.
            _ScorerRace(scorers: scorers.take(8).toList()),
            const SizedBox(height: 16),
            for (var i = 0; i < scorers.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ScorerCard(rank: i + 1, scorer: scorers[i]),
              ),
          ]),
        );
      },
    );
  }
}

class _ScorerCard extends StatelessWidget {
  const _ScorerCard({required this.rank, required this.scorer});

  final int rank;
  final TopScorer scorer;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final s = scorer;
    return GlassPanel(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text('$rank',
                style: TextStyle(
                    fontFamily: kSportFont,
                    color: rank == 1 ? AppColors.primary : p.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    height: 1.2)),
          ),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.glassFill(),
              border: Border.all(
                  color: rank == 1 ? const Color(0xFFFFB800) : p.glassFillEdge(), width: rank == 1 ? 1.6 : 0.8),
              boxShadow: p.glassShadow,
            ),
            clipBehavior: Clip.antiAlias,
            child: CachedNetworkImage(
              imageUrl: s.photoUrl,
              cacheManager: appImageCache,
              memCacheWidth: 192,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Icon(Icons.person_rounded, color: p.textFaint, size: 34),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(s.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontFamily: kSportFont,
                              color: p.text,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              height: 1.2)),
                    ),
                    if (s.live) ...[
                      const SizedBox(width: 6),
                      // A goal of his is from a match still being played.
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.primary.withOpacity(0.5), width: 0.8),
                        ),
                        child: const Text('مباشر',
                            style: TextStyle(
                                fontFamily: kSportFont,
                                color: AppColors.primary,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                height: 1.2)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    CachedNetworkImage(
                      imageUrl: s.crestUrl,
                      cacheManager: appImageCache,
                      memCacheWidth: 64,
                      width: 16,
                      height: 16,
                      fit: BoxFit.contain,
                      errorWidget: (_, __, ___) => const SizedBox.shrink(),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(s.teamName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: p.textMuted, fontSize: 11.5, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${s.goals}',
                  style: TextStyle(
                      fontFamily: kSportFont, color: p.text, fontSize: 26, fontWeight: FontWeight.w800, height: 1)),
              Text('هدف',
                  style: TextStyle(
                      fontFamily: kSportFont,
                      color: p.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      height: 1.2)),
            ],
          ),
          if (s.assists > 0) ...[
            const SizedBox(width: 14),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${s.assists}',
                    style: TextStyle(
                        fontFamily: kSportFont,
                        color: p.textMuted,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        height: 1)),
                Text('صناعة',
                    style: TextStyle(
                        fontFamily: kSportFont,
                        color: p.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        height: 1.2)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The scorers racing to the cup: lanes running from the start edge to
/// the cup at the far end, each scorer's face placed along the track by
/// his goals - the leader nearest the cup. Nobody stands on anybody:
/// a scorer goes to a lane with room at his spot, and when every lane
/// is taken there he steps back behind the nearest runner.
class _ScorerRace extends StatelessWidget {
  const _ScorerRace({required this.scorers});

  final List<TopScorer> scorers;

  static const double _laneHeight = 84;
  static const double _face = 48;
  static const double _runner = 78;
  static const double _gap = 10;

  int get _lanes => scorers.length < 3 ? scorers.length : (scorers.length > 6 ? 4 : 3);

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final most = scorers.fold<int>(1, (m, s) => s.goals > m ? s.goals : m);
    final lanes = _lanes;
    // The last lane needs only a runner's height, not a whole lane.
    final height = (lanes - 1) * _laneHeight + _face + 26;
    return GlassPanel(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events_rounded, color: Color(0xFFFFB800), size: 18),
              const SizedBox(width: 6),
              Text('السباق إلى كأس الهداف',
                  style: TextStyle(fontFamily: kSportFont, color: p.text, fontSize: 15, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: height,
            child: LayoutBuilder(
              builder: (context, box) {
                // The cup takes the far end; the track is what is left.
                const cup = 56.0;
                final track = box.maxWidth - cup - _runner;
                final spots = placeRunners([for (final s in scorers) s.goals],
                    lanes: lanes, track: track, runner: _runner, gap: _gap);
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (var lane = 0; lane < lanes; lane++)
                      PositionedDirectional(
                        start: _runner / 2,
                        end: cup - 4,
                        top: lane * _laneHeight + _face / 2 + 2,
                        child:
                            CustomPaint(size: const Size(double.infinity, 2), painter: _DashPainter(color: p.border)),
                      ),
                    // The cup, at the finish.
                    PositionedDirectional(
                      end: 0,
                      top: 0,
                      bottom: 0,
                      child: SizedBox(
                        width: cup,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFFFFB800).withOpacity(0.18),
                                border: Border.all(color: const Color(0xFFFFB800).withOpacity(0.6), width: 1),
                                boxShadow: [
                                  BoxShadow(color: const Color(0xFFFFB800).withOpacity(0.25), blurRadius: 14)
                                ],
                              ),
                              child: const Icon(Icons.emoji_events_rounded, color: Color(0xFFFFB800), size: 28),
                            ),
                            const SizedBox(height: 4),
                            Text('$most',
                                style: TextStyle(color: p.textMuted, fontSize: 10.5, fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ),
                    for (var i = 0; i < scorers.length; i++)
                      if (spots[i] != null)
                        PositionedDirectional(
                          start: spots[i]!.$2,
                          top: spots[i]!.$1 * _laneHeight,
                          child: _Runner(scorer: scorers[i], leader: i == 0),
                        ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Where each runner of the race stands, by [goals] in order of rank:
/// (lane, start offset along a [track] this long) - or null when the
/// track has no room left for him. A runner [runner] wide goes to a lane
/// with room at his spot, [gap] clear of the runner before; when every
/// lane is taken there he steps back behind the nearest one. Visible for
/// testing.
List<(int, double)?> placeRunners(
  List<int> goals, {
  required int lanes,
  required double track,
  required double runner,
  required double gap,
}) {
  final most = goals.fold<int>(1, (m, g) => g > m ? g : m);
  // The start edge of the last runner placed in each lane; runners come
  // in order, so each one stands at or behind the one before him.
  final edge = List<double>.filled(lanes, double.infinity);
  var next = 0;
  final out = <(int, double)?>[];
  for (final g in goals) {
    final ideal = (track * g / most).clamp(0.0, track);
    // A lane with room at his spot, in turn so the lanes fill evenly.
    int? free;
    for (var k = 0; k < lanes; k++) {
      final lane = (next + k) % lanes;
      if (ideal + runner + gap <= edge[lane]) {
        free = lane;
        break;
      }
    }
    if (free != null) {
      next = (free + 1) % lanes;
      edge[free] = ideal;
      out.add((free, ideal));
      continue;
    }
    // No room: step back behind the runner nearest the cup among the lanes.
    var lane = 0;
    for (var k = 1; k < lanes; k++) {
      if (edge[k] > edge[lane]) lane = k;
    }
    final x = edge[lane] - runner - gap;
    if (x < 0) {
      out.add(null);
      continue;
    }
    next = (lane + 1) % lanes;
    edge[lane] = x;
    out.add((lane, x));
  }
  return out;
}

class _Runner extends StatelessWidget {
  const _Runner({required this.scorer, required this.leader});

  final TopScorer scorer;
  final bool leader;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    const size = _ScorerRace._face;
    return SizedBox(
      width: _ScorerRace._runner,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.glassFill(),
                  border:
                      Border.all(color: leader ? const Color(0xFFFFB800) : p.glassFillEdge(), width: leader ? 2 : 0.8),
                  boxShadow:
                      leader ? [BoxShadow(color: const Color(0xFFFFB800).withOpacity(0.35), blurRadius: 12)] : null,
                ),
                clipBehavior: Clip.antiAlias,
                child: CachedNetworkImage(
                  imageUrl: scorer.photoUrl,
                  cacheManager: appImageCache,
                  memCacheWidth: 138,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Icon(Icons.person_rounded, color: p.textFaint, size: 26),
                ),
              ),
              // The goals, on a red badge at the shoulder.
              PositionedDirectional(
                end: -4,
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: p.bg, width: 1.5),
                  ),
                  child: Text('${scorer.goals}',
                      style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            // The whole name when it is short enough for the runner's width,
            // else what he is called - «خيمينيز», not «نيكولاس خيم…».
            scorer.name.length <= 12 || scorer.shortName.isEmpty
                ? scorer.name.split(' ').take(2).join(' ')
                : scorer.shortName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: kSportFont, color: p.text, fontSize: 11, fontWeight: FontWeight.w700, height: 1.2),
          ),
        ],
      ),
    );
  }
}

/// A dashed lane line.
class _DashPainter extends CustomPainter {
  const _DashPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    const dash = 6.0, gap = 5.0;
    for (var x = 0.0; x < size.width; x += dash + gap) {
      canvas.drawLine(Offset(x, size.height / 2), Offset((x + dash).clamp(0, size.width), size.height / 2), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

// ---------------------------------------------------------------- bits

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2.5)),
      );
}

class _Message extends StatelessWidget {
  const _Message(this.text, this.p);

  final String text;
  final AppPalette p;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Center(child: Text(text, style: TextStyle(color: p.textMuted, fontSize: 13.5))),
      );
}
