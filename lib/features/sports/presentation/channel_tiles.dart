import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_palette.dart';
import 'package:youtube_downloader/core/network/image_cache.dart';
import '../../shahid/data/shahid_models.dart';
import '../../shahid/presentation/shahid_player_screen.dart';
import '../data/models/sports_models.dart';
import 'providers/sports_provider.dart';
import 'screens/sports_player_screen.dart';
import 'screens/youtube_live_screen.dart';

/// Opens a live channel straight in the right player: YouTube-hosted
/// channels in the YouTube player, HLS channels in the native player with
/// the other HLS channels underneath, anything else in the sports player.
/// (The dedicated channels page is gone; the home row opens channels here.)
void openSportsChannel(BuildContext context, WidgetRef ref, SportsChannel channel) {
  if (channel.channelType == 'YOUTUBE_LIVE') {
    final id = Uri.tryParse(channel.channelUrl)?.queryParameters['v'];
    if (id != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => YoutubeLiveScreen(
            videoId: id,
            title: channel.channelName,
            logoUrl: channel.channelImage,
          ),
        ),
      );
      return;
    }
  }
  if (channel.channelUrl.contains('.m3u8')) {
    final all = ref.read(sportsChannelsProvider).valueOrNull ?? [channel];
    final items = all.where((c) => c.channelUrl.contains('.m3u8')).map(_asPlayable).toList();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShahidPlayerScreen(channel: _asPlayable(channel), channels: items),
      ),
    );
    return;
  }
  final match = SportMatchItem.fromSportsChannel(channel);
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => SportsPlayerScreen(
        match: match,
        initialSportsChannel: channel,
      ),
    ),
  );
}

ShahidItem _asPlayable(SportsChannel c) => ShahidItem(
      id: c.channelId,
      title: c.channelName,
      productType: 'LIVESTREAM',
      // Shahid channels get their stream re-resolved by id on open.
      pageUrl: c.channelType == 'SHAHID' ? 'https://shahid.mbc.net/' : '',
      logoTemplate: c.channelImage.isEmpty ? null : c.channelImage,
      isFree: true,
      streamUrl: c.channelUrl,
    );

/// A channel's picture on its card: Shahid's branded 16:9 tile fills the card
/// edge to edge (same ratio, so nothing is cut); other channels' logos are
/// shown whole with a little breathing room. Images are kept on disk, so a
/// logo seen once (on the home page or under the player) shows at once.
///
/// [caption] names the channel under its logo - used only where several
/// channels share one logo (Karbala's, Al Iraqiya's).
Widget channelTileImage(SportsChannel channel, {String? caption}) {
  Widget buildFallback(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.live_tv_rounded, size: 30, color: Color(0xFFE50914)),
          const SizedBox(height: 6),
          Text(
            channel.channelName,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: p.text,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  if (channel.channelImage.isEmpty) {
    return Builder(builder: buildFallback);
  }
  final isTile = channel.channelType == 'SHAHID';
  final image = CachedNetworkImage(
    imageUrl: channel.channelImage,
    cacheManager: appImageCache,
    fit: isTile ? BoxFit.cover : BoxFit.contain,
    // Some broadcasters serve 3000px+ logos; decode at card size.
    memCacheWidth: 480,
    fadeInDuration: Duration.zero,
    fadeOutDuration: Duration.zero,
    placeholderFadeInDuration: Duration.zero,
    useOldImageOnUrlChange: true,
    placeholder: (_, __) => const SizedBox.shrink(),
    errorWidget: (context, _, ___) => buildFallback(context),
  );
  final picture = isTile
      ? image
      : Padding(
          padding: EdgeInsets.fromLTRB(16, 22, 16, caption == null ? 14 : 30),
          child: image,
        );
  if (caption == null) return picture;
  return Stack(
    fit: StackFit.expand,
    children: [
      picture,
      PositionedDirectional(
        start: 8,
        end: 8,
        bottom: 7,
        child: Builder(
          builder: (context) => Text(
            caption,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppPalette.of(context).textMuted, fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    ],
  );
}

/// Channels whose logo another channel also uses - they get their name
/// under the logo so they can be told apart.
Set<String> channelsSharingLogo(Iterable<SportsChannel> channels) {
  final byLogo = <String, int>{};
  for (final c in channels) {
    if (c.channelImage.isNotEmpty) byLogo[c.channelImage] = (byLogo[c.channelImage] ?? 0) + 1;
  }
  return {
    for (final c in channels)
      if ((byLogo[c.channelImage] ?? 0) > 1) c.channelName,
  };
}

/// Downloads every channel logo into the image cache ahead of time, so the
/// player's channel list and the home row never wait for them.
void precacheChannelLogos(BuildContext context, Iterable<SportsChannel> channels) {
  for (final c in channels) {
    if (c.channelImage.isEmpty) continue;
    precacheImage(
      // Same key CachedNetworkImage(memCacheWidth: 480) looks up, and the
      // same disk store, so the logo is downloaded once for the whole app.
      ResizeImage.resizeIfNeeded(480, null, CachedNetworkImageProvider(c.channelImage, cacheManager: appImageCache)),
      context,
      onError: (_, __) {},
    );
  }
}
