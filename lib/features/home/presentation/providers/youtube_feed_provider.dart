import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:youtube_downloader/features/downloads/domain/download_service.dart';
import 'package:youtube_downloader/features/downloads/presentation/providers/downloads_provider.dart';

class YouTubeFeedState {
  final String currentCategory;
  final String searchQuery;
  final List<Video> videos;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? errorMessage;

  const YouTubeFeedState({
    this.currentCategory = 'الكل',
    this.searchQuery = '',
    this.videos = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.errorMessage,
  });

  YouTubeFeedState copyWith({
    String? currentCategory,
    String? searchQuery,
    List<Video>? videos,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? errorMessage,
  }) {
    return YouTubeFeedState(
      currentCategory: currentCategory ?? this.currentCategory,
      searchQuery: searchQuery ?? this.searchQuery,
      videos: videos ?? this.videos,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      errorMessage: errorMessage,
    );
  }
}

class YouTubeFeedNotifier extends StateNotifier<YouTubeFeedState> {
  final DownloadService _downloadService;

  YouTubeFeedNotifier(this._downloadService) : super(const YouTubeFeedState()) {
    // Initial load with default trending/explore feed
    loadCategory('الكل');
  }

  Future<void> loadCategory(String category) async {
    state = state.copyWith(
      currentCategory: category,
      searchQuery: '',
      isLoading: true,
      isLoadingMore: false,
      hasMore: true,
      errorMessage: null,
    );

    try {
      final videos = await _downloadService.getFeedVideos(category: category);
      state = state.copyWith(
        videos: videos,
        isLoading: false,
        hasMore: videos.isNotEmpty,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'تعذر تحميل قائمة الفيديوهات، يرجى التحقق من الاتصال بالإنترنت',
      );
    }
  }

  Future<void> clearSearch() async {
    state = state.copyWith(searchQuery: '');
    await loadCategory(state.currentCategory);
  }

  Future<void> search(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) {
      await clearSearch();
      return;
    }

    state = state.copyWith(
      searchQuery: clean,
      isLoading: true,
      isLoadingMore: false,
      hasMore: true,
      errorMessage: null,
    );

    try {
      final videos = await _downloadService.searchVideos(clean);
      state = state.copyWith(
        videos: videos,
        isLoading: false,
        hasMore: videos.isNotEmpty,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'حدث خطأ أثناء البحث، يرجى المحاولة مرة أخرى',
      );
    }
  }

  /// Loads the next page of videos seamlessly (Infinite Scroll)
  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;

    state = state.copyWith(isLoadingMore: true);

    try {
      final moreVideos = await _downloadService.loadMoreVideos();
      if (moreVideos.isEmpty) {
        state = state.copyWith(
          isLoadingMore: false,
          hasMore: false,
        );
      } else {
        // Filter duplicates by video id
        final existingIds = state.videos.map((v) => v.id.value).toSet();
        final uniqueList = moreVideos.where((v) => !existingIds.contains(v.id.value)).toList();

        state = state.copyWith(
          videos: [...state.videos, ...uniqueList],
          isLoadingMore: false,
          hasMore: true,
        );
      }
    } catch (e) {
      state = state.copyWith(isLoadingMore: false);
    }
  }

  Future<void> refresh() async {
    if (state.searchQuery.isNotEmpty) {
      await search(state.searchQuery);
    } else {
      await loadCategory(state.currentCategory);
    }
  }
}

final youtubeFeedProvider = StateNotifierProvider<YouTubeFeedNotifier, YouTubeFeedState>((ref) {
  final downloadService = ref.watch(downloadServiceProvider);
  return YouTubeFeedNotifier(downloadService);
});
