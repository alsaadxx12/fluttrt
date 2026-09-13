import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';
import 'package:youtube_downloader/features/cinemana/presentation/providers/cinemana_provider.dart';
import 'package:youtube_downloader/features/downloads/presentation/providers/downloads_provider.dart';
import 'package:youtube_downloader/features/settings/presentation/providers/settings_provider.dart';
import 'package:youtube_downloader/features/sports/presentation/providers/sports_provider.dart';
import 'package:youtube_downloader/features/update/presentation/update_controller.dart';

import 'package:youtube_downloader/core/constants/star_personalities.dart';
export 'package:youtube_downloader/core/constants/star_personalities.dart';

class AppDrawer extends ConsumerStatefulWidget {
  const AppDrawer({super.key});

  @override
  ConsumerState<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends ConsumerState<AppDrawer> {
  // 0: Actors (ممثلون مشاهير), 1: Players (لاعبون مشاهير)
  int _selectedCelebrityTab = 0;

  void _onCelebrityTap(BuildContext context, StarPersonality star) {
    Navigator.pop(context); // Close drawer smoothly

    if (star.isPlayer) {
      // 1. Set Sports search query & reset tab to matches
      ref.read(sportsSearchQueryProvider.notifier).state = star.searchQuery;
      ref.read(sportsTabProvider.notifier).state = 0;
      context.push('/sports');
    } else {
      // 2. Search Cinemana catalog for this actor
      ref.read(cinemanaSectionProvider('movies').notifier).search(star.searchQuery);
      context.push('/cinemana/movies');
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(stringsProvider);
    final settings = ref.watch(settingsProvider);
    final downloadsState = ref.watch(downloadsProvider);
    final activeCount = downloadsState.activeTasks.length;
    final favorites = ref.watch(cinemanaFavoritesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = AppPalette.of(context);
    final currentPath = GoRouterState.of(context).uri.path;
    final update = ref.watch(updateControllerProvider);

    final starsList = _selectedCelebrityTab == 0 ? kCinemaStars : kFootballStars;

    return Drawer(
      backgroundColor: palette.bg,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // ==========================================
            // 1. Drawer Header (Clean Title & Close Button)
            // ==========================================
            Container(
              width: double.infinity,
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 16,
                bottom: 16,
                left: 18,
                right: 18,
              ),
              decoration: BoxDecoration(
                color: palette.bg,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      strings.appName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                        color: isDark ? Colors.white : const Color(0xFF111827),
                      ),
                    ),
                  ),
                  // Close Drawer Button
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.pop(context),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withOpacity(0.08)
                              : Colors.black.withOpacity(0.05),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ==========================================
            // 2. Navigation List & Spotlight
            // ==========================================
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                children: [
                  // ----------------------------------------------------
                  // ⭐ نجوم وشخصيات التطبيق (Actors & Football Legends)
                  // ----------------------------------------------------
                  _buildCelebritySpotlight(isDark, starsList),

                  const SizedBox(height: 14),

                  // ----------------------------------------------------
                  // 🏠 القسم الأول: الرئيسية والمحتوى
                  // ----------------------------------------------------
                  _buildDrawerItem(
                    context: context,
                    icon: Icons.home_rounded,
                    title: 'الرئيسية',
                    isSelected: currentPath == '/',
                    onTap: () {
                      Navigator.pop(context);
                      context.go('/');
                    },
                  ),
                  _buildDrawerItem(
                    context: context,
                    icon: Icons.smart_display_rounded,
                    title: 'يوتيوب سينمائي',
                    isSelected: currentPath == '/youtube_cinematic',
                    onTap: () {
                      Navigator.pop(context);
                      context.go('/youtube_cinematic');
                    },
                  ),
                  _buildDrawerItem(
                    context: context,
                    icon: Icons.download_rounded,
                    title: 'التنزيلات المباشرة',
                    badgeCount: activeCount > 0 ? activeCount : null,
                    badgeText: activeCount > 0 ? '$activeCount نشط' : null,
                    isSelected: currentPath == '/downloads',
                    onTap: () {
                      Navigator.pop(context);
                      context.go('/downloads');
                    },
                  ),

                  const SizedBox(height: 16),

                  // ----------------------------------------------------
                  // 🎬 القسم الثاني: سينمانا والترفيه
                  // ----------------------------------------------------
                  _buildDrawerItem(
                    context: context,
                    icon: Icons.movie_filter_rounded,
                    title: 'أفلام هوليوود وعربية',
                    isSelected: currentPath == '/cinemana/movies' || currentPath == '/cinemana',
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/cinemana/movies');
                    },
                  ),
                  _buildDrawerItem(
                    context: context,
                    icon: Icons.tv_rounded,
                    title: 'مسلسلات تلفزيونية',
                    isSelected: currentPath == '/cinemana/series',
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/cinemana/series');
                    },
                  ),
                  _buildDrawerItem(
                    context: context,
                    icon: Icons.whatshot_rounded,
                    title: 'أنمي ورسوم متحركة',
                    isSelected: currentPath == '/cinemana/anime',
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/cinemana/anime');
                    },
                  ),
                  _buildDrawerItem(
                    context: context,
                    icon: Icons.favorite_rounded,
                    title: 'قائمتي المفضلة',
                    badgeCount: favorites.isNotEmpty ? favorites.length : null,
                    isSelected: currentPath == '/cinemana/favorites',
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/cinemana/favorites');
                    },
                  ),

