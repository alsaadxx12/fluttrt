import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/alkass_service.dart';

final alkassServiceProvider = Provider<AlkassService>((ref) => AlkassService());

/// Alkass's free channels, for the home page row.
final alkassChannelsProvider = FutureProvider<List<AlkassChannel>>((ref) {
  return ref.watch(alkassServiceProvider).fetchFree();
});
