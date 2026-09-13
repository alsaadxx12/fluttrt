import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/shahid_models.dart';
import '../data/shahid_service.dart';

final shahidServiceProvider = Provider<ShahidService>((ref) => ShahidService());

final shahidChannelsProvider = FutureProvider<List<ShahidItem>>((ref) {
  return ref.watch(shahidServiceProvider).fetchLiveChannels();
});

/// One Shahid home row, keyed by its row id (see [ShahidRows]).
final shahidRowProvider = FutureProvider.family<List<ShahidItem>, String>((ref, rowId) {
  return ref.watch(shahidServiceProvider).fetchRow(rowId);
});

const kShahidFilterAll = 'الكل';
const kShahidFilterFree = 'مجانية';

/// Filter chips for the channel list: "all", then the genres that actually
/// occur, most common first. (Every listed channel is free, so no "free" chip.)
List<String> shahidChannelFilters(List<ShahidItem> channels, {int maxGenres = 8}) {
  final counts = <String, int>{};
  for (final c in channels) {
    for (final g in c.genres) {
      counts[g] = (counts[g] ?? 0) + 1;
    }
  }
  final genres = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  return [kShahidFilterAll, ...genres.take(maxGenres)];
}

List<ShahidItem> filterShahidChannels(List<ShahidItem> channels, String filter) {
  if (filter == kShahidFilterAll) return channels;
  if (filter == kShahidFilterFree) return channels.where((c) => c.isFree).toList();
  return channels.where((c) => c.genres.contains(filter)).toList();
}
