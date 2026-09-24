import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../data/models/exclusive_media_models.dart';
import '../providers/exclusive_media_providers.dart';
import 'exclusive_player_screen.dart';
import 'package:youtube_downloader/presentation/widgets/house_notice.dart';
import 'package:youtube_downloader/presentation/widgets/title_profile.dart';
import '../../../../core/constants/app_palette.dart';
import 'package:youtube_downloader/presentation/widgets/episode_row.dart';
import 'package:youtube_downloader/features/trailers/data/tmdb_service.dart';

class ExclusiveDetailsScreen extends ConsumerStatefulWidget {
  final ExclusiveMediaItem item;

  const ExclusiveDetailsScreen({super.key, required this.item});

  @override
  ConsumerState<ExclusiveDetailsScreen> createState() => _ExclusiveDetailsScreenState();
}

final TmdbService _tmdb = TmdbService();

class _ExclusiveDetailsScreenState extends ConsumerState<ExclusiveDetailsScreen> {
  /// A picture for each episode, from TMDB, for an episode listed without one.
  Map<int, String> _stills = const {};
  String? _stillsFor;

  void _loadStills(ExclusiveMediaItem media) {
    if (_stillsFor == media.url) return;
    _stillsFor = media.url;
    _tmdb.episodeStills(media.title, year: media.year).then((found) {
      if (mounted && found.isNotEmpty) setState(() => _stills = found);
    });
  }

  @override
  Widget build(BuildContext context) {
    final detailsAsync = ref.watch(exclusiveDetailsProvider(widget.item.url));

    return Scaffold(
      backgroundColor: AppPalette.of(context).bg,
      // The popcorn notice sits over the page until the viewer sends it away.
      body: Stack(
        children: [
          detailsAsync.when(
            loading: () => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: AppColors.primary),
                  const SizedBox(height: 16),
                  Text(
                    'جاري تحميل تفاصيل العمل والحلقات...',
                    style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13),
                  ),
                ],
              ),
            ),
            error: (err, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
                    const SizedBox(height: 12),
                    const Text(
                      'تعذّر جلب تفاصيل العمل',
                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => ref.refresh(exclusiveDetailsProvider(widget.item.url)),
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                      child: const Text('إعادة المحاولة', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ),
            data: (details) {
              final media = details.item;
              final episodes = details.episodes;
              if (episodes.isNotEmpty) _loadStills(media);
              final poster = media.posterUrl.isNotEmpty ? media.posterUrl : widget.item.posterUrl;

              return CustomScrollView(
                slivers: [
                  // Sliver AppBar with Poster Banner
                  ProfileHeader(
                    posterUrl: poster,
                    tooltip: media.isMovie ? 'شاهد الآن' : 'مشاهدة المسلسل',
                    onPlay: () {
                      final first = episodes.isNotEmpty ? episodes.first : null;
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ExclusivePlayerScreen(
                            item: media,
                            stills: _stills,
                            initialWatchUrl: first?.url ?? media.url,
                            title: first?.title ?? media.title,
                            allEpisodes: first == null ? null : episodes,
                            currentEpisodeNumber: first?.number,
                          ),
                        ),
                      );
                    },
                  ),

                  // Content Details
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ProfileTitle(media.title),
                          const SizedBox(height: 12),
                          ProfileMeta(
                            rating: media.rating,
                            year: media.year,
                            kind: media.isMovie ? 'فيلم' : 'مسلسل',
                            extras: [
                              if (media.country != null) media.country!,
                              if (media.duration != null) media.duration!,
                              if (media.quality != null) media.quality!,
                            ],
                          ),
                          const SizedBox(height: 14),
                          ProfileTags([
                            ...?media.genres?.split(RegExp(r'[,،/]')).map((g) => g.trim()),
                            'خالٍ من الإعلانات',
                          ]),
                          const SizedBox(height: 4),
                          ProfileStory(media.story ?? ''),
                          const SizedBox(height: 24),

                          // Episodes Section (for series)
                          if (episodes.isNotEmpty) ...[
                            ProfileSectionTitle(Icons.video_library_rounded, 'حلقات العمل (${episodes.length})'),
                            const SizedBox(height: 12),

                            // One row for every source: see EpisodeRow.
                            EpisodeRow(
                              tiles: [
                                for (final ep in episodes)
                                  EpisodeTile(
                                    label: 'الحلقة ${ep.number}',
                                    image:
                                        (ep.thumbnailUrl?.isNotEmpty ?? false) ? ep.thumbnailUrl : _stills[ep.number],
                                    note: ep.date,
                                  ),
                              ],
                              fallbackImage: media.posterUrl,
                              onTap: (i) {
                                final ep = episodes[i];
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ExclusivePlayerScreen(
                                      item: media,
                                      stills: _stills,
                                      initialWatchUrl: ep.url,
                                      title: ep.title,
                                      allEpisodes: episodes,
                                      currentEpisodeNumber: ep.number,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const HouseNotice.snacks(),
        ],
      ),
    );
  }
}
