import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';
import 'package:youtube_downloader/features/cinemana/presentation/providers/cinemana_provider.dart';
import 'package:youtube_downloader/features/downloads/presentation/providers/downloads_provider.dart';
import 'package:youtube_downloader/features/settings/presentation/providers/settings_provider.dart';
import 'package:youtube_downloader/features/update/data/update_service.dart';
import 'package:youtube_downloader/features/update/presentation/update_controller.dart';
import 'package:youtube_downloader/features/subscription/presentation/providers/subscription_provider.dart';

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
    final favorites = ref.watch(cinemanaFavoritesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = AppPalette.of(context);
    final currentPath = GoRouterState.of(context).uri.path;
    final update = ref.watch(updateControllerProvider);
    final activeDownloads = ref.watch(downloadsProvider).activeTasks.length;
    final installed = ref.watch(installedVersionProvider);
    final isSportsUnlocked = ref.watch(isSportsUnlockedProvider);

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
                _buildSidebarItem(
                  icon: Icons.home_rounded,
                  title: 'الرئيسية',
                  isSelected: currentPath == '/',
                  isDark: isDark,
                  onTap: () => context.go('/'),
                ),
                _buildSidebarItem(
                  icon: Icons.movie_rounded,
                  title: 'الأفلام',
                  isSelected: currentPath == '/cinemana/movies' || currentPath == '/cinemana',
                  isDark: isDark,
                  onTap: () => context.push('/cinemana/movies'),
                ),
                _buildSidebarItem(
                  icon: Icons.tv_rounded,
                  title: 'المسلسلات',
                  isSelected: currentPath == '/cinemana/series',
                  isDark: isDark,
                  onTap: () => context.push('/cinemana/series'),
                ),
                _buildSidebarItem(
                  icon: Icons.whatshot_rounded,
                  title: 'الأنمي',
                  isSelected: currentPath == '/cinemana/anime',
                  isDark: isDark,
                  onTap: () => context.push('/cinemana/anime'),
                ),
                _buildSidebarItem(
                  icon: isSportsUnlocked
                      ? Icons.sports_soccer_rounded
                      : Icons.lock_outline_rounded,
                  title: isSportsUnlocked ? 'المباريات' : 'المباريات',
                  badgeText: isSportsUnlocked ? null : '🔒',
                  isSelected: currentPath == '/sports' ||
                      currentPath == '/sports-activation',
                  isDark: isDark,
                  onTap: () {
                    if (isSportsUnlocked) {
                      context.push('/sports');
                    } else {
                      context.push('/sports-activation');
                    }
                  },
                ),
                _buildSidebarItem(
                  icon: Icons.smart_display_rounded,
                  title: 'يوتيوب',
                  isSelected: currentPath == '/youtube_cinematic',
                  isDark: isDark,
                  onTap: () => context.go('/youtube_cinematic'),
                ),
                _buildSidebarItem(
                  icon: Icons.play_circle_fill_rounded,
                  title: 'مشاهد',
                  isSelected: currentPath == '/reels',
                  isDark: isDark,
                  onTap: () => context.go('/reels'),
                ),

                const SizedBox(height: 10),

                _buildSidebarItem(
                  icon: Icons.favorite_rounded,
                  title: 'المفضلة',
                  badgeCount: favorites.isNotEmpty ? favorites.length : null,
                  isSelected: currentPath == '/cinemana/favorites',
                  isDark: isDark,
                  onTap: () => context.push('/cinemana/favorites'),
                ),
                _buildSidebarItem(
                  icon: Icons.history_rounded,
                  title: 'سجل المشاهدة',
                  isSelected: currentPath == '/history',
                  isDark: isDark,
                  onTap: () => context.push('/history'),
                ),
                _buildSidebarItem(
                  icon: Icons.download_rounded,
                  title: 'التنزيلات',
                  badgeCount: activeDownloads > 0 ? activeDownloads : null,
                  isSelected: currentPath == '/downloads',
                  isDark: isDark,
                  onTap: () => context.go('/downloads'),
                ),

                const SizedBox(height: 10),

                _buildSidebarItem(
                  icon: Icons.settings_rounded,
                  title: 'الإعدادات',
                  isSelected: currentPath == '/settings',
                  isDark: isDark,
                  onTap: () => context.go('/settings'),
                ),
                _buildSidebarItem(
                  icon: Icons.info_outline_rounded,
                  title: 'حول التطبيق',
                  badgeText: update.hasUpdate ? 'تحديث' : null,
                  isSelected: currentPath == '/about',
                  isDark: isDark,
                  onTap: () => context.go('/about'),
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        ),

          // ----------------------------------------------------
          // 3. Footer — logo, name, installed version, update pill
          // ----------------------------------------------------
          _buildFooter(
            collapsed: collapsed,
            isDark: isDark,
            palette: palette,
            installed: installed,
            hasUpdate: update.hasUpdate,
          ),
        ],
      ),
    );
  }

  Widget _buildFooter({
    required bool collapsed,
    required bool isDark,
    required AppPalette palette,
    required AsyncValue<InstalledVersion> installed,
    required bool hasUpdate,
  }) {
    final logo = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.asset(
        'assets/images/app_logo.png',
        width: 28,
        height: 28,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox(
          width: 28,
          height: 28,
          child: Icon(
            Icons.play_circle_fill_rounded,
            size: 24,
            color: AppColors.primary,
          ),
        ),
      ),
    );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: collapsed ? 0 : 16,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: palette.bg,
        border: Border(
          top: BorderSide(color: palette.border, width: 1),
        ),
      ),
      child: collapsed
          ? Center(child: logo)
          : Row(
              children: [
                logo,
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'CINEBALL',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        installed.when(
                          data: (v) => 'الإصدار ${v.versionName}',
                          loading: () => 'الإصدار …',
                          error: (_, __) => 'الإصدار —',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasUpdate) ...[
                  const SizedBox(width: 8),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () =>
                          ref.read(updateControllerProvider.notifier).showPrompt(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'تحديث متاح',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
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
    required VoidCallback onTap,
  }) {
    const activeColor = AppColors.primary;

    final unselectedIconColor =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final unselectedTextColor =
        isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155);

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
            // The 72 px rail minus the list's 10 px sides leaves 52 px; the
            // 32 px icon slot needs the row's own sides at 8 px to fit.
            padding: EdgeInsets.symmetric(
              horizontal: _collapsed ? 8 : 12,
              vertical: 8,
            ),
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
