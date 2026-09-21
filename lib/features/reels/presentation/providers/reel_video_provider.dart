import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/features/reels/presentation/providers/reels_service_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// The full video record for a reel (the watch page carries the like count
/// that search results lack); null when it could not be fetched.
///
/// Auto-disposed: it lives while a page shows the reel, and the service
/// keeps the record itself so coming back costs nothing.
final reelVideoProvider = FutureProvider.autoDispose.family<Video?, String>(
  (ref, id) => ref.watch(reelsServiceProvider).video(id),
);
