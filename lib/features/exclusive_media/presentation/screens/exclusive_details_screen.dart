import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../data/models/exclusive_media_models.dart';
import '../providers/exclusive_media_providers.dart';
import 'exclusive_player_screen.dart';

class ExclusiveDetailsScreen extends ConsumerStatefulWidget {
  final ExclusiveMediaItem item;

  const ExclusiveDetailsScreen({super.key, required this.item});

  @override
  ConsumerState<ExclusiveDetailsScreen> createState() => _ExclusiveDetailsScreenState();
}

class _ExclusiveDetailsScreenState extends ConsumerState<ExclusiveDetailsScreen> {
  bool _storyExpanded = false;

  @override
  Widget build(BuildContext context) {
    final detailsAsync = ref.watch(exclusiveDetailsProvider(widget.item.url));

    return Scaffold(
      backgroundColor: const Color(0xFF04060A),
      body: detailsAsync.when(
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
          final poster = media.posterUrl.isNotEmpty ? media.posterUrl : widget.item.posterUrl;

          return CustomScrollView(
            slivers: [
              // Sliver AppBar with Poster Banner
              SliverAppBar(
                expandedHeight: 360,
                pinned: true,
                backgroundColor: const Color(0xFF04060A),
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
                          errorWidget: (_, __, ___) => Container(color: const Color(0xFF04060A)),
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
                              const Color(0xFF04060A),
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
                                        builder: (_) => ExclusivePlayerScreen(
                                          item: media,
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
                                        builder: (_) => ExclusivePlayerScreen(
                                          item: media,
                                          initialWatchUrl: media.url,
                                          title: media.title,
                                        ),
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                                label: Text(
                                  episodes.isNotEmpty
                                      ? (media.isMovie ? 'مشاهدة الفيلم الآن' : 'بدء مشاهدة الحلقة 1')
                                      : 'مشاهدة الآن (بدون إعلانات)',
                                  style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w900),
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
                        media.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          height: 1.3,
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Metadata Tags Row (Country, Year, Category)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (media.country != null && media.country!.isNotEmpty)
                            _buildMetaBadge(Icons.flag_rounded, media.country!),
                          if (media.year != null && media.year!.isNotEmpty)
                            _buildMetaBadge(Icons.calendar_today_rounded, media.year!),
                          if (media.quality != null && media.quality!.isNotEmpty)
                            _buildMetaBadge(Icons.hd_rounded, media.quality!, color: AppColors.primary),
                          if (media.duration != null && media.duration!.isNotEmpty)
                            _buildMetaBadge(Icons.timer_outlined, media.duration!),
                          _buildMetaBadge(Icons.security_rounded, 'خالٍ من الإعلانات', color: const Color(0xFF10B981)),
                          if (media.rating != null && media.rating!.isNotEmpty)
                            _buildMetaBadge(Icons.star_rounded, media.rating!, color: const Color(0xFFFFB800)),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Story Section
                      if (media.story != null && media.story!.isNotEmpty) ...[
                        const Text(
                          'قصة العمل',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D121F),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withOpacity(0.06)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                media.story!,
                                maxLines: _storyExpanded ? 100 : 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.85),
                                  fontSize: 13.5,
                                  height: 1.6,
                                ),
                              ),
                              if (media.story!.length > 140) ...[
                                const SizedBox(height: 6),
                                GestureDetector(
                                  onTap: () => setState(() => _storyExpanded = !_storyExpanded),
                                  child: Text(
                                    _storyExpanded ? 'عرض أقل' : 'قراءة المزيد...',
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // Episodes Section (for series)
                      if (episodes.isNotEmpty) ...[
                        Row(
                          children: [
                            const Text(
                              'قائمة الحلقات',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${episodes.length} حلقة',
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Episodes Grid
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: 1.8,
                          ),
                          itemCount: episodes.length,
                          itemBuilder: (context, idx) {
                            final ep = episodes[idx];
                            return Material(
                              color: const Color(0xFF0D121F),
                              borderRadius: BorderRadius.circular(10),
                              child: InkWell(
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ExclusivePlayerScreen(
                                        item: media,
                                        initialWatchUrl: ep.url,
                                        title: ep.title,
                                        allEpisodes: episodes,
                                        currentEpisodeNumber: ep.number,
                                      ),
                                    ),
                                  );
                                },
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.play_circle_fill_rounded, color: AppColors.primary, size: 18),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'حلقة ${ep.number}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
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
    );
  }

  Widget _buildMetaBadge(IconData icon, String label, {Color? color}) {
    final badgeColor = color ?? Colors.white.withOpacity(0.7);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0D121F),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: (color ?? Colors.white).withOpacity(0.12), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: badgeColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(color: badgeColor, fontSize: 11.5, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
