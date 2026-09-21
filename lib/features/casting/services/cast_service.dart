import '../models/cast_models.dart';

/// What every kind of device looks like to the rest of the app.
///
/// The sheet, the remote and the mini controller talk to this and never
/// learn whether the picture is on a Chromecast or in a browser.
abstract class CastService {
  /// Which transport this implementation speaks.
  CastTransport get transport;

  /// Devices it can see right now. A browser cannot be discovered — it is
  /// paired by code — so the web implementation returns whatever sessions
  /// the viewer has already paired.
  Future<List<CastDevice>> discoverDevices();

  Future<void> connect(CastDevice device);
  Future<void> disconnect();

  Future<void> loadMedia(CastMedia media);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> setMuted(bool muted);
  Future<void> stop();

  /// What the device reports back: where it is, whether it is playing, and
  /// when the picture ends. Never completes; closed by [dispose].
  Stream<CastPlaybackEvent> get events;

  void dispose();
}

/// A report from the device.
class CastPlaybackEvent {
  const CastPlaybackEvent({
    this.position,
    this.duration,
    this.isPlaying,
    this.isMuted,
    this.volume,
    this.ended = false,
    this.error,
    this.disconnected = false,
  });

  final Duration? position;
  final Duration? duration;
  final bool? isPlaying;
  final bool? isMuted;
  final double? volume;

  /// The picture ran out; the app may offer the next episode.
  final bool ended;

  /// Something went wrong on the device, in words the viewer can read.
  final String? error;

  /// The device is gone: the page was closed, or the session expired.
  final bool disconnected;
}

/// Thrown when a device cannot be reached or a pairing code is refused.
class CastException implements Exception {
  const CastException(this.message);
  final String message;

  @override
  String toString() => message;
}
