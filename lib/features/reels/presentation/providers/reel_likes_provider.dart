import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The reels the user has liked, as their ids, kept on the device.
///
/// There is no account behind it: a like is the red heart on this phone, and
/// it survives a restart. Every write waits for the saved set to be read
/// first, so an early tap never wipes what was stored.
class ReelLikesNotifier extends StateNotifier<Set<String>> {
  ReelLikesNotifier() : super(const {}) {
    ready = _load();
  }

  static const String key = 'reel_likes_v1';

  /// Completes once the saved set has been read. Never fails.
  late final Future<void> ready;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(key);
      if (list != null && mounted) state = list.toSet();
    } catch (_) {
      // A bad store just means nothing is liked yet.
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(key, state.toList());
    } catch (_) {}
  }

  bool isLiked(String id) => state.contains(id);

  /// Likes [id] if it is not liked, otherwise takes the like back.
  Future<void> toggle(String id) async {
    if (id.isEmpty) return;
    await ready;
    if (!mounted) return;
    final next = Set<String>.of(state);
    if (!next.remove(id)) next.add(id);
    state = next;
    await _save();
  }

  /// Likes [id]; already liked stays liked (the double tap never un-likes).
  Future<void> like(String id) async {
    if (id.isEmpty) return;
    await ready;
    if (!mounted || state.contains(id)) return;
    state = {...state, id};
    await _save();
  }
}

final reelLikesProvider =
    StateNotifierProvider<ReelLikesNotifier, Set<String>>((ref) => ReelLikesNotifier());
