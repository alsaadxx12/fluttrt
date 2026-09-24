import 'dart:io';
import 'package:flutter/foundation.dart' show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'dart:async';

import 'package:flutter/gestures.dart' show GestureBinding;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:youtube_downloader/core/constants/app_theme.dart';
import 'package:youtube_downloader/core/localization/app_localizations.dart';
import 'package:youtube_downloader/core/scroll/app_scroll_physics.dart';
import 'package:youtube_downloader/core/services/storage_service.dart';
import 'package:youtube_downloader/features/settings/presentation/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:youtube_downloader/core/config/supabase_config.dart';
import 'package:youtube_downloader/router/app_router.dart';
import 'features/update/presentation/update_gate.dart';
import 'core/tv/tv_mode.dart';
import 'package:youtube_downloader/features/casting/services/cast_log.dart';
import 'package:youtube_downloader/features/casting/services/google_cast_service.dart';
import 'package:youtube_downloader/features/trailers/tmdb_config.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Touch events arrive on the screen's own clock, not the frame's: a
  // finger dragging a list delivers a sample a little before or after each
  // frame, and the list moves by uneven steps - the jitter that reads as
  // stutter on a 120 Hz screen. Resampling interpolates the touch to the
  // frame time, so every frame moves the list by exactly what the finger
  // did.
  GestureBinding.instance.resamplingEnabled = true;
  // Every `[cast]` line is kept for the diagnostics page from here on.
  CastLog.install();
  _registerFontLicense();
  // Initialize Supabase Authentication & Database
  try {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      // ignore: deprecated_member_use
      anonKey: SupabaseConfig.anonKey,
    );
  } catch (e) {
    debugPrint('Supabase init error: $e');
  }

  // Start the Cast framework here rather than when the sheet opens: Android
  // asks the options provider for the receiver id on its own schedule — when
  // it restores a session, or raises the media notification — and the id
  // comes from Dart, so it has to be in place before any of that.
  //
  // Not awaited, and on a leash: this is a platform channel into the Cast
  // SDK, and a handset where that SDK is unhappy can leave the call hanging
  // for good. Waiting for it here would hold up runApp and leave the viewer
  // looking at a white screen with no way out — a dead cast button is a far
  // smaller price.
  unawaited(
    GoogleCastService.ensureStarted().timeout(
      const Duration(seconds: 5),
      onTimeout: () => debugPrint('[cast] google cast did not start in time'),
    ),
  );

  // Load the bundled TMDB token if the build did not compile one in, so the
  // trailers section works whether or not --dart-define was passed.
  await TmdbConfig.ensureLoaded();
  // The app stays upright everywhere; only the video players turn.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // Keep the in-memory cache large enough so scrolling long feeds with hundreds
  // of posters and thumbnails retains decoded bitmaps without re-decoding lag.
  PaintingBinding.instance.imageCache.maximumSize = 3500;
  // 200 MB: enough for the whole home page decoded at 1x, and still well
  // below the budget that once starved the match WebView of tile memory.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 200 << 20; // 200 MB

  // MediaKit on every platform: the reels play through media_kit on Android
  // and iOS too (a video-only stream paired with a separate audio track).
  try {
    MediaKit.ensureInitialized();
  } catch (e) {
    debugPrint('MediaKit init error: $e');
  }

  // Desktop platforms (Windows, Linux, macOS)
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    try {
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
          if (Platform.isMacOS) {
            await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: true);
          } else {
            await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
          }
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

/// Puts the bundled font's licence on the app's own licences page.
///
/// Noto Sans Arabic ships inside the app rather than being fetched, and the
/// SIL Open Font License asks that its text travel with the font.
void _registerFontLicense() {
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(const ['Noto Sans Arabic'], text);
  });
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
      scrollBehavior: const AppScrollBehavior(),
      title: strings.appName,
      debugShowCheckedModeBanner: false,
      routerConfig: appRouter,
      // Night unless the settings say day (or leave it to the phone).
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

