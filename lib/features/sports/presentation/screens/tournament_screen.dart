import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
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

final tournamentServiceProvider = Provider<TournamentService>((ref) => TournamentService());

final tournamentStandingsProvider = FutureProvider.family<TournamentStandings, int>(
  (ref, id) => ref.watch(tournamentServiceProvider).fetchStandings(id),
);

final tournamentScorersProvider = FutureProvider.family<List<TopScorer>, int>(
  (ref, id) => ref.watch(tournamentServiceProvider).fetchTopScorers(id),
);

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

    return Scaffold(
      backgroundColor: p.bg,
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: p.card,
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: SafeArea(
                bottom: false,
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
            ),
            if (_tab == 0) _StandingsSliver(tournament: t, standings: standings),
            if (_tab == 1) _FixturesSliver(tournament: t, streamable: _streamable()),
            if (_tab == 2) _ScorersSliver(tournament: t),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
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
    return SizedBox(
      height: 168,
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
    final p = AppPalette.of(context);
    final light = Color(tournament.accent);
    final dark = Color(tournament.accent2 ?? tournament.accent).withOpacity(1);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.centerStart,
          end: AlignmentDirectional.centerEnd,
          colors: [dark, Color.lerp(dark, light, 0.55)!],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // A wash of the brand's light behind the emblem.
          PositionedDirectional(
            start: -40,
            top: -60,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [light.withOpacity(0.55), light.withOpacity(0.0)]),
              ),
            ),
          ),
          // The sheen of the app's glass over the colours.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.white.withOpacity(0.10), Colors.black.withOpacity(0.18)],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 16),
            child: Row(
              children: [
                // The emblem, large, on nothing.
                SizedBox(
                  width: 116,
                  height: 116,
                  child: CachedNetworkImage(
                    imageUrl: tournament.logoUrl,
                    cacheManager: appImageCache,
                    memCacheWidth: 360,
                    fit: BoxFit.contain,
                    errorWidget: (_, __, ___) => const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 64),
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
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          height: 1.2,
                          shadows: [Shadow(color: Colors.black38, blurRadius: 6)],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.swipe_rounded, color: Colors.white.withOpacity(0.7), size: 14),
                          const SizedBox(width: 5),
                          Text(
                            position,
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.8), fontSize: 11.5, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // The banner's foot fades into the page.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 28,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [p.bg.withOpacity(0), p.bg],
                ),
              ),
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
              style:
                  TextStyle(color: accent ? AppColors.primary : p.text, fontSize: 11.5, fontWeight: FontWeight.w700)),
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
                        color: i == index ? p.text : p.onGlassMuted,
                        fontSize: 13,
                        fontWeight: i == index ? FontWeight.w900 : FontWeight.w600,
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
          SectionTitle(group.name, padding: EdgeInsets.zero),
          const SizedBox(height: 10),
        ],
        GlassPanel(
          radius: 14,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
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
      decoration: BoxDecoration(
        color: r.qualifies ? green.withOpacity(p.isDark ? 0.08 : 0.10) : null,
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: Row(
        children: [
          // A green mark on the rows that go through.
          Container(width: 3, height: 44, color: r.qualifies ? green : Colors.transparent),
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
        radius: 14,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: InkWell(
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
                          color: live ? const Color(0xFFFF2A4A) : p.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: live ? const Color(0xFFFF2A4A).withOpacity(0.16) : p.glassFill(),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          sub,
                          style: TextStyle(
                            color: live ? const Color(0xFFFF2A4A) : p.textMuted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
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
                      style: const TextStyle(color: AppColors.primary, fontSize: 11.5, fontWeight: FontWeight.w800),
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
        style: TextStyle(color: p.text, fontSize: 12.5, fontWeight: FontWeight.w800),
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
            _ScorerRace(scorers: scorers.take(9).toList()),
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
      radius: 14,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text('$rank',
                style: TextStyle(
                    color: rank == 1 ? AppColors.primary : p.text, fontSize: 14, fontWeight: FontWeight.w900)),
          ),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.glassFill(),
              border: Border.all(color: p.glassFillEdge(), width: 0.8),
            ),
            clipBehavior: Clip.antiAlias,
            child: CachedNetworkImage(
              imageUrl: s.photoUrl,
              cacheManager: appImageCache,
              memCacheWidth: 132,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Icon(Icons.person_rounded, color: p.textFaint, size: 26),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.text, fontSize: 13, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Row(
                  children: [
                    CachedNetworkImage(
                      imageUrl: s.crestUrl,
                      cacheManager: appImageCache,
                      memCacheWidth: 64,
                      width: 14,
                      height: 14,
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
              Text('${s.goals}', style: TextStyle(color: p.text, fontSize: 20, fontWeight: FontWeight.w900, height: 1)),
              Text('هدف', style: TextStyle(color: p.textMuted, fontSize: 10, fontWeight: FontWeight.w700)),
            ],
          ),
          if (s.assists > 0) ...[
            const SizedBox(width: 14),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${s.assists}',
                    style: TextStyle(color: p.textMuted, fontSize: 16, fontWeight: FontWeight.w900, height: 1)),
                Text('صناعة', style: TextStyle(color: p.textMuted, fontSize: 10, fontWeight: FontWeight.w700)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The scorers racing to the cup: three lanes running from the start
/// edge to the cup at the far end, each scorer's face placed along the
/// track by his goals - the leader nearest the cup.
class _ScorerRace extends StatelessWidget {
  const _ScorerRace({required this.scorers});

  final List<TopScorer> scorers;

  static const int _lanes = 3;
  static const double _laneHeight = 74;
  static const double _face = 46;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final most = scorers.fold<int>(1, (m, s) => s.goals > m ? s.goals : m);
    final lanes = scorers.length < _lanes ? scorers.length : _lanes;
    final height = lanes * _laneHeight + 10;
    return GlassPanel(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events_rounded, color: Color(0xFFFFB800), size: 18),
              const SizedBox(width: 6),
              Text('السباق إلى كأس الهداف',
                  style: TextStyle(color: p.text, fontSize: 13.5, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: height,
            child: LayoutBuilder(
              builder: (context, box) {
                // The cup takes the far end; the track is what is left.
                const cup = 52.0;
                final track = box.maxWidth - cup - _face;
                return Stack(
                  children: [
                    for (var lane = 0; lane < lanes; lane++)
                      PositionedDirectional(
                        start: _face / 2,
                        end: cup,
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
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFFFFB800).withOpacity(0.18),
                                border: Border.all(color: const Color(0xFFFFB800).withOpacity(0.6), width: 1),
                              ),
                              child: const Icon(Icons.emoji_events_rounded, color: Color(0xFFFFB800), size: 26),
                            ),
                            const SizedBox(height: 4),
                            Text('$most',
                                style: TextStyle(color: p.textMuted, fontSize: 10.5, fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ),
                    for (var i = 0; i < scorers.length; i++)
                      PositionedDirectional(
                        // The leader stands nearest the cup; a scorer with a
                        // third of his goals stands a third of the way.
                        start: (track * scorers[i].goals / most).clamp(0.0, track),
                        top: (i % lanes) * _laneHeight,
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

class _Runner extends StatelessWidget {
  const _Runner({required this.scorer, required this.leader});

  final TopScorer scorer;
  final bool leader;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    const size = _ScorerRace._face;
    return SizedBox(
      width: 88,
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
            scorer.name.split(' ').take(2).join(' '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(color: p.text, fontSize: 10, fontWeight: FontWeight.w800),
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
