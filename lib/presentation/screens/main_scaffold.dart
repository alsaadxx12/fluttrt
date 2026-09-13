import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';
import '../widgets/app_drawer.dart';
import '../widgets/app_header.dart';
import '../widgets/app_sidebar.dart';
import '../../features/watch/presentation/providers/watch_provider.dart';

final GlobalKey<ScaffoldState> mainScaffoldKey = GlobalKey<ScaffoldState>();

class MainScaffold extends ConsumerWidget {
  final Widget child;
  final String location;

  const MainScaffold({
    super.key,
    required this.child,
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
    final isFullscreen = ref.watch(watchProvider.select((s) => s.isFullscreen));

    // When video is in fullscreen, hide top header, sidebar, and expand page ONLY on video!
    if (isFullscreen && location.startsWith('/watch')) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: child,
      );
    }

    final selectedIndex = _calculateSelectedIndex(location);
    final isMobile = MediaQuery.of(context).size.width < 700;

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
    final isBare = isHome || location.startsWith('/about');
    final palette = AppPalette.of(context);

    if (isMobile) {
      return Scaffold(
        backgroundColor: palette.bg,
        key: mainScaffoldKey,
        drawer: const AppDrawer(),
        body: isBare
            ? child
            : Column(
                children: [
                  const AppHeader(),
                  Expanded(child: child),
                ],
              ),
        bottomNavigationBar: null,
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

