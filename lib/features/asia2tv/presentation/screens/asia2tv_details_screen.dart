import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_palette.dart';
import '../../data/models/asia2tv_models.dart';
import '../providers/asia2tv_providers.dart';
import 'asia2tv_watch_screen.dart';
import 'package:youtube_downloader/presentation/widgets/house_notice.dart';
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

  bool _storyExpanded = false;

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
                  SliverAppBar(
                    expandedHeight: 360,
                    pinned: true,
                    backgroundColor: palette.bg,
                    leading: Container(
                      margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    flexibleSpace: FlexibleSpaceBar(
                      background: Stack(
                        fit: StackFit.expand,
                        children: [
                          // Backdrop / Poster Image
                          if (poster.isNotEmpty)
                            CachedNetworkImage(
                              imageUrl: poster,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Container(color: const Color(0xFF0B101B)),
                            ),
                          // Gradient overlay
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withOpacity(0.4),
                                  Colors.black.withOpacity(0.7),
                                  palette.bg,
                                ],
                                stops: const [0.0, 0.6, 1.0],
                              ),
                            ),
                          ),
                          // Floating Watch Button on Header
                          Positioned(
                            bottom: 24,
                            right: 18,
                            left: 18,
                            child: Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      if (episodes.isNotEmpty) {
                                        final firstEp = episodes.first;
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => Asia2TvWatchScreen(
                                              item: drama,
                                              stills: _stills,
                                              initialWatchUrl: firstEp.url,
                                              title: firstEp.title,
                                              allEpisodes: episodes,
                                              currentEpisodeNumber: firstEp.number,
                                            ),
                                          ),
                                        );
                                      } else {
                                        // Movie direct watch
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => Asia2TvWatchScreen(
                                              item: drama,
                                              initialWatchUrl: drama.url,
                                              title: drama.title,
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                    icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                                    label: Text(
                                      episodes.isNotEmpty
                                          ? (drama.isMovie ? 'مشاهدة الفيلم الآن' : 'بدء مشاهدة الحلقة 1')
                                          : 'مشاهدة الآن (بدون إعلانات)',
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w900),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      elevation: 4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Content Details
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title
                          Text(
                            drama.title,
                            style: TextStyle(
                              color: palette.text,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              height: 1.3,
                            ),
                          ),

                          if (drama.otherNames != null && drama.otherNames!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              drama.otherNames!,
                              style: TextStyle(
                                color: palette.textMuted,
                                fontSize: 13,
                              ),
                            ),
                          ],

                          const SizedBox(height: 14),

                          // Metadata Tags Row (Country, Year, Category)
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (drama.country != null && drama.country!.isNotEmpty)
                                _buildMetaBadge(Icons.flag_rounded, drama.country!),
                              if (drama.year != null && drama.year!.isNotEmpty)
                                _buildMetaBadge(Icons.calendar_today_rounded, drama.year!),
                              if (drama.genre != null && drama.genre!.isNotEmpty)
                                _buildMetaBadge(Icons.movie_filter_rounded, drama.genre!),
                              _buildMetaBadge(Icons.security_rounded, 'خالٍ من الإعلانات',
                                  color: const Color(0xFF10B981)),
                              _buildMetaBadge(Icons.hd_rounded, '1080p تلقائي', color: AppColors.primary),
                            ],
                          ),

                          const SizedBox(height: 18),

                          // Story Synopsis
                          if (drama.story != null && drama.story!.isNotEmpty) ...[
                            Text(
                              'قصة العمل',
                              style: TextStyle(
                                color: palette.text,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            GestureDetector(
                              onTap: () => setState(() => _storyExpanded = !_storyExpanded),
                              child: Text(
                                drama.story!,
                                maxLines: _storyExpanded ? 100 : 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.text.withOpacity(0.78),
                                  fontSize: 13.5,
                                  height: 1.5,
                                ),
                              ),
                            ),
                            if (drama.story!.length > 120)
                              GestureDetector(
                                onTap: () => setState(() => _storyExpanded = !_storyExpanded),
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    _storyExpanded ? 'عرض أقل' : 'قراءة المزيد...',
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                          ],

                          const SizedBox(height: 24),
                          Divider(color: palette.divider, height: 1),
                          const SizedBox(height: 18),

                          // Episodes Section
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                drama.isMovie ? 'روابط المشاهدة' : 'قائمة الحلقات',
                                style: TextStyle(
                                  color: palette.text,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                drama.isMovie ? 'فيلم كامل' : '${episodes.length} حلقة متوفرة',
                                style: TextStyle(color: palette.textMuted, fontSize: 12.5),
                              ),
                            ],
                          ),

                          const SizedBox(height: 14),

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

  Widget _buildMetaBadge(IconData icon, String text, {Color? color}) {
    final p = AppPalette.of(context);
    final c = color ?? p.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (color ?? p.text).withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: (color ?? p.text).withOpacity(0.2), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: c, size: 13),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: c,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
