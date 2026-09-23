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
    this.recoverable = false,
    this.stalled = false,
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

  /// True when [error] is the kind that connecting again may cure — a set
  /// that stopped answering, not one that refused the film — so the
  /// controller tries to get it back before telling anyone.
  final bool recoverable;

  /// The picture has not moved for a while though the set says it is
  /// playing: the link is not keeping up. The controller may answer with a
  /// softer picture.
  final bool stalled;
}

/// Thrown when a device cannot be reached or a pairing code is refused.
class CastException implements Exception {
  const CastException(this.message, {this.code, this.retryable = false});
  final String message;

  /// The UPnP or HTTP code the device answered with, when it answered.
  ///
  /// 404 is used for a device that is no longer on the network at all.
  final int? code;

  /// True when the same request a moment later may well succeed: a timeout,
  /// a dropped connection, a set that was not ready yet. A refusal is not.
  final bool retryable;

  @override
  String toString() => message;
}
