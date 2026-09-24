import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';
import 'package:youtube_downloader/core/network/image_cache.dart';
import 'package:youtube_downloader/presentation/widgets/glass.dart';

/// The one profile every title gets, whichever catalogue it came from.
///
/// A series from Cinemana had the tidy page - the whole poster, the round
/// play button in a bite out of its foot, badges, tags, the story - while
/// the Asian, exclusive and Viu catalogues each drew their own. These are
/// that page's pieces, so every details screen is built from the same
/// ones: [ProfileHeader] on top, then [ProfileTitle], [ProfileMeta],
/// [ProfileTags], [ProfileStory], and a [ProfileSectionTitle] over the
/// episodes.

/// How far the artwork stops short of the bottom of its box.
///
/// The lower half of the play button stands in that gap, over the page's own
/// colour. The button cannot hang outside the box - the collapsing app bar
/// clips whatever its background draws - so the artwork gives up the room
/// instead.
const double kProfileEdgeInset = 36;

/// The collapsing poster at the head of a profile: the whole picture at
/// full width, a back button, [actions] at the end, and the round play
/// button sitting in the curve cut into the picture's foot.
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.posterUrl,
    required this.onPlay,
    required this.tooltip,
    this.busy = false,
    this.actions = const [],
  });

  final String posterUrl;
  final VoidCallback onPlay;
  final String tooltip;

  /// A stream is being resolved for a connected screen.
  final bool busy;

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final media = MediaQuery.of(context);
    // The whole portrait poster at full width (2:3), never cropped.
    final maxH = media.size.height * 0.68;
    final minH = maxH < 300.0 ? (maxH > 150.0 ? maxH * 0.8 : maxH) : 300.0;
    final target = media.size.width * 1.5;
    final expanded = minH >= maxH ? maxH : target.clamp(minH, maxH);

    return SliverAppBar(
      expandedHeight: expanded,
      pinned: true,
      backgroundColor: p.bg,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.6),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [...actions, if (actions.isNotEmpty) const SizedBox(width: 6)],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // The artwork, its bottom edge curved around the play button.
            ClipPath(
              clipper: const PosterNotchClipper(),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (posterUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: posterUrl,
                      cacheManager: appImageCache,
                      // contain: the full picture always shows, whatever its shape.
                      fit: BoxFit.contain,
                      alignment: Alignment.topCenter,
                      filterQuality: FilterQuality.high,
                      memCacheWidth: (media.size.width * media.devicePixelRatio).round(),
                      placeholder: (_, __) => ColoredBox(color: p.isDark ? Colors.black26 : p.skeleton),
                      errorWidget: (_, __, ___) => ColoredBox(color: p.isDark ? Colors.black26 : p.skeleton),
                    )
                  else
                    ColoredBox(color: p.isDark ? Colors.black26 : p.skeleton),
                  // A scrim at the very top only, so the buttons read over a
                  // bright poster.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0x73000000), Colors.transparent],
                        stops: [0, 0.28],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // The play button, its centre on the edge the curve is cut into:
            // half of it over the artwork, half over the page.
            Positioned(
              left: 0,
              right: 0,
              bottom: kProfileEdgeInset - RoundPlayButton.diameter / 2,
              child: Center(
                child: RoundPlayButton(onTap: onPlay, busy: busy, tooltip: tooltip),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A round button for the profile's top corner: a heart, a share, whatever
/// the page offers besides playing.
class ProfileAction extends StatelessWidget {
  const ProfileAction({super.key, required this.icon, required this.onTap, this.lit = false, this.tooltip});

  final IconData icon;
  final VoidCallback onTap;

  /// Filled red: a favourite that is one, say.
  final bool lit;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: lit ? Colors.red.withOpacity(0.9) : Colors.black.withOpacity(0.6),
          shape: BoxShape.circle,
          border: Border.all(color: lit ? Colors.redAccent : Colors.white24, width: 1),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
      onPressed: onTap,
    );
  }
}

/// The artwork's outline: a rectangle whose bottom edge dips smoothly around
/// the play button, so the button sits in a bite taken out of the picture.
///
/// The curve is Flutter's own [CircularNotchedRectangle] - the shape a
/// floating action button makes in a bottom bar. It notches the top edge,
/// so the path is flipped to put the bite at the foot.
class PosterNotchClipper extends CustomClipper<Path> {
  const PosterNotchClipper();

  /// The bite's radius: the button, plus a little air all round it.
  static const double notchRadius = RoundPlayButton.diameter / 2 + 9;

  @override
  Path getClip(Size size) {
    final w = size.width;
    final edge = size.height - kProfileEdgeInset;
    final notched = const CircularNotchedRectangle().getOuterPath(
      Rect.fromLTWH(0, 0, w, edge),
      Rect.fromCircle(center: Offset(w / 2, 0), radius: notchRadius),
    );
    // (x, y) -> (x, edge - y): the notch moves from the top edge to the foot.
    final flip = Matrix4.identity()
      ..translate(0.0, edge)
      ..scale(1.0, -1.0);
    return notched.transform(flip.storage);
  }

  @override
  bool shouldReclip(PosterNotchClipper oldClipper) => false;
}

/// The round play button that sits in the artwork's curve.
class RoundPlayButton extends StatelessWidget {
  const RoundPlayButton({super.key, required this.onTap, required this.tooltip, this.busy = false});

  final VoidCallback onTap;
  final String tooltip;

  /// A stream is being resolved for a connected screen.
  final bool busy;

  static const double diameter = 64;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.primary,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: diameter,
            height: diameter,
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                  )
                : const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 38),
          ),
        ),
      ),
    );
  }
}

