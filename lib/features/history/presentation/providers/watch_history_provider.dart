import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';

/// What the user has opened to watch, newest first, kept on the device.
///
/// A title is recorded when its player opens (film, series episode, anime);
/// opening it again moves it to the front. The list is capped so it stays a
/// quick "where was I" rather than an archive.
class WatchHistoryNotifier extends StateNotifier<List<CinemanaItem>> {
  WatchHistoryNotifier() : super(const []) {
    ready = _load();
  }

  static const String _key = 'watch_history_v1';
  static const int maxEntries = 60;

  /// Completes once the saved list has been read from the device. Every
  /// write waits for it, so an early [record] can never overwrite the
  /// history that was still loading. Never fails: a bad store just means an
  /// empty list.
  late final Future<void> ready;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((m) => CinemanaItem.fromJson(Map<String, dynamic>.from(m)))
          .where((e) => e.id.isNotEmpty)
          .toList();
      if (mounted) state = list;
    } catch (_) {
      // A corrupt entry must never break the app: start with an empty list.
    }
  }

  /// What gets stored for one entry.
  ///
  /// [CinemanaItem.toJson] is the API shape and leaves out a few fields that
  /// [CinemanaItem.fromJson] does read: the backdrop (`coverUrl`), season and
  /// episode numbers and the two dates. They are added here, under the keys
  /// `fromJson` expects, so an entry comes back exactly as it went in without
  /// the model having to change.
  static Map<String, dynamic> encode(CinemanaItem item) => {
        ...item.toJson(),
        'coverUrl': item.backdropUrl,
        'season': item.season,
        'episodeNummer': item.episodeNummer,
        'itemDate': item.itemDate,
        'mDate': item.mDate,
      };

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(state.map(encode).toList()));
    } catch (_) {}
  }

  /// Puts [item] at the front (removing any older copy of it).
  ///
  /// For a series or anime pass the show, not the episode: the history lists
  /// each title once.
  Future<void> record(CinemanaItem item) async {
    if (item.id.isEmpty) return;
    await ready;
    if (!mounted) return;
    final rest = state.where((e) => e.id != item.id).toList();
    state = [item, ...rest].take(maxEntries).toList();
    await _save();
  }

  Future<void> remove(String id) async {
    await ready;
    if (!mounted) return;
    state = state.where((e) => e.id != id).toList();
    await _save();
  }

  Future<void> clear() async {
    await ready;
    if (!mounted) return;
    state = const [];
    await _save();
  }
}

final watchHistoryProvider =
    StateNotifierProvider<WatchHistoryNotifier, List<CinemanaItem>>((ref) => WatchHistoryNotifier());