                  const SizedBox(height: 16),

                  // ----------------------------------------------------
                  // ⚽ القسم الثالث: البث المباشر والرياضة
                  // ----------------------------------------------------
                  _buildDrawerItem(
                    context: context,
                    icon: Icons.sports_soccer_rounded,
                    title: 'مباريات اليوم والرياضة',
                    badgeText: 'مباشر 🔴',
                    isSelected: currentPath == '/sports',
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/sports');
                    },
                  ),
                  _buildDrawerItem(
                    context: context,
                    icon: Icons.live_tv_rounded,
                    title: 'القنوات التلفزيونية المباشرة',
                    badgeText: 'HD',
                    isSelected: currentPath == '/channels',
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/channels');
                    },
                  ),

                  const SizedBox(height: 16),

                  // ----------------------------------------------------
                  _buildDrawerItem(
                    context: context,
                    icon: Icons.settings_rounded,
                    title: 'الإعدادات العامة',
                    isSelected: currentPath == '/settings',
                    onTap: () {
                      Navigator.pop(context);
                      context.go('/settings');
                    },
                  ),
                  _buildDrawerItem(
                    context: context,
                    icon: update.status == UpdateStatus.loading
                        ? Icons.sync_rounded
                        : (update.hasUpdate ? Icons.system_update_rounded : Icons.verified_rounded),
                    title: update.status == UpdateStatus.loading
                        ? 'جارٍ فحص التحديثات…'
                        : (update.hasUpdate
                            ? 'تحديث جديد (${update.info!.versionName})'
                            : 'التطبيق محدّث لأحدث إصدار'),
                    accentColor: update.hasUpdate ? const Color(0xFFE50914) : const Color(0xFF10B981),
                    badgeText: update.hasUpdate ? 'تحديث متاح' : null,
                    dimmed: !update.hasUpdate,
                    onTap: () {
                      final c = ref.read(updateControllerProvider.notifier);
                      if (update.hasUpdate) {
                        Navigator.pop(context);
                        c.showPrompt();
                      } else if (update.status != UpdateStatus.loading) {
                        c.checkNow();
                      }
                    },
                  ),
                  _buildDrawerItem(
                    context: context,
                    icon: Icons.info_outline_rounded,
                    title: 'حول التطبيق',
                    isSelected: currentPath == '/about',
                    onTap: () {
                      Navigator.pop(context);
                      context.go('/about');
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),

            // ==========================================
            // 3. Sleek Footer (Dark Mode & Version)
            // ==========================================
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: palette.bg,
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1C1C24)
                          : const Color(0xFFE5E7EB),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      settings.themeMode == ThemeMode.dark
                          ? Icons.dark_mode_rounded
                          : Icons.light_mode_rounded,
                      size: 18,
                      color: settings.themeMode == ThemeMode.dark
                          ? const Color(0xFFFBBF24)
                          : const Color(0xFFF59E0B),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'الوضع الليلي',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : const Color(0xFF111827),
                        ),
                      ),
                      Text(
                        settings.themeMode == ThemeMode.dark ? 'مفعّل حالياً' : 'الوضع النهاري',
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Switch.adaptive(
                    value: settings.themeMode == ThemeMode.dark,
                    activeColor: AppColors.primary,
                    activeTrackColor: AppColors.primary.withOpacity(0.4),
                    onChanged: (val) {
                      ref.read(settingsProvider.notifier).setThemeMode(
                            val ? ThemeMode.dark : ThemeMode.light,
                          );
                    },
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
  // ⭐ Build Celebrity Spotlight Section
  // ==========================================
  Widget _buildCelebritySpotlight(bool isDark, List<StarPersonality> starsList) {
    final activeColor = _selectedCelebrityTab == 0
        ? const Color(0xFFFF2A4A) // Cinema crimson
        : const Color(0xFF10B981); // Sports emerald

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF16161F) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF282836) : const Color(0xFFE2E8F0),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.25 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header of Stars section + Tabs
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _selectedCelebrityTab == 0
                        ? [const Color(0xFFFF2A4A), const Color(0xFFFF758C)]
                        : [const Color(0xFF10B981), const Color(0xFF06B6D4)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _selectedCelebrityTab == 0
                      ? Icons.stars_rounded
                      : Icons.sports_soccer_rounded,
                  size: 15,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'نجوم وشخصيات التطبيق',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const Spacer(),
              // Mini hint badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: activeColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'اضغط للبحث',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: activeColor,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Tab Selector: [🎬 ممثلون مشاهير] | [⚽ أساطير الكرة]
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF20202C) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildSpotlightTab(
                    title: '🎬 ممثلون مشاهير',
                    isSelected: _selectedCelebrityTab == 0,
                    activeColor: const Color(0xFFFF2A4A),
                    isDark: isDark,
                    onTap: () => setState(() => _selectedCelebrityTab = 0),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _buildSpotlightTab(
                    title: '⚽ أساطير الرياضة',
                    isSelected: _selectedCelebrityTab == 1,
                    activeColor: const Color(0xFF10B981),
                    isDark: isDark,
                    onTap: () => setState(() => _selectedCelebrityTab = 1),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Horizontal Avatar Carousel of Stars
          SizedBox(
            height: 116,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: starsList.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final star = starsList[index];
                return _buildCelebrityAvatarCard(
                  star: star,
                  isDark: isDark,
                  accentColor: activeColor,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpotlightTab({
    required String title,
    required bool isSelected,
    required Color activeColor,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF2C2C3C) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected
                ? activeColor
                : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
          ),
        ),
      ),
    );
  }

  Widget _buildCelebrityAvatarCard({
    required StarPersonality star,
    required bool isDark,
    required Color accentColor,
  }) {
    return InkWell(
      onTap: () => _onCelebrityTap(context, star),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 76,
        padding: const EdgeInsets.all(4),
        child: Column(
          children: [
            // Circular Avatar with glowing gradient ring
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        accentColor,
                        accentColor.withOpacity(0.3),
                        const Color(0xFFF59E0B),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withOpacity(0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(2.5), // border width
                  child: ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: star.imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: isDark ? const Color(0xFF252530) : const Color(0xFFE2E8F0),
                        child: const Center(
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: isDark ? const Color(0xFF252530) : const Color(0xFFE2E8F0),
                        child: Icon(
                          star.isPlayer
                              ? Icons.sports_soccer_rounded
                              : Icons.person_rounded,
                          size: 26,
                          color: accentColor,
                        ),
                      ),
                    ),
                  ),
                ),
                // Badge overlay at bottom of avatar
                Positioned(
                  bottom: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E28) : Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: accentColor.withOpacity(0.6),
                        width: 0.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 3,
                        ),
                      ],
                    ),
                    child: Text(
                      star.badge,
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Star Name
            Text(
              star.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 1),
            // Star Subtitle / Role
            Text(
              star.role,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w500,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // Section Header
  // ==========================================

  Widget _buildDrawerItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    String? subtitle,
    int? badgeCount,
    String? badgeText,
    bool isSelected = false,
    bool dimmed = false,
    Color? accentColor,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const itemColor = AppColors.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8.5),
            decoration: BoxDecoration(
              color: isSelected
                  ? itemColor.withOpacity(isDark ? 0.16 : 0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: isSelected
                  ? Border.all(color: itemColor.withOpacity(0.35), width: 1)
                  : null,
            ),
            child: Row(
              children: [
                // Icon Tile
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? itemColor
                        : (isDark ? const Color(0xFF1B1B24) : const Color(0xFFEDF2F7)),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: itemColor.withOpacity(0.4),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    icon,
                    size: 24,
                    color: isSelected
                        ? Colors.white
                        : dimmed
                            ? (isDark ? Colors.white38 : Colors.black38)
                            : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155)),
                  ),
                ),
                const SizedBox(width: 12),
                // Title and Subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                          color: isSelected
                              ? itemColor
                              : dimmed
                                  ? (isDark ? Colors.white38 : Colors.black38)
                                  : (isDark ? Colors.white : const Color(0xFF1E293B)),
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 1.5),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Badges
                if (badgeText != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: itemColor,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: itemColor.withOpacity(0.35),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Text(
                      badgeText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ] else if (badgeCount != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$badgeCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ] else
                  Icon(
                    Icons.chevron_left_rounded,
                    size: 18,
                    color: isDark ? Colors.white24 : Colors.black26,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
