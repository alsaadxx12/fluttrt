import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// What the watch page shows about the channel behind the playing video:
/// its round picture, its name and its subscriber count.
class ChannelInfo {
  final String id;
  final String title;
  final String logoUrl;
  final int subscribersCount;

  const ChannelInfo({
    required this.id,
    required this.title,
    required this.logoUrl,
    required this.subscribersCount,
  });
}

/// One YoutubeExplode client shared by every channel lookup, kept for the
/// life of the app so its connection pool is reused across videos.
final _channelClientProvider = Provider<YoutubeExplode>((ref) {
  final yt = YoutubeExplode();
  ref.onDispose(yt.close);
  return yt;
});

/// The channel with [channelId], or null when YouTube cannot be reached,
/// answers slowly (10 s) or rejects the id. A result is kept alive so the
/// next video of the same channel shows its row at once.
final channelInfoProvider = FutureProvider.family<ChannelInfo?, String>((ref, channelId) async {
  ref.keepAlive();
  final yt = ref.watch(_channelClientProvider);
  try {
    final channel = await yt.channels.get(ChannelId(channelId)).timeout(const Duration(seconds: 10));
    return ChannelInfo(
      id: channel.id.value,
      title: channel.title,
      logoUrl: channel.logoUrl,
      subscribersCount: channel.subscribersCount ?? 0,
    );
  } catch (_) {
    return null;
  }
});
