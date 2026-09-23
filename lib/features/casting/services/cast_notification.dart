import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// The notification that stands for a film playing on another screen.
///
/// While something is cast, a line in the notification shade says what is
/// playing and where, with play/pause and stop on it — so the phone can be
/// put down, or used for something else, and the film still has a remote.
/// Android draws it; the buttons come back here as [onAction].
///
/// Only Android has the code behind this. Elsewhere every call is a no-op.
class CastNotification {
  CastNotification._();

  static const MethodChannel _channel = MethodChannel('cineball/cast_notification');

  /// Called with 'play', 'pause' or 'stop' when a button on the
  /// notification is pressed.
  static void Function(String action)? onAction;

  static bool _wired = false;
  static bool _asked = false;

  static void _wire() {
    if (_wired) return;
    _wired = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'action') {
        final action = call.arguments;
        if (action is String) onAction?.call(action);
      }
      return null;
    });
  }

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Puts the notification up, or updates it.
  static Future<void> show({
    required String title,
    required String where,
    required bool playing,
  }) async {
    if (!_supported) return;
    _wire();
    if (!_asked) {
      _asked = true;
      // Android 13 asks before any notification is shown. Asked once, when
      // the first film is cast: what the permission is for is on screen.
      try {
        final status = await Permission.notification.status;
        if (!status.isGranted && !status.isPermanentlyDenied) {
          await Permission.notification.request();
        }
      } catch (_) {}
    }
    try {
      await _channel.invokeMethod<void>('show', {
        'title': title,
        'where': where,
        'playing': playing,
      });
    } catch (e) {
      debugPrint('[cast] notification: $e');
    }
  }

  static Future<void> hide() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('hide');
    } catch (_) {}
  }
}
