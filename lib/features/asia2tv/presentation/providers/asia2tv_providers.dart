import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/asia2tv_models.dart';
import '../../data/services/asia2tv_service.dart';

final asia2tvServiceProvider = Provider<Asia2TvService>((ref) {
  final service = Asia2TvService();
  ref.onDispose(service.dispose);
  return service;
});

/// Category items provider with caching
final asia2tvCategoryProvider =
    FutureProvider.family<List<Asia2TvItem>, Asia2TvCategory>((ref, category) async {
  final service = ref.watch(asia2tvServiceProvider);
  return service.fetchCategory(category, page: 1);
});

/// 1. أحدث الحلقات
final asia2tvLatestEpisodesProvider = FutureProvider<List<Asia2TvItem>>((ref) async {
  final service = ref.watch(asia2tvServiceProvider);
  return service.fetchLatestEpisodes(page: 1);
});

/// 2. الدراما الكورية
final asia2tvKoreanDramasProvider = FutureProvider<List<Asia2TvItem>>((ref) async {
  final service = ref.watch(asia2tvServiceProvider);
  return service.fetchCategory(Asia2TvCategory.korean, page: 1);
});

/// 3. الدراما اليابانية
final asia2tvJapaneseDramasProvider = FutureProvider<List<Asia2TvItem>>((ref) async {
  final service = ref.watch(asia2tvServiceProvider);
  return service.fetchCategory(Asia2TvCategory.japanese, page: 1);
});

/// 4. الدراما الصينية والتايوانية
final asia2tvChineseDramasProvider = FutureProvider<List<Asia2TvItem>>((ref) async {
  final service = ref.watch(asia2tvServiceProvider);
  return service.fetchCategory(Asia2TvCategory.chinese, page: 1);
});

/// 5. الدراما التايلاندية
final asia2tvThaiDramasProvider = FutureProvider<List<Asia2TvItem>>((ref) async {
  final service = ref.watch(asia2tvServiceProvider);
  return service.fetchCategory(Asia2TvCategory.thai, page: 1);
});

/// 6. الأفلام الآسيوية
final asia2tvMoviesProvider = FutureProvider<List<Asia2TvItem>>((ref) async {
  final service = ref.watch(asia2tvServiceProvider);
  return service.fetchCategory(Asia2TvCategory.movies, page: 1);
});

/// 7. برامج الترفيه
final asia2tvKShowProvider = FutureProvider<List<Asia2TvItem>>((ref) async {
  final service = ref.watch(asia2tvServiceProvider);
  return service.fetchCategory(Asia2TvCategory.kshow, page: 1);
});

/// Drama details & episodes list provider
final asia2tvDetailsProvider =
    FutureProvider.family<Asia2TvItemDetails, String>((ref, url) async {
  final service = ref.watch(asia2tvServiceProvider);
  return service.fetchDramaDetails(url);
});

/// Playback and highest resolution streams provider (Ad-Free)
final asia2tvPlaybackProvider =
    FutureProvider.family<Asia2TvPlayback, String>((ref, watchUrl) async {
  final service = ref.watch(asia2tvServiceProvider);
  return service.resolveEpisodePlayback(watchUrl);
});

/// Search provider
final asia2tvSearchProvider =
    FutureProvider.family<List<Asia2TvItem>, String>((ref, query) async {
  if (query.trim().isEmpty) return const [];
  final service = ref.watch(asia2tvServiceProvider);
  return service.search(query);
});
