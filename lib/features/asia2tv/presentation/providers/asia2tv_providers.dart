import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';
import 'package:youtube_downloader/features/cinemana/presentation/providers/cinemana_provider.dart';
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

/// أحدث المسلسلات الآسيوية: the app's own Asian series and the Asian drama
/// catalogue, in one row.
///
/// The catalogue used to get three rows of its own, each named after it.
/// It has none now — its dramas are folded into the row the app already
/// had. A title the app already carries is not repeated, single episodes
/// are left out (an episode is not a title), and the row reads newest
/// first whichever catalogue an entry came from.
final asianSeriesMergedProvider = FutureProvider<List<CinemanaItem>>((ref) async {
  final own = await ref.watch(homeAsianSeriesProvider.future);

  const cats = [
    Asia2TvCategory.korean,
    Asia2TvCategory.japanese,
    Asia2TvCategory.chinese,
    Asia2TvCategory.thai,
  ];
  final service = ref.watch(asia2tvServiceProvider);
  final lists = await Future.wait([
    for (final c in cats) service.fetchCategory(c).catchError((_) => <Asia2TvItem>[]),
  ]);

  final merged = <CinemanaItem>[...own];
  final seen = {
    for (final i in own)
      if (CinemanaItem.normalizeTitle(i.displayTitle).isNotEmpty)
        CinemanaItem.normalizeTitle(i.displayTitle),
  };
  for (final list in lists) {
    for (final it in list) {
      if (it.isEpisode) continue;
      final key = CinemanaItem.normalizeTitle(it.title);
      if (key.isEmpty || !seen.add(key)) continue;
      merged.add(it.toCinemanaItem());
    }
  }

  // Newest first, and stable: two titles of the same year keep the order
  // their own catalogue gave them rather than swapping about on each load.
  final decorated = [
    for (var i = 0; i < merged.length; i++) (i, merged[i]),
  ]..sort((a, b) {
      final ya = int.tryParse(a.$2.year) ?? -1;
      final yb = int.tryParse(b.$2.year) ?? -1;
      return ya != yb ? yb.compareTo(ya) : a.$1.compareTo(b.$1);
    });
  return [for (final d in decorated) d.$2];
});
