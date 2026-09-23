import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_downloader/features/casting/services/resume_store.dart';
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';

import '../../data/watch_history_entry.dart';
import '../../data/watch_history_service.dart';

/// What the user has watched, newest first, with how far each got.
///
/// A title is recorded when its player opens — on the phone or on a
/// television — and moves to the front each time; the position is written
/// down as it plays. The list lives on the device and, for a signed-in
/// user, in the cloud as well, so another phone signed in as the same
/// person sees the same list and picks the film up from the same minute.
class WatchHistoryNotifier extends StateNotifier<List<WatchHistoryEntry>> {
  WatchHistoryNotifier({WatchHistoryService? service, bool cloud = true})
      : _service = service ?? (cloud ? WatchHistoryService.tryCreate() : null),
        super(const []) {
    ready = _load();
  }

  static const String _key = 'watch_history_v2';
  static const String _legacyKey = 'watch_history_v1';

  /// Kept on the device, at most. The page shows the newest [shown] of
  /// them unless a search is on.
  static const int maxEntries = 60;

  /// How many the page shows without a search.
  static const int shown = 10;

  /// How often a position update goes to the cloud, per title.
  static const Duration _cloudEvery = Duration(seconds: 15);

  final WatchHistoryService? _service;
  final Map<String, DateTime> _lastSent = <String, DateTime>{};

  /// Completes once the saved list has been read from the device and,
  /// when signed in, merged with the cloud's copy. Every write waits for
  /// it, so an early [record] can never overwrite the history that was
  /// still loading. Never fails: a bad store just means an empty list.
  late final Future<void> ready;

  Future<void> _load() async {
    var local = <WatchHistoryEntry>[];
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        local = (jsonDecode(raw) as List)
            .whereType<Map>()
            .map((m) => WatchHistoryEntry.fromJson(Map<String, dynamic>.from(m)))
            .whereType<WatchHistoryEntry>()
            .toList();
      } else {
        // The list from before positions were kept: the titles, in order,
        // with no minute to go back to.
        final legacy = prefs.getString(_legacyKey);
        if (legacy != null && legacy.isNotEmpty) {
          var age = 0;
          local = (jsonDecode(legacy) as List)
              .whereType<Map>()
              .map((m) => CinemanaItem.fromJson(Map<String, dynamic>.from(m)))
              .where((e) => e.id.isNotEmpty)
              .map((item) => WatchHistoryEntry(
                    item: item,
                    videoId: item.id,
                    watchedAt: DateTime.now().subtract(Duration(minutes: age++)),
                  ))
              .toList();
        }
      }
    } catch (_) {
      // A corrupt entry must never break the app: start with an empty list.
    }
    if (mounted) state = local;

    final service = _service;
    if (service == null || !service.signedIn) return;
    final cloud = await service.fetch(limit: maxEntries);
    if (!mounted) return;
    if (cloud.isEmpty) {
      // A fresh cloud, or one that did not answer. What is here goes up so
      // the next device sees it; nothing is taken away.
      for (final entry in state) {
        unawaited(service.upsert(entry));
      }
      return;
    }
    state = _merged(state, cloud);
    await _save();
    // The minute each film was left at, so the player on this device
    // starts there too.
    for (final entry in state) {
      if (entry.hasPosition) {
        unawaited(ResumeStore.save(entry.videoId, entry.position, duration: entry.duration));
      }
    }
  }

  /// One list from two, newest first; where both hold a title, the one
  /// watched later wins.
  static List<WatchHistoryEntry> _merged(
    List<WatchHistoryEntry> a,
    List<WatchHistoryEntry> b,
  ) {
    final byId = <String, WatchHistoryEntry>{};
    for (final entry in [...a, ...b]) {
      final have = byId[entry.item.id];
      if (have == null || entry.watchedAt.isAfter(have.watchedAt)) {
        byId[entry.item.id] = entry;
      }
    }
    final list = byId.values.toList()..sort((x, y) => y.watchedAt.compareTo(x.watchedAt));
    return list.take(maxEntries).toList();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(state.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  /// Puts [item] at the front, as the thing being watched now.
  ///
  /// For a series or anime pass the show and the [episode]: the history
  /// lists each title once, with the episode it is on. The position is
  /// whatever was written down for that episode before, so the entry says
  /// «you were at 42:10» from the moment the player opens.
  Future<void> record(CinemanaItem item, {CinemanaEpisode? episode}) async {
    if (item.id.isEmpty) return;
    await ready;
    if (!mounted) return;
    final videoId = episode?.id ?? item.id;
    final previous = state.where((e) => e.item.id == item.id).firstOrNull;
    final sameEpisode = previous != null && previous.videoId == videoId;
    final position = sameEpisode
        ? previous.position
        : (await ResumeStore.read(videoId) ?? Duration.zero);
    if (!mounted) return;
    final entry = WatchHistoryEntry(
      item: item,
      videoId: videoId,
      episodeLabel: WatchHistoryEntry.labelFor(episode),
      position: position,
      duration: sameEpisode ? previous.duration : null,
      watchedAt: DateTime.now(),
    );
    state = [entry, ...state.where((e) => e.item.id != item.id)].take(maxEntries).toList();
    await _save();
    _lastSent[item.id] = DateTime.now();
    unawaited(_service?.upsert(entry) ?? Future<void>.value());
  }

  /// Writes down where [videoId] has got to — from the phone's player or
  /// from a television. The device copy every time; the cloud every
  /// [_cloudEvery], or at once when [now] says so (a pause, a stop).
  Future<void> updatePosition(
    String videoId,
    Duration position, {
    Duration? duration,
    bool now = false,
  }) async {
    await ready;
    if (!mounted) return;
    final index = state.indexWhere((e) => e.videoId == videoId);
    if (index < 0) return;
    final was = state[index];
    if (was.position == position && (duration == null || was.duration == duration)) return;
    final entry = was.copyWith(
      position: position,
      duration: duration ?? was.duration,
      watchedAt: DateTime.now(),
    );
    // To the front: it is the thing being watched.
    state = [entry, ...state.where((e) => e.item.id != entry.item.id)];
    await _save();

    final service = _service;
    if (service == null) return;
    final sent = _lastSent[entry.item.id];
    if (now || sent == null || DateTime.now().difference(sent) >= _cloudEvery) {
      _lastSent[entry.item.id] = DateTime.now();
      unawaited(service.upsert(entry));
    }
  }

  Future<void> remove(String id) async {
    await ready;
    if (!mounted) return;
    state = state.where((e) => e.item.id != id).toList();
    await _save();
    unawaited(_service?.delete(id) ?? Future<void>.value());
  }

  Future<void> clear() async {
    await ready;
    if (!mounted) return;
    state = const [];
    await _save();
    unawaited(_service?.clear() ?? Future<void>.value());
  }
}

final watchHistoryProvider =
    StateNotifierProvider<WatchHistoryNotifier, List<WatchHistoryEntry>>(
        (ref) => WatchHistoryNotifier());
