import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_palette.dart';
import '../../../../core/network/image_cache.dart';
import '../../../../presentation/widgets/card_motion.dart';
import '../../../../presentation/widgets/reveal.dart';
import '../../../shahid/data/shahid_models.dart';
import '../../../shahid/presentation/shahid_player_screen.dart';
import '../../../sports/data/services/alkass_service.dart';
import '../../../sports/presentation/providers/alkass_provider.dart';

/// Alkass's free channels on the home page: one page-black tile per channel
/// with its mark filling it, and a tap opens the channel full-screen at
/// once, the other channels a tap away over the picture.
class AlkassChannelsRow extends ConsumerWidget {
  const AlkassChannelsRow({super.key});

  static const double _tileW = 236;
  static const double _tileH = 140;
  static const double _gap = 12;

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
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E).withOpacity(0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'مجاني',
                  style: TextStyle(color: Color(0xFF22C55E), fontSize: 10, fontWeight: FontWeight.w800),
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

class _Tile extends StatelessWidget {
  const _Tile({required this.channel, required this.all});

  final AlkassChannel channel;
  final List<AlkassChannel> all;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: PressScale(
        onTap: () => openAlkassChannel(context, channel, all),
        child: SizedBox(
          width: AlkassChannelsRow._tileW,
          height: AlkassChannelsRow._tileH,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            clipBehavior: Clip.antiAliasWithSaveLayer,
            // The page's own black under the mark, and the mark as big as
            // the card allows: no edge, no name.
            child: ColoredBox(
              color: AppPalette.of(context).bg,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: channel.logo.isEmpty
                    ? const Icon(Icons.live_tv_rounded, color: Colors.white54, size: 40)
                    : CachedNetworkImage(
                        imageUrl: channel.logo,
                        cacheManager: appImageCache,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        memCacheWidth: 480,
                        fadeInDuration: Duration.zero,
                        fadeOutDuration: Duration.zero,
                        placeholderFadeInDuration: Duration.zero,
                        placeholder: (_, __) => const SizedBox.shrink(),
                        errorWidget: (_, __, ___) => const Icon(Icons.live_tv_rounded, color: Colors.white54, size: 40),
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
