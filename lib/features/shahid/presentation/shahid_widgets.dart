import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/shahid_models.dart';
import 'shahid_player_screen.dart';
import 'shahid_providers.dart';
import 'shahid_web_screen.dart';
import 'dart:io' show Platform;
import 'package:url_launcher/url_launcher.dart';
import 'screens/shahid_catalog_screen.dart';
import '../../../../core/constants/app_palette.dart';

void openShahidItem(BuildContext context, ShahidItem item) {
  if (Platform.isAndroid || Platform.isIOS) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => ShahidWebScreen(item: item)),
    );
  } else {
    final uri = Uri.tryParse(item.pageUrl);
    if (uri != null) {
      launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

/// "مجاني" for Shahid's free-with-ads titles, "VIP" for subscription ones.
class ShahidAccessBadge extends StatelessWidget {
  final bool isFree;

  const ShahidAccessBadge({super.key, required this.isFree});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isFree ? const Color(0xFF16A34A) : const Color(0xFFB8860B),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isFree ? 'مجاني' : 'VIP',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Section title matching the rest of the home page, with an optional
/// "عرض الكل" link.
class ShahidSectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onViewAll;

  const ShahidSectionHeader({super.key, required this.title, this.onViewAll});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              ),
            ),
          ),
          if (onViewAll != null)
            InkWell(
              onTap: onViewAll,
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'عرض الكل',
                      style: TextStyle(
                        color: Color(0xFFE50914),
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(width: 2),
                    Icon(Icons.chevron_left_rounded, size: 18, color: Color(0xFFE50914)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Horizontal filter pills (all / free / genres).
class ShahidFilterChips extends StatelessWidget {
  final List<String> filters;
  final String selected;
  final ValueChanged<String> onSelected;

  const ShahidFilterChips({
    super.key,
    required this.filters,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = AppPalette.of(context);
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final f = filters[i];
          final isOn = f == selected;
          return InkWell(
            onTap: () => onSelected(f),
            borderRadius: BorderRadius.circular(17),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isOn ? const Color(0xFFE50914) : palette.card,
                borderRadius: BorderRadius.circular(17),
                border: Border.all(
                  color: isOn
                      ? const Color(0xFFE50914)
                      : (isDark ? Colors.white.withOpacity(0.08) : palette.border),
                ),
              ),
              child: Text(
                f,
                style: TextStyle(
                  color: isOn ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF334155)),
                  fontSize: 12.5,
                  fontWeight: isOn ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A live channel: its whole logo on a dark tile. No name - the logo says it.
/// Opens the native player; [channels] feeds the player's channel switcher.
class ShahidChannelCard extends StatelessWidget {
  final ShahidItem channel;
  final List<ShahidItem> channels;
  final double width;

  const ShahidChannelCard({
    super.key,
    required this.channel,
    this.channels = const [],
    this.width = 150,
  });

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final logo = channel.logoUrl((width * dpr).round());
    final palette = AppPalette.of(context);
    return GestureDetector(
      onTap: () => Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => ShahidPlayerScreen(channel: channel, channels: channels),
        ),
      ),
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(14),
          // Light mode: a flat white tile on the white page, hairline border only.
          border: Border.all(color: palette.isDark ? Colors.white.withOpacity(0.08) : palette.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
                child: logo != null
                    ? CachedNetworkImage(
                        imageUrl: logo,
                        fit: BoxFit.contain,
                        fadeInDuration: const Duration(milliseconds: 120),
                        placeholder: (_, __) => const SizedBox.shrink(),
                        errorWidget: (_, __, ___) => const Icon(
                          Icons.live_tv_rounded,
                          color: Colors.white24,
                          size: 30,
                        ),
                      )
                    : const Icon(Icons.live_tv_rounded, color: Colors.white24, size: 30),
              ),
            ),
            PositionedDirectional(
              top: 6,
              start: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: const Color(0xFFE50914),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'LIVE',
                  style: TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A show/series/movie poster (2:3) with its title under it.
class ShahidPosterCard extends StatelessWidget {
  final ShahidItem item;
  final double? width;

  const ShahidPosterCard({super.key, required this.item, this.width});

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final palette = AppPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget cardContent(double actualWidth, double actualHeight) {
      final poster = item.posterUrl((actualWidth * dpr).round(), (actualHeight * dpr).round());
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: palette.isDark ? palette.card : palette.skeleton,
                borderRadius: BorderRadius.circular(14),
                border: palette.isDark ? null : Border.all(color: palette.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (poster != null)
                    CachedNetworkImage(
                      imageUrl: poster,
                      fit: BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 120),
                      placeholder: (_, __) => const SizedBox.shrink(),
                      errorWidget: (_, __, ___) =>
                          const Icon(Icons.movie_rounded, color: Colors.white24, size: 34),
                    )
                  else
                    const Icon(Icons.movie_rounded, color: Colors.white24, size: 34),
                  PositionedDirectional(
                    top: 7,
                    start: 7,
                    child: ShahidAccessBadge(isFree: item.isFree),
                  ),
                  if (item.episodeCount > 0)
                    PositionedDirectional(
                      bottom: 7,
                      start: 7,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${item.episodeCount} حلقة',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }

    if (width != null && width!.isFinite) {
      final w = width!;
      final h = w * 1.5;
      return GestureDetector(
        onTap: () => openShahidItem(context, item),
        child: SizedBox(
          width: w,
          height: h + 24,
          child: cardContent(w, h),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight - 24;
        return GestureDetector(
          onTap: () => openShahidItem(context, item),
          child: cardContent(w, h.clamp(50, 500)),
        );
      },
    );
  }
}

/// A dedicated home page row for Shahid free titles (e.g. Free Arabic Series),
/// with a title, a "شاهد مجاني" badge, and an optional "عرض الكل" button
/// leading to [ShahidCatalogScreen].
class ShahidHomeSection extends ConsumerWidget {
  final String rowId;
  final String title;
  final String? badge;

  const ShahidHomeSection({
    super.key,
    required this.rowId,
    required this.title,
    this.badge,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(shahidRowProvider(rowId));
    final p = AppPalette.of(context);

    return async.when(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF16A34A),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badge ?? 'شاهد مجاني',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: p.text,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute(
                        builder: (_) => ShahidCatalogScreen(
                          initialRowId: rowId,
                          initialTitle: title,
                        ),
                      ),
                    ),
                    borderRadius: BorderRadius.circular(8),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'عرض الكل',
                            style: TextStyle(
                              color: Color(0xFFE50914),
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(width: 2),
                          Icon(Icons.chevron_left_rounded, size: 18, color: Color(0xFFE50914)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 235,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) => ShahidPosterCard(
                  item: items[i],
                  width: 130,
                ),
              ),
            ),
          ],
        );
      },
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 18,
                  decoration: BoxDecoration(
                    color: p.skeleton,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 140,
                  height: 20,
                  decoration: BoxDecoration(
                    color: p.skeleton,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 235,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: 5,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, __) => Container(
                width: 130,
                height: 195,
                decoration: BoxDecoration(
                  color: p.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: p.border),
                ),
              ),
            ),
          ),
        ],
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

