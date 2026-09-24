import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/qitv_models.dart';
import '../data/qitv_service.dart';

final qiTvServiceProvider = Provider<QiTvService>((ref) => QiTvService());

/// Free active channels from Qi TV.
final qiTvChannelsProvider = FutureProvider<List<QiChannel>>((ref) {
  return ref.watch(qiTvServiceProvider).fetchFreeActiveChannels();
});

/// Showcase content (Top 10 movies & series).
final qiTvShowcaseProvider = FutureProvider<List<QiShowcase>>((ref) {
  return ref.watch(qiTvServiceProvider).fetchShowcase();
});

/// Exclusive original Iraqi works (Qi Originals).
final qiTvExclusiveProvider = FutureProvider<List<QiExclusiveWork>>((ref) {
  return ref.watch(qiTvServiceProvider).fetchExclusiveWorks();
});