/// The title, and under it the other name it goes by, if any.
class ProfileTitle extends StatelessWidget {
  const ProfileTitle(this.title, {super.key, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
              fontSize: 22, fontWeight: FontWeight.w900, color: p.isDark ? Colors.white : const Color(0xFF111115)),
        ),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(subtitle!, style: TextStyle(fontSize: 14, color: p.textMuted)),
        ],
      ],
    );
  }
}

/// The row of badges under the title: the rating in amber, the year, the
/// kind in red, and any [extras] after them (the version, the country).
class ProfileMeta extends StatelessWidget {
  const ProfileMeta({super.key, this.rating, this.year, this.kind, this.extras = const []});

  final String? rating;
  final String? year;
  final String? kind;
  final List<String> extras;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    Widget plain(String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: p.glassFill(),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: p.glassFillEdge(), width: 0.8),
          ),
          child: Text(
            text,
            style:
                TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.isDark ? Colors.white70 : Colors.black87),
          ),
        );
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (rating != null && rating!.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.18),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.amber.withOpacity(0.4), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star_rounded, size: 16, color: Colors.amber),
                const SizedBox(width: 4),
                Text(rating!, style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
          ),
        if (year != null && year!.isNotEmpty) plain(year!),
        if (kind != null && kind!.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(kind!,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
          ),
        for (final e in extras)
          if (e.isNotEmpty) plain(e),
      ],
    );
  }
}

/// The genre chips.
class ProfileTags extends StatelessWidget {
  const ProfileTags(this.tags, {super.key});

  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final shown = tags.where((t) => t.trim().isNotEmpty).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final tag in shown)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: p.glassFill(),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: p.glassFillEdge(), width: 0.8),
            ),
            child: Text(tag, style: TextStyle(fontSize: 11.5, color: p.isDark ? Colors.white70 : Colors.black87)),
          ),
      ],
    );
  }
}

/// «القصة والنبذة» and the story under it, folded after a few lines with a
/// word to unfold it.
class ProfileStory extends StatefulWidget {
  const ProfileStory(this.text, {super.key, this.heading = 'القصة والنبذة'});

  final String text;
  final String heading;

  @override
  State<ProfileStory> createState() => _ProfileStoryState();
}

class _ProfileStoryState extends State<ProfileStory> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final text = widget.text.trim().isEmpty ? 'لا يوجد وصف متاح لهذا المحتوى.' : widget.text.trim();
    final long = text.length > 220;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.heading,
          style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.bold, color: p.isDark ? Colors.white : const Color(0xFF0F172A)),
        ),
        const SizedBox(height: 8),
        // The story on its own pane of glass.
        GlassPanel(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: long ? () => setState(() => _open = !_open) : null,
                child: Text(
                  text,
                  maxLines: _open || !long ? null : 5,
                  overflow: _open || !long ? null : TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    color: p.isDark ? const Color(0xFFD0D0D8) : const Color(0xFF475569),
                  ),
                ),
              ),
              if (long)
                GestureDetector(
                  onTap: () => setState(() => _open = !_open),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _open ? 'عرض أقل' : 'قراءة المزيد...',
                      style: const TextStyle(color: AppColors.primary, fontSize: 12.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A red icon and a bold title over a section: the episodes, the suggestions.
class ProfileSectionTitle extends StatelessWidget {
  const ProfileSectionTitle(this.icon, this.text, {super.key, this.trailing});

  final IconData icon;
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: p.isDark ? Colors.white : const Color(0xFF0F172A)),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
