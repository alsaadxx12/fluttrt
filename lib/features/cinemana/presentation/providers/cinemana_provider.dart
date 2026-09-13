import '../../data/cinemana_franchises.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/cinemana_models.dart';
import '../../data/services/cinemana_service.dart';
import '../../data/services/cinemana_favorites_service.dart';

final cinemanaServiceProvider = Provider<CinemanaService>((ref) {
  return CinemanaService();
});

final cinemanaFavoritesServiceProvider = Provider<CinemanaFavoritesService>((ref) {
  return CinemanaFavoritesService();
});

// ==========================================
// Favorites Provider (Local Storage)
// ==========================================

class CinemanaFavoritesNotifier extends StateNotifier<List<CinemanaItem>> {
  final CinemanaFavoritesService _service;

  CinemanaFavoritesNotifier(this._service) : super([]) {
    loadFavorites();
  }

  Future<void> loadFavorites() async {
    final list = await _service.getFavorites();
    state = list;
  }

  Future<bool> toggleFavorite(CinemanaItem item) async {
    final isNowFavorited = await _service.toggleFavorite(item);
    await loadFavorites();
    return isNowFavorited;
  }

  Future<void> removeFavorite(String id) async {
    await _service.removeFavorite(id);
    await loadFavorites();
  }

  bool isFavorite(String id) {
    return state.any((it) => it.id == id);
  }
}

final cinemanaFavoritesProvider =
    StateNotifierProvider<CinemanaFavoritesNotifier, List<CinemanaItem>>((ref) {
  final service = ref.watch(cinemanaFavoritesServiceProvider);
  return CinemanaFavoritesNotifier(service);
});

// ==========================================
// Independent Section State (Movies, Series, Anime)
// ==========================================

class CinemanaSectionState {
  final String kind; // 'movies', 'series', 'anime'
  final List<CinemanaItem> items;
  final List<CinemanaItem> searchResults;
  final List<CinemanaItem> rawSearchResults;
  final String searchQuery;
  final int? selectedCategoryId; // null or 0 = All
  final String selectedOrder; // 'desc', 'release', 'views', 'trending', 'stars', 'name', 'featured'
  final String? selectedYear; // null or e.g. '2026'
  final double? selectedRating; // null or e.g. 7.0
  final String? selectedStatus; // null or 'مستمر', 'مكتمل'
  final int animeSubKind; // 2: Anime Series, 1: Anime Movies
  final int page;
  final bool isLoading;
  final bool isLoadingMore;
  final bool isSearchLoading;
  final String? errorMessage;

  const CinemanaSectionState({
    required this.kind,
    this.items = const [],
    this.searchResults = const [],
    this.rawSearchResults = const [],
    this.searchQuery = '',
    this.selectedCategoryId,
    this.selectedOrder = 'desc',
    this.selectedYear,
    this.selectedRating,
    this.selectedStatus,
    this.animeSubKind = 2,
    this.page = 0,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.isSearchLoading = false,
    this.errorMessage,
  });

  List<CinemanaItem> get displayItems =>
      searchQuery.isNotEmpty ? searchResults : items;

  /// Search hits that belong to another section
  int get hiddenSearchCount =>
      searchQuery.isEmpty ? 0 : rawSearchResults.length - searchResults.length;

  CinemanaSectionState copyWith({
    String? kind,
    List<CinemanaItem>? items,
    List<CinemanaItem>? searchResults,
    List<CinemanaItem>? rawSearchResults,
    String? searchQuery,
    int? selectedCategoryId,
    bool clearCategory = false,
    String? selectedOrder,
    String? selectedYear,
    bool clearYear = false,
    double? selectedRating,
    bool clearRating = false,
    String? selectedStatus,
    bool clearStatus = false,
    int? animeSubKind,
    int? page,
    bool? isLoading,
    bool? isLoadingMore,
    bool? isSearchLoading,
    String? errorMessage,
  }) {
    return CinemanaSectionState(
      kind: kind ?? this.kind,
      items: items ?? this.items,
      searchResults: searchResults ?? this.searchResults,
      rawSearchResults: rawSearchResults ?? this.rawSearchResults,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedCategoryId:
          clearCategory ? null : (selectedCategoryId ?? this.selectedCategoryId),
      selectedOrder: selectedOrder ?? this.selectedOrder,
      selectedYear: clearYear ? null : (selectedYear ?? this.selectedYear),
      selectedRating: clearRating ? null : (selectedRating ?? this.selectedRating),
      selectedStatus: clearStatus ? null : (selectedStatus ?? this.selectedStatus),
      animeSubKind: animeSubKind ?? this.animeSubKind,
      page: page ?? this.page,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isSearchLoading: isSearchLoading ?? this.isSearchLoading,
      errorMessage: errorMessage,
    );
  }
}

