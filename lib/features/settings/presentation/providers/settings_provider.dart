import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/core/localization/app_localizations.dart';
import 'package:youtube_downloader/core/services/storage_service.dart';

final storageServiceProvider = Provider<StorageService>((ref) {
  throw UnimplementedError('StorageService must be overridden in ProviderScope');
});

class SettingsState {
  final ThemeMode themeMode;
  final AppLanguage language;
  final String downloadFolder;
  final int maxConcurrentDownloads;
  final String defaultVideoQuality;
  final String defaultAudioFormat;
  final bool askBeforeOverwrite;

  const SettingsState({
    required this.themeMode,
    required this.language,
    required this.downloadFolder,
    required this.maxConcurrentDownloads,
    required this.defaultVideoQuality,
    required this.defaultAudioFormat,
    required this.askBeforeOverwrite,
  });

  SettingsState copyWith({
    ThemeMode? themeMode,
    AppLanguage? language,
    String? downloadFolder,
    int? maxConcurrentDownloads,
    String? defaultVideoQuality,
    String? defaultAudioFormat,
    bool? askBeforeOverwrite,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      language: language ?? this.language,
      downloadFolder: downloadFolder ?? this.downloadFolder,
      maxConcurrentDownloads: maxConcurrentDownloads ?? this.maxConcurrentDownloads,
      defaultVideoQuality: defaultVideoQuality ?? this.defaultVideoQuality,
      defaultAudioFormat: defaultAudioFormat ?? this.defaultAudioFormat,
      askBeforeOverwrite: askBeforeOverwrite ?? this.askBeforeOverwrite,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  final StorageService _storage;

  SettingsNotifier(this._storage)
      : super(
          SettingsState(
            themeMode: _storage.getThemeMode(),
            language: _storage.getLanguage(),
            downloadFolder: _storage.getDownloadFolder(),
            maxConcurrentDownloads: _storage.getMaxConcurrentDownloads(),
            defaultVideoQuality: _storage.getDefaultVideoQuality(),
            defaultAudioFormat: _storage.getDefaultAudioFormat(),
            askBeforeOverwrite: _storage.getAskBeforeOverwrite(),
          ),
        );

  Future<void> setThemeMode(ThemeMode mode) async {
    await _storage.setThemeMode(mode);
    state = state.copyWith(themeMode: mode);
  }

  Future<void> setLanguage(AppLanguage lang) async {
    await _storage.setLanguage(lang);
    state = state.copyWith(language: lang);
  }

  Future<bool> pickDownloadFolder() async {
    try {
      final selectedDirectory = await FilePicker.getDirectoryPath(
        dialogTitle: 'اختر مجلد التنزيل الافتراضي',
        initialDirectory: state.downloadFolder.isNotEmpty ? state.downloadFolder : null,
      );

      if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
        await _storage.setDownloadFolder(selectedDirectory);
        state = state.copyWith(downloadFolder: selectedDirectory);
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> setMaxConcurrentDownloads(int count) async {
    await _storage.setMaxConcurrentDownloads(count);
    state = state.copyWith(maxConcurrentDownloads: count);
  }

  Future<void> setDefaultVideoQuality(String quality) async {
    await _storage.setDefaultVideoQuality(quality);
    state = state.copyWith(defaultVideoQuality: quality);
  }

  Future<void> setDefaultAudioFormat(String format) async {
    await _storage.setDefaultAudioFormat(format);
    state = state.copyWith(defaultAudioFormat: format);
  }

  Future<void> setAskBeforeOverwrite(bool value) async {
    await _storage.setAskBeforeOverwrite(value);
    state = state.copyWith(askBeforeOverwrite: value);
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return SettingsNotifier(storage);
});

final stringsProvider = Provider<AppStrings>((ref) {
  final settings = ref.watch(settingsProvider);
  return AppStrings(settings.language);
});
