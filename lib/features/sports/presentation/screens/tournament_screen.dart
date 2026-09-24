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
        accent: l.colors.first.value,
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
                    const SizedBox(height: 12),
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

/// The competitions on a row of glass cards, swiped through; the one in
/// the middle is the page's.
class _TournamentPicker extends StatefulWidget {
  const _TournamentPicker({required this.tournaments, required this.index, required this.onChanged});

  final List<Tournament> tournaments;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  State<_TournamentPicker> createState() => _TournamentPickerState();
}

class _TournamentPickerState extends State<_TournamentPicker> {
  late final PageController _pages = PageController(viewportFraction: 0.58, initialPage: widget.index);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 128,
      child: PageView.builder(
        controller: _pages,
        itemCount: widget.tournaments.length,
        onPageChanged: widget.onChanged,
        itemBuilder: (context, i) => AnimatedBuilder(
          animation: _pages,
          builder: (context, child) {
            // The card in the middle stands full size; the neighbours a
            // step back and dimmer.
            var page = widget.index.toDouble();
            if (_pages.hasClients && _pages.position.haveDimensions) page = _pages.page ?? page;
            final away = (page - i).abs().clamp(0.0, 1.0);
            return Transform.scale(
              scale: 1 - away * 0.08,
              child: Opacity(opacity: 1 - away * 0.35, child: child),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: _TournamentCard(
              tournament: widget.tournaments[i],
              selected: i == widget.index,
              onTap: () => _pages.animateToPage(i, duration: const Duration(milliseconds: 260), curve: Curves.easeOut),
            ),
          ),
        ),
      ),
    );
  }
}

class _TournamentCard extends StatelessWidget {
  const _TournamentCard({required this.tournament, required this.selected, required this.onTap});

  final Tournament tournament;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final accent = Color(tournament.accent);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: p.glass,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? AppColors.primary : p.glassEdge, width: selected ? 1.4 : 0.8),
          boxShadow: p.glassShadow,
        ),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 58,
              height: 58,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: tournament.darkBadge ? const Color(0xFF0C1410) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: accent.withOpacity(selected ? 0.40 : 0.18), blurRadius: 16, spreadRadius: 1)
                ],
              ),
              child: CachedNetworkImage(
                imageUrl: tournament.logoUrl,
                cacheManager: appImageCache,
                memCacheWidth: 180,
                fit: BoxFit.contain,
                errorWidget: (_, __, ___) => Icon(Icons.emoji_events_rounded, color: accent, size: 28),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tournament.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(color: p.text, fontSize: 12.5, fontWeight: FontWeight.w900),
            ),
          ],
        ),
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
          sliver: SliverList.builder(
            itemCount: scorers.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ScorerCard(rank: i + 1, scorer: scorers[i]),
            ),
          ),
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
