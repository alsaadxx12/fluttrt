import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';
import 'package:youtube_downloader/features/cinemana/presentation/providers/cinemana_provider.dart';
import 'package:youtube_downloader/features/downloads/presentation/providers/downloads_provider.dart';
import 'package:youtube_downloader/features/settings/presentation/providers/settings_provider.dart';
import 'package:youtube_downloader/features/update/presentation/update_controller.dart';

/// Light red wash behind the active row — replaces the old solid red tile.
const Color _kActiveFill = Color(0x14E50914);

class AppDrawer extends ConsumerStatefulWidget {
  const AppDrawer({super.key});

  @override
  ConsumerState<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends ConsumerState<AppDrawer> {
  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(stringsProvider);
    final favorites = ref.watch(cinemanaFavoritesProvider);
    final activeDownloads = ref.watch(downloadsProvider).activeTasks.length;
    final update = ref.watch(updateControllerProvider);
    final installed = ref.watch(installedVersionProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = AppPalette.of(context);
    final currentPath = GoRouterState.of(context).uri.path;

    return Drawer(
      backgroundColor: palette.bg,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // ==========================================
            // 1. Header — centred title, menu button at the end
            // ==========================================
            Container(
              width: double.infinity,
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 12,
                bottom: 8,
                left: 18,
                right: 18,
              ),
              color: palette.bg,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Text(
                    strings.appName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.2,
                      color: isDark ? Colors.white : const Color(0xFF111827),
                    ),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.pop(context),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withOpacity(0.08)
                                : Colors.white,
                            shape: BoxShape.circle,
                            border: isDark
                                ? null
                                : Border.all(color: palette.border, width: 1),
                          ),
                          child: Icon(
                            Icons.menu_rounded,
                            size: 18,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ==========================================
            // 2. Navigation list
            // ==========================================
            Expanded(
              child: ListView(
                padding:
                    const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                children: [
                  _DrawerItem(
                    icon: Icons.home_rounded,
                    title: 'الرئيسية',
                    isSelected: currentPath == '/',
                    onTap: () {
                      Navigator.pop(context);
                      context.go('/');
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.movie_rounded,
                    title: 'الأفلام',
                    isSelected: currentPath == '/cinemana/movies' ||
                        currentPath == '/cinemana',
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/cinemana/movies');
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.tv_rounded,
                    title: 'المسلسلات',
                    isSelected: currentPath == '/cinemana/series',
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/cinemana/series');
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.whatshot_rounded,
                    title: 'الأنمي',
                    isSelected: currentPath == '/cinemana/anime',
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/cinemana/anime');
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.sports_soccer_rounded,
                    title: 'المباريات',
                    isSelected: currentPath == '/sports',
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/sports');
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.smart_display_rounded,
                    title: 'يوتيوب',
                    isSelected: currentPath == '/youtube_cinematic',
                    onTap: () {
                      Navigator.pop(context);
                      context.go('/youtube_cinematic');
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.play_circle_fill_rounded,
                    title: 'مشاهد',
                    isSelected: currentPath == '/reels',
                    onTap: () {
                      Navigator.pop(context);
                      context.go('/reels');
                    },
                  ),

                  const SizedBox(height: 10),

                  _DrawerItem(
                    icon: Icons.favorite_rounded,
                    title: 'المفضلة',
                    badgeText:
                        favorites.isNotEmpty ? '${favorites.length}' : null,
                    isSelected: currentPath == '/cinemana/favorites',
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/cinemana/favorites');
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.history_rounded,
                    title: 'سجل المشاهدة',
                    isSelected: currentPath == '/history',
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/history');
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.download_rounded,
                    title: 'التنزيلات',
                    badgeText: activeDownloads > 0 ? '$activeDownloads' : null,
                    isSelected: currentPath == '/downloads',
                    onTap: () {
                      Navigator.pop(context);
                      context.go('/downloads');
                    },
                  ),

                  const SizedBox(height: 10),

                  _DrawerItem(
                    icon: Icons.settings_rounded,
                    title: 'الإعدادات',
                    isSelected: currentPath == '/settings',
                    onTap: () {
                      Navigator.pop(context);
                      context.go('/settings');
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.info_outline_rounded,
                    title: 'حول التطبيق',
                    badgeText: update.hasUpdate ? 'تحديث' : null,
                    isSelected: currentPath == '/about',
                    onTap: () {
                      Navigator.pop(context);
                      context.go('/about');
                    },
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            ),

            // ==========================================
            // 3. Footer — logo, name, installed version, update pill
            // ==========================================
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: palette.bg,
                border: Border(
                  top: BorderSide(color: palette.border, width: 1),
                ),
              ),
              child: Row(
                children: [
                  ClipRRect(
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
                  ),
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
                            color:
                                isDark ? Colors.white : const Color(0xFF0F172A),
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
                  if (update.hasUpdate) ...[
                    const SizedBox(width: 8),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          Navigator.pop(context);
                          ref
                              .read(updateControllerProvider.notifier)
                              .showPrompt();
                        },
                        child: const _Pill(text: 'تحديث متاح'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// Navigation row — uniform for every entry
// ==========================================
class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool isSelected;
  final String? badgeText;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.title,
    required this.onTap,
    this.isSelected = false,
    this.badgeText,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isSelected
        ? AppColors.primary
        : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155));
    final labelColor = isSelected
        ? AppColors.primary
        : (isDark ? Colors.white : const Color(0xFF1E293B));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            height: 46,
            decoration: BoxDecoration(
              color: isSelected ? _kActiveFill : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              children: [
                // Active marker: a slim red bar hugging the start edge.
                if (isSelected)
                  PositionedDirectional(
                    start: 0,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Container(
                        width: 3,
                        height: 22,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: Center(
                          child: Icon(icon, size: 22, color: iconColor),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                isSelected ? FontWeight.w800 : FontWeight.w600,
                            color: labelColor,
                          ),
                        ),
                      ),
                      if (badgeText != null) ...[
                        const SizedBox(width: 8),
                        _Pill(text: badgeText!),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// Small red pill used for counts and the update badge
// ==========================================
class _Pill extends StatelessWidget {
  final String text;

  const _Pill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          height: 1.2,
        ),
      ),
    );
  }
}
