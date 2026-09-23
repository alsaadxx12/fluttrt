import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where each film was left, so the next viewing starts there.
///
/// Kept by the catalogue's video id — the film's, or the episode's — so the
/// phone's player and a television pick up from the same place whichever
/// of them was watching last. Positions in the first half minute are not
/// worth keeping, and a film watched to within a couple of minutes of its
/// end is a film finished, and starts over.
class ResumeStore {
  ResumeStore._();

  static const String _key = 'resume_positions_v1';
  static const int _maxEntries = 200;

  /// Under this, it was not really started.
  static const Duration _tooEarly = Duration(seconds: 30);

  /// Within this of the end, it was finished.
  static const Duration _nearEnd = Duration(minutes: 2);

  static Map<String, dynamic>? _cache;

  static Future<Map<String, dynamic>> _all() async {
    final cached = _cache;
    if (cached != null) return cached;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      final map = raw == null || raw.isEmpty
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return _cache = map;
    } catch (_) {
      return _cache = <String, dynamic>{};
    }
  }

  /// Where [videoId] was left, or null when it was never left anywhere.
  static Future<Duration?> read(String videoId) async {
    final entry = (await _all())[videoId];
    if (entry is! Map) return null;
    final seconds = entry['s'];
    if (seconds is! num || seconds <= 0) return null;
    return Duration(seconds: seconds.round());
  }

  /// Remembers that [videoId] is at [position], of [duration] when known.
  static Future<void> save(String videoId, Duration position, {Duration? duration}) async {
    if (videoId.isEmpty) return;
    final all = await _all();
    final finished = duration != null &&
        duration > Duration.zero &&
        duration - position < _nearEnd;
    if (position < _tooEarly || finished) {
      if (all.remove(videoId) != null) await _flush(all);
      return;
    }
    final previous = all[videoId];
    if (previous is Map && previous['s'] == position.inSeconds) return;
    all[videoId] = {'s': position.inSeconds, 'at': DateTime.now().millisecondsSinceEpoch};
    if (all.length > _maxEntries) {
      // The oldest go first.
      final entries = all.entries.toList()
        ..sort((a, b) {
          final x = (a.value as Map)['at'] as num? ?? 0;
          final y = (b.value as Map)['at'] as num? ?? 0;
          return x.compareTo(y);
        });
      for (final e in entries.take(all.length - _maxEntries)) {
        all.remove(e.key);
      }
    }
    await _flush(all);
  }

  /// Forgets [videoId]: the film was finished, or the viewer said so.
  static Future<void> clear(String videoId) async {
    final all = await _all();
    if (all.remove(videoId) != null) await _flush(all);
  }

  static Future<void> _flush(Map<String, dynamic> all) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(all));
    } catch (e) {
      debugPrint('[resume] could not save: $e');
    }
  }

  /// Forgets everything, and the copy in memory — for a test.
  @visibleForTesting
  static Future<void> reset() async {
    _cache = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
