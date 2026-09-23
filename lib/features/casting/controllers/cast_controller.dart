import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/cast_models.dart';
import '../services/cast_notification.dart';
import '../services/cast_prefs.dart';
import '../services/cast_service.dart';
import '../services/dlna_cast_service.dart';
import '../services/google_cast_service.dart';
import '../services/local_network.dart';
import '../services/resume_store.dart';
import '../services/web_cast_service.dart';
import 'package:youtube_downloader/features/history/presentation/providers/watch_history_provider.dart';

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
    // The app closing is the viewer leaving: the set is told to stop and
    // let go, rather than left playing a film nobody is watching from a
    // phone that has gone. Detach is the last word the framework gives
    // before the engine goes; the commands are short and go out in time.
    _lifecycle = AppLifecycleListener(onDetach: _letGo);
    // The buttons on the notification come back here.
    CastNotification.onAction = (action) {
      switch (action) {
        case 'play':
          unawaited(play());
        case 'pause':
          unawaited(pause());
        case 'stop':
          unawaited(stopMedia());
      }
    };
  }

  /// Connects to the screen used last time — the sheet does this on its
  /// own the moment it opens. A set not yet seen by the search is looked
  /// for first; a search that finds nothing ends the attempt quietly.
  Future<void> connectToLast(CastDevice last) async {
    state = state.copyWith(
        note: 'جارٍ الاتصال بآخر شاشة: ${last.name}…', clearError: true);
    if (last.transport == CastTransport.dlna) {
      try {
        await _dlna.discoverDevices();
      } catch (_) {}
    }
    try {
      await connectTo(last);
    } on CastException catch (e) {
      // Not the viewer's doing: the failure is a note, not an error, and
      // the list under it is still there to pick from.
      state = state.copyWith(
        status: CastStatus.idle,
        clearError: true,
        note: 'آخر شاشة «${last.name}» لم تُجب — اختر شاشة من القائمة',
      );
      debugPrint('[cast] last device: ${e.message}');
      rethrow;
    }
  }

  late final AppLifecycleListener _lifecycle;

  /// Told where the film on the screen has got to, every few seconds and
  /// at every stop — for the history page, which lives elsewhere and
  /// should not be a thing the casting code knows about.
  void Function(String videoId, Duration position, Duration? duration,
      {bool now})? onProgress;

  Future<void> _letGo() async {
    if (state.device == null) return;
    try {
      await disconnect().timeout(const Duration(seconds: 3));
    } catch (_) {}
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
      if (!controller.isClosed) controller.add(merged(fromCast, fromDlna));
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

  /// One list from the two searches, Cast first.
  ///
  /// A television that speaks both — an Android TV with DLNA switched on,
  /// a Samsung with Chromecast built in — answers both searches and would
  /// appear twice. It appears once, as the Cast device: over Cast the set
  /// fetches the film itself and the phone sends nothing but the address,
  /// which is the lighter of the two by the whole weight of the film. The
  /// two answers are matched by name, which is all the two protocols
  /// share.
  @visibleForTesting
  static List<CastDevice> merged(List<CastDevice> cast, List<CastDevice> dlna) {
    if (cast.isEmpty) return [...dlna];
    final castNames = cast.map((d) => _plainName(d.name)).toList();
    bool alsoOnCast(CastDevice d) {
      final name = _plainName(d.name);
      if (name.isEmpty) return false;
      return castNames
          .any((c) => c == name || c.contains(name) || name.contains(c));
    }

    return [
      ...cast,
      for (final d in dlna)
        if (!alsoOnCast(d)) d
    ];
  }

  static String _plainName(String name) => name
      .toLowerCase()
      .replaceAll(RegExp(r'\[.*?\]'), '')
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();

  Future<void> startDiscovery() => _tv.startDiscovery();
  Future<void> stopDiscovery() => _tv.stopDiscovery();

  /// How many times a television is tried before the viewer is told it
  /// cannot be reached.
  ///
  /// Four, a few seconds apart. A set answers its first question late
  /// when it has just woken, a wifi that is slow drops the odd packet, and
  /// on either count one try was «تعذّر الاتصال» for a television that
  /// would have connected on the second.
  static const int _connectAttempts = 4;

  /// How many times a film is sent before its failure is believed.
  static const int _loadAttempts = 2;

  /// How many times a lost set is looked for before it is given up on.
  static const int _recoverAttempts = 3;

  /// Connects to a television the viewer picked out of the list.
  ///
  /// A browser is reached by [pairWithCode] instead — it cannot be found on
  /// the network, which is the whole reason it shows a code.
  ///
  /// Tried again, a few seconds apart, while what went wrong is the kind of
  /// thing that goes right the next time — a set that did not answer, a
  /// session that did not start, a set that dropped out of the list
  /// between the sweep and the tap. A refusal is believed the first time.
  Future<void> connectTo(CastDevice device) async {
    state = state.copyWith(
      status: CastStatus.connecting,
      clearError: true,
      clearNote: true,
    );
    final service = _serviceFor(device);
    CastException last = const CastException('تعذّر الاتصال بالتلفاز');
    for (var attempt = 1; attempt <= _connectAttempts; attempt++) {
      try {
        await service.connect(device);
        state = state.copyWith(
          status: CastStatus.connected,
          device: device,
          clearError: true,
          clearNote: true,
        );
        unawaited(CastPrefs.rememberDevice(device));
        final media = state.media;
        if (media != null) await _load(service, media);
        return;
      } on CastException catch (e) {
        last = e;
      } catch (e) {
        debugPrint('[cast] connect failed: $e');
        last = const CastException('تعذّر الاتصال بالتلفاز', retryable: true);
      }
      if (attempt == _connectAttempts || !_worthAnotherTry(last)) break;
      state = state.copyWith(
        note: 'لم يستجب التلفاز، محاولة ${attempt + 1} من $_connectAttempts…',
      );
      await Future<void>.delayed(Duration(seconds: attempt));
      // A set that dropped out of the list is looked for again before the
      // next try, or the next try is the same answer.
      if (last.code == 404 && device.transport == CastTransport.dlna) {
        try {
          await _dlna.discoverDevices();
        } catch (_) {}
      }
    }
    state = state.copyWith(
      status: CastStatus.error,
      error: last.message,
      clearNote: true,
    );
    throw last;
  }

  CastService _serviceFor(CastDevice device) => switch (device.transport) {
        CastTransport.web => _web,
        CastTransport.googleCast => _tv,
        CastTransport.dlna => _dlna,
      };

  static bool _worthAnotherTry(CastException e) => e.retryable || e.code == 404;

  /// Sends [media] to [service], and once more if the set did not answer.
  ///
  /// The DLNA service tries each command of its own accord and falls back
  /// from mkv to mp4 by itself; this is for the Cast SDK, whose load can
  /// fail on a platform error that a second load does not repeat, and for
  /// a set that timed out on the whole exchange.
  Future<void> _load(CastService service, CastMedia media) async {
    for (var attempt = 1;; attempt++) {
      try {
        await service.loadMedia(media);
        state = state.copyWith(clearNote: true);
        _showNotification(playing: true);
        return;
      } on CastException catch (e) {
        if (attempt >= _loadAttempts || !e.retryable) rethrow;
        debugPrint('[cast] load ($attempt/$_loadAttempts): ${e.message}');
      } catch (e) {
        if (attempt >= _loadAttempts) {
          throw const CastException('تعذّر إرسال المحتوى إلى الجهاز');
        }
        debugPrint('[cast] load ($attempt/$_loadAttempts): $e');
      }
      state = state.copyWith(note: 'إعادة إرسال الفيلم إلى التلفاز…');
      await Future<void>.delayed(const Duration(seconds: 2));
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
    await _rememberWhereItIs();
    await _active?.disconnect();
    state = const CastState();
    unawaited(CastNotification.hide());
  }

  /// The line in the notification shade: what is playing, where, and the
  /// buttons for it.
  void _showNotification({required bool playing}) {
    final media = state.media;
    final device = state.device;
    if (media == null || device == null) return;
    unawaited(CastNotification.show(
      title: media.title,
      where: device.name,
      playing: playing,
    ));
  }

  DateTime _lastSaved = DateTime.fromMillisecondsSinceEpoch(0);

  /// Writes down where the film is, so it can be picked up from there —
  /// on this screen or any other. Every few seconds, not every tick.
  Future<void> _rememberWhereItIs({bool force = false}) async {
    final media = state.media;
    if (media == null || media.isLive) return;
    if (!force &&
        DateTime.now().difference(_lastSaved) < const Duration(seconds: 5))
      return;
    _lastSaved = DateTime.now();
    await ResumeStore.save(media.mediaId, state.position,
        duration: state.duration);
    onProgress?.call(media.mediaId, state.position, state.duration, now: force);
  }

  // -------------------------------------------------------------- playback
  /// Sends [media] to the connected device.
  ///
  /// Nothing happens when no device is connected: a page may call this
  /// freely and let the viewer decide whether to cast.
  Future<void> cast(CastMedia media) async {
    if (!state.isConnected) {
      debugPrint(
          '[cast] cast(${media.mediaId}) with nothing connected (status ${state.status.name})');
      return;
    }
    final swapping =
        state.media != null && state.media!.mediaId != media.mediaId;
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
    try {
      if (swapping && service is WebCastService) {
        await service.changeMedia(media);
      } else {
        await _load(service, media);
      }
    } on CastException catch (e) {
      // Said where the remote can read it, not only thrown at the page.
      state = state.copyWith(error: e.message, clearNote: true);
      rethrow;
    }
  }

  Future<void> play() async {
    await _active?.play();
    state = state.copyWith(isPlaying: true);
    _showNotification(playing: true);
  }

  Future<void> pause() async {
    await _active?.pause();
    state = state.copyWith(isPlaying: false);
    _showNotification(playing: false);
    unawaited(_rememberWhereItIs(force: true));
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
    await _rememberWhereItIs(force: true);
    await _active?.stop();
    state = state.copyWith(
        clearMedia: true, isPlaying: false, position: Duration.zero);
    unawaited(CastNotification.hide());
  }

  /// When the link last proved too slow; a softer picture is tried at most
  /// once a minute and a half, so a single rough patch does not walk the
  /// quality all the way down.
  DateTime _lastStepDown = DateTime.fromMillisecondsSinceEpoch(0);

  /// The link is not keeping up: send the same film again, one picture
  /// softer, from the minute it is at.
  Future<void> _stepDown() async {
    final media = state.media;
    final softer = media?.softer;
    if (media == null || softer == null || _recovering) return;
    if (DateTime.now().difference(_lastStepDown) < const Duration(seconds: 90))
      return;
    _lastStepDown = DateTime.now();
    final next = media.copyWith(
      streamUrl: softer.url,
      height: softer.height,
      position: state.position,
      quality: '${softer.height}p · الإنترنت أبطأ من اللازم، تم التخفيف',
    );
    debugPrint(
        '[cast] link too slow at ${media.height}p; sending ${softer.height}p from ${state.position}');
    state = state.copyWith(
        note: 'الإنترنت بطيء — التبديل إلى ${softer.height}p من نفس الدقيقة…');
    try {
      await cast(next);
    } catch (e) {
      debugPrint('[cast] step down: $e');
    }
  }

  void _onEvent(CastPlaybackEvent e) {
    if (e.disconnected) {
      if (_tryToRecover()) return;
      state = const CastState(error: 'انقطع الاتصال بالجهاز');
      return;
    }
    if (e.error != null) {
      if (e.recoverable && _tryToRecover()) return;
      state = state.copyWith(error: e.error, clearNote: true);
      return;
    }
    if (e.stalled) {
      unawaited(_stepDown());
      return;
    }
    if (e.ended) {
      final media = state.media;
      if (media != null) unawaited(ResumeStore.clear(media.mediaId));
    }
    state = state.copyWith(
      position: e.position,
      duration: e.duration,
      isPlaying: e.isPlaying,
      isMuted: e.isMuted,
      volume: e.volume,
    );
    if (e.position != null) unawaited(_rememberWhereItIs());
  }

  /// True while a lost set is being got back.
  bool _recovering = false;

  /// Starts getting a lost set back, when there is something to get back
  /// to: a device, and a film that was on it.
  ///
  /// The remote stays up and says what is happening; the film is sent
  /// again from where it was. Only when every try fails is the connection
  /// declared gone.
  bool _tryToRecover() {
    final device = state.device;
    final media = state.media;
    if (device == null || media == null || _recovering) return false;
    if (device.transport == CastTransport.web) return false;
    _recovering = true;
    unawaited(_recover(device, media.copyWith(position: state.position)));
    return true;
  }

  Future<void> _recover(CastDevice device, CastMedia media) async {
    try {
      final service = _serviceFor(device);
      for (var attempt = 1; attempt <= _recoverAttempts; attempt++) {
        state = state.copyWith(
          note:
              'انقطع الاتصال بالتلفاز، إعادة الربط ($attempt من $_recoverAttempts)…',
          clearError: true,
        );
        try {
          // A set that restarted is back on a new port; a sweep finds it
          // there before it is knocked at.
          if (device.transport == CastTransport.dlna) {
            await _dlna.discoverDevices();
          }
          await service.connect(device);
          await service.loadMedia(media);
          state = state.copyWith(
            status: CastStatus.connected,
            device: device,
            media: media,
            isPlaying: true,
            clearError: true,
            clearNote: true,
          );
          debugPrint('[cast] got ${device.name} back on try $attempt');
          return;
        } catch (e) {
          debugPrint('[cast] recover ($attempt/$_recoverAttempts): $e');
        }
        await Future<void>.delayed(Duration(seconds: 2 * attempt));
      }
      state =
          const CastState(error: 'انقطع الاتصال بالتلفاز ولم تنجح إعادة الربط');
    } finally {
      _recovering = false;
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
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
  (ref) {
    final controller = CastController(
        WebCastService(), GoogleCastService(), DlnaCastService());
    // Where the film on the screen has got to goes into the history too.
    controller.onProgress = (videoId, position, duration, {bool now = false}) {
      ref.read(watchHistoryProvider.notifier).updatePosition(
            videoId,
            position,
            duration: duration,
            now: now,
          );
    };
    return controller;
  },
);

/// The screen connected to last time, for the top of the list.
final lastCastDeviceProvider = FutureProvider.autoDispose<CastDevice?>(
  (ref) => CastPrefs.lastDevice(),
);

/// The viewer's own names for their screens, by device id.
final castDeviceNamesProvider = FutureProvider.autoDispose<Map<String, String>>(
  (ref) => CastPrefs.customNames(),
);

/// Whether the phone is on a network a television can be found on.
final localNetworkProvider = FutureProvider.autoDispose<LocalNetworkStatus>(
  (ref) => LocalNetwork.status(),
);

/// Televisions currently answering on the network.
///
/// Discovery runs only while something is watching this — the sheet, in
/// practice — because a Cast scan is a steady trickle of multicast traffic
/// and there is no reason to keep it up behind a closed sheet.
final castTelevisionsProvider =
    StreamProvider.autoDispose<List<CastDevice>>((ref) {
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
