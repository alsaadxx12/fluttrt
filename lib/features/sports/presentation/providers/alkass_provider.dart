import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../casting/services/local_stream_server.dart';
import '../../data/services/alkass_service.dart';
import '../../data/services/aloula_service.dart';

/// The phone's own relay for a channel whose CDN turns the player's
/// requests away but takes the app's: the app fetches, the player reads
/// one continuous stream from the phone itself.
final phoneRelayProvider = Provider<LocalStreamServer>((ref) {
  final relay = LocalStreamServer();
  ref.onDispose(relay.stop);
  return relay;
});

final alkassServiceProvider = Provider<AlkassService>((ref) => AlkassService());
final aloulaServiceProvider = Provider<AloulaService>((ref) => AloulaService());

/// The home page's channels: Alkass's free channels, then KSA Sports 1
/// from the Saudi Broadcasting Authority's platform.
final alkassChannelsProvider = FutureProvider<List<AlkassChannel>>((ref) async {
  final alkass = await ref.watch(alkassServiceProvider).fetchFree();
  return [...alkass, ref.watch(aloulaServiceProvider).sports1()];
});
