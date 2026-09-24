import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';
import 'package:youtube_downloader/features/settings/presentation/providers/settings_provider.dart';
import 'package:youtube_downloader/features/update/presentation/update_controller.dart';
import 'package:youtube_downloader/features/subscription/presentation/providers/subscription_provider.dart';
import 'package:youtube_downloader/features/auth/presentation/providers/auth_provider.dart';

/// Subtle neutral wash behind the active row — replaces red active tint.

class AppDrawer extends ConsumerStatefulWidget {
  const AppDrawer({super.key});

  @override
  ConsumerState<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends ConsumerState<AppDrawer> {
  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(stringsProvider);
    final update = ref.watch(updateControllerProvider);
    final installed = ref.watch(installedVersionProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = AppPalette.of(context);
    final currentPath = GoRouterState.of(context).uri.path;
    final isSportsUnlocked = ref.watch(isSportsUnlockedProvider);
    final userProfile = ref.watch(userProfileProvider).valueOrNull;
    final sportsSub = ref.watch(sportsSubscriptionProvider).valueOrNull;

    // Glass: the page behind shows through a deep blur and a dark tint
    // that lightens towards the top, with a thin light edge on the open
    // side. Every panel inside is a lighter sheen on the same glass.
    return Drawer(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: palette.glassSheet,
              ),
              border: BorderDirectional(end: BorderSide(color: palette.glassSheetEdge, width: 0.8)),
            ),
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
              color: Colors.transparent,
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
                  // Day or night, one tap.
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => ref
                            .read(settingsProvider.notifier)
                            .setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: palette.glassFill(),
                            shape: BoxShape.circle,
                            border: Border.all(color: palette.glassFillEdge(), width: 0.8),
                          ),
                          child: Icon(
                            isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                            size: 18,
                            color: palette.text,
                          ),
                        ),
                      ),
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
            // User Profile & Subscription Card
            // ==========================================
            Container(
              margin: const EdgeInsets.fromLTRB(14, 4, 14, 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: palette.panel,
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: palette.panelEdge, width: 0.8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // User info row
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: palette.glassFill(),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.person_rounded,
                            color: palette.text,
                            size: 22,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              userProfile?.fullName.isNotEmpty == true
                                  ? userProfile!.fullName
                                  : 'مستخدم CineBall',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: isDark ? Colors.white : Colors.black87,
                                letterSpacing: -0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (userProfile?.phone.isNotEmpty == true) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(
                                    Icons.phone_android_rounded,
                                    size: 13,
                                    color: isDark ? Colors.white38 : Colors.black38,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      userProfile!.phone,
                                      style: TextStyle(
                                        fontSize: 11.5,
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

                  const SizedBox(height: 10),
                  const Divider(height: 1, thickness: 0.8),
                  const SizedBox(height: 8),

                  // Subscription status
                  if (isSportsUnlocked) ...[
                    Row(
                      children: [
                        // The animation carries the «active» half of what
                        // two lines of text used to say, so the words are
                        // down to the one thing it cannot show: how long is
                        // left.
                        const _SubscriptionMark(),
                        const SizedBox(width: 8),
                        const Text(
                          'المباريات',
                          style: TextStyle(
                            color: AppColors.success,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${sportsSub?.remainingDays ?? 0} يوم',
                          style: const TextStyle(
                            color: AppColors.success,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Icon(
                          Icons.sports_soccer_rounded,
                          size: 16,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'المباريات غير مفعّلة',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 28,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              context.push('/sports-activation');
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isDark
                                  ? Colors.white.withOpacity(0.12)
                                  : const Color(0xFF1E293B),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 0),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              'اشتراك',
                              style: TextStyle(
                                fontSize: 11.5,
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
                    icon: Icons.live_tv_rounded,
                    title: 'المسلسلات',
                    isSelected: currentPath == '/cinemana/series',
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/cinemana/series');
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.auto_awesome_rounded,
                    title: 'الأنمي',
                    isSelected: currentPath == '/cinemana/anime',
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/cinemana/anime');
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.tv_rounded,
                    title: 'الدراما الآسيوية',
                    isSelected: currentPath == '/asia2tv',
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/asia2tv');
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.sports_soccer_rounded,
                    title: 'المباريات',
                    badgeText: null,
                    isSelected: currentPath == '/sports' ||
                        currentPath == '/sports-activation',
                    onTap: () {
                      Navigator.pop(context);
                      if (isSportsUnlocked) {
                        context.push('/sports');
                      } else {
                        context.push('/sports-activation');
                      }
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

                  const SizedBox(height: 10),

                  _DrawerItem(
                    icon: Icons.settings_suggest_rounded,
                    title: 'الإعدادات',
                    isSelected: currentPath == '/settings',
                    onTap: () {
                      Navigator.pop(context);
                      context.go('/settings');
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.info_rounded,
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
                color: Colors.transparent,
                border: Border(
                  top: BorderSide(color: palette.glassSheetEdge, width: 0.8),
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
                      errorBuilder: (_, __, ___) => SizedBox(
                        width: 28,
                        height: 28,
                        child: Icon(
                          Icons.play_circle_fill_rounded,
                          size: 24,
                          color: palette.text,
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
          ),
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
    final p = AppPalette.of(context);
    final iconColor = p.text;
    final labelColor = isSelected ? p.text : p.onGlassMuted;

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
              color: isSelected ? p.glassFill(selected: true) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: isSelected ? Border.all(color: p.glassFillEdge(selected: true), width: 0.8) : null,
            ),
            child: Stack(
              // Centred: the row used to sit along the top of its band.
              alignment: AlignmentDirectional.centerStart,
              children: [
                // Active marker: a slim white bar hugging the start edge.
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
                          color: p.text,
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
    final p = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: p.glassFill(selected: true),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.glassFillEdge(selected: true), width: 0.8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: p.text,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          height: 1.2,
        ),
      ),
    );
  }
}

/// The mark beside «المباريات» when the subscription is live.
///
/// An animation rather than a tick because it is saying something a static
/// icon cannot: that the thing is running right now. It loops quietly and
/// is small enough to sit on a line of text.
class _SubscriptionMark extends StatelessWidget {
  const _SubscriptionMark();

  @override
  Widget build(BuildContext context) {
    // Anyone who has asked the system for less motion gets the plain tick.
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      return const Icon(Icons.verified_rounded, size: 26, color: AppColors.success);
    }

    return SizedBox(
      width: 34,
      height: 34,
      child: Lottie.asset(
        'assets/animations/screencast.json',
        repeat: true,
        fit: BoxFit.contain,
        // A drawer that cannot load one asset is not a drawer worth
        // failing: the tick says the same thing.
        errorBuilder: (_, __, ___) => const Icon(
          Icons.verified_rounded,
          size: 18,
          color: AppColors.success,
        ),
      ),
    );
  }
}
