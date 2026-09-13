import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the app is running on a television.
///
/// A television is not a large phone. It is watched from across a room and
/// driven by a remote, so text has to carry further and whatever currently
/// has focus has to be obvious without a finger to point with.
class TvMode {
  TvMode._();

  static const _channel = MethodChannel('cineball/updater');

  static Future<bool> detect() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isTv') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Text grows because the viewer sits metres away rather than
  /// centimetres. Kept modest: beyond this, layouts drawn for a phone begin
  /// to overflow rather than simply read larger.
  static const textScale = 1.15;

  /// Turns the focus ring on for every control, so the remote's current
  /// position is always visible. On a phone that ring only appears for a
  /// physical keyboard, which would leave a television viewer with no idea
  /// what the arrow keys are pointing at.
  static void enableRemoteFocus() {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
  }
}

/// Resolved once at start-up. False on anything that is not a television,
/// and false rather than an error when the platform cannot say.
final tvModeProvider = FutureProvider<bool>((ref) async {
  final isTv = await TvMode.detect();
  if (isTv) TvMode.enableRemoteFocus();
  return isTv;
});

/// Search by speaking, through the platform's own recogniser.
///
/// The recogniser app asks for the microphone and shows its own listening
/// screen, so this app needs no audio permission of its own and a remote's
/// microphone button behaves the way its owner already expects. Returns the
/// words heard, or null when the viewer said nothing, cancelled, or the
/// device has no recogniser at all.
class VoiceSearch {
  VoiceSearch._();

  static const _channel = MethodChannel('cineball/updater');

  static Future<String?> listen({String prompt = 'تحدث الآن'}) async {
    if (!Platform.isAndroid) return null;
    try {
      final heard = await _channel.invokeMethod<String>('startVoiceSearch', {'prompt': prompt});
      final text = heard?.trim() ?? '';
      return text.isEmpty ? null : text;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}

