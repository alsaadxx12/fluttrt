import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/features/reels/data/reels_service.dart';

/// The one [ReelsService] (and so the one YoutubeExplode client) for the
/// feed, search and comments providers.
final reelsServiceProvider = Provider<ReelsService>((ref) {
  final service = ReelsService();
  ref.onDispose(service.dispose);
  return service;
});
