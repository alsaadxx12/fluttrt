import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';
import '../widgets/app_bottom_bar.dart';
import 'package:youtube_downloader/features/casting/widgets/cast_mini_controller.dart';
import '../widgets/app_drawer.dart';
import '../widgets/app_header.dart';
import '../widgets/app_sidebar.dart';
import '../../features/watch/presentation/providers/watch_provider.dart';
import '../../core/tv/tv_mode.dart';

final GlobalKey<ScaffoldState> mainScaffoldKey = GlobalKey<ScaffoldState>();

class MainScaffold extends ConsumerWidget {
  /// The shell's pages, kept side by side in an IndexedStack so leaving one
  /// for another never rebuilds it.
  final StatefulNavigationShell navigationShell;
  final String location;

  const MainScaffold({
    super.key,
    required this.navigationShell,
    required this.location,
  });

  int _calculateSelectedIndex(String loc) {
    if (loc.startsWith('/downloads')) return 1;
    if (loc.startsWith('/settings')) return 2;
    if (loc.startsWith('/about')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Widget child = navigationShell;
    final isFullscreen = ref.watch(watchProvider.select((s) => s.isFullscreen));

    // When video is in fullscreen, hide top header, sidebar, and expand page ONLY on video!
    if (isFullscreen && location.startsWith('/watch')) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: child,
      );
    }

    final selectedIndex = _calculateSelectedIndex(location);
    // A television always uses the wide, Windows-style layout with the side
    // menu, whatever logical width it reports: a set-top box driven by a
    // remote should never fall into the narrow, drawer-based phone layout.
    final isTv = ref.watch(tvModeProvider).valueOrNull ?? false;
    final isDesktopPlatform = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final isTablet = MediaQuery.of(context).size.shortestSide >= 600;
    final isMobile = !isTv && !isDesktopPlatform && !isTablet;

    void onDestinationSelected(int index) {
      switch (index) {
        case 0:
          context.go('/');
          break;
        case 1:
          context.go('/downloads');
          break;
        case 2:
          context.go('/settings');
          break;
        case 3:
          context.go('/about');
          break;
      }
    }

    final isHome = location == '/';
    // The about page carries its own quiet header: no shared bar, no search.
    // The watch page starts with its player at the very top, like YouTube's,
    // so nothing may sit above it either. The reels page is a full-screen
    // player with its own top bar, and «قائمتي» carries its own compact
    // header.
    final isReels = location.startsWith('/reels');
    final isWatch = location.startsWith('/watch');
    final isBare = isHome ||
        location.startsWith('/about') ||
        isWatch ||
        isReels ||
        location.startsWith('/my-list');
    final palette = AppPalette.of(context);

    if (isMobile) {
      final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
      return Scaffold(
        backgroundColor: palette.bg,
        key: mainScaffoldKey,
        drawer: const AppDrawer(),
        body: isBare
            ? child
            : Column(
                children: [
                  if (!isLandscape) const AppHeader(),
                  Expanded(child: child),
                ],
              ),
        // The phone's bottom bar on every page of the shell but the YouTube
        // watch page, which — like YouTube's — has none; black over the reels.
        // Above it, while something plays on another screen, the strip that
        // says what and where — it takes no room when nothing is casting.
        bottomNavigationBar: (isWatch || isLandscape)
            ? null
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CastMiniController(),
                  AppBottomBar(location: location, dark: isReels),
                ],
              ),
      );
    }

    return Scaffold(
      backgroundColor: palette.bg,
      drawer: const AppDrawer(),
      body: Column(
        children: [
          if (!isBare) const AppHeader(),
          Expanded(
            child: Row(
              children: [
                AppSidebar(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: onDestinationSelected,
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

