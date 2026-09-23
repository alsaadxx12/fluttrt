import 'dart:async';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';
import 'package:youtube_downloader/core/network/image_cache.dart';
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';
import 'package:youtube_downloader/features/cinemana/presentation/providers/cinemana_provider.dart';
import 'package:youtube_downloader/features/cinemana/presentation/screens/cinemana_detail_screen.dart';

/// A floating side-sliding card on the HomeScreen showcasing the latest
/// cinema movies and TV series with smooth horizontal swiping (يمين ويسار).
class FloatingCinemaShowcase extends ConsumerStatefulWidget {
  const FloatingCinemaShowcase({super.key});

  @override
  ConsumerState<FloatingCinemaShowcase> createState() => _FloatingCinemaShowcaseState();
}

class _FloatingCinemaShowcaseState extends ConsumerState<FloatingCinemaShowcase>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;
  late final PageController _pageController;

  int _currentPage = 0;
  bool _isDismissed = false;
  bool _isCardVisible = false;
  // 0: الكل (All), 1: أفلام (Movies), 2: مسلسلات (Series)
  int _selectedFilter = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.94);

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    // Smooth entrance from the right/side with spring curve
    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.15, 0.0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );

    // Trigger entrance animation with a pleasant delay on app start
    Timer(const Duration(milliseconds: 900), () {
      if (mounted && !_isDismissed) {
        setState(() => _isCardVisible = true);
        _animController.forward();
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _dismissCard() {
    _animController.reverse().then((_) {
      if (mounted) {
        setState(() {
          _isDismissed = true;
          _isCardVisible = false;
        });
      }
    });
  }

  void _reopenCard() {
    setState(() {
      _isDismissed = false;
      _isCardVisible = true;
    });
    _animController.forward();
  }

  void _openDetail(CinemanaItem item) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => CinemanaDetailScreen(item: item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch latest movies, series, and recently added
    final latestMovies = ref.watch(homeLatestMoviesProvider).valueOrNull ?? [];
    final latestSeries = ref.watch(homeLatestSeriesProvider).valueOrNull ?? [];
    final recentlyAdded = ref.watch(homeRecentlyAddedProvider).valueOrNull ?? [];

    // Combine and curate a distinct list
    final Map<String, CinemanaItem> distinctItems = {};
    for (final item in [...latestMovies, ...latestSeries, ...recentlyAdded]) {
      if (item.id.isNotEmpty && (item.imgMediumUrl != null || item.imgUrl != null)) {
        distinctItems[item.id] = item;
      }
    }

    final allItems = distinctItems.values.toList();
    if (allItems.isEmpty) {
      return const SizedBox.shrink();
    }

    // Filter by user selection
    final filteredItems = allItems.where((it) {
      if (_selectedFilter == 1) return !it.isSeries; // Movies
      if (_selectedFilter == 2) return it.isSeries; // Series
      return true; // All
    }).take(15).toList();

    if (filteredItems.isEmpty) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // If completely dismissed, show a sleek floating reopen badge at the screen edge
    if (_isDismissed) {
      return PositionedDirectional(
        end: 12,
        bottom: 24,
        child: _buildReopenFloatingPill(isDark, filteredItems.length),
      );
    }

    if (!_isCardVisible) {
      return const SizedBox.shrink();
    }

    return PositionedDirectional(
      start: 12,
      end: 12,
      bottom: 20,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: _buildMainFloatingCard(context, filteredItems, isDark),
        ),
      ),
    );
  }

  // ==========================================
  // 🌟 Main Floating Card Container
  // ==========================================
  Widget _buildMainFloatingCard(
    BuildContext context,
    List<CinemanaItem> items,
    bool isDark,
  ) {
    final clampedIndex = _currentPage.clamp(0, items.length - 1);

    return Container(
      constraints: const BoxConstraints(maxHeight: 280),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF13131A).withOpacity(0.94)
            : Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFFFF2A4A).withOpacity(isDark ? 0.35 : 0.25),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF2A4A).withOpacity(0.18),
            blurRadius: 20,
            spreadRadius: 1,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.5 : 0.12),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Header Bar
              _buildCardHeader(isDark, items.length, clampedIndex),

              // Filter Chips: [الكل] [🎬 أفلام] [📺 مسلسلات]
              _buildFilterBar(isDark),

              // Horizontal Swipeable Cards View (يمين ويسار)
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  physics: const BouncingScrollPhysics(),
                  itemCount: items.length,
                  onPageChanged: (idx) {
                    setState(() => _currentPage = idx);
                  },
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _buildShowcaseItem(item, isDark);
                  },
                ),
              ),

              // Bottom Navigation & Page Indicators
              _buildBottomControls(items.length, clampedIndex, isDark),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // Header with Title & Dismiss Button
  // ==========================================
  Widget _buildCardHeader(bool isDark, int totalCount, int currentIndex) {
    return Container(
      padding: const EdgeInsets.only(top: 10, left: 14, right: 14, bottom: 4),
      child: Row(
        children: [
          // Animated Live Flare Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF2A4A), Color(0xFFFF758C)],
              ),
              borderRadius: BorderRadius.circular(7),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF2A4A).withOpacity(0.4),
                  blurRadius: 6,
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome_rounded, size: 12, color: Colors.white),
                SizedBox(width: 4),
                Text(
                  'جديد وحصري',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'أحدث الأفلام والمسلسلات',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
          ),
          // Swipe tip
          Text(
            'اسحب يمين ويسار ⇄',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white38 : Colors.black45,
            ),
          ),
          const SizedBox(width: 6),
          // Dismiss Button (X)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _dismissCard,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.08) : Colors.white,
                  shape: BoxShape.circle,
                  border: isDark ? null : Border.all(color: const Color(0xFFE8ECF2)),
                ),
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // Filter Tabs (الكل • أفلام • مسلسلات)
  // ==========================================
  Widget _buildFilterBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          _buildFilterChip(title: 'الكل ✨', index: 0, isDark: isDark),
          const SizedBox(width: 6),
          _buildFilterChip(title: '🎬 أفلام', index: 1, isDark: isDark),
          const SizedBox(width: 6),
          _buildFilterChip(title: '📺 مسلسلات', index: 2, isDark: isDark),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String title,
    required int index,
    required bool isDark,
  }) {
    final isSelected = _selectedFilter == index;
    return InkWell(
      onTap: () {
        if (_selectedFilter != index) {
          setState(() {
            _selectedFilter = index;
            _currentPage = 0;
          });
          if (_pageController.hasClients) {
            _pageController.jumpToPage(0);
          }
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFF2A4A)
              : (isDark ? const Color(0xFF22222E) : Colors.white),
          borderRadius: BorderRadius.circular(8),
          border: isSelected || isDark ? null : Border.all(color: const Color(0xFFE8ECF2)),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected
                ? Colors.white
                : (isDark ? const Color(0xFFA0A0AB) : const Color(0xFF64748B)),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // Individual Movie/Series Showcase Item Card
  // ==========================================
  Widget _buildShowcaseItem(CinemanaItem item, bool isDark) {
    final posterUrl = item.bestPosterUrl.isNotEmpty ? item.bestPosterUrl : item.cardImageUrl;
    final rating = double.tryParse(item.stars) ?? 0.0;
    final categories = item.categories.take(2).join(' • ');
    final dpr = MediaQuery.of(context).devicePixelRatio;

    return InkWell(
      onTap: () => _openDetail(item),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1B1B24) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? const Color(0xFF282836) : const Color(0xFFE8ECF2),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Poster with Overlays
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: posterUrl,
                    cacheManager: appImageCache,
                    width: 90,
                    height: double.infinity,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.high,
                    // The poster is 90 lp wide; decode at its own pixel width.
                    memCacheWidth: (90 * dpr).round(),
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                    placeholderFadeInDuration: Duration.zero,
                    useOldImageOnUrlChange: true,
                    placeholder: (ctx, __) => ColoredBox(color: AppPalette.of(ctx).skeleton),
                    errorWidget: (_, __, ___) => Container(
                      width: 90,
                      color: isDark ? const Color(0xFF2A2A38) : const Color(0xFFF1F3F6),
                      child: const Icon(Icons.movie_rounded, color: Colors.white38, size: 28),
                    ),
                  ),
                ),
                // Type Badge (Movie / Series)
                Positioned(
                  top: 5,
                  right: 5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: item.isSeries
                          ? const Color(0xFF3B82F6).withOpacity(0.92)
                          : const Color(0xFFFF2A4A).withOpacity(0.92),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      item.isSeries ? 'مسلسل' : 'فيلم',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                // Quality tag
                Positioned(
                  bottom: 5,
                  left: 5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '4K UHD',
                      style: TextStyle(
                        color: Color(0xFFFBBF24),
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),

            // Information & Play Action
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Rating & Year Row
                  Row(
                    children: [
                      if (rating > 0) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withOpacity(0.18),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded, size: 12, color: Color(0xFFF59E0B)),
                              const SizedBox(width: 2.5),
                              Text(
                                rating.toStringAsFixed(1),
                                style: const TextStyle(
                                  color: Color(0xFFF59E0B),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (item.year.isNotEmpty)
                        Text(
                          item.year,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                      const Spacer(),
                      if (categories.isNotEmpty)
                        Flexible(
                          child: Text(
                            categories,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 9.5,
                              color: isDark ? const Color(0xFFA0A0AB) : const Color(0xFF64748B),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),

                  // Title (Arabic & English)
                  Text(
                    item.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  if (item.enTitle.isNotEmpty && item.enTitle != item.arTitle) ...[
                    Text(
                      item.enTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.5,
                        color: isDark ? Colors.white38 : Colors.black45,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),

                  // Story synopsis preview
                  Text(
                    item.arContent.isNotEmpty
                        ? item.arContent.replaceAll('\n', ' ').trim()
                        : 'شاهد الآن بأعلى جودة مع الترجمة العربية وسيرفرات تشغيل سريعة.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.25,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(height: 7),

                  // Watch Button
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: InkWell(
                      onTap: () => _openDetail(item),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF2A4A), Color(0xFFFF5252)],
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFF2A4A).withOpacity(0.35),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_arrow_rounded, size: 15, color: Colors.white),
                            SizedBox(width: 4),
                            Text(
                              'مشاهدة الآن',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // Bottom Controls (Chevrons & Page Dots)
  // ==========================================
  Widget _buildBottomControls(int total, int currentIndex, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 14, right: 14, bottom: 8, top: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Previous button
          InkWell(
            onTap: currentIndex > 0
                ? () {
                    _pageController.previousPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  }
                : null,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.06) : Colors.white,
                shape: BoxShape.circle,
                border: isDark ? null : Border.all(color: const Color(0xFFE8ECF2)),
              ),
              child: Icon(
                Icons.chevron_right_rounded, // In RTL, right means previous
                size: 16,
                color: currentIndex > 0
                    ? (isDark ? Colors.white70 : Colors.black87)
                    : (isDark ? Colors.white24 : Colors.black26),
              ),
            ),
          ),

          // Dots Indicator
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(
              total.clamp(0, 8),
              (index) {
                final isCurrent = index == (currentIndex % 8);
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 2.5),
                  width: isCurrent ? 14 : 5,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? const Color(0xFFFF2A4A)
                        : (isDark ? Colors.white24 : Colors.black26),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              },
            ),
          ),

          // Next button
          InkWell(
            onTap: currentIndex < total - 1
                ? () {
                    _pageController.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  }
                : null,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.06) : Colors.white,
                shape: BoxShape.circle,
                border: isDark ? null : Border.all(color: const Color(0xFFE8ECF2)),
              ),
              child: Icon(
                Icons.chevron_left_rounded, // In RTL, left means next
                size: 16,
                color: currentIndex < total - 1
                    ? (isDark ? Colors.white70 : Colors.black87)
                    : (isDark ? Colors.white24 : Colors.black26),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // Sleek Re-open Pill (Appears when user closes card)
  // ==========================================
  Widget _buildReopenFloatingPill(bool isDark, int count) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _reopenCard,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF281318), Color(0xFF18141F)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFFFF2A4A).withOpacity(0.5),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF2A4A).withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFFFF2A4A),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.movie_filter_rounded, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              const Text(
                'أحدث الأعمال',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF2A4A),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
