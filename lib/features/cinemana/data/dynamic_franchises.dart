import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cinemana_franchises.dart';
import 'models/cinemana_models.dart';
import 'services/cinemana_service.dart';

/// A franchise discovered live from Cinemana rather than listed by hand: a
/// lead title and the parts that belong with it (seasons, sequels, spin-offs),
/// in release order. Until [partsResolved] the parts are just the lead.
class DynamicFranchise {
  /// How many parts a franchise needs before it is one.
  ///
  /// A card offering a single title is not a series, and two is a pair, not a
  /// collection - both read as filler in a row headed "سلاسل". Three is the
  /// floor, so every card in the deck is a real run of films or seasons.
  static const int minParts = 3;

  final String id;
  final String name;
  final CinemanaItem lead;
  final List<CinemanaItem> parts;
  final bool partsResolved;

  const DynamicFranchise({
    required this.id,
    required this.name,
    required this.lead,
    required this.parts,
    required this.partsResolved,
  });

  DynamicFranchise withParts(List<CinemanaItem> p) =>
      DynamicFranchise(id: id, name: name, lead: lead, parts: p, partsResolved: true);

  /// A short franchise name from a title: the part before ":" / " - ", with a
  /// trailing part number stripped ("Harry Potter and the ... 2" → stem).
  static String nameOf(CinemanaItem item) {
    String cut(String t) {
      var s = t.trim();
      for (final sep in [':', ' - ', ' – ']) {
        if (s.contains(sep)) s = s.split(sep).first.trim();
      }
      s = s.replaceAll(RegExp(r'\s+(part\s+)?(\d+|[ivx]+)$', caseSensitive: false), '').trim();
      s = s.replaceAll(RegExp(r'\s+(الجزء|الموسم)\s+\S+$'), '').trim();
      return s;
    }

    final ar = cut(item.arTitle);
    if (ar.length >= 4) return ar;
    final en = cut(item.enTitle);
    if (en.length >= 4) return en;
    // A stem this short ("Re" from "Re:Zero", "Go") is too generic to name a
    // series; keep the full title instead.
    return item.displayTitle;
  }
}

class FranchiseFeedState {
  final List<DynamicFranchise> items;
  final bool loading;
  final bool done;
  const FranchiseFeedState({this.items = const [], this.loading = false, this.done = false});

  FranchiseFeedState copyWith({List<DynamicFranchise>? items, bool? loading, bool? done}) =>
      FranchiseFeedState(items: items ?? this.items, loading: loading ?? this.loading, done: done ?? this.done);
}

/// An endless feed of franchises for one home row.
///
/// Opens with the hand-curated entries (instant, high quality), then walks
/// Cinemana page by page:
///  * anime — every anime series in the catalogue is a series, so each one is
///    a card; its seasons and sequels are resolved lazily when the card shows.
///  * films — popular films are scanned and only those with related parts
///    (a real series) are kept, deduplicated so a franchise appears once.
class FranchiseFeedNotifier extends StateNotifier<FranchiseFeedState> {
  FranchiseFeedNotifier(this._service, this._section) : super(const FranchiseFeedState()) {
    _init();
  }

  final CinemanaService _service;
  final FranchiseSection _section;

  int _page = 0;
  int _empties = 0;

  /// Lead ids already shown, and every part id already covered by a card, so
  /// a second film of the same series never becomes its own card.
  final Set<String> _seen = {};
  final Set<String> _covered = {};
  final Set<String> _resolving = {};

  bool get _isAnime => _section == FranchiseSection.anime;

  Future<void> _init() async {
    // Curated head: resolve the hand-listed franchises through a small pool
    // of workers, so the home page's own requests are never queued behind
    // dozens of franchise searches fired at once.
    final curated = FilmFranchise.inSection(_section);
    final lists = List<List<CinemanaItem>>.filled(curated.length, const []);
    var next = 0;
    Future<void> worker() async {
      while (next < curated.length) {
        final i = next++;
        lists[i] = await _service.fetchFranchise(curated[i]).catchError((_) => <CinemanaItem>[]);
      }
    }

    await Future.wait(List.generate(4, (_) => worker()));
    final head = <DynamicFranchise>[];
    for (var i = 0; i < curated.length; i++) {
      final parts = _ordered(lists[i]);
      // Hand-listed or not, a franchise that resolved to fewer than three
      // parts is not a series worth a card.
      if (parts.length < DynamicFranchise.minParts) continue;
      // The lead is the series' first entry - the end of a newest-first list.
      final lead = parts.last;
      if (!_seen.add(lead.id)) continue;
      _covered.addAll(parts.map((p) => p.id));
      head.add(DynamicFranchise(id: lead.id, name: curated[i].name, lead: lead, parts: parts, partsResolved: true));
    }
    if (!mounted) return;
    // The carousel asks for more on demand as its last cards come into view;
    // only an empty head (nothing curated resolved) needs a first page now,
    // since there is no card yet to trigger it.
    state = state.copyWith(items: head);
    if (head.isEmpty) await loadMore();
  }

