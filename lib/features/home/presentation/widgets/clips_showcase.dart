import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../../../core/constants/app_palette.dart';
import '../../../../presentation/widgets/reveal.dart';
import '../../../cinemana/data/models/cinemana_models.dart';
import '../../../cinemana/data/services/cinemana_service.dart';

/// A short clip that belongs to a title in the library.
class HomeClip {
  final String videoId;
  final String title;
  final String? poster;
  final String? year;

  const HomeClip({required this.videoId, required this.title, this.poster, this.year});

  /// YouTube's own still for the clip, used when the library has no artwork.
  String get thumbnail => 'https://img.youtube.com/vi/$videoId/hqdefault.jpg';
}

/// The id inside any of the shapes a YouTube link takes, or null when the
/// link is not a YouTube one at all.
String? youtubeIdOf(String? url) {
  final raw = (url ?? '').trim();
  if (raw.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.hasAuthority) return null;
  final host = uri.host.toLowerCase().replaceFirst('www.', '');
  String? id;
  if (host == 'youtu.be') {
    id = uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
  } else if (host.endsWith('youtube.com') || host.endsWith('youtube-nocookie.com')) {
    id = uri.queryParameters['v'];
    if (id == null && uri.pathSegments.length >= 2) {
      final first = uri.pathSegments.first;
      if (first == 'embed' || first == 'v' || first == 'shorts') id = uri.pathSegments[1];
    }
  }
  if (id == null) return null;
  // A YouTube id is exactly eleven characters of its own alphabet.
  return RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id) ? id : null;
}

/// The clips among a list of titles, newest first, without repeats.
List<HomeClip> clipsFrom(List<CinemanaItem> items, {int limit = 12}) {
  final out = <HomeClip>[];
  final seen = <String>{};
  for (final i in items) {
    final id = youtubeIdOf(i.trailerUrl);
    if (id == null || !seen.add(id)) continue;
    final title = i.arTitle.trim().isNotEmpty ? i.arTitle.trim() : i.enTitle.trim();
    if (title.isEmpty) continue;
    out.add(HomeClip(
      videoId: id,
      title: title,
      poster: i.backdropUrl ?? i.imgMediumUrl ?? i.imgUrl,
      year: i.year.trim().isEmpty ? null : i.year.trim(),
    ));
    if (out.length >= limit) break;
  }
  return out;
}

/// Clips for the home page: the newest titles that have one.
final homeClipsProvider = FutureProvider<List<HomeClip>>((ref) async {
  final service = CinemanaService();
  // Films and series both, so the row is not all one kind.
  final lists = await Future.wait([
    service.fetchLatestMoviesRelease(itemsPerPage: 30).catchError((_) => <CinemanaItem>[]),
    service.fetchLatestSeriesRelease(itemsPerPage: 20).catchError((_) => <CinemanaItem>[]),
  ]);
  return clipsFrom([...lists[0], ...lists[1]]);
});

/// "لقطات ومقاطع": wide clip cards that play where they sit.
///
/// One player serves the whole row. Tapping a second card moves that single
/// player to it rather than building another, so a row of twelve clips costs
/// one web view, not twelve.
class ClipsShowcase extends ConsumerStatefulWidget {
  const ClipsShowcase({super.key});

  @override
  ConsumerState<ClipsShowcase> createState() => _ClipsShowcaseState();
}

class _ClipsShowcaseState extends ConsumerState<ClipsShowcase> {
  YoutubePlayerController? _controller;
  String? _playingId;

  @override
  void dispose() {
    _controller?.close();
    super.dispose();
  }

  void _play(HomeClip clip) {
    final existing = _controller;
    if (existing == null) {
      _controller = YoutubePlayerController.fromVideoId(
        videoId: clip.videoId,
        autoPlay: true,
        params: const YoutubePlayerParams(
          showFullscreenButton: true,
          strictRelatedVideos: true,
          interfaceLanguage: 'ar',
          enableCaption: false,
        ),
      );
    } else {
      existing.loadVideoById(videoId: clip.videoId);
    }
    setState(() => _playingId = clip.videoId);
  }

  void _stop() {
    _controller?.stopVideo();
    setState(() => _playingId = null);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(homeClipsProvider);
    final p = AppPalette.of(context);

    return async.when(
      error: (_, __) => const SizedBox.shrink(),
      loading: () => _shell(p, child: _loadingRow(p)),
      data: (clips) {
        if (clips.isEmpty) return const SizedBox.shrink();
        return _shell(
          p,
          child: SizedBox(
            height: 178,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: clips.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) => Reveal(
                index: i,
                step: const Duration(milliseconds: 45),
                maxDelay: const Duration(milliseconds: 320),
                offset: 12,
                child: _ClipCard(
                  clip: clips[i],
                  isPlaying: clips[i].videoId == _playingId,
                  controller: _controller,
                  onPlay: () => _play(clips[i]),
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
                Text(
                  'لقطات ومقاطع',
                  style: TextStyle(color: p.text, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.3),
                ),
                const SizedBox(width: 8),
                Icon(Icons.movie_filter_rounded, size: 17, color: p.textFaint),
              ],
            ),
          ),
          child,
        ],
      );

  Widget _loadingRow(AppPalette p) => SizedBox(
        height: 178,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 3,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, __) => ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Shimmer(
              base: p.skeleton,
              highlight: p.isDark ? const Color(0xFF1E2636) : const Color(0xFFF4F7FC),
              child: const SizedBox(width: 260, height: 178),
            ),
          ),
        ),
      );
}

class _ClipCard extends StatelessWidget {
  final HomeClip clip;
  final bool isPlaying;
  final YoutubePlayerController? controller;
  final VoidCallback onPlay;
  final VoidCallback onStop;

  const _ClipCard({
    required this.clip,
    required this.isPlaying,
    required this.controller,
    required this.onPlay,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    const width = 260.0;

    if (isPlaying && controller != null) {
      return SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: width,
                height: width * 9 / 16,
                child: YoutubePlayer(controller: controller!, aspectRatio: 16 / 9),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    clip.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.text, fontSize: 12.5, fontWeight: FontWeight.w800),
                  ),
                ),
                InkWell(
                  onTap: onStop,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.close_rounded, size: 17, color: p.textFaint),
                  ),
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
              height: width * 9 / 16,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: p.border),
                boxShadow: p.cardShadow,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: clip.poster?.isNotEmpty == true ? clip.poster! : clip.thumbnail,
                      fit: BoxFit.cover,
                      fadeInDuration: Duration.zero,
                      imageBuilder: (_, provider) => RevealImage(
                        child: Image(image: provider, fit: BoxFit.cover, width: double.infinity, height: double.infinity),
                      ),
                      placeholder: (_, __) => Shimmer(
                        base: p.skeleton,
                        highlight: p.isDark ? const Color(0xFF1E2636) : const Color(0xFFF4F7FC),
                        child: const SizedBox.expand(),
                      ),
                      errorWidget: (_, __, ___) => CachedNetworkImage(imageUrl: clip.thumbnail, fit: BoxFit.cover),
                    ),
                    // Keeps the play badge readable on any still.
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0x66000000)],
                          stops: [0.55, 1.0],
                        ),
                      ),
                    ),
                    Center(
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE50914).withOpacity(0.92),
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 12)],
                        ),
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              clip.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.text, fontSize: 12.5, fontWeight: FontWeight.w800),
            ),
            if (clip.year != null)
              Text(clip.year!, style: TextStyle(color: p.textFaint, fontSize: 10.5, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
