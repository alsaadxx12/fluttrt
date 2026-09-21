import 'package:flutter/cupertino.dart' show CupertinoPage;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/about/presentation/screens/about_screen.dart';
import '../features/cinemana/presentation/screens/cinemana_catalog_screen.dart';
import '../features/cinemana/presentation/screens/cinemana_favorites_screen.dart';
import '../features/downloads/presentation/screens/downloads_screen.dart';
import '../features/history/presentation/screens/watch_history_screen.dart';
import '../features/home/presentation/screens/home_screen.dart';
import '../features/home/presentation/screens/youtube_cinematic_screen.dart';
import '../features/mylist/presentation/screens/my_list_screen.dart';
import '../features/reels/presentation/screens/reels_screen.dart';
import '../features/settings/presentation/screens/settings_screen.dart';
import '../features/watch/presentation/screens/watch_screen.dart';
import '../features/sports/presentation/screens/sports_screen.dart';
import '../presentation/screens/main_scaffold.dart';

import '../features/splash/presentation/screens/splash_screen.dart';
import '../features/cinemana/presentation/screens/cinemana_detail_screen.dart';
import '../features/cinemana/data/models/cinemana_models.dart';
import '../features/auth/presentation/screens/login_screen.dart';
import '../features/auth/presentation/screens/register_screen.dart';
import '../features/subscription/presentation/screens/sports_activation_screen.dart';
import '../features/asia2tv/data/models/asia2tv_models.dart';
import '../features/asia2tv/presentation/screens/asia2tv_category_screen.dart';
import '../features/asia2tv/presentation/screens/asia2tv_details_screen.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();
// One navigator per page of the main shell. The pages sit side by side in an
// IndexedStack, so going from the home to settings (or anywhere else in the
// shell) and back keeps the home built: its scroll position, its rows and
// its already-decoded posters are all still there.
final GlobalKey<NavigatorState> _homeNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'home');
final GlobalKey<NavigatorState> _youtubeNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'youtube');
final GlobalKey<NavigatorState> _watchNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'watch');
final GlobalKey<NavigatorState> _settingsNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'settings');
final GlobalKey<NavigatorState> _aboutNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'about');
final GlobalKey<NavigatorState> _downloadsNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'downloads');
final GlobalKey<NavigatorState> _reelsNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'reels');
final GlobalKey<NavigatorState> _myListNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'myList');

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/splash',
  routes: [
    GoRoute(
      path: '/splash',
      parentNavigatorKey: _rootNavigatorKey,
      // No transition: the splash is already white, so the home simply
      // appears in its place with no zoom or fade in between.
      pageBuilder: (context, state) => NoTransitionPage(
        key: state.pageKey,
        child: const SplashScreen(),
      ),
    ),
    StatefulShellRoute.indexedStack(
      parentNavigatorKey: _rootNavigatorKey,
      // A page with no transition of its own: the entering page decides the
      // animation, so a default (Material, zooming) page here would still
      // zoom the home in over the splash.
      pageBuilder: (context, state, navigationShell) => NoTransitionPage(
        key: state.pageKey,
        child: MainScaffold(
          location: state.uri.path,
          navigationShell: navigationShell,
        ),
      ),
      branches: [
        StatefulShellBranch(
          navigatorKey: _homeNavigatorKey,
          routes: [
            GoRoute(
              path: '/',
              pageBuilder: (context, state) => NoTransitionPage(
                key: state.pageKey,
                child: const HomeScreen(),
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _youtubeNavigatorKey,
          routes: [
            GoRoute(
              path: '/youtube_cinematic',
              pageBuilder: (context, state) => NoTransitionPage(
                key: state.pageKey,
                child: const YoutubeCinematicScreen(),
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _watchNavigatorKey,
          routes: [
            GoRoute(
              path: '/watch',
              pageBuilder: (context, state) => NoTransitionPage(
                key: state.pageKey,
                child: const WatchScreen(),
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _downloadsNavigatorKey,
          routes: [
            GoRoute(
              path: '/downloads',
              pageBuilder: (context, state) => NoTransitionPage(
                key: state.pageKey,
                child: const DownloadsScreen(),
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _settingsNavigatorKey,
          routes: [
            GoRoute(
              path: '/settings',
              pageBuilder: (context, state) => NoTransitionPage(
                key: state.pageKey,
                child: const SettingsScreen(),
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _aboutNavigatorKey,
          routes: [
            GoRoute(
              path: '/about',
              pageBuilder: (context, state) => NoTransitionPage(
                key: state.pageKey,
                child: const AboutScreen(),
              ),
            ),
          ],
        ),
        // The reels player and «قائمتي» are reached from the bottom bar, so
        // they are pages of the shell like the home: the bar stays under
        // them and switching back and forth keeps each one built.
        StatefulShellBranch(
          navigatorKey: _reelsNavigatorKey,
          routes: [
            GoRoute(
              path: '/reels',
              pageBuilder: (context, state) => NoTransitionPage(
                key: state.pageKey,
                child: const ReelsScreen(),
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _myListNavigatorKey,
          routes: [
            GoRoute(
              path: '/my-list',
              pageBuilder: (context, state) => NoTransitionPage(
                key: state.pageKey,
                child: const MyListScreen(),
              ),
            ),
          ],
        ),
      ],
    ),
    // Cinemana dedicated routes. Cupertino pages: the catalogue screens have
    // no back button, so they are left by swiping from the edge, like sports.
    GoRoute(
      path: '/cinemana',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) {
        final tab = state.uri.queryParameters['tab'];
        final kind = (tab == '1')
            ? 'series'
            : (tab == '2')
                ? 'anime'
                : 'movies';
        return CupertinoPage(key: state.pageKey, child: CinemanaCatalogScreen(kind: kind));
      },
    ),
    GoRoute(
      path: '/cinemana/movies',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) =>
          CupertinoPage(key: state.pageKey, child: const CinemanaCatalogScreen(kind: 'movies')),
    ),
    GoRoute(
      path: '/cinemana/series',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) =>
          CupertinoPage(key: state.pageKey, child: const CinemanaCatalogScreen(kind: 'series')),
    ),
    GoRoute(
      path: '/cinemana/anime',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) =>
          CupertinoPage(key: state.pageKey, child: const CinemanaCatalogScreen(kind: 'anime')),
    ),
    GoRoute(
      path: '/history',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => CupertinoPage(key: state.pageKey, child: const WatchHistoryScreen()),
    ),
    GoRoute(
      path: '/cinemana/favorites',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => CupertinoPage(key: state.pageKey, child: const CinemanaFavoritesScreen()),
    ),
    GoRoute(
      path: '/cinemana/detail',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final item = state.extra as CinemanaItem;
        return CinemanaDetailScreen(item: item);
      },
    ),
    GoRoute(
      path: '/sports',
      parentNavigatorKey: _rootNavigatorKey,
      // A Cupertino page so the matches screen (which has no back button) is
      // left by swiping from the edge — start-edge, mirrored for RTL — the
      // way the user asked, without fighting the page's horizontal lists.
      pageBuilder: (context, state) => CupertinoPage(key: state.pageKey, child: const SportsScreen()),
    ),
    GoRoute(
      path: '/sports-activation',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => CupertinoPage(key: state.pageKey, child: const SportsActivationScreen()),
    ),
    GoRoute(
      path: '/login',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => NoTransitionPage(key: state.pageKey, child: const LoginScreen()),
    ),
    GoRoute(
      path: '/register',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => CupertinoPage(key: state.pageKey, child: const RegisterScreen()),
    ),
    GoRoute(
      path: '/asia2tv',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) {
        final cat = state.extra is Asia2TvCategory ? state.extra as Asia2TvCategory : Asia2TvCategory.newEpisodes;
        return CupertinoPage(key: state.pageKey, child: Asia2TvCategoryScreen(initialCategory: cat));
      },
    ),
    GoRoute(
      path: '/asia2tv/details',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final item = state.extra as Asia2TvItem;
        return Asia2TvDetailsScreen(item: item);
      },
    ),
  ],
);