  Future<void> loadMore() async {
    if (state.loading || state.done) return;
    state = state.copyWith(loading: true);

    final gathered = <DynamicFranchise>[...state.items];
    final before = gathered.length;
    var done = false;
    // Keep going until this call adds at least one card, so a page of films
    // that are all stand-alone never stalls the row.
    for (var guard = 0; guard < 4; guard++) {
      List<CinemanaItem> page;
      try {
        page = _isAnime
            ? await _service.fetchContent(kind: 'anime', orderby: 'views', videoKind: 2, page: _page)
            : await _service.fetchContent(kind: 'movies', orderby: 'views', page: _page);
      } catch (_) {
        page = const [];
      }
      _page++;
      _empties = page.isEmpty ? _empties + 1 : 0;
      if (_empties >= 3) {
        done = true;
        break;
      }

      final fresh = page.where((it) => !_seen.contains(it.id) && !_covered.contains(it.id)).toList();
      // Films and anime alike: a title earns a card only once its other parts
      // are in hand and there are enough of them. Anime used to become a card
      // on sight and look up its parts later, which is how a single-season
      // show ended up in the deck labelled "مسلسل واحد".
      for (var i = 0; i < fresh.length; i += 6) {
        final chunk = fresh.sublist(i, (i + 6).clamp(0, fresh.length));
        final related = await Future.wait(
          chunk.map((it) => _service.fetchFranchiseParts(it).catchError((_) => <CinemanaItem>[])),
        );
        for (var j = 0; j < chunk.length; j++) {
          final it = chunk[j];
          final parts = _ordered([it, ...related[j]]);
          if (parts.length < DynamicFranchise.minParts) continue;
          final ids = parts.map((p) => p.id).toSet();
          if (ids.any(_covered.contains)) continue; // same series already shown
          // Named after the series' first entry, at the end of a newest-first
          // list. A stem under 4 chars means the parts matched on a generic
          // fragment ("Re", "Go") rather than a real series name: skip.
          final name = DynamicFranchise.nameOf(parts.last);
          if (name.length < 4) continue;
          _seen.add(it.id);
          _covered.addAll(ids);
          gathered.add(DynamicFranchise(id: it.id, name: name, lead: it, parts: parts, partsResolved: true));
        }
      }
      if (gathered.length > before) break;
    }
    if (!mounted) return;
    state = state.copyWith(items: gathered, loading: false, done: done);
  }

  /// Resolve an anime card's seasons and sequels the first time it is shown.
  Future<void> resolveParts(String id) async {
    final idx = state.items.indexWhere((f) => f.id == id);
    if (idx < 0) return;
    final f = state.items[idx];
    if (f.partsResolved || !_resolving.add(id)) return;
    try {
      final rel = await _service.fetchFranchiseParts(f.lead).catchError((_) => <CinemanaItem>[]);
      if (!mounted) return;
      final parts = _ordered([f.lead, ...rel]);
      _covered.addAll(parts.map((p) => p.id));
      final items = [...state.items];
      final i = items.indexWhere((x) => x.id == id);
      if (i >= 0) {
        items[i] = f.withParts(parts);
        state = state.copyWith(items: items);
      }
    } finally {
      _resolving.remove(id);
    }
  }

  /// Release order, newest first, de-duplicated by id.
  ///
  /// A year that will not parse sorts last rather than first: an unknown date
  /// is not news. Callers that want the first entry of the series read the
  /// end of this list.
  static List<CinemanaItem> _ordered(List<CinemanaItem> items) {
    final byId = <String, CinemanaItem>{};
    for (final it in items) {
      byId.putIfAbsent(it.id, () => it);
    }
    final list = byId.values.toList()
      ..sort((a, b) {
        final ya = int.tryParse(a.year) ?? -1;
        final yb = int.tryParse(b.year) ?? -1;
        return ya != yb ? yb.compareTo(ya) : a.displayTitle.compareTo(b.displayTitle);
      });
    return list;
  }
}

final franchiseFeedProvider = StateNotifierProvider.family<FranchiseFeedNotifier, FranchiseFeedState, FranchiseSection>(
  (ref, section) => FranchiseFeedNotifier(CinemanaService(), section),
);
