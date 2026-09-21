import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:youtube_downloader/core/network/image_cache.dart';
import 'package:youtube_downloader/core/tv/tv_mode.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';
import 'package:youtube_downloader/features/cinemana/presentation/providers/cinemana_provider.dart';
import 'package:youtube_downloader/features/reels/presentation/providers/reels_feed_provider.dart';
import 'package:youtube_downloader/features/sports/presentation/providers/sports_provider.dart';
import 'package:youtube_downloader/features/auth/presentation/providers/auth_provider.dart';
import 'package:youtube_downloader/features/subscription/presentation/providers/subscription_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.2, 1.0, curve: Curves.easeIn),
    );

    _controller.forward();

    final session = Supabase.instance.client.auth.currentSession;
    final minWait = Future<void>.delayed(const Duration(milliseconds: 900));

    if (session == null) {
      // No active session: show splash animation then transition to login
      minWait.then((_) {
        if (mounted) {
          context.go('/login');
        }
      });
      return;
    }

    // Active session: load user profile & subscription in background
    ref.read(userProfileProvider.notifier).reload();
    ref.read(sportsSubscriptionProvider.notifier).refresh();

    // Warm the home while the logo animates, so it opens already filled
    // instead of loading in front of the user. Reading a provider is enough
    // to start its request, and none of these auto-dispose. The hero and the
    // first rows go first; the rest follow a moment later so they do not all
    // fight for the connection at once.
    final Future<List<CinemanaItem>> hero = ref.read(heroBannerMoviesProvider.future);
    ref.read(homeRecentlyAddedProvider);
    ref.read(homeLatestMoviesProvider);
    ref.read(sportsNotifierProvider('today'));
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      ref.read(homeLatestSeriesProvider);
      ref.read(homeAnimeProvider);
      ref.read(homeMostViewedProvider);
      ref.read(homeArabicMoviesProvider);
      ref.read(homeArabicSeriesProvider);
      // The scenes tab: its first page takes a few searches and probes, so
      // it starts now and is ready by the time the tab is opened.
      ref.read(reelsFeedProvider);
    });

    // The first hero slide is decoded here, under the exact cache key the
    // home hero asks for, so it is on screen the instant the home appears.
    final Future<void> heroSettled = hero.then<void>((movies) {
      if (mounted && movies.isNotEmpty) _precacheFirstHeroSlide(movies.first);
    }).catchError((_) {});

    // Leave once the logo has had its 900 ms and the hero has answered
    // (success or error), but never later than 1600 ms in total.
    Future.any<void>([
      Future.wait<void>([heroSettled, minWait]),
      Future<void>.delayed(const Duration(milliseconds: 1600)),
    ]).then((_) {
      if (mounted) {
        context.go('/');
      }
    });
  }

  /// Mirrors the home hero's image choice and decode size exactly (see
  /// `_buildHeroFullPoster` / `_precacheNextHeroSlides` in home_screen.dart):
  /// on phones the high-res poster, decoded at the hero's own pixel width;
  /// on desktop the wide cover (or backdrop, or poster) at native size, plus
  /// the 400px blurred copy a poster gets behind it.
  ///
  /// The hero sizes itself from the width it is given, not the screen's: from
  /// 700px up (and on a television) MainScaffold puts the 240px AppSidebar
  /// beside the page, so that much comes off first.
  void _precacheFirstHeroSlide(CinemanaItem m) {
    final mq = MediaQuery.of(context);
    final isTv = ref.read(tvModeProvider).valueOrNull ?? false;
    final hasSidebar = isTv || mq.size.width >= 700;
    final availableWidth = hasSidebar ? mq.size.width - 240 : mq.size.width;
    final isDesktop = availableWidth >= 700;
    final wideCover = (m.backdropUrl != null && m.backdropUrl!.isNotEmpty && m.backdropUrl!.contains('cover'))
        ? m.backdropUrl!
        : '';
    final highResPoster = (m.imgUrl != null && m.imgUrl!.isNotEmpty) ? m.imgUrl! : m.bestPosterUrl;
    final url = isDesktop
        ? (wideCover.isNotEmpty ? wideCover : (m.bestBackdropUrl.isNotEmpty ? m.bestBackdropUrl : highResPoster))
        : (highResPoster.isNotEmpty ? highResPoster : m.bestBackdropUrl);
    if (url.isEmpty) return;
    final base = CachedNetworkImageProvider(url, cacheManager: appImageCache);
    if (isDesktop) {
      precacheImage(base, context, onError: (_, __) {});
      if (wideCover.isEmpty) {
        precacheImage(ResizeImage(base, width: 400), context, onError: (_, __) {});
      }
    } else {
      precacheImage(
        ResizeImage(base, width: (availableWidth * mq.devicePixelRatio).round()),
        context,
        onError: (_, __) {},
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // White, like every page after it, so the home appears in place with no
    // dark-to-white jump.
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Ambient Crimson Background Glow
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFE50914).withOpacity(0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Center: Animated Logo, App Name & Slogan
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ScaleTransition(
                  scale: _scaleAnimation,
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFE50914).withOpacity(0.45),
                          blurRadius: 30,
                          spreadRadius: 2,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: Image.asset(
                        'assets/images/app_logo.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Container(
                          color: const Color(0xFFE50914),
                          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 50),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: const Column(
                    children: [
                      Text(
                        'CINEBALL',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.5,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'سينما ومباريات بلا حدود',
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Bottom: Developer Credit
          Positioned(
            left: 0,
            right: 0,
            bottom: 30,
            child: SafeArea(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'تطوير',
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.2,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'ALI ALSAADY',
                      style: TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
