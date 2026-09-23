import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'watch_history_entry.dart';

/// The history in the cloud, one row per user and title.
///
/// Every method is safe to call signed out or with the table missing: the
/// history lives on the device first and the cloud is a copy of it, so a
/// cloud that answers with an error is a warning in the log and nothing
/// else. See `supabase/migrations/06_watch_history.sql` for the table.
class WatchHistoryService {
  WatchHistoryService({required SupabaseClient client}) : _client = client;

  /// The service on the app's own client, or null before Supabase is up —
  /// a test, or a start-up that failed — in which case the history is
  /// kept on the device alone.
  static WatchHistoryService? tryCreate() {
    try {
      return WatchHistoryService(client: Supabase.instance.client);
    } catch (_) {
      return null;
    }
  }

  static const String _table = 'watch_history';

  final SupabaseClient _client;

  String? get userId {
    try {
      return _client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  bool get signedIn => userId != null;

  /// The user's most recent [limit] titles, newest first; empty when
  /// signed out or when the cloud does not answer.
  Future<List<WatchHistoryEntry>> fetch({int limit = 60}) async {
    final uid = userId;
    if (uid == null) return const [];
    try {
      final rows = await _client
          .from(_table)
          .select('item_id, video_id, item_data, episode_label, position_seconds, duration_seconds, watched_at')
          .eq('user_id', uid)
          .order('watched_at', ascending: false)
          .limit(limit);
      final entries = <WatchHistoryEntry>[];
      for (final row in rows as List) {
        try {
          final map = Map<String, dynamic>.from(row as Map);
          final entry = WatchHistoryEntry.fromJson({
            'item': map['item_data'],
            'videoId': map['video_id'],
            'episodeLabel': map['episode_label'],
            'position': map['position_seconds'],
            'duration': map['duration_seconds'],
            'watchedAt': map['watched_at'],
          });
          if (entry != null) entries.add(entry);
        } catch (e) {
          debugPrint('[history] bad row: $e');
        }
      }
      return entries;
    } catch (e) {
      debugPrint('[history] cloud fetch failed: $e');
      return const [];
    }
  }

  Future<void> upsert(WatchHistoryEntry entry) async {
    final uid = userId;
    if (uid == null) return;
    try {
      await _client.from(_table).upsert({
        'user_id': uid,
        'item_id': entry.item.id,
        'video_id': entry.videoId,
        'item_data': WatchHistoryEntry.encodeItem(entry.item),
        'episode_label': entry.episodeLabel,
        'position_seconds': entry.position.inSeconds,
        'duration_seconds': entry.duration?.inSeconds ?? 0,
        'watched_at': entry.watchedAt.toUtc().toIso8601String(),
      }, onConflict: 'user_id, item_id');
    } catch (e) {
      debugPrint('[history] cloud upsert failed: $e');
    }
  }

  Future<void> delete(String itemId) async {
    final uid = userId;
    if (uid == null) return;
    try {
      await _client.from(_table).delete().eq('user_id', uid).eq('item_id', itemId);
    } catch (e) {
      debugPrint('[history] cloud delete failed: $e');
    }
  }

  Future<void> clear() async {
    final uid = userId;
    if (uid == null) return;
    try {
      await _client.from(_table).delete().eq('user_id', uid);
    } catch (e) {
      debugPrint('[history] cloud clear failed: $e');
    }
  }
}
