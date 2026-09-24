import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'app_colors.dart';
import '../localization/app_localizations.dart';

class AppTheme {
  AppTheme._();

  static const double borderRadius = 12.0;

  /// The Arabic face, bundled with the app (see pubspec.yaml).
  ///
  /// It used to come from google_fonts, which fetched it over the network on
  /// first launch: the app opened in a fallback face and re-laid out every
  /// line of text the moment the real one arrived. English keeps the
  /// platform's own default - Roboto on Android, San Francisco on iOS - which
  /// is already on the device and needs nothing fetched either.
  static const String arabicFamily = 'NotoSansArabic';

  /// The family every piece of text in the app is drawn with, or null to
  /// leave the platform's own default in place. Set on [ThemeData] as well as
  /// on the text theme, so the many hand-written `TextStyle`s on the cards -
  /// which name no family - inherit it too.
  static String? _fontFamilyFor(AppLanguage language) => language == AppLanguage.arabic ? arabicFamily : null;

  // Exact YouTube Typography: the platform face for English & Latin,
  // Noto Sans Arabic for Arabic.
  static TextTheme _getTextTheme(
    AppLanguage language,
    Brightness brightness,
    Color primaryTextColor,
    Color secondaryTextColor,
  ) {
    final typography = Typography.material2021(platform: defaultTargetPlatform);
    final defaults = brightness == Brightness.dark ? typography.white : typography.black;
    final family = _fontFamilyFor(language);
    final baseTextTheme = family == null ? defaults : defaults.apply(fontFamily: family);

    return baseTextTheme.copyWith(
      displayLarge: baseTextTheme.displayLarge?.copyWith(
        color: primaryTextColor,
        fontWeight: FontWeight.bold,
        letterSpacing: -0.5,
      ),
      headlineMedium: baseTextTheme.headlineMedium?.copyWith(
        color: primaryTextColor,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        color: primaryTextColor,
        fontWeight: FontWeight.w600,
        fontSize: 18,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        color: primaryTextColor,
        fontWeight: FontWeight.w600,
        fontSize: 14,
        height: 1.3,
      ),
      titleSmall: baseTextTheme.titleSmall?.copyWith(
        color: primaryTextColor,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(
        color: primaryTextColor,
        fontSize: 14,
      ),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(
        color: secondaryTextColor,
        fontSize: 12,
        height: 1.2,
      ),
      bodySmall: baseTextTheme.bodySmall?.copyWith(
        color: secondaryTextColor,
        fontSize: 11,
      ),
    );
  }

  /// Day mode: the same theme on a pale page with deep navy text.
  static ThemeData lightTheme(AppLanguage language) {
    final textTheme =
        _getTextTheme(language, Brightness.light, AppColors.lightTextPrimary, AppColors.lightTextSecondary);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: _fontFamilyFor(language),
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: AppColors.lightBg,
      canvasColor: AppColors.lightBg,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: Colors.white,
        primaryContainer: AppColors.primaryContainer,
        surface: AppColors.lightCard,
        onSurface: AppColors.lightTextPrimary,
        surfaceContainerHighest: AppColors.lightSecondaryBg,
        outline: AppColors.lightBorder,
        error: AppColors.error,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.lightBg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.lightTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.lightBg,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogTheme(
        backgroundColor: AppColors.lightCard,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(borderRadius)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.lightCard,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: AppColors.lightCard,
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: AppColors.lightCard,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardTheme(
        color: AppColors.lightCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          side: const BorderSide(color: AppColors.lightBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.lightSecondaryBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          borderSide: const BorderSide(color: AppColors.lightBorder, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          borderSide: const BorderSide(color: AppColors.lightBorder, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          borderSide: const BorderSide(color: AppColors.error, width: 1),
        ),
        hintStyle: TextStyle(color: AppColors.lightTextSecondary.withOpacity(0.7)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered) || states.contains(WidgetState.pressed)) {
              return AppColors.primaryDark;
            }
            if (states.contains(WidgetState.disabled)) {
              return AppColors.primary.withOpacity(0.4);
            }
            return AppColors.primary;
          }),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          elevation: const WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(borderRadius)),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.lightTextPrimary,
          side: const BorderSide(color: AppColors.lightBorder, width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(borderRadius)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(borderRadius)),
          ),
          side: const WidgetStatePropertyAll(
            BorderSide(color: AppColors.lightBorder, width: 1),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.primary;
            }
            return AppColors.lightSecondaryBg;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            return AppColors.lightTextPrimary;
          }),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.lightBorder,
        thickness: 1,
        space: 1,
      ),
      textTheme: textTheme,
    );
  }

  static ThemeData darkTheme(AppLanguage language) {
    final textTheme = _getTextTheme(language, Brightness.dark, AppColors.darkTextPrimary, AppColors.darkTextSecondary);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: _fontFamilyFor(language),
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: AppColors.darkBg,
      canvasColor: AppColors.darkBg,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        onPrimary: Colors.white,
        primaryContainer: AppColors.primaryContainer,
        surface: AppColors.darkCard,
        onSurface: AppColors.darkTextPrimary,
        surfaceContainerHighest: AppColors.darkSecondaryBg,
        outline: AppColors.darkBorder,
        error: AppColors.error,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkBg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.darkTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.darkBg,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogTheme(
        backgroundColor: AppColors.darkCard,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black54,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(borderRadius)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.darkCard,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: AppColors.darkCard,
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: AppColors.darkCard,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardTheme(
        color: AppColors.darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          side: const BorderSide(color: AppColors.darkBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkSecondaryBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          borderSide: const BorderSide(color: AppColors.darkBorder, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          borderSide: const BorderSide(color: AppColors.darkBorder, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          borderSide: const BorderSide(color: AppColors.error, width: 1),
        ),
        hintStyle: TextStyle(color: AppColors.darkTextSecondary.withOpacity(0.7)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered) || states.contains(WidgetState.pressed)) {
              return AppColors.primaryDark;
            }
            if (states.contains(WidgetState.disabled)) {
              return AppColors.primary.withOpacity(0.4);
            }
            return AppColors.primary;
          }),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          elevation: const WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(borderRadius)),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.darkTextPrimary,
          side: const BorderSide(color: AppColors.darkBorder, width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(borderRadius)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(borderRadius)),
          ),
          side: const WidgetStatePropertyAll(
            BorderSide(color: AppColors.darkBorder, width: 1),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.primary;
            }
            return AppColors.darkSecondaryBg;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            return AppColors.darkTextPrimary;
          }),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.darkBorder,
        thickness: 1,
        space: 1,
      ),
      textTheme: textTheme,
    );
  }
}
