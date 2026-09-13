import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_downloader/core/localization/app_localizations.dart';
import 'package:youtube_downloader/features/downloads/data/models/download_task_model.dart';

class StorageService {
  final SharedPreferences _prefs;

  StorageService(this._prefs);

  static const String _keyThemeMode = 'app_theme_mode';
  static const String _keyLanguage = 'app_language';
  static const String _keyDownloadFolder = 'app_download_folder';
  static const String _keyConcurrentDownloads = 'app_concurrent_downloads';
  static const String _keyDefaultVideoQuality = 'app_default_video_quality';
  static const String _keyDefaultAudioFormat = 'app_default_audio_format';
  static const String _keyAskOverwrite = 'app_ask_overwrite';
  static const String _keyDownloadHistory = 'app_download_history';

  static Future<StorageService> init() async {
    final prefs = await SharedPreferences.getInstance();
    final service = StorageService(prefs);
    await service._ensureDefaultFolder();
    return service;
  }

  Future<void> _ensureDefaultFolder() async {
    if (_prefs.getString(_keyDownloadFolder) == null) {
      Directory? downloadDir;
      try {
        if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
          downloadDir = await getDownloadsDirectory();
        }
      } catch (_) {}

      try {
        downloadDir ??= await getApplicationDocumentsDirectory();
      } catch (_) {}

      if (downloadDir != null) {
        await _prefs.setString(_keyDownloadFolder, downloadDir.path);
      }
    }
  }

  // --- Theme Mode ---
  ThemeMode getThemeMode() {
    final val = _prefs.getString(_keyThemeMode);
    if (val == 'light') return ThemeMode.light;
    if (val == 'dark') return ThemeMode.dark;
    return ThemeMode.system;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final str = mode == ThemeMode.light
        ? 'light'
        : mode == ThemeMode.dark
            ? 'dark'
            : 'system';
    await _prefs.setString(_keyThemeMode, str);
  }

  // --- Language ---
  AppLanguage getLanguage() {
    final code = _prefs.getString(_keyLanguage) ?? 'ar';
    return AppLanguage.fromCode(code);
  }

  Future<void> setLanguage(AppLanguage language) async {
    await _prefs.setString(_keyLanguage, language.code);
  }

  // --- Download Directory ---
  String getDownloadFolder() {
    return _prefs.getString(_keyDownloadFolder) ?? '';
  }

  Future<void> setDownloadFolder(String path) async {
    await _prefs.setString(_keyDownloadFolder, path);
  }

  // --- Settings Options ---
  int getMaxConcurrentDownloads() {
    return _prefs.getInt(_keyConcurrentDownloads) ?? 3;
  }

  Future<void> setMaxConcurrentDownloads(int value) async {
    await _prefs.setInt(_keyConcurrentDownloads, value);
  }

  String getDefaultVideoQuality() {
    return _prefs.getString(_keyDefaultVideoQuality) ?? '1080p';
  }

  Future<void> setDefaultVideoQuality(String quality) async {
    await _prefs.setString(_keyDefaultVideoQuality, quality);
  }

  String getDefaultAudioFormat() {
    return _prefs.getString(_keyDefaultAudioFormat) ?? 'mp3';
  }

  Future<void> setDefaultAudioFormat(String format) async {
    await _prefs.setString(_keyDefaultAudioFormat, format);
  }

  bool getAskBeforeOverwrite() {
    return _prefs.getBool(_keyAskOverwrite) ?? true;
  }

  Future<void> setAskBeforeOverwrite(bool value) async {
    await _prefs.setBool(_keyAskOverwrite, value);
  }

  // --- Download History Persistence ---
  List<DownloadTaskModel> getDownloadHistory() {
    final jsonString = _prefs.getString(_keyDownloadHistory);
    if (jsonString == null || jsonString.isEmpty) return [];

    try {
      final List<dynamic> list = jsonDecode(jsonString);
      return list
          .map((item) => DownloadTaskModel.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveDownloadHistory(List<DownloadTaskModel> tasks) async {
    final encoded = jsonEncode(tasks.map((t) => t.toJson()).toList());
    await _prefs.setString(_keyDownloadHistory, encoded);
  }
}
