import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';
import 'package:youtube_downloader/features/cinemana/presentation/providers/cinemana_provider.dart';
import 'package:youtube_downloader/features/downloads/presentation/providers/downloads_provider.dart';
import 'package:youtube_downloader/features/settings/presentation/providers/settings_provider.dart';
import 'package:youtube_downloader/features/update/presentation/update_controller.dart';

class AppSidebar extends ConsumerStatefulWidget {
  final int selectedIndex;
  final Function(int index) onDestinationSelected;

  const AppSidebar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  ConsumerState<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends ConsumerState<AppSidebar> {
  // A narrow rail of icons only, for more room for the content beside it.
  bool _collapsed = false;

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

    final collapsed = _collapsed;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      width: collapsed ? 72 : 240,
      decoration: BoxDecoration(
        color: palette.bg,
      ),
      child: Column(
        children: [
          // ----------------------------------------------------
          // 1. Sidebar Header (Title & Toggle, No Logo, No Gradient)
          // ----------------------------------------------------
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: palette.bg,
            ),
            child: Row(
              children: [
                if (!collapsed)
                  Expanded(
                    child: Text(
                      strings.appName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                        color: isDark ? Colors.white : const Color(0xFF111827),
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: collapsed ? 'توسيع' : 'طي',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _collapsed = !_collapsed),
                  icon: Icon(
                    collapsed ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                    size: 20,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),

          // ----------------------------------------------------
          // 2. Scrollable Navigation Menu (Unified Icons)
          // ----------------------------------------------------
          Expanded(
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                children: [
                // 🏠 القسم الأول: الرئيسية والمحتوى
                _buildSidebarItem(
                  icon: Icons.home_rounded,
                  title: 'الرئيسية',
                  isSelected: currentPath == '/',
                  isDark: isDark,
                  onTap: () => context.go('/'),
                ),
                _buildSidebarItem(
                  icon: Icons.smart_display_rounded,
                  title: 'يوتيوب سينمائي',
                  isSelected: currentPath == '/youtube_cinematic',
                  isDark: isDark,
                  onTap: () => context.go('/youtube_cinematic'),
                ),
                _buildSidebarItem(
                  icon: Icons.download_rounded,
                  title: 'التنزيلات',
                  badgeCount: activeCount > 0 ? activeCount : null,
                  badgeText: activeCount > 0 ? '$activeCount نشط' : null,
                  isSelected: currentPath == '/downloads',
                  isDark: isDark,
                  onTap: () => context.go('/downloads'),
                ),

                const SizedBox(height: 12),

                // 🎬 القسم الثاني: سينمانا والترفيه
                _buildSidebarItem(
                  icon: Icons.movie_filter_rounded,
                  title: 'أفلام هوليوود وعربية',
                  isSelected: currentPath == '/cinemana/movies' || currentPath == '/cinemana',
                  isDark: isDark,
                  onTap: () => context.push('/cinemana/movies'),
                ),
                _buildSidebarItem(
                  icon: Icons.tv_rounded,
                  title: 'مسلسلات تلفزيونية',
                  isSelected: currentPath == '/cinemana/series',
                  isDark: isDark,
                  onTap: () => context.push('/cinemana/series'),
                ),
                _buildSidebarItem(
                  icon: Icons.whatshot_rounded,
                  title: 'أنمي ورسوم متحركة',
                  isSelected: currentPath == '/cinemana/anime',
                  isDark: isDark,
                  onTap: () => context.push('/cinemana/anime'),
                ),
                _buildSidebarItem(
                  icon: Icons.favorite_rounded,
                  title: 'المفضلة',
                  badgeCount: favorites.isNotEmpty ? favorites.length : null,
                  isSelected: currentPath == '/cinemana/favorites',
                  isDark: isDark,
                  onTap: () => context.push('/cinemana/favorites'),
                ),

                const SizedBox(height: 12),

                // ⚽ القسم الثالث: البث المباشر والرياضة
                _buildSidebarItem(
                  icon: Icons.sports_soccer_rounded,
                  title: 'مباريات اليوم والرياضة',
                  badgeText: 'مباشر 🔴',
                  isSelected: currentPath == '/sports',
                  isDark: isDark,
                  onTap: () => context.push('/sports'),
                ),
                _buildSidebarItem(
                  icon: Icons.live_tv_rounded,
                  title: 'القنوات التلفزيونية',
                  badgeText: 'HD',
                  isSelected: currentPath == '/channels',
                  isDark: isDark,
                  onTap: () => context.push('/channels'),
                ),

                const SizedBox(height: 12),

                // ⚙️ القسم الرابع: النظام والتطبيق
                _buildSidebarItem(
                  icon: Icons.settings_rounded,
                  title: 'الإعدادات العامة',
                  isSelected: currentPath == '/settings',
                  isDark: isDark,
                  onTap: () => context.go('/settings'),
                ),
                _buildSidebarItem(
                  icon: update.status == UpdateStatus.loading
                      ? Icons.sync_rounded
                      : (update.hasUpdate ? Icons.system_update_rounded : Icons.verified_rounded),
                  title: update.status == UpdateStatus.loading
                      ? 'جارٍ فحص التحديث…'
                      : (update.hasUpdate
                          ? 'تحديث متاح (${update.info!.versionName})'
                          : 'التطبيق محدّث'),
                  badgeText: update.hasUpdate ? 'جديد' : null,
                  isSelected: false,
                  dimmed: !update.hasUpdate,
                  isDark: isDark,
                  onTap: () {
                    final c = ref.read(updateControllerProvider.notifier);
                    if (update.hasUpdate) {
                      c.showPrompt();
                    } else if (update.status != UpdateStatus.loading) {
                      c.checkNow();
                    }
                  },
                ),
                _buildSidebarItem(
                  icon: Icons.info_outline_rounded,
                  title: 'حول البرنامج',
                  isSelected: currentPath == '/about',
                  isDark: isDark,
                  onTap: () => context.go('/about'),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),

          // ----------------------------------------------------
          // 3. Footer (Theme Switch & Status)
          // ----------------------------------------------------
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: palette.bg,
            ),
            child: Row(
              children: [
                Icon(
                  settings.themeMode == ThemeMode.dark
                      ? Icons.dark_mode_rounded
                      : Icons.light_mode_rounded,
                  size: 17,
                  color: settings.themeMode == ThemeMode.dark
                      ? const Color(0xFFFBBF24)
                      : const Color(0xFFF59E0B),
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 8),
                  Text(
                    'الوضع الليلي',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF111827),
                    ),
                  ),
                  const Spacer(),
                ],
                Switch.adaptive(
                  value: settings.themeMode == ThemeMode.dark,
                  activeColor: AppColors.primary,
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
    );
  }

  Widget _buildSidebarItem({
    required IconData icon,
    required String title,
    required bool isSelected,
    required bool isDark,
    int? badgeCount,
    String? badgeText,
    bool dimmed = false,
    required VoidCallback onTap,
  }) {
    const activeColor = AppColors.primary;

    final unselectedIconColor = dimmed
        ? (isDark ? Colors.white38 : Colors.black38)
        : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B));
    final unselectedTextColor = dimmed
        ? (isDark ? Colors.white38 : Colors.black38)
        : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155));

    final iconColor = isSelected ? activeColor : unselectedIconColor;
    final textColor = isSelected ? activeColor : unselectedTextColor;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          hoverColor: activeColor.withOpacity(0.04),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment:
                  _collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: Center(
                    child: Icon(
                      icon,
                      size: 24,
                      color: iconColor,
                    ),
                  ),
                ),
                if (!_collapsed) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                  ),
                  if (badgeText != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: activeColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        badgeText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ] else if (badgeCount != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: activeColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$badgeCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
