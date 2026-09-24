import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/core/network/image_cache.dart';

import '../data/qitv_models.dart';
import 'qitv_open.dart';
import 'qitv_providers.dart';
import '../../../core/constants/app_palette.dart';
import '../../../presentation/widgets/card_motion.dart';
import '../../../presentation/widgets/reveal.dart';

// ─── Poster card (2:3) for showcase items ────────────────────────────────────

class QiTvPosterCard extends StatelessWidget {
  final QiShowcase item;
  final double width;

  const QiTvPosterCard({super.key, required this.item, this.width = 104});

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final poster = item.posterUrl;
    return PressScale(
      onTap: () => openQiTitle(
        context,
        title: item.title,
        kind: item.isMovie ? 'فيلم' : 'مسلسل',
        poster: poster,
      ),
      child: SizedBox(
        width: width,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          clipBehavior: Clip.antiAlias,
          child: AspectRatio(
            aspectRatio: 2 / 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: AppPalette.of(context).bg),
                if (poster != null)
                  CachedNetworkImage(
                    imageUrl: poster,
                    cacheManager: appImageCache,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.high,
                    memCacheWidth: (width * dpr).round(),
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                    placeholderFadeInDuration: Duration.zero,
                    useOldImageOnUrlChange: true,
                    placeholder: (_, __) => const SizedBox.shrink(),
                    errorWidget: (_, __, ___) => const Icon(Icons.movie_rounded, color: Colors.white24),
                  ),
                // Type badge
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: item.isMovie ? const Color(0xFFE50914) : const Color(0xFF1DB954),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      item.isMovie ? 'فيلم' : 'مسلسل',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Circular logo for a channel ─────────────────────────────────────────────

class QiChannelCard extends StatelessWidget {
  final QiChannel channel;
  final double size;
  final VoidCallback? onTap;

  const QiChannelCard({super.key, required this.channel, this.size = 64, this.onTap});

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PressScale(
      onTap: onTap ?? () {},
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? const Color(0xFF1A1A2E) : const Color(0xFFF1F5F9),
                  border: Border.all(
                    color: channel.hasDrm ? Colors.amber.withOpacity(0.4) : const Color(0xFF1DB954).withOpacity(0.4),
                    width: 1.5,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: channel.logoUrl != null
                    ? CachedNetworkImage(
                        imageUrl: channel.logoUrl!,
                        cacheManager: appImageCache,
                        fit: BoxFit.contain,
                        memCacheWidth: (size * dpr).round(),
                        fadeInDuration: Duration.zero,
                        placeholder: (_, __) => const SizedBox.shrink(),
                        errorWidget: (_, __, ___) =>
                            Icon(Icons.tv_rounded, color: isDark ? Colors.white24 : Colors.black26, size: 28),
                      )
                    : Icon(Icons.tv_rounded, color: isDark ? Colors.white24 : Colors.black26, size: 28),
              ),
              // Encrypted: plays only in Qi TV's own app, and says so.
              if (!channel.playable)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.amber.withOpacity(0.6), width: 1),
                    ),
                    child: Icon(Icons.lock_rounded, size: 10, color: Colors.amber.shade600),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: size + 8,
            child: Text(
              channel.title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isDark ? Colors.white70 : const Color(0xFF334155),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Wide card for exclusive works ───────────────────────────────────────────

class QiExclusiveCard extends StatelessWidget {
  final QiExclusiveWork work;
  final double width;

  const QiExclusiveCard({super.key, required this.work, this.width = 220});

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return PressScale(
      onTap: () => openQiTitle(
        context,
        title: work.title,
        kind: 'مسلسل',
        poster: work.posterUrl,
        description: work.description,
      ),
      child: SizedBox(
        width: width,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: AppPalette.of(context).bg),
                if (work.posterUrl != null)
                  CachedNetworkImage(
                    imageUrl: work.posterUrl!,
                    cacheManager: appImageCache,
                    fit: BoxFit.cover,
                    memCacheWidth: (width * dpr).round(),
                    fadeInDuration: Duration.zero,
                    placeholder: (_, __) => const SizedBox.shrink(),
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
                // Gradient overlay
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                        stops: [0.4, 1.0],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 8,
                  left: 8,
                  right: 8,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE50914),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Text(
                          'حصري',
                          style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        work.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (work.description.isNotEmpty)
                        Text(
                          work.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── The combined Qi TV home section ─────────────────────────────────────────

/// Shows Qi TV's exclusive Iraqi works, showcase content, and live channels
/// in one branded block on the home page. Hides itself when everything fails.
class QiTvHomeSection extends ConsumerWidget {
  const QiTvHomeSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showcaseAsync = ref.watch(qiTvShowcaseProvider);
    final exclusiveAsync = ref.watch(qiTvExclusiveProvider);
    final channelsAsync = ref.watch(qiTvChannelsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final showcase = showcaseAsync.valueOrNull ?? const <QiShowcase>[];
    final exclusives = exclusiveAsync.valueOrNull ?? const <QiExclusiveWork>[];
    final channels = sortPlayableFirst(channelsAsync.valueOrNull ?? const <QiChannel>[]);

    final isLoading = showcaseAsync.isLoading || exclusiveAsync.isLoading || channelsAsync.isLoading;
    if (!isLoading && showcase.isEmpty && exclusives.isEmpty && channels.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE50914), Color(0xFFB71C1C)],
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Qi TV',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'المحتوى العراقي',
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ── Exclusive Works (Iraqi Originals) ──
        if (exclusives.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(right: 16, left: 16, bottom: 8),
            child: Text(
              'أعمال عراقية حصرية',
              style: TextStyle(
                color: isDark ? Colors.white70 : const Color(0xFF475569),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(
            height: 140,
            child: WheelScroll(
              builder: (controller) => ListView.separated(
                key: const PageStorageKey('qitv-exclusives'),
                controller: controller,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                cacheExtent: 900,
                itemCount: exclusives.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) => CardEntrance(
                  group: 'qitv-exclusives',
                  index: i,
                  child: CarouselFocus(
                    controller: controller,
                    index: i,
                    extent: 232,
                    width: 220,
                    child: QiExclusiveCard(work: exclusives[i]),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
        ],

        // ── Showcase (Top 10) ──
        if (showcase.isNotEmpty || isLoading) ...[
          Padding(
            padding: const EdgeInsets.only(right: 16, left: 16, bottom: 8),
            child: Text(
              'الأكثر مشاهدة',
              style: TextStyle(
                color: isDark ? Colors.white70 : const Color(0xFF475569),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(
            height: 156,
            child: WheelScroll(
              builder: (controller) => ListView.separated(
                key: const PageStorageKey('qitv-showcase'),
                controller: controller,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                cacheExtent: 900,
                physics: showcase.isEmpty ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics(),
                itemCount: showcase.isEmpty ? 4 : showcase.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) => showcase.isEmpty
                    ? Container(
                        width: 104,
                        decoration: BoxDecoration(
                          color: AppPalette.of(context).skeleton,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      )
                    : CardEntrance(
                        group: 'qitv-showcase',
                        index: i,
                        child: CarouselFocus(
                          controller: controller,
                          index: i,
                          extent: 116,
                          width: 104,
                          child: QiTvPosterCard(item: showcase[i]),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 18),
        ],

        // ── Live Channels ──
        if (channels.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(right: 16, left: 16, bottom: 8),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE50914),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'القنوات المباشرة',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : const Color(0xFF475569),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${channels.length} قناة',
                  style: TextStyle(
                    color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 96,
            child: WheelScroll(
              builder: (controller) => ListView.separated(
                key: const PageStorageKey('qitv-channels'),
                controller: controller,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                cacheExtent: 900,
                itemCount: channels.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (_, i) => CardEntrance(
                  group: 'qitv-channels',
                  index: i,
                  child: QiChannelCard(
                    channel: channels[i],
                    onTap: () => openQiChannel(context, channels[i], channels),
                  ),
                ),
              ),
            ),
          ),
        ],

        const SizedBox(height: 24),
      ],
    );
  }
}