class CinemanaSectionNotifier extends StateNotifier<CinemanaSectionState> {
  final CinemanaService _service;
  final String _kind;
  CancelToken? _cancelToken;

  CinemanaSectionNotifier(this._service, this._kind)
      : super(CinemanaSectionState(kind: _kind)) {
    loadInitial();
  }

  void _renewCancelToken() {
    _cancelToken?.cancel('Cancelled by new request');
    _cancelToken = CancelToken();
  }

  @override
  void dispose() {
    _cancelToken?.cancel('Disposed');
    super.dispose();
  }

  Future<void> loadInitial() async {
    _renewCancelToken();
    state = state.copyWith(isLoading: true, errorMessage: null, page: 0);
    try {
      final items = await _service.fetchContent(
        kind: _kind,
        categoryId: state.selectedCategoryId,
        orderby: state.selectedOrder,
        videoKind: _kind == 'anime' ? state.animeSubKind : null,
        page: 0,
        year: state.selectedYear,
        minRating: state.selectedRating,
        cancelToken: _cancelToken,
      );
      state = state.copyWith(
        items: items,
        isLoading: false,
        page: 0,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, errorMessage: 'تعذر جلب البيانات');
    }
  }

  Future<void> applyFilters({
    String? order,
    int? categoryId,
    bool clearCategory = false,
    String? year,
    bool clearYear = false,
    double? minRating,
    bool clearRating = false,
    String? status,
    bool clearStatus = false,
  }) async {
    _renewCancelToken();
    final newOrder = order ?? state.selectedOrder;
    final newCategoryId = clearCategory ? null : (categoryId ?? state.selectedCategoryId);
    final newYear = clearYear ? null : (year ?? state.selectedYear);
    final newRating = clearRating ? null : (minRating ?? state.selectedRating);
    final newStatus = clearStatus ? null : (status ?? state.selectedStatus);

    state = state.copyWith(
      selectedOrder: newOrder,
      selectedCategoryId: newCategoryId,
      clearCategory: clearCategory,
      selectedYear: newYear,
      clearYear: clearYear,
      selectedRating: newRating,
      clearRating: clearRating,
      selectedStatus: newStatus,
      clearStatus: clearStatus,
      isLoading: true,
      page: 0,
      searchQuery: '',
      searchResults: const [],
      rawSearchResults: const [],
    );

    try {
      final items = await _service.fetchContent(
        kind: _kind,
        categoryId: newCategoryId,
        orderby: newOrder,
        videoKind: _kind == 'anime' ? state.animeSubKind : null,
        page: 0,
        year: newYear,
        minRating: newRating,
        cancelToken: _cancelToken,
      );
      if (!mounted) return;
      state = state.copyWith(items: items, isLoading: false);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> resetFilters() async {
    _renewCancelToken();
    state = state.copyWith(
      selectedOrder: 'desc',
      clearCategory: true,
      clearYear: true,
      clearRating: true,
      clearStatus: true,
      isLoading: true,
      page: 0,
      searchQuery: '',
      searchResults: const [],
      rawSearchResults: const [],
    );
    try {
      final items = await _service.fetchContent(
        kind: _kind,
        categoryId: null,
        orderby: 'desc',
        videoKind: _kind == 'anime' ? state.animeSubKind : null,
        page: 0,
        cancelToken: _cancelToken,
      );
      if (!mounted) return;
      state = state.copyWith(items: items, isLoading: false);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> setAnimeSubKind(int subKind) async {
    if (state.animeSubKind == subKind) return;
    state = state.copyWith(animeSubKind: subKind);

    if (state.searchQuery.isNotEmpty) {
      state = state.copyWith(
        searchResults: _filterForSection(state.rawSearchResults),
      );
      return;
    }

    _renewCancelToken();
    state = state.copyWith(isLoading: true, page: 0);
    try {
      final items = await _service.fetchContent(
        kind: _kind,
        categoryId: state.selectedCategoryId,
        orderby: state.selectedOrder,
        videoKind: subKind,
        page: 0,
        year: state.selectedYear,
        minRating: state.selectedRating,
        cancelToken: _cancelToken,
      );
      if (!mounted) return;
      state = state.copyWith(items: items, isLoading: false);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> setCategory(int? categoryId) async {
    if (state.selectedCategoryId == categoryId) return;
    await applyFilters(
      categoryId: categoryId,
      clearCategory: categoryId == null || categoryId == 0,
    );
  }

  Future<void> setOrder(String order) async {
    if (state.selectedOrder == order) return;
    await applyFilters(order: order);
  }

  List<CinemanaItem> _filterForSection(List<CinemanaItem> results) {
    switch (_kind) {
      case 'series':
        return results.where((r) => r.isSeries).toList();
      case 'anime':
        final wantSeries = state.animeSubKind == 2;
        return results
            .where((r) =>
                r.isSeries == wantSeries &&
                r.hasCategoryEn(CinemanaService.animationCategoryEnTitle))
            .toList();
      case 'movies':
      default:
        return results.where((r) => !r.isSeries).toList();
    }
  }

  Future<void> search(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) {
      clearSearch();
      return;
    }
    _renewCancelToken();
    state = state.copyWith(
      searchQuery: clean,
      isSearchLoading: true,
      rawSearchResults: const [],
      searchResults: const [],
    );
    try {
      final results = await _service.search(clean, cancelToken: _cancelToken);
      if (!mounted) return;
      state = state.copyWith(
        rawSearchResults: results,
        searchResults: _filterForSection(results),
        isSearchLoading: false,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isSearchLoading: false);
    }
  }

  void clearSearch() {
    state = state.copyWith(
      searchQuery: '',
      searchResults: const [],
      rawSearchResults: const [],
      isSearchLoading: false,
    );
  }

  Future<void> refresh() async {
    if (state.searchQuery.isNotEmpty) {
      await search(state.searchQuery);
      return;
    }
    await loadInitial();
  }

  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || state.searchQuery.isNotEmpty) return;
    state = state.copyWith(isLoadingMore: true);
    final nextPage = state.page + 1;
    try {
      final items = await _service.fetchContent(
        kind: _kind,
        categoryId: state.selectedCategoryId,
        orderby: state.selectedOrder,
        videoKind: _kind == 'anime' ? state.animeSubKind : null,
        page: nextPage,
        year: state.selectedYear,
        minRating: state.selectedRating,
      );
      if (!mounted) return;
      // Prevent duplicates by ID
      final existingIds = state.items.map((i) => i.id).toSet();
      final freshItems = items.where((i) => !existingIds.contains(i.id)).toList();

      state = state.copyWith(
        items: [...state.items, ...freshItems],
        page: nextPage,
        isLoadingMore: false,
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(isLoadingMore: false);
    }
  }
}

final cinemanaSectionProvider = StateNotifierProvider.family<
    CinemanaSectionNotifier, CinemanaSectionState, String>((ref, kind) {
  final service = ref.watch(cinemanaServiceProvider);
  return CinemanaSectionNotifier(service, kind);
});

// Dedicated providers for the 11 Home Screen Sections (Strictly separated queries)

/// 1. المحتوى المميز (Featured)
final homeFeaturedProvider = FutureProvider<List<CinemanaItem>>((ref) async {
  final service = ref.watch(cinemanaServiceProvider);
  return service.fetchFeatured();
});

/// 2. أضيف حديثًا (Recently Added)
final homeRecentlyAddedProvider = FutureProvider<List<CinemanaItem>>((ref) async {
  final service = ref.watch(cinemanaServiceProvider);
  return service.fetchRecentlyAdded(page: 0, itemsPerPage: 24);
});

/// 3. أحدث الأفلام (Latest Movies)
final homeLatestMoviesProvider = FutureProvider<List<CinemanaItem>>((ref) async {
  final service = ref.watch(cinemanaServiceProvider);
  return service.fetchLatestMoviesRelease(page: 0, itemsPerPage: 24);
});

/// 4. أحدث المسلسلات (Latest Series)
final homeLatestSeriesProvider = FutureProvider<List<CinemanaItem>>((ref) async {
  final service = ref.watch(cinemanaServiceProvider);
  return service.fetchLatestSeriesRelease(page: 0, itemsPerPage: 24);
});

/// 5. أحدث الحلقات (Latest Episodes)
final homeLatestEpisodesProvider = FutureProvider<List<CinemanaItem>>((ref) async {
  final service = ref.watch(cinemanaServiceProvider);
  return service.fetchLatestEpisodes(page: 0, itemsPerPage: 24);
});

/// 6. الأكثر مشاهدة (Most Viewed)
final homeMostViewedProvider = FutureProvider<List<CinemanaItem>>((ref) async {
  final service = ref.watch(cinemanaServiceProvider);
  return service.fetchMostViewed(page: 0, itemsPerPage: 24);
});

/// 7. الرائج هذا الأسبوع (Trending)
final homeTrendingProvider = FutureProvider<List<CinemanaItem>>((ref) async {
  final service = ref.watch(cinemanaServiceProvider);
  return service.fetchTrending(page: 0, itemsPerPage: 24);
});

/// 8. الأعلى تقييمًا (Top Rated)
final homeTopRatedProvider = FutureProvider<List<CinemanaItem>>((ref) async {
  final service = ref.watch(cinemanaServiceProvider);
  return service.fetchTopRated(page: 0, itemsPerPage: 24);
});

/// 9. الأفلام العربية (Arabic Movies)
final homeArabicMoviesProvider = FutureProvider<List<CinemanaItem>>((ref) async {
  final service = ref.watch(cinemanaServiceProvider);
  return service.fetchArabicMovies(page: 0, itemsPerPage: 24);
});

/// 10. المسلسلات العربية (Arabic Series)
final homeArabicSeriesProvider = FutureProvider<List<CinemanaItem>>((ref) async {
  final service = ref.watch(cinemanaServiceProvider);
  return service.fetchArabicSeries(page: 0, itemsPerPage: 24);
});

/// 11. اقتراحات لك (Suggestions For You)
final homeSuggestionsProvider = FutureProvider<List<CinemanaItem>>((ref) async {
  final service = ref.watch(cinemanaServiceProvider);
  return service.fetchSuggestions(page: 0, itemsPerPage: 24);
});

/// قسم الأنمي (Anime)
final homeAnimeProvider = FutureProvider<List<CinemanaItem>>((ref) async {
  final service = ref.watch(cinemanaServiceProvider);
  return service.fetchAnime(page: 0, itemsPerPage: 24);
});

// Dedicated provider for official Cinemana Hero Banners ("الإصدارات الجديدة")
final heroBannerMoviesProvider = FutureProvider<List<CinemanaItem>>((ref) async {
  final service = ref.watch(cinemanaServiceProvider);
  return service.fetchBannersWithPosters();
});

// Backward compatibility providers
final categoryActionMoviesProvider = FutureProvider<List<CinemanaItem>>((ref) async {
  final service = ref.watch(cinemanaServiceProvider);
  return service.fetchContent(kind: 'movies', categoryId: 84);
});

final categoryRomanceMoviesProvider = FutureProvider<List<CinemanaItem>>((ref) async {
  final service = ref.watch(cinemanaServiceProvider);
  return service.fetchContent(kind: 'movies', categoryId: 77);
});

final categoryBioMoviesProvider = FutureProvider<List<CinemanaItem>>((ref) async {
  final service = ref.watch(cinemanaServiceProvider);
  return service.fetchContent(kind: 'movies', categoryId: 58);
});

final categoryAnimeMoviesProvider = FutureProvider<List<CinemanaItem>>((ref) async {
  final service = ref.watch(cinemanaServiceProvider);
  return service.fetchContent(kind: 'anime');
});

final topRatedWorthWatchingProvider = homeTopRatedProvider;
final homeSeriesSectionProvider = homeLatestSeriesProvider;
final cinemanaCatalogProvider = cinemanaSectionProvider('movies');

/// The films of one big series (see [FilmFranchise]), by its id.
final franchiseFilmsProvider = FutureProvider.family<List<CinemanaItem>, String>((ref, id) {
  final franchise = FilmFranchise.all.firstWhere((f) => f.id == id);
  return ref.watch(cinemanaServiceProvider).fetchFranchise(franchise);
});
