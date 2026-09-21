import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';
import '../../data/models/exclusive_media_models.dart';
import '../../data/services/exclusive_media_service.dart';

final exclusiveServiceProvider = Provider<ExclusiveMediaService>((ref) {
  final service = ExclusiveMediaService();
  ref.onDispose(service.dispose);
  return service;
});

/// Recent 60 items (both series and movies)
final exclusiveRecentProvider = FutureProvider<List<ExclusiveMediaItem>>((ref) async {
  final service = ref.watch(exclusiveServiceProvider);
  return service.fetchRecent(page: 1);
});

/// Latest series formatted as [CinemanaItem] for home screen display
final exclusiveLatestSeriesProvider = FutureProvider<List<CinemanaItem>>((ref) async {
  final service = ref.watch(exclusiveServiceProvider);
  final items = await service.fetchSeries(page: 1);
  return items.map((i) => i.toCinemanaItem()).toList();
});

/// Latest movies formatted as [CinemanaItem] for home screen display
final exclusiveLatestMoviesProvider = FutureProvider<List<CinemanaItem>>((ref) async {
  final service = ref.watch(exclusiveServiceProvider);
  final items = await service.fetchMovies(page: 1);
  return items.map((i) => i.toCinemanaItem()).toList();
});

/// Dynamic category provider
final exclusiveCategoryProvider =
    FutureProvider.family<List<ExclusiveMediaItem>, ExclusiveCategory>((ref, category) async {
  final service = ref.watch(exclusiveServiceProvider);
  return service.fetchCategory(category, page: 1);
});

/// Details and episode list provider
final exclusiveDetailsProvider =
    FutureProvider.family<ExclusiveDetails, String>((ref, url) async {
  final service = ref.watch(exclusiveServiceProvider);
  return service.fetchDetails(url);
});

/// Direct CDN stream resolver
final exclusiveStreamsProvider =
    FutureProvider.family<List<ExclusiveStream>, String>((ref, url) async {
  final service = ref.watch(exclusiveServiceProvider);
  return service.resolveDirectStreams(url);
});

/// Search provider
final exclusiveSearchProvider =
    FutureProvider.family<List<ExclusiveMediaItem>, String>((ref, query) async {
  if (query.trim().isEmpty) return const [];
  final service = ref.watch(exclusiveServiceProvider);
  return service.search(query);
});
