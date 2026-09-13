import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../../core/constants/app_palette.dart';
import '../../../core/tv/tv_mode.dart';
import '../../../presentation/widgets/reveal.dart';
import '../data/movie_trailer.dart';
import '../data/tmdb_service.dart';
import '../tmdb_config.dart';

/// Official trailers of films now in cinemas, from TMDB, played on YouTube's
/// own player. Wide cinematic cards that play in place.
final trailersProvider = FutureProvider<List<MovieTrailer>>((ref) async {
  return TmdbService().trending();
});

/// "مقاطع وإعلانات": the trailers row. Phone only.
///
/// A trailer wall suits a phone held close, not a television across the room
/// or a desktop window, so it renders on a phone and nowhere else.
class TrailersShowcase extends ConsumerStatefulWidget {
  const TrailersShowcase({super.key});

  @override
  ConsumerState<TrailersShowcase> createState() => _TrailersShowcaseState();
}

class _TrailersShowcaseState extends ConsumerState<TrailersShowcase> {
  YoutubePlayerController? _controller;
  int? _playingMovieId;

  /// A phone: not a television, not a desktop.
  bool get _isPhone => (Platform.isAndroid || Platform.isIOS);

  @override
  void dispose() {
    _controller?.close();
    super.dispose();
  }

  void _play(MovieTrailer t) {
    final id = t.youtubeId;
    if (id == null) return;
    if (_controller == null) {
      _controller = YoutubePlayerController.fromVideoId(
        videoId: id,
        autoPlay: true,
        params: const YoutubePlayerParams(
          showFullscreenButton: true,
          strictRelatedVideos: true,
          interfaceLanguage: 'ar',
          enableCaption: false,
        ),
      );
    } else {
      _controller!.loadVideoById(videoId: id);
    }
    setState(() => _playingMovieId = t.movieId);
  }

  void _stop() {
    _controller?.stopVideo();
    setState(() => _playingMovieId = null);
  }

  @override
  Widget build(BuildContext context) {
    // Phone only; hidden entirely on TV, desktop, and when TMDB is not set up.
    final isTv = ref.watch(tvModeProvider).valueOrNull ?? false;
    if (!_isPhone || isTv || !TmdbConfig.isConfigured) return const SizedBox.shrink();

    final async = ref.watch(trailersProvider);
    final p = AppPalette.of(context);
    return async.when(
      error: (_, __) => const SizedBox.shrink(),
      loading: () => _shell(p, child: _loadingRow(p)),
      data: (trailers) {
        if (trailers.isEmpty) return const SizedBox.shrink();
        return _shell(
          p,
          child: SizedBox(
            height: 210,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: trailers.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) => Reveal(
                index: i,
                step: const Duration(milliseconds: 45),
                maxDelay: const Duration(milliseconds: 320),
                offset: 12,
                child: _TrailerCard(
                  trailer: trailers[i],
                  isPlaying: trailers[i].movieId == _playingMovieId,
                  controller: _controller,
                  onPlay: () => _play(trailers[i]),
                  onStop: _stop,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _shell(AppPalette p, {required Widget child}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
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
                Text('مقاطع وإعلانات',
                    style: TextStyle(color: p.text, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
                const SizedBox(width: 8),
                Icon(Icons.theaters_rounded, size: 17, color: p.textFaint),
              ],
            ),
          ),
          child,
        ],
      );

  Widget _loadingRow(AppPalette p) => SizedBox(
        height: 210,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 3,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, __) => ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Shimmer(
              base: p.skeleton,
              highlight: p.isDark ? const Color(0xFF1E2636) : const Color(0xFFF4F7FC),
              child: const SizedBox(width: 300, height: 210),
            ),
          ),
        ),
      );
}

class _TrailerCard extends StatelessWidget {
  final MovieTrailer trailer;
  final bool isPlaying;
  final YoutubePlayerController? controller;
  final VoidCallback onPlay;
  final VoidCallback onStop;

  const _TrailerCard({
    required this.trailer,
    required this.isPlaying,
    required this.controller,
    required this.onPlay,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    const width = 300.0, imageH = 168.0;

    if (isPlaying && controller != null) {
      return SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                width: width,
                height: imageH,
                child: YoutubePlayer(controller: controller!, aspectRatio: 16 / 9),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(trailer.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.text, fontSize: 13, fontWeight: FontWeight.w800)),
                ),
                InkWell(
                  onTap: onStop,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.close_rounded, size: 18, color: p.textFaint)),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return PressScale(
      onTap: onPlay,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: width,
              height: imageH,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: p.border),
                boxShadow: p.cardShadow,
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: trailer.bestImage,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.high,
                    errorWidget: (_, __, ___) => ColoredBox(
                      color: p.skeleton,
                      child: Icon(Icons.theaters_rounded, color: p.textFaint, size: 40),
                    ),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xB3000000)],
                        stops: [0.45, 1.0],
                      ),
                    ),
                  ),
                  Center(
                    child: Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE50914).withOpacity(0.92),
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 14)],
                      ),
                      child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 34),
                    ),
                  ),
                  if (trailer.rating > 0)
                    PositionedDirectional(
                      top: 8,
                      start: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(8)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.star_rounded, color: Color(0xFFFFB800), size: 13),
                          const SizedBox(width: 3),
                          Text(trailer.rating.toStringAsFixed(1),
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                        ]),
                      ),
                    ),
                  PositionedDirectional(
                    start: 10,
                    end: 10,
                    bottom: 10,
                    child: Text(trailer.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (trailer.year != null)
                  Text(trailer.year!, style: TextStyle(color: p.textFaint, fontSize: 11.5, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Text('إعلان رسمي', style: TextStyle(color: p.textMuted, fontSize: 11.5, fontWeight: FontWeight.w700)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
