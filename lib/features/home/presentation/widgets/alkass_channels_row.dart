import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_palette.dart';
import '../../../../core/network/image_cache.dart';
import '../../../../presentation/widgets/card_motion.dart';
import '../../../../presentation/widgets/reveal.dart';
import '../../../shahid/data/shahid_models.dart';
import '../../../shahid/presentation/shahid_player_screen.dart';
import '../../../sports/data/services/alkass_service.dart';
import '../../../sports/presentation/providers/alkass_provider.dart';
import '../../../subscription/presentation/providers/subscription_provider.dart';

/// Alkass's free channels on the home page: one glass tile per channel with
/// its mark across it, and a tap opens the channel full-screen at once.
class AlkassChannelsRow extends ConsumerWidget {
  const AlkassChannelsRow({super.key});

  static const double _tileW = 176;
  static const double _tileH = 104;
  static const double _gap = 12;

  /// The marks come as 1000x1000 pictures with the mark itself a strip
  /// across the middle, about half the width and a fifth of the height,
  /// the rest transparent. Shown whole in a card the mark is a thumbnail;
  /// so the picture is blown up until the mark alone is as wide as the
  /// card, and the transparent margins fall outside the clip.
  static const double _zoom = 1.6;

  /// How wide each mark is inside its 1000x1000 picture, as measured: the
  /// third is wider than the rest, so it is blown up less, and all four
  /// come out the same size on the page.
  static const Map<String, double> _markWidth = {'one': 0.52, 'two': 0.51, 'three': 0.64, 'four': 0.55};

  static double zoomFor(String webname) => _zoom * 0.52 / (_markWidth[webname] ?? 0.52);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channels = ref.watch(alkassChannelsProvider);
    return channels.when(
      data: (items) => items.isEmpty ? const SizedBox.shrink() : _section(context, items),
      loading: () => _section(context, const []),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _section(BuildContext context, List<AlkassChannel> items) {
    final p = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              // The same short brand bar every section's title hangs from.
              Container(
                width: 3.5,
                height: 18,
                margin: const EdgeInsetsDirectional.only(end: 9),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFFF4757), Color(0xFFE50914)],
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Text(
                'قنوات',
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark ? Colors.white : const Color(0xFF0F172A),
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: _tileH,
          child: items.isEmpty
              ? ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: 4,
                  separatorBuilder: (_, __) => const SizedBox(width: _gap),
                  itemBuilder: (_, __) => Container(
                    width: _tileW,
                    decoration: BoxDecoration(color: p.skeleton, borderRadius: BorderRadius.circular(6)),
                  ),
                )
              // The same entrance and the same focus as every other row.
              : WheelScroll(
                  builder: (controller) => ListView.separated(
                    key: const PageStorageKey('row-alkass'),
                    controller: controller,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(width: _gap),
                    itemBuilder: (context, i) => CardEntrance(
                      group: 'row-alkass',
                      index: i,
                      child: CarouselFocus(
                        controller: controller,
                        index: i,
                        extent: _tileW + _gap,
                        width: _tileW,
                        child: _Tile(channel: items[i], all: items),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _Tile extends ConsumerWidget {
  const _Tile({required this.channel, required this.all});

  final AlkassChannel channel;
  final List<AlkassChannel> all;

  /// Behind the sports subscription, like a match: a subscriber goes
  /// straight through, anyone else is taken to the activation page. What
  /// is remembered may be stale - a code entered a moment ago, a
  /// subscription that ran out overnight - so the server is asked once
  /// more before anyone is turned away.
  Future<void> _play(BuildContext context, WidgetRef ref) async {
    var unlocked = ref.read(isSportsUnlockedProvider);
    if (!unlocked) {
      await ref.read(sportsSubscriptionProvider.notifier).refresh();
      unlocked = ref.read(isSportsUnlockedProvider);
    }
    if (!context.mounted) return;
    if (!unlocked) {
      context.push('/sports-activation');
      return;
    }
    openAlkassChannel(context, channel, all);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RepaintBoundary(
      child: PressScale(
        onTap: () => _play(context, ref),
        child: SizedBox(
          width: AlkassChannelsRow._tileW,
          height: AlkassChannelsRow._tileH,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            clipBehavior: Clip.antiAliasWithSaveLayer,
            // Glass, like the match card: a deep blur under a white sheen
            // and a thin light edge, with the mark across it.
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Colors.white.withOpacity(0.16), Colors.white.withOpacity(0.05)],
                  ),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white.withOpacity(0.22), width: 0.8),
                ),
                child: channel.logo.isEmpty
                    ? const Icon(Icons.live_tv_rounded, color: Colors.white54, size: 40)
                    : ClipRect(
                        child: OverflowBox(
                          maxWidth: double.infinity,
                          maxHeight: double.infinity,
                          child: SizedBox(
                            width: AlkassChannelsRow._tileW * AlkassChannelsRow.zoomFor(channel.webname),
                            height: AlkassChannelsRow._tileW * AlkassChannelsRow.zoomFor(channel.webname),
                            child: CachedNetworkImage(
                              imageUrl: channel.logo,
                              cacheManager: appImageCache,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                              memCacheWidth: 800,
                              fadeInDuration: Duration.zero,
                              fadeOutDuration: Duration.zero,
                              placeholderFadeInDuration: Duration.zero,
                              placeholder: (_, __) => const SizedBox.shrink(),
                              errorWidget: (_, __, ___) =>
                                  const Icon(Icons.live_tv_rounded, color: Colors.white54, size: 40),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens [channel] straight into the full-screen picture, with [all] in a
/// strip over it to switch to: no channel page on the way.
void openAlkassChannel(BuildContext context, AlkassChannel channel, List<AlkassChannel> all) {
  final items = all.map(asShahidItem).toList();
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ShahidPlayerScreen(channel: asShahidItem(channel), channels: items, startFullscreen: true),
    ),
  );
}

/// The live player's own channel record for [c]. The page address is what
/// tells the player to ask Alkass for a fresh stream address on opening.
ShahidItem asShahidItem(AlkassChannel c) => ShahidItem(
      id: c.id,
      title: c.arabicTitle,
      productType: 'LIVESTREAM',
      pageUrl: c.pageUrl,
      logoTemplate: c.logo.isEmpty ? null : c.logo,
      isFree: true,
      streamUrl: c.streamUrl,
    );
