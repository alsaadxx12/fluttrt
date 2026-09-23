import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/alkass_service.dart';
import '../../data/services/aloula_service.dart';

final alkassServiceProvider = Provider<AlkassService>((ref) => AlkassService());
final aloulaServiceProvider = Provider<AloulaService>((ref) => AloulaService());

/// The home page's channels: Alkass's free channels, then KSA Sports 1
/// from the Saudi Broadcasting Authority's platform.
final alkassChannelsProvider = FutureProvider<List<AlkassChannel>>((ref) async {
  final alkass = await ref.watch(alkassServiceProvider).fetchFree();
  return [...alkass, ref.watch(aloulaServiceProvider).sports1()];
});
