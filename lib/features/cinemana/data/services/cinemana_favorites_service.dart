import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cinemana_models.dart';

class CinemanaFavoritesService {
  static const String _key = 'cinemana_favorites_v1';

  /// Get all favorited items
  Future<List<CinemanaItem>> getFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_key) ?? [];
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

  /// Check if an item is favorited
  Future<bool> isFavorite(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_key) ?? [];
      for (final raw in rawList) {
        try {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          if (map['nb']?.toString() == id) {
            return true;
          }
        } catch (_) {}
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Toggle favorite status. Returns true if now favorited, false if removed.
  Future<bool> toggleFavorite(CinemanaItem item) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_key) ?? [];
      int existingIndex = -1;

      for (int i = 0; i < rawList.length; i++) {
        try {
          final map = jsonDecode(rawList[i]) as Map<String, dynamic>;
          if (map['nb']?.toString() == item.id) {
            existingIndex = i;
            break;
          }
        } catch (_) {}
      }

      if (existingIndex >= 0) {
        rawList.removeAt(existingIndex);
        await prefs.setStringList(_key, rawList);
        return false;
      } else {
        rawList.insert(0, jsonEncode(item.toJson()));
        await prefs.setStringList(_key, rawList);
        return true;
      }
    } catch (_) {
      return false;
    }
  }

  /// Remove item by id
  Future<void> removeFavorite(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_key) ?? [];
      rawList.removeWhere((raw) {
        try {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          return map['nb']?.toString() == id;
        } catch (_) {
          return false;
        }
      });
      await prefs.setStringList(_key, rawList);
    } catch (_) {}
  }
}
