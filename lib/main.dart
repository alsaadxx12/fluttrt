import 'package:flutter/gestures.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:youtube_downloader/core/constants/app_theme.dart';
import 'package:youtube_downloader/core/localization/app_localizations.dart';
import 'package:youtube_downloader/core/services/storage_service.dart';
import 'package:youtube_downloader/features/settings/presentation/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_downloader/router/app_router.dart';
import 'features/update/presentation/update_gate.dart';
import 'core/tv/tv_mode.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The app stays upright everywhere; only the video players turn.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // Keep the image cache modest. Every cached image is a GPU texture, and a
  // 400MB budget let the home screen hold ~555MB of them - which starved the
  // WebView of tile memory and made the match stream render black
  // ("tile memory limits exceeded" in logcat). Images are now decoded at the
  // size they are drawn, so this is ample.
  PaintingBinding.instance.imageCache.maximumSize = 400;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 80 << 20; // 80 MB
  GoogleFonts.config.allowRuntimeFetching = true;

  // Initialize MediaKit only on desktop platforms (Windows, Linux, macOS)
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    try {
      MediaKit.ensureInitialized();
      // video_player has no Windows implementation, so every film and series
      // player threw on open there. This hands video_player's calls to
      // media_kit, and the existing players run unchanged.
      VideoPlayerMediaKit.ensureInitialized(windows: true, linux: true, macOS: true);
    } catch (e) {
      debugPrint('MediaKit init error: $e');
    }

    try {
      await windowManager.ensureInitialized();
      const windowOptions = WindowOptions(
        title: 'CINEBALL',
        size: Size(1280, 800),
        minimumSize: Size(960, 640),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.hidden,
      );
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        try {
          await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
        } catch (_) {}
        await windowManager.show();
        await windowManager.focus();
      });
    } catch (e) {
      debugPrint('WindowManager init error: $e');
    }
  }

  // Initialize Storage Service (SharedPreferences & default folders)
  late final StorageService storageService;
  try {
    storageService = await StorageService.init();
  } catch (e) {
    debugPrint('StorageService init error: $e');
    final prefs = await SharedPreferences.getInstance();
    storageService = StorageService(prefs);
  }

  runApp(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storageService),
      ],
      child: const YouTubeDownloaderApp(),
    ),
  );
}

class YouTubeDownloaderApp extends ConsumerWidget {
  const YouTubeDownloaderApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final strings = ref.watch(stringsProvider);

    final isArabic = settings.language == AppLanguage.arabic;
    final locale = Locale(settings.language.code);

    return MaterialApp.router(
      scrollBehavior: const _NoStretchScrollBehavior(),
      title: strings.appName,
      debugShowCheckedModeBanner: false,
      routerConfig: appRouter,
      themeMode: settings.themeMode,
      theme: AppTheme.lightTheme(settings.language),
      darkTheme: AppTheme.darkTheme(settings.language),
      locale: locale,
      supportedLocales: const [
        Locale('ar'),
        Locale('en'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        // On a television the viewer is metres away, so everything is
        // scaled up a step. Anywhere else this resolves to false and the
        // layout is untouched.
        final isTv = ref.watch(tvModeProvider).valueOrNull ?? false;
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: isTv
              ? media.copyWith(textScaler: const TextScaler.linear(TvMode.textScale))
              : media,
          child: Directionality(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            // Self-update prompt (checked in the background after start-up).
            child: UpdateGate(child: child ?? const SizedBox.shrink()),
          ),
        );
      },
    );
  }
}

/// Lists stop dead at their edges: no stretch and no glow when pulled past
/// the end, so pull-to-refresh only shows its spinner.
class _NoStretchScrollBehavior extends MaterialScrollBehavior {
  const _NoStretchScrollBehavior();

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;

  // Every list can be grabbed and dragged, with a mouse or a finger. Without
  // the mouse here a desktop user can only reach a row's end with the tiny
  // scrollbar; with it, press-and-drag scrolls the cards like a touch screen.
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}
