import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/viu_models.dart';
import '../data/viu_service.dart';

final viuServiceProvider = Provider<ViuService>((ref) => ViuService());

/// A home row: free series of a category, or the free films.
final viuHomeRowProvider = FutureProvider.family<List<ViuShow>, ViuCategory>((ref, category) async {
  final service = ref.watch(viuServiceProvider);
  final shows = category.isMovies
      ? await service.fetchFreeMovies()
      : (await service.fetchFreeShows(category.id, want: 18)).shows;
  // Original and dubbed versions of a title share one card.
  return ViuShow.mergeVersions(shows);
});

/// The free episodes of a series (or the film itself).
final viuFreeEpisodesProvider = FutureProvider.family<List<ViuEpisode>, String>(
  (ref, seriesId) => ref.watch(viuServiceProvider).fetchFreeEpisodes(seriesId),
);
