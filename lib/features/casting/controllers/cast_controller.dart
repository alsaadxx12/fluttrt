import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/cast_models.dart';
import '../services/cast_service.dart';
import '../services/web_cast_service.dart';

/// Everything the app knows about casting, in one place.
///
/// Pages ask this to connect, to send a title, and to drive playback; they
/// never touch a service directly, so a Chromecast and a browser look the
/// same from a widget's side.
class CastController extends StateNotifier<CastState> {
  CastController(this._web) : super(const CastState()) {
    _events = _web.events.listen(_onEvent);
  }

  final WebCastService _web;
  late final StreamSubscription<CastPlaybackEvent> _events;

  /// The service driving the connected device.
  CastService? get _active => state.device == null ? null : _web;

  // ------------------------------------------------------------ connecting
  /// Pairs with a browser showing [code] and connects to it.
  Future<void> pairWithCode(String code) async {
    state = state.copyWith(status: CastStatus.connecting, clearError: true);
    try {
      final device = await _web.pair(code);
      await _web.connect(device);
      state = state.copyWith(
        status: CastStatus.connected,
        device: device,
        devices: [device],
        clearError: true,
      );
      // A device chosen while something was already casting picks it up.
      final media = state.media;
      if (media != null) await _web.loadMedia(media);
    } on CastException catch (e) {
      state = state.copyWith(status: CastStatus.error, error: e.message);
      rethrow;
    } catch (_) {
      const message = 'تعذّر الاتصال بالجهاز';
      state = state.copyWith(status: CastStatus.error, error: message);
      throw const CastException(message);
    }
  }

  Future<void> disconnect() async {
    await _web.disconnect();
    state = const CastState();
  }

  // -------------------------------------------------------------- playback
  /// Sends [media] to the connected device.
  ///
  /// Nothing happens when no device is connected: a page may call this
  /// freely and let the viewer decide whether to cast.
  Future<void> cast(CastMedia media) async {
    if (!state.isConnected) return;
    final swapping = state.media != null && state.media!.mediaId != media.mediaId;
    state = state.copyWith(
      media: media,
      position: media.position,
      duration: media.duration,
      isPlaying: true,
      clearError: true,
    );
    if (swapping) {
      await _web.changeMedia(media);
    } else {
      await _web.loadMedia(media);
    }
  }

  Future<void> play() async {
    await _active?.play();
    state = state.copyWith(isPlaying: true);
  }

  Future<void> pause() async {
    await _active?.pause();
    state = state.copyWith(isPlaying: false);
  }

  Future<void> togglePlay() => state.isPlaying ? pause() : play();

  Future<void> seek(Duration position) async {
    if (state.media?.isLive ?? false) return;
    final clamped = position < Duration.zero ? Duration.zero : position;
    await _active?.seek(clamped);
    state = state.copyWith(position: clamped);
  }

  Future<void> skip(Duration by) => seek(state.position + by);

  Future<void> setVolume(double volume) async {
    await _active?.setVolume(volume);
    state = state.copyWith(volume: volume, isMuted: volume == 0);
  }

  Future<void> toggleMute() async {
    final muted = !state.isMuted;
    await _active?.setMuted(muted);
    state = state.copyWith(isMuted: muted);
  }

  /// Stops the picture but keeps the device: the viewer can send something
  /// else without pairing again.
  Future<void> stopMedia() async {
    await _active?.stop();
    state = state.copyWith(clearMedia: true, isPlaying: false, position: Duration.zero);
  }

  void _onEvent(CastPlaybackEvent e) {
    if (e.disconnected) {
      state = const CastState(error: 'انقطع الاتصال بالجهاز');
      return;
    }
    if (e.error != null) {
      state = state.copyWith(error: e.error);
      return;
    }
    state = state.copyWith(
      position: e.position,
      duration: e.duration,
      isPlaying: e.isPlaying,
      isMuted: e.isMuted,
      volume: e.volume,
    );
  }

  @override
  void dispose() {
    _events.cancel();
    _web.dispose();
    super.dispose();
  }
}

final castControllerProvider = StateNotifierProvider<CastController, CastState>(
  (ref) => CastController(WebCastService()),
);

/// True while a device is connected — the button and the mini controller
/// watch this alone, so neither rebuilds on every tick of the clock.
final isCastingProvider = Provider<bool>(
  (ref) => ref.watch(castControllerProvider.select((s) => s.isConnected)),
);
