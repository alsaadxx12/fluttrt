import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../home/presentation/widgets/clips_showcase.dart' show youtubeIdOf;
import '../data/tmdb_service.dart';
import '../data/trailer_stream_resolver.dart';
import '../tmdb_config.dart';
import 'inline_trailer_player.dart';

/// What to look a trailer up by for one title.
class TrailerQuery {
  final String title;
  final String? year;
  final String? trailerUrl;
  const TrailerQuery({required this.title, this.year, this.trailerUrl});

  @override
  bool operator ==(Object other) =>
      other is TrailerQuery && other.title == title && other.year == year && other.trailerUrl == trailerUrl;

  @override
  int get hashCode => Object.hash(title, year, trailerUrl);
}

/// The YouTube id for a title's trailer: its own trailer link when that is a
/// YouTube one, otherwise TMDB's trailer found by searching the title. Null
/// when neither yields one.
final detailTrailerProvider = FutureProvider.autoDispose.family<String?, TrailerQuery>((ref, q) async {
  final own = youtubeIdOf(q.trailerUrl);
  if (own != null) return own;
  if (!TmdbConfig.isConfigured) return null;
  final id = await TmdbService().trailerForTitle(q.title, year: q.year);
  if (id != null) {
    // Warm the stream so tapping plays at once.
    TrailerStreamResolver.instance.prewarm([id]);
  }
  return id;
});

/// "الإعلان الرسمي": a title's trailer on its detail page. Tap to play in place.
///
/// Phone only (the player uses the platform video pipeline, matching the
/// trailers row's phone-only stance). Shows nothing until a trailer is found,
/// so a title without one simply has no trailer section.
class DetailTrailer extends ConsumerStatefulWidget {
  final String title;
  final String? year;
  final String? trailerUrl;
  final String? posterUrl;
  const DetailTrailer({
    super.key,
    required this.title,
    this.year,
    this.trailerUrl,
    this.posterUrl,
  });

  @override
  ConsumerState<DetailTrailer> createState() => _DetailTrailerState();
}

class _DetailTrailerState extends ConsumerState<DetailTrailer> {
  bool _playing = false;

  bool get _isPhone => Platform.isAndroid || Platform.isIOS;

  @override
  Widget build(BuildContext context) {
    if (!_isPhone) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final async = ref.watch(detailTrailerProvider(
      TrailerQuery(title: widget.title, year: widget.year, trailerUrl: widget.trailerUrl),
    ));
    final id = async.valueOrNull;
    if (async.isLoading || id == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Row(
          children: [
            const Icon(Icons.theaters_rounded, color: Color(0xFFE50914), size: 20),
            const SizedBox(width: 8),
            Text(
              'الإعلان الرسمي',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: _playing
                ? InlineTrailerPlayer(key: ValueKey(id), videoId: id)
                : _poster(context, isDark),
          ),
        ),
      ],
    );
  }

  Widget _poster(BuildContext context, bool isDark) {
    final base = isDark ? const Color(0xFF14141A) : const Color(0xFFEBEBF0);
    return GestureDetector(
      onTap: () => setState(() => _playing = true),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if ((widget.posterUrl ?? '').isNotEmpty)
            CachedNetworkImage(
              imageUrl: widget.posterUrl!,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
              placeholder: (_, __) => ColoredBox(color: base),
              errorWidget: (_, __, ___) => ColoredBox(color: base),
            )
          else
            ColoredBox(color: base),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x22000000), Color(0x88000000)],
              ),
            ),
          ),
          const Positioned(
            left: 12,
            bottom: 12,
            child: Row(
              children: [
                Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 26),
                SizedBox(width: 8),
                Text('شغّل الإعلان',
                    style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
