import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_palette.dart';
import '../../data/models/asia2tv_models.dart';
import '../providers/asia2tv_providers.dart';
import 'asia2tv_watch_screen.dart';
import 'package:youtube_downloader/presentation/widgets/house_notice.dart';
import 'package:youtube_downloader/presentation/widgets/title_profile.dart';
import 'package:youtube_downloader/presentation/widgets/episode_row.dart';
import 'package:youtube_downloader/features/trailers/data/tmdb_service.dart';

class Asia2TvDetailsScreen extends ConsumerStatefulWidget {
  final Asia2TvItem item;

  const Asia2TvDetailsScreen({super.key, required this.item});

  @override
  ConsumerState<Asia2TvDetailsScreen> createState() => _Asia2TvDetailsScreenState();
}

/// One TMDB client for every details page: its cache of stills is shared.
final TmdbService _tmdb = TmdbService();

class _Asia2TvDetailsScreenState extends ConsumerState<Asia2TvDetailsScreen> {
  /// A picture for each episode, from TMDB: the catalogue lists its
  /// episodes with no pictures of their own.
  Map<int, String> _stills = const {};
  String? _stillsFor;

  void _loadStills(Asia2TvItem drama) {
    if (_stillsFor == drama.url) return;
    _stillsFor = drama.url;
    _tmdb.episodeStills(drama.title, hint: drama.otherNames, year: drama.year).then((found) {
      if (mounted && found.isNotEmpty) setState(() => _stills = found);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final detailsAsync = ref.watch(asia2tvDetailsProvider(widget.item.url));

    return Scaffold(
      backgroundColor: palette.bg,
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
                      onPressed: () => ref.refresh(asia2tvDetailsProvider(widget.item.url)),
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                      child: const Text('إعادة المحاولة', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ),
            data: (details) {
              final drama = details.item;
              final episodes = details.episodes;
              final poster = drama.posterUrl.isNotEmpty ? drama.posterUrl : widget.item.posterUrl;
              if (!drama.isMovie && episodes.isNotEmpty) _loadStills(drama);

              return CustomScrollView(
                slivers: [
                  // Sliver AppBar with Poster Banner
                  ProfileHeader(
                    posterUrl: poster,
                    tooltip: drama.isMovie ? 'شاهد الآن' : 'مشاهدة المسلسل',
                    onPlay: () {
                      final first = episodes.isNotEmpty ? episodes.first : null;
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => Asia2TvWatchScreen(
                            item: drama,
                            stills: _stills,
                            initialWatchUrl: first?.url ?? drama.url,
                            title: first?.title ?? drama.title,
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
                          ProfileTitle(drama.title, subtitle: drama.otherNames),
                          const SizedBox(height: 12),
                          ProfileMeta(
                            year: drama.year,
                            kind: drama.isMovie ? 'فيلم' : 'مسلسل',
                            extras: [if (drama.country != null) drama.country!],
                          ),
                          const SizedBox(height: 14),
                          ProfileTags([
                            if (drama.genre != null) drama.genre!,
                            'خالٍ من الإعلانات',
                            '1080p تلقائي',
                          ]),
                          const SizedBox(height: 4),
                          ProfileStory(drama.story ?? ''),
                          const SizedBox(height: 24),
                          ProfileSectionTitle(
                            Icons.video_library_rounded,
                            drama.isMovie ? 'روابط المشاهدة' : 'حلقات العمل (${episodes.length})',
                          ),
                          const SizedBox(height: 12),
                          if (episodes.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: palette.cardAlt,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Text(
                                  'لا توجد حلقات معلنة حالياً',
                                  style: TextStyle(color: palette.textMuted, fontSize: 13),
                                ),
                              ),
                            )
                          else
                            // One row for every source: see EpisodeRow.
                            EpisodeRow(
                              tiles: [
                                for (final ep in episodes)
                                  EpisodeTile(
                                    label: drama.isMovie ? ep.title : 'الحلقة ${ep.number}',
                                    image: _stills[ep.number],
                                  ),
                              ],
                              fallbackImage: poster,
                              onTap: (i) {
                                final ep = episodes[i];
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => Asia2TvWatchScreen(
                                      item: drama,
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
