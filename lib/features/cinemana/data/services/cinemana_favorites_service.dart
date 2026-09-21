import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cinemana_models.dart';

class CinemanaFavoritesService {
  static const String _legacyKey = 'cinemana_favorites_v1';
  static const String _userCachePrefix = 'cinemana_favorites_u_';

  final SupabaseClient _client;

  CinemanaFavoritesService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  String? get _currentUserId => _client.auth.currentUser?.id;

  String get _currentStorageKey {
    final uid = _currentUserId;
    return uid != null ? '$_userCachePrefix$uid' : _legacyKey;
  }

  /// Get all favorited items (Synced from Supabase database for current user)
  Future<List<CinemanaItem>> getFavorites() async {
    final uid = _currentUserId;

    // 1. If user is logged in, sync with Supabase cloud database
    if (uid != null) {
      try {
        final res = await _client
            .from('user_favorites')
            .select('item_id, item_data')
            .eq('user_id', uid)
            .order('created_at', ascending: false);

        final List<CinemanaItem> cloudItems = [];
        for (final row in (res as List)) {
          try {
            final data = row['item_data'];
            if (data is Map<String, dynamic>) {
              cloudItems.add(CinemanaItem.fromJson(data));
            } else if (data is String) {
              cloudItems.add(CinemanaItem.fromJson(jsonDecode(data)));
            }
          } catch (e) {
            debugPrint('Error parsing favorite item from Supabase: $e');
          }
        }

        // Cache cloud items locally for fast offline/startup access
        await _saveToLocalCache(_currentStorageKey, cloudItems);

        // If user has no cloud favorites yet, check if there are legacy local favorites to migrate
        if (cloudItems.isEmpty) {
          final legacyItems = await _readFromLocalCache(_legacyKey);
          if (legacyItems.isNotEmpty) {
            for (final item in legacyItems) {
              await _insertToCloud(uid, item);
            }
            await _saveToLocalCache(_currentStorageKey, legacyItems);
            return legacyItems;
          }
        }

        return cloudItems;
      } catch (e) {
        debugPrint('Supabase cloud favorites fetch failed, using local cache: $e');
        return await _readFromLocalCache(_currentStorageKey);
      }
    }

    // 2. Fallback to local storage if not logged in
    return await _readFromLocalCache(_legacyKey);
  }

  /// Check if an item is favorited
  Future<bool> isFavorite(String id) async {
    final favorites = await getFavorites();
    return favorites.any((it) => it.id == id);
  }

  /// Toggle favorite status (Adds or removes from cloud DB and local cache)
  Future<bool> toggleFavorite(CinemanaItem item) async {
    final uid = _currentUserId;
    final currentList = await _readFromLocalCache(_currentStorageKey);
    final existsIndex = currentList.indexWhere((it) => it.id == item.id);
    final bool isRemoving = existsIndex >= 0;

    // 1. Update Supabase if logged in
    if (uid != null) {
      try {
        if (isRemoving) {
          await _client
              .from('user_favorites')
              .delete()
              .eq('user_id', uid)
              .eq('item_id', item.id);
        } else {
          await _insertToCloud(uid, item);
        }
      } catch (e) {
        debugPrint('Error syncing toggle favorite to Supabase: $e');
      }
    }

    // 2. Update local cache
    if (isRemoving) {
      currentList.removeAt(existsIndex);
      await _saveToLocalCache(_currentStorageKey, currentList);
      return false;
    } else {
      currentList.insert(0, item);
      await _saveToLocalCache(_currentStorageKey, currentList);
      return true;
    }
  }

  /// Remove item by id from cloud DB and local cache
  Future<void> removeFavorite(String id) async {
    final uid = _currentUserId;

    if (uid != null) {
      try {
        await _client
            .from('user_favorites')
            .delete()
            .eq('user_id', uid)
            .eq('item_id', id);
      } catch (e) {
        debugPrint('Error removing favorite from Supabase: $e');
      }
    }

    final currentList = await _readFromLocalCache(_currentStorageKey);
    currentList.removeWhere((it) => it.id == id);
    await _saveToLocalCache(_currentStorageKey, currentList);
  }

  // ===========================================================================
  // Internal Helpers
  // ===========================================================================

  Future<void> _insertToCloud(String uid, CinemanaItem item) async {
    try {
      await _client.from('user_favorites').upsert({
        'user_id': uid,
        'item_id': item.id,
        'item_data': item.toJson(),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id, item_id');
    } catch (e) {
      debugPrint('Error inserting to user_favorites: $e');
    }
  }

  Future<List<CinemanaItem>> _readFromLocalCache(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(key) ?? [];
      final List<CinemanaItem> items = [];
      for (final raw in rawList) {
        try {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          items.add(CinemanaItem.fromJson(map));
        } catch (_) {}
      }
      return items;
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveToLocalCache(String key, List<CinemanaItem> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = items.map((item) => jsonEncode(item.toJson())).toList();
      await prefs.setStringList(key, rawList);
    } catch (_) {}
  }
}
