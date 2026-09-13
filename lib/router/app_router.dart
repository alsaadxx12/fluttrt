import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/about/presentation/screens/about_screen.dart';
import '../features/cinemana/presentation/screens/cinemana_catalog_screen.dart';
import '../features/cinemana/presentation/screens/cinemana_favorites_screen.dart';
import '../features/downloads/presentation/screens/downloads_screen.dart';
import '../features/home/presentation/screens/home_screen.dart';
import '../features/home/presentation/screens/youtube_cinematic_screen.dart';
import '../features/settings/presentation/screens/settings_screen.dart';
import '../features/watch/presentation/screens/watch_screen.dart';
import '../features/sports/presentation/screens/sports_screen.dart';
import '../features/sports/data/models/sports_models.dart';
import '../features/sports/presentation/screens/channels_screen.dart';
import '../features/shahid/presentation/shahid_channels_screen.dart';
import '../presentation/screens/main_scaffold.dart';

import '../features/splash/presentation/screens/splash_screen.dart';
import '../features/cinemana/presentation/screens/cinemana_detail_screen.dart';
import '../features/cinemana/data/models/cinemana_models.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _shellNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/splash',
  routes: [
    GoRoute(
      path: '/splash',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const SplashScreen(),
    ),
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) {
        return MainScaffold(
          location: state.uri.path,
          child: child,
        );
      },
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: HomeScreen(),
          ),
        ),
        GoRoute(
          path: '/youtube_cinematic',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: YoutubeCinematicScreen(),
          ),
        ),
        GoRoute(
          path: '/watch',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: WatchScreen(),
          ),
        ),
        GoRoute(
          path: '/downloads',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: DownloadsScreen(),
          ),
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: SettingsScreen(),
          ),
        ),
        GoRoute(
          path: '/about',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: AboutScreen(),
          ),
        ),
      ],
    ),
    // Cinemana dedicated routes
    GoRoute(
      path: '/cinemana',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final tab = state.uri.queryParameters['tab'];
        final kind = (tab == '1')
            ? 'series'
            : (tab == '2')
                ? 'anime'
                : 'movies';
        return CinemanaCatalogScreen(kind: kind);
      },
    ),
    GoRoute(
      path: '/cinemana/movies',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const CinemanaCatalogScreen(kind: 'movies'),
    ),
    GoRoute(
      path: '/cinemana/series',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const CinemanaCatalogScreen(kind: 'series'),
    ),
    GoRoute(
      path: '/cinemana/anime',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const CinemanaCatalogScreen(kind: 'anime'),
    ),
    GoRoute(
      path: '/cinemana/favorites',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const CinemanaFavoritesScreen(),
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
      builder: (context, state) => const SportsScreen(),
    ),
    GoRoute(
      path: '/channels',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => ChannelsScreen(
        // A channel tapped elsewhere (e.g. the home row) opens straight away.
        initialChannel: state.extra is SportsChannel ? state.extra as SportsChannel : null,
      ),
    ),
    GoRoute(
      path: '/shahid/channels',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const ShahidChannelsScreen(),
    ),
  ],
);
