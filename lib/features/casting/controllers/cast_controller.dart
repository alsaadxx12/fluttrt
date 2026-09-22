import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/cast_models.dart';
import '../services/cast_service.dart';
import '../services/dlna_cast_service.dart';
import '../services/google_cast_service.dart';
import '../services/web_cast_service.dart';

/// Everything the app knows about casting, in one place.
///
/// Pages ask this to connect, to send a title, and to drive playback; they
/// never touch a service directly, so a Chromecast and a browser look the
/// same from a widget's side.
class CastController extends StateNotifier<CastState> {
  CastController(this._web, this._tv, this._dlna) : super(const CastState()) {
    _webEvents = _web.events.listen(_onEvent);
    _tvEvents = _tv.events.listen(_onEvent);
    _dlnaEvents = _dlna.events.listen(_onEvent);
  }

  final WebCastService _web;
  final GoogleCastService _tv;
  final DlnaCastService _dlna;
  late final StreamSubscription<CastPlaybackEvent> _webEvents;
  late final StreamSubscription<CastPlaybackEvent> _tvEvents;
  late final StreamSubscription<CastPlaybackEvent> _dlnaEvents;

  /// The service driving the connected device.
  ///
  /// Which one it is follows from the device itself, so nothing above this
  /// line — not the sheet, not the remote, not the mini controller — has to
  /// know whether the picture is on a television or in a browser.
  CastService? get _active => switch (state.device?.transport) {
        CastTransport.web => _web,
        CastTransport.googleCast => _tv,
        CastTransport.dlna => _dlna,
        null => null,
      };

  /// Every screen on the network, whichever protocol it happens to speak.
  ///
  /// Two searches run at once and their results are merged, because a house
  /// can hold both a Chromecast and a Samsung and the viewer should not
  /// have to know which is which. Cast devices arrive on a stream as the
  /// SDK finds them; a UPnP search is a question with an answer, so it is
  /// asked again every few seconds and folded into the same list.
  Stream<List<CastDevice>> get televisions {
    final cast = _tv.deviceStream;
    final controller = StreamController<List<CastDevice>>();

    var fromCast = <CastDevice>[];
    var fromDlna = <CastDevice>[];
    void emit() {
      if (!controller.isClosed) controller.add([...fromCast, ...fromDlna]);
    }

    final castSub = cast.listen((devices) {
      fromCast = devices;
      emit();
    });

    var searching = false;
    Future<void> sweep() async {
      if (searching) return;
      searching = true;
      try {
        fromDlna = await _dlna.discoverDevices();
        emit();
      } catch (e) {
        debugPrint('[cast] dlna sweep: $e');
      } finally {
        searching = false;
      }
    }

    unawaited(sweep());
    final repeat = Timer.periodic(const Duration(seconds: 8), (_) => sweep());

    controller.onCancel = () {
      repeat.cancel();
      castSub.cancel();
    };
    return controller.stream;
  }

  Future<void> startDiscovery() => _tv.startDiscovery();
  Future<void> stopDiscovery() => _tv.stopDiscovery();

  /// Connects to a television the viewer picked out of the list.
  ///
  /// A browser is reached by [pairWithCode] instead — it cannot be found on
  /// the network, which is the whole reason it shows a code.
  Future<void> connectTo(CastDevice device) async {
    state = state.copyWith(status: CastStatus.connecting, clearError: true);
    final service =
        device.transport == CastTransport.dlna ? _dlna : _tv;
    try {
      await service.connect(device);
      state = state.copyWith(
        status: CastStatus.connected,
        device: device,
        clearError: true,
      );
      final media = state.media;
      if (media != null) await service.loadMedia(media);
    } on CastException catch (e) {
      state = state.copyWith(status: CastStatus.error, error: e.message);
      rethrow;
    } catch (e) {
      debugPrint('[cast] connect failed: $e');
      const message = 'تعذّر الاتصال بالتلفاز';
      state = state.copyWith(status: CastStatus.error, error: message);
      throw const CastException(message);
    }
  }

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
    await _active?.disconnect();
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
    final service = _active;
    if (service == null) return;
    // Only the browser receiver distinguishes the two: swapping lets it keep
    // its player and trade the source, where a fresh load would blink the
    // screen black. A Chromecast simply loads again.
    if (swapping && service is WebCastService) {
      await service.changeMedia(media);
    } else {
      await service.loadMedia(media);
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
    _webEvents.cancel();
    _tvEvents.cancel();
    _dlnaEvents.cancel();
    _web.dispose();
    _tv.dispose();
    _dlna.dispose();
    super.dispose();
  }
}

final castControllerProvider = StateNotifierProvider<CastController, CastState>(
  (ref) => CastController(WebCastService(), GoogleCastService(), DlnaCastService()),
);

/// Televisions currently answering on the network.
///
/// Discovery runs only while something is watching this — the sheet, in
/// practice — because a Cast scan is a steady trickle of multicast traffic
/// and there is no reason to keep it up behind a closed sheet.
final castTelevisionsProvider = StreamProvider.autoDispose<List<CastDevice>>((ref) {
  final controller = ref.watch(castControllerProvider.notifier);
  controller.startDiscovery();
  ref.onDispose(controller.stopDiscovery);
  return controller.televisions;
});

/// True while a device is connected — the button and the mini controller
/// watch this alone, so neither rebuilds on every tick of the clock.
final isCastingProvider = Provider<bool>(
  (ref) => ref.watch(castControllerProvider.select((s) => s.isConnected)),
);
