import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';
import 'package:youtube_downloader/features/downloads/presentation/providers/downloads_provider.dart';
import 'package:youtube_downloader/features/settings/presentation/providers/settings_provider.dart';
import 'package:youtube_downloader/features/update/data/update_service.dart';
import 'package:youtube_downloader/features/update/presentation/update_controller.dart';
import 'package:youtube_downloader/features/update/presentation/update_feedback.dart';
import 'package:youtube_downloader/features/subscription/presentation/providers/subscription_provider.dart';
import 'package:youtube_downloader/features/auth/presentation/providers/auth_provider.dart';

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = AppPalette.of(context);
    final currentPath = GoRouterState.of(context).uri.path;
    final update = ref.watch(updateControllerProvider);
    final activeDownloads = ref.watch(downloadsProvider).activeTasks.length;
    final installed = ref.watch(installedVersionProvider);
    final isSportsUnlocked = ref.watch(isSportsUnlockedProvider);
    final userProfile = ref.watch(userProfileProvider).valueOrNull;
    final sportsSub = ref.watch(sportsSubscriptionProvider).valueOrNull;

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

          // User Profile & Subscription Card in Sidebar
          if (!collapsed)
            Container(
              margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.04)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.08),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.person_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              userProfile?.fullName.isNotEmpty == true
                                  ? userProfile!.fullName
                                  : 'مستخدم CineBall',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: isDark ? Colors.white : Colors.black87,
                                letterSpacing: -0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (userProfile?.phone.isNotEmpty == true) ...[
                              const SizedBox(height: 5),
                              Row(
                                children: [
                                  Icon(
                                    Icons.phone_android_rounded,
                                    size: 11.5,
                                    color: isDark ? Colors.white38 : Colors.black38,
                                  ),
                                  const SizedBox(width: 3),
                                  Expanded(
                                    child: Text(
                                      userProfile!.phone,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? Colors.white60 : Colors.black54,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1, thickness: 0.8),
                  const SizedBox(height: 6),
                  if (isSportsUnlocked) ...[
                    Row(
                      children: [
                        const Icon(
                          Icons.verified_rounded,
                          size: 14,
                          color: AppColors.success,
                        ),
                        const SizedBox(width: 4),
                        const Expanded(
                          child: Text(
                            'المباريات: مفعّل',
                            style: TextStyle(
                              color: AppColors.success,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Text(
                          'متبقي ${sportsSub?.remainingDays ?? 0} يوم',
                          style: const TextStyle(
                            color: AppColors.success,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'المباريات: غير مفعّل',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: isDark ? Colors.white60 : Colors.black54,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 24,
                          child: ElevatedButton(
                            onPressed: () => context.push('/sports-activation'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isDark
                                  ? Colors.white.withOpacity(0.12)
                                  : const Color(0xFF1E293B),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            child: const Text(
                              'اشتراك',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
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
                  icon: Icons.live_tv_rounded,
                  title: 'المسلسلات',
                  isSelected: currentPath == '/cinemana/series',
                  isDark: isDark,
                  onTap: () => context.push('/cinemana/series'),
                ),
                _buildSidebarItem(
                  icon: Icons.auto_awesome_rounded,
                  title: 'الأنمي',
                  isSelected: currentPath == '/cinemana/anime',
                  isDark: isDark,
                  onTap: () => context.push('/cinemana/anime'),
                ),
                _buildSidebarItem(
                  icon: Icons.tv_rounded,
                  title: 'الدراما الآسيوية',
                  isSelected: currentPath == '/asia2tv',
                  isDark: isDark,
                  onTap: () => context.push('/asia2tv'),
                ),
                _buildSidebarItem(
                  icon: Icons.sports_soccer_rounded,
                  title: 'المباريات',
                  badgeText: null,
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
                  icon: Icons.settings_suggest_rounded,
                  title: 'الإعدادات',
                  isSelected: currentPath == '/settings',
                  isDark: isDark,
                  onTap: () => context.go('/settings'),
                ),
                _buildSidebarItem(
                  icon: Icons.system_update_rounded,
                  title: 'التحقق من وجود تحديث',
                  badgeText: update.hasUpdate ? 'تحديث متوفر' : null,
                  isSelected: false,
                  isDark: isDark,
                  onTap: () => checkUpdateWithFeedback(context, ref),
                ),
                _buildSidebarItem(
                  icon: Icons.info_rounded,
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
            color: Colors.white,
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
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white30, width: 0.8),
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
                ] else ...[
                  const SizedBox(width: 8),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => checkUpdateWithFeedback(context, ref),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isDark ? Colors.white.withOpacity(0.12) : const Color(0xFFCBD5E1),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.refresh_rounded, size: 11, color: palette.textMuted),
                            const SizedBox(width: 3),
                            Text(
                              'تحقق',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: palette.textMuted,
                              ),
                            ),
                          ],
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
    final textColor = isSelected
        ? Colors.white
        : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155));

    const iconColor = Colors.white;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          hoverColor: Colors.white.withOpacity(0.04),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
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
                        fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                  ),
                  if (badgeText != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white24, width: 0.8),
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
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white24, width: 0.8),
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
