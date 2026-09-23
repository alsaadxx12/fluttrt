import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cast_models.dart';

/// What the viewer has settled on about their screens: which one they used
/// last, and what they call each of them.
class CastPrefs {
  CastPrefs._();

  static const String _lastKey = 'cast_last_device_v1';
  static const String _namesKey = 'cast_device_names_v1';

  static Map<String, String>? _names;

  /// The screen connected to last time, or null on a fresh install.
  static Future<CastDevice?> lastDevice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_lastKey);
      if (raw == null || raw.isEmpty) return null;
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final transport = CastTransport.values.firstWhere(
        (t) => t.name == map['transport'],
        orElse: () => CastTransport.dlna,
      );
      // A browser is paired by a code that has long expired; it is not a
      // screen to go back to.
      if (transport == CastTransport.web) return null;
      return CastDevice(
        id: '${map['id']}',
        name: '${map['name']}',
        subtitle: '${map['subtitle'] ?? ''}',
        brand: '${map['brand'] ?? ''}',
        transport: transport,
      );
    } catch (_) {
      return null;
    }
  }

  /// Remembers [device] as the one to offer first next time.
  static Future<void> rememberDevice(CastDevice device) async {
    if (device.transport == CastTransport.web) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _lastKey,
        jsonEncode({
          'id': device.id,
          'name': device.name,
          'subtitle': device.subtitle,
          'brand': device.brand,
          'transport': device.transport.name,
        }),
      );
    } catch (e) {
      debugPrint('[cast] could not remember the device: $e');
    }
  }

  static Future<void> forgetDevice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastKey);
    } catch (_) {}
  }

  static Future<Map<String, String>> _allNames() async {
    final cached = _names;
    if (cached != null) return cached;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_namesKey);
      final map = raw == null || raw.isEmpty
          ? <String, String>{}
          : Map<String, String>.from(jsonDecode(raw) as Map);
      return _names = map;
    } catch (_) {
      return _names = <String, String>{};
    }
  }

  /// The viewer's own name for a screen, when they gave it one.
  static Future<Map<String, String>> customNames() => _allNames();

  /// Calls the screen with [id] [name]; an empty name goes back to what the
  /// screen calls itself.
  static Future<void> rename(String id, String name) async {
    final all = await _allNames();
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      all.remove(id);
    } else {
      all[id] = trimmed;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_namesKey, jsonEncode(all));
    } catch (e) {
      debugPrint('[cast] could not save the name: $e');
    }
  }

  @visibleForTesting
  static void resetCache() => _names = null;
}
