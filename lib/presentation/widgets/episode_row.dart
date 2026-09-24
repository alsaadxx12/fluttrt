import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';
import 'package:youtube_downloader/core/network/image_cache.dart';

/// One episode as the row draws it: a number, a picture, and a note under
/// the number (the running time, the date - whatever the source knows).
class EpisodeTile {
  const EpisodeTile({required this.label, this.image, this.note});

  /// «الحلقة 5».
  final String label;

  /// The episode's own picture, or null when the source has none: the row
  /// then shows the show's picture, so no card is ever bare.
  final String? image;

  /// A short word under the number, or null.
  final String? note;
}

/// Every source's episodes in one row, the same on every page.
///
/// A series came from three catalogues with three lists: a grid of bare
/// numbers here, chips there, cards with pictures on the third. This is
/// the one row now: cards of a size, a picture on each, the number under
/// it, reading right to left from the first episode. The episode playing
/// is ringed in red, and the row opens on it.
class EpisodeRow extends StatefulWidget {
  const EpisodeRow({
    super.key,
    required this.tiles,
    required this.onTap,
    this.fallbackImage = '',
    this.currentIndex,
  });

  final List<EpisodeTile> tiles;

  /// The show's own picture, for an episode without one.
  final String fallbackImage;

  /// The episode playing, if one is; the row starts scrolled to it.
  final int? currentIndex;

  final ValueChanged<int> onTap;

  /// The card and its gap.
  static const double cardWidth = 150;
  static const double gap = 10;

  /// The card plus the list's bottom padding.
  static const double height = 160;

  @override
  State<EpisodeRow> createState() => _EpisodeRowState();
}

class _EpisodeRowState extends State<EpisodeRow> {
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    final at = widget.currentIndex ?? -1;
    _scroll = ScrollController(initialScrollOffset: at > 0 ? at * (EpisodeRow.cardWidth + EpisodeRow.gap) : 0);
  }

  @override
  void didUpdateWidget(EpisodeRow old) {
    super.didUpdateWidget(old);
    final at = widget.currentIndex;
    if (at != null && at != old.currentIndex && _scroll.hasClients) {
      _scroll.animateTo(
        (at * (EpisodeRow.cardWidth + EpisodeRow.gap)).clamp(0.0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return SizedBox(
      height: EpisodeRow.height,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: ListView.separated(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(bottom: 10),
          physics: const BouncingScrollPhysics(),
          itemCount: widget.tiles.length,
          separatorBuilder: (_, __) => const SizedBox(width: EpisodeRow.gap),
          itemBuilder: (context, i) => _Card(
            tile: widget.tiles[i],
            fallbackImage: widget.fallbackImage,
            current: i == widget.currentIndex,
            palette: p,
            dpr: dpr,
            onTap: () => widget.onTap(i),
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.tile,
    required this.fallbackImage,
    required this.current,
    required this.palette,
    required this.dpr,
    required this.onTap,
  });

  final EpisodeTile tile;
  final String fallbackImage;
  final bool current;
  final AppPalette palette;
  final double dpr;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final image = (tile.image != null && tile.image!.isNotEmpty) ? tile.image! : fallbackImage;
    // Glass: the picture fills the card, and the number sits on a frosted
    // strip across its foot - the picture blurred through it, under a
    // bright line where the light catches the edge. The one playing is
    // ringed in red and throws a red glow.
    return Semantics(
      button: true,
      selected: current,
      label: tile.label,
      child: Container(
        width: EpisodeRow.cardWidth,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: current
              ? [
                  BoxShadow(color: AppColors.primary.withOpacity(0.45), blurRadius: 16, spreadRadius: 1),
                  ...p.glassShadow,
                ]
              : p.glassShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAliasWithSaveLayer,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (image.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: image,
                  cacheManager: appImageCache,
                  fit: BoxFit.cover,
                  memCacheWidth: (EpisodeRow.cardWidth * dpr).round(),
                  fadeInDuration: Duration.zero,
                  placeholder: (_, __) => ColoredBox(color: p.isDark ? const Color(0xFF1B1B22) : p.skeleton),
                  errorWidget: (_, __, ___) => ColoredBox(color: p.isDark ? const Color(0xFF1B1B22) : p.skeleton),
                )
              else
                ColoredBox(color: p.isDark ? const Color(0xFF1B1B22) : p.skeleton),
              if (current) ColoredBox(color: AppColors.primary.withOpacity(0.30)),
              // The play mark, a little above the strip.
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                bottom: 30,
                child: Center(
                  child: Icon(
                    current ? Icons.play_circle_fill_rounded : Icons.play_circle_outline_rounded,
                    color: Colors.white,
                    size: 36,
                    shadows: const [Shadow(color: Colors.black54, blurRadius: 10)],
                  ),
                ),
              ),
              // The frosted strip.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withOpacity(p.isDark ? 0.22 : 0.70),
                            Colors.white.withOpacity(p.isDark ? 0.10 : 0.55),
                          ],
                        ),
                        border: Border(top: BorderSide(color: p.glassHighlight, width: 0.8)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              tile.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: p.isDark ? Colors.white : p.text,
                                shadows: p.isDark ? const [Shadow(color: Colors.black45, blurRadius: 4)] : null,
                              ),
                            ),
                          ),
                          if (tile.note != null && tile.note!.isNotEmpty)
                            Text(
                              tile.note!,
                              style: TextStyle(fontSize: 10, color: p.isDark ? Colors.white70 : p.textMuted),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // The edge of the pane, drawn last so it sits over everything.
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: current ? AppColors.primary : p.glassEdge,
                      width: current ? 2 : 0.8,
                    ),
                  ),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
