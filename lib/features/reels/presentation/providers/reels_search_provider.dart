import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_downloader/features/reels/data/reels_service.dart';
import 'package:youtube_downloader/features/reels/presentation/providers/reels_service_provider.dart';

/// A reels search: the query, what it found, and the recent queries.
class ReelsSearchState {
  const ReelsSearchState({
    this.query = '',
    this.results = const [],
    this.isLoading = false,
    this.hasMore = false,
    this.failed = false,
    this.searched = false,
    this.recent = const [],
    this.page,
  });

  final String query;
  final List<Reel> results;
  final bool isLoading;
  final bool hasMore;

  /// The request failed and there is nothing to show.
  final bool failed;

  /// A search has been submitted (so the page shows results, not the
  /// suggestions).
  final bool searched;

  /// Recent queries, newest first.
  final List<String> recent;
  final ReelsPage? page;

  ReelsSearchState copyWith({
    String? query,
    List<Reel>? results,
    bool? isLoading,
    bool? hasMore,
    bool? failed,
    bool? searched,
    List<String>? recent,
    ReelsPage? page,
    bool clearPage = false,
  }) =>
      ReelsSearchState(
        query: query ?? this.query,
        results: results ?? this.results,
        isLoading: isLoading ?? this.isLoading,
        hasMore: hasMore ?? this.hasMore,
        failed: failed ?? this.failed,
        searched: searched ?? this.searched,
        recent: recent ?? this.recent,
        page: clearPage ? null : (page ?? this.page),
      );
}

class ReelsSearchNotifier extends StateNotifier<ReelsSearchState> {
  ReelsSearchNotifier(this._service) : super(const ReelsSearchState()) {
    _loadRecent();
  }

  final ReelsService _service;

  static const String recentKey = 'reels_recent_v1';
  static const int maxRecent = 10;

  /// Bumped by every new search or clear so a late result of an earlier
  /// request is dropped.
  int _generation = 0;
  bool _loadingMore = false;

  Future<void> _loadRecent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(recentKey);
      if (list != null && mounted) state = state.copyWith(recent: list.take(maxRecent).toList());
    } catch (_) {}
  }

  Future<void> _saveRecent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(recentKey, state.recent);
    } catch (_) {}
  }

  void _remember(String q) {
    final next = [q, ...state.recent.where((e) => e != q)].take(maxRecent).toList();
    state = state.copyWith(recent: next);
    _saveRecent();
  }

  Future<void> removeRecent(String q) async {
    state = state.copyWith(recent: state.recent.where((e) => e != q).toList());
    await _saveRecent();
  }

  /// Runs a fresh search for [query]; an empty query is ignored.
  Future<void> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final gen = ++_generation;
    _loadingMore = false;
    _remember(q);
    state = state.copyWith(
      query: q,
      results: const [],
      isLoading: true,
      hasMore: false,
      failed: false,
      searched: true,
      clearPage: true,
    );
    final page = await _service.search(q);
    if (!mounted || gen != _generation) return;
    state = state.copyWith(
      results: page.items,
      isLoading: false,
      hasMore: page.hasMore,
      failed: page.failed && page.items.isEmpty,
      page: page,
    );
  }

  /// The next batch for the current query, once at a time.
  Future<void> loadMore() async {
    final page = state.page;
    if (_loadingMore || state.isLoading || !state.hasMore || page == null) return;
    final gen = _generation;
    _loadingMore = true;
    state = state.copyWith(isLoading: true);
    try {
      final next = await _service.search(state.query, after: page);
      if (!mounted || gen != _generation) return;
      state = state.copyWith(
        results: [...state.results, ...next.items],
        isLoading: false,
        hasMore: next.hasMore,
        page: next,
      );
    } finally {
      if (gen == _generation) _loadingMore = false;
    }
  }

  /// Back to the suggestions, with nothing searched.
  void clear() {
    ++_generation;
    _loadingMore = false;
    state = state.copyWith(
      query: '',
      results: const [],
      isLoading: false,
      hasMore: false,
      failed: false,
      searched: false,
      clearPage: true,
    );
  }
}

final reelsSearchProvider = StateNotifierProvider<ReelsSearchNotifier, ReelsSearchState>(
  (ref) => ReelsSearchNotifier(ref.watch(reelsServiceProvider)),
);
