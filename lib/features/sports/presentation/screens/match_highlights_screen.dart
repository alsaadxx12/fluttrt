import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_palette.dart';
import '../../../../presentation/widgets/app_search_field.dart';
import '../../data/match_highlights_service.dart';
import 'highlight_player_screen.dart';

/// Yesterday's and today's finished matches, each with its goals summary.
final matchHighlightsProvider = FutureProvider<List<MatchHighlight>>((ref) async {
  return MatchHighlightsService().recent();
});

/// A page to search for a match and watch its goals summary. Reached from the
/// home banner. Search runs against YouTube so any match can be found.
class MatchHighlightsScreen extends ConsumerStatefulWidget {
  const MatchHighlightsScreen({super.key});

  @override
  ConsumerState<MatchHighlightsScreen> createState() => _MatchHighlightsScreenState();
}

class _MatchHighlightsScreenState extends ConsumerState<MatchHighlightsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;

  String _query = '';
  bool _searching = false;
  List<HighlightHit>? _results;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () => _runSearch(value.trim()));
  }

  Future<void> _runSearch(String q) async {
    setState(() {
      _query = q;
      _searching = q.isNotEmpty;
      _results = null;
    });
    if (q.isEmpty) return;
    final hits = await HighlightResolver.instance.search(q);
    if (!mounted || q != _query) return;
    setState(() {
      _results = hits;
      _searching = false;
    });
  }

  void _openVideo(String videoId, String title) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => HighlightPlayerScreen(videoId: videoId, title: title)),
    );
  }

  Future<void> _openMatch(MatchHighlight m) async {
    // Resolve the match's highlight, showing a brief spinner.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Color(0xFF00E0A1))),
    );
    final v = await HighlightResolver.instance.find(m);
    if (!mounted) return;
    Navigator.of(context).pop(); // dismiss spinner
    if (v == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد ملخّص متاح لهذه المباراة')),
      );
      return;
    }
    _openVideo(v.videoId, '${m.home} ${m.score} ${m.away}');
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final recentAsync = ref.watch(matchHighlightsProvider);

    return Scaffold(
      backgroundColor: p.isDark ? const Color(0xFF0F0F13) : Colors.white,
      appBar: AppBar(
        backgroundColor: p.isDark ? const Color(0xFF14141A) : Colors.white,
        elevation: 0,
        title: Text('ملخص الأهداف', style: TextStyle(color: p.text, fontWeight: FontWeight.w900)),
        iconTheme: IconThemeData(color: p.text),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: _searchField(),
          ),
          Expanded(child: _content(p, recentAsync)),
        ],
      ),
    );
  }

  Widget _content(AppPalette p, AsyncValue<List<MatchHighlight>> recentAsync) {
    if (_query.isNotEmpty) {
      if (_searching) return const Center(child: CircularProgressIndicator(color: Color(0xFF00E0A1)));
      final hits = _results ?? const <HighlightHit>[];
      if (hits.isEmpty) return _message(p, 'لا توجد نتائج لـ "$_query"');
      return _grid(
        p,
        hits.length,
        (i) => _HitCard(hit: hits[i], onTap: () => _openVideo(hits[i].videoId, hits[i].title)),
      );
    }
    return recentAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFF00E0A1))),
      error: (_, __) => _message(p, 'تعذّر جلب المباريات'),
      data: (items) {
        if (items.isEmpty) return _message(p, 'لا مباريات منتهية بعد. جرّب البحث بالأعلى.');
        return _grid(p, items.length, (i) => _MatchCard(match: items[i], onTap: () => _openMatch(items[i])));
      },
    );
  }

  Widget _grid(AppPalette p, int count, Widget Function(int) builder) => GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.82,
        ),
        itemCount: count,
        itemBuilder: (_, i) => builder(i),
      );

  Widget _message(AppPalette p, String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(color: p.textFaint, fontSize: 14, fontWeight: FontWeight.w700)),
        ),
      );

  Widget _searchField() => AppSearchField(
        controller: _searchCtrl,
        hints: const ['ابحث عن مباراة', 'ابحث عن فريق', 'ابحث عن ملخص أهداف'],
        onChanged: _onSearchChanged,
        onSubmitted: (v) => _runSearch(v.trim()),
        onClear: () => _runSearch(''),
        isLoading: _searching,
      );
}

/// A finished match tile: crests and final score; tap to watch the summary.
class _MatchCard extends StatelessWidget {
  final MatchHighlight match;
  final VoidCallback onTap;
  const _MatchCard({required this.match, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: p.isDark ? const Color(0xFF12161C) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.border),
        ),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          children: [
            Row(
              children: [
                if ((match.leagueLogo ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 5),
                    child: CachedNetworkImage(
                      memCacheWidth: 64,
                        imageUrl: match.leagueLogo!, width: 15, height: 15, errorWidget: (_, __, ___) => const SizedBox.shrink()),
                  ),
                Expanded(
                  child: Text(match.league ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.textMuted, fontSize: 10.5, fontWeight: FontWeight.w800)),
                ),
                Text(match.yesterday ? 'أمس' : 'اليوم',
                    style: TextStyle(color: p.textFaint, fontSize: 10, fontWeight: FontWeight.w700)),
              ],
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _team(p, match.home, match.homeLogo)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(match.score,
                        style: TextStyle(color: p.text, fontSize: 20, fontWeight: FontWeight.w900)),
                  ),
                  Expanded(child: _team(p, match.away, match.awayLogo)),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF00A870).withOpacity(0.14),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.play_arrow_rounded, color: Color(0xFF00A870), size: 18),
                  SizedBox(width: 4),
                  Text('شاهد الملخّص',
                      style: TextStyle(color: Color(0xFF00A870), fontSize: 11.5, fontWeight: FontWeight.w900)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _team(AppPalette p, String name, String? logo) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: (logo ?? '').isNotEmpty
                ? CachedNetworkImage(
                  memCacheWidth: 400,
                    imageUrl: logo!,
                    fit: BoxFit.contain,
                    errorWidget: (_, __, ___) => Icon(Icons.shield_rounded, color: p.textFaint, size: 30),
                  )
                : Icon(Icons.shield_rounded, color: p.textFaint, size: 30),
          ),
          const SizedBox(height: 5),
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(color: p.text, fontSize: 11, fontWeight: FontWeight.w800)),
        ],
      );
}

/// A YouTube search hit tile: still and title; tap to watch.
class _HitCard extends StatelessWidget {
  final HighlightHit hit;
  final VoidCallback onTap;
  const _HitCard({required this.hit, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      // Clipped by the container itself (not an outer ClipRRect) so the
      // hairline border follows the rounded corners.
      child: Container(
        decoration: BoxDecoration(
          color: p.isDark ? null : p.card,
          border: Border.all(color: p.border),
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if ((hit.thumbUrl ?? '').isNotEmpty)
                    CachedNetworkImage(
                      memCacheWidth: 800,
                      imageUrl: hit.thumbUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => ColoredBox(color: p.skeleton),
                    )
                  else
                    ColoredBox(color: p.skeleton),
                  Center(
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), shape: BoxShape.circle),
                      child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(hit.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.text, fontSize: 11.5, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}
