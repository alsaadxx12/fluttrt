import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_chrome_cast/lib.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/cast_models.dart';
import 'cast_service.dart';

/// Casting to a Chromecast, a Google TV or an Android TV.
///
/// Unlike the browser receiver, the television is not sent the picture: it is
/// sent the address and fetches the stream from the CDN itself. That is how
/// Cast works and there is no way around it — but it also means the address
/// must survive leaving the phone, so this checks nothing the phone can see
/// and trusts the CDN's own signed url.
///
/// Only the plugin's managers are used here. Its widgets are deliberately
/// left alone: they carry a state framework of their own, and the app already
/// has a sheet and a remote of its own design.
class GoogleCastService implements CastService {
  GoogleCastService() {
    _media = GoogleCastRemoteMediaClient.instance.mediaStatusStream.listen(
      _onStatus,
      onError: (Object e) => debugPrint('[cast] media status: $e'),
    );
    _ticks = GoogleCastRemoteMediaClient.instance.playerPositionStream.listen(
      (position) => _emit(CastPlaybackEvent(position: position)),
      onError: (Object e) => debugPrint('[cast] position: $e'),
    );
    _sessions = GoogleCastSessionManager.instance.currentSessionStream.listen(
      _onSession,
      onError: (Object e) => debugPrint('[cast] session: $e'),
    );
  }

  /// Google's Default Media Receiver.
  ///
  /// It plays mp4 and HLS and needs no registration, which is the whole
  /// reason it is here: a receiver carrying CineBall's own name and colours
  /// has to be registered in the Google Cast Developer Console, and only the
  /// owner of that account can do it. Swapping this constant for the id it
  /// issues is the only change that takes.
  static const String receiverAppId = 'CC1AD845';

  static bool _contextReady = false;

  /// Starts the Cast framework, once, before anything asks it for a device.
  ///
  /// Safe to call from app start on every platform: anything other than
  /// Android and iOS has no Cast SDK behind it, and saying so quietly here
  /// keeps the check out of every call site.
  static Future<void> ensureStarted() async {
    if (_contextReady) return;
    if (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    try {
      // Never awaited to completion, because it never completes: the
      // plugin's Android handler configures the Cast framework and returns
      // without ever calling back into Flutter, so the future it hands over
      // hangs for the life of the app. Awaiting it in main() is what put a
      // white screen in front of the viewer — runApp was never reached.
      //
      // The work on the other side is synchronous, so once the call has had
      // a moment to land, the framework is up whether or not anyone says so.
      await GoogleCastContext.instance
          .setSharedInstanceWithOptions(
            GoogleCastOptionsAndroid(appId: receiverAppId),
          )
          .timeout(const Duration(seconds: 2), onTimeout: () => true);
      _contextReady = true;
    } catch (e) {
      // A handset without Play Services has no Cast framework to start. The
      // browser receiver still works, so this is a missing device list, not
      // a broken app.
      debugPrint('[cast] google cast unavailable: $e');
    }
  }

  final StreamController<CastPlaybackEvent> _events = StreamController<CastPlaybackEvent>.broadcast();

  late final StreamSubscription<GoggleCastMediaStatus?> _media;
  late final StreamSubscription<Duration> _ticks;
  late final StreamSubscription<GoogleCastSession?> _sessions;

  /// The SDK's device objects, kept by id: connecting needs the whole thing
  /// back, and [CastDevice] deliberately carries only what a widget draws.
  final Map<String, GoogleCastDevice> _found = <String, GoogleCastDevice>{};

  CastDevice? _device;
  double _volumeBeforeMute = 1;

  @override
  CastTransport get transport => CastTransport.googleCast;

  @override
  Stream<CastPlaybackEvent> get events => _events.stream;

  /// Televisions as they appear and disappear on the network.
  ///
  /// The sheet watches this rather than polling: a Chromecast can take a few
  /// seconds to answer, and a list that fills in as they reply reads far
  /// better than one that is empty until it is not.
  Stream<List<CastDevice>> get deviceStream => GoogleCastDiscoveryManager.instance.devicesStream.map(_remember);

  Future<void> startDiscovery() async {
    await ensureStarted();
    if (!_contextReady) return;
    await _askForTheLocalNetwork();
    try {
      await GoogleCastDiscoveryManager.instance.startDiscovery();
    } catch (e) {
      debugPrint('[cast] discovery: $e');
    }
  }

  /// Asks for the permission that finding a television actually needs.
  ///
  /// A Chromecast is found by mDNS on the local wifi, and from Android 13
  /// that is behind NEARBY_WIFI_DEVICES. Denied, discovery still runs and
  /// still reports nothing wrong — it simply never sees a device, which is
  /// indistinguishable from a house with no Chromecast in it.
  ///
  /// Asked here rather than at startup: the viewer is looking at a list of
  /// televisions when the prompt appears, so what it is for is obvious.
  /// A refusal is not fatal; the browser receiver does not need it.
  static Future<void> _askForTheLocalNetwork() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final status = await Permission.nearbyWifiDevices.status;
      // isPermanentlyDenied means only the system settings can undo it, and
      // asking again from here would do nothing at all.
      if (status.isGranted || status.isPermanentlyDenied) return;
      await Permission.nearbyWifiDevices.request();
    } catch (e) {
      // Older Android has no such permission and answers with an error;
      // discovery there works without it.
      debugPrint('[cast] nearby devices permission: $e');
    }
  }

  /// Whether the Cast framework is up at all: false on a handset without
  /// Play Services, where no Chromecast can ever be listed.
  static bool get frameworkReady => _contextReady;

  /// True when the viewer has refused, for good, the permission a Cast
  /// search needs (Android 13 and later): the search then finds nothing
  /// and says nothing, so this is the one thing to tell them.
  static Future<bool> searchBlockedByPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final status = await Permission.nearbyWifiDevices.status;
      return status.isPermanentlyDenied || status.isDenied;
    } catch (_) {
      return false;
    }
  }

  /// Opens the app's page in the system settings, where a refused
  /// permission can be given.
  static Future<void> openSettings() async {
    try {
      await openAppSettings();
    } catch (_) {}
  }

  Future<void> stopDiscovery() async {
    if (!_contextReady) return;
    try {
      await GoogleCastDiscoveryManager.instance.stopDiscovery();
    } catch (_) {}
  }

  @override
  Future<List<CastDevice>> discoverDevices() async {
    await startDiscovery();
    if (!_contextReady) return const [];
    return _remember(GoogleCastDiscoveryManager.instance.devices);
  }

  List<CastDevice> _remember(List<GoogleCastDevice> devices) {
    _found
      ..clear()
      ..addEntries(devices.map((d) => MapEntry(d.deviceID, d)));
    return devices.map(_asCastDevice).toList(growable: false);
  }

  CastDevice _asCastDevice(GoogleCastDevice d) => CastDevice(
        id: d.deviceID,
        name: d.friendlyName,
        subtitle: d.modelName?.trim().isNotEmpty ?? false ? d.modelName!.trim() : 'Google Cast',
        transport: CastTransport.googleCast,
      );

  @override
  Future<void> connect(CastDevice device) async {
    await ensureStarted();
    final target = _found[device.id];
    if (target == null) {
      throw const CastException('لم يعد الجهاز ظاهرًا على الشبكة', code: 404);
    }
    // A session that does not start is usually a session that will start
    // on the next try: the set was asleep, or the first mDNS answer was
    // stale. Said so, and the controller asks again.
    final started = await GoogleCastSessionManager.instance
        .startSessionWithDevice(target)
        .timeout(const Duration(seconds: 15), onTimeout: () => false);
    if (!started) {
      throw const CastException('تعذّر الاتصال بالتلفاز', retryable: true);
    }
    _device = device;
  }

  @override
  Future<void> disconnect() async {
    _device = null;
    if (!_contextReady) return;
    try {
      await GoogleCastSessionManager.instance.endSessionAndStopCasting();
    } catch (_) {}
  }

  @override
  Future<void> loadMedia(CastMedia media) async {
    if (_device == null) throw const CastException('لا يوجد جهاز متصل');

    final images = <GoogleCastImage>[
      if (media.posterUrl.isNotEmpty) GoogleCastImage(url: Uri.parse(media.posterUrl)),
    ];

    await GoogleCastRemoteMediaClient.instance.loadMedia(
      GoogleCastMediaInformationAndroid(
        contentId: media.mediaId,
        contentUrl: Uri.parse(media.streamUrl),
        // A live channel has no end to seek towards, and telling the receiver
        // so is what turns its scrubber into a LIVE badge.
        streamType: media.isLive ? CastMediaStreamType.LIVE : CastMediaStreamType.BUFFERED,
        contentType: media.contentType ?? (media.isHls ? 'application/x-mpegURL' : 'video/mp4'),
        duration: media.duration,
        metadata: GoogleCastMovieMediaMetadataAndroid(
          title: media.title,
          subtitle: media.description.isEmpty ? null : media.description,
          images: images.isEmpty ? null : images,
        ),
      ),
      autoPlay: true,
      playPosition: media.isLive ? Duration.zero : media.position,
    );
  }

  @override
  Future<void> play() => GoogleCastRemoteMediaClient.instance.play();

  @override
  Future<void> pause() => GoogleCastRemoteMediaClient.instance.pause();

  @override
  Future<void> seek(Duration position) => GoogleCastRemoteMediaClient.instance.seek(
        GoogleCastMediaSeekOption(position: position),
      );

  @override
  Future<void> setVolume(double volume) async {
    final value = volume.clamp(0.0, 1.0);
    if (value > 0) _volumeBeforeMute = value;
    GoogleCastSessionManager.instance.setDeviceVolume(value);
  }

  /// Cast has no mute of its own here, only a volume.
  ///
  /// Silencing is therefore a trip to zero and back, which is why the level
  /// on the way down is kept: unmuting to some assumed default would be a
  /// surprise on a television somebody had set quietly on purpose.
  @override
  Future<void> setMuted(bool muted) => setVolume(muted ? 0 : _volumeBeforeMute);

  @override
  Future<void> stop() => GoogleCastRemoteMediaClient.instance.stop();

  void _emit(CastPlaybackEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  void _onStatus(GoggleCastMediaStatus? status) {
    if (status == null) return;
    final state = status.playerState;

    // Idle after something played means it ran out; idle before anything did
    // is just a receiver waiting, and must not be reported as an ending.
    final ended = state == CastMediaPlayerState.idle && status.idleReason == GoogleCastMediaIdleReason.finished;

    _emit(CastPlaybackEvent(
      duration: status.mediaInformation?.duration,
      isPlaying: state == CastMediaPlayerState.playing || state == CastMediaPlayerState.buffering,
      isMuted: status.isMuted || status.volume == 0,
      volume: status.volume.toDouble(),
      ended: ended,
    ));
  }

  void _onSession(GoogleCastSession? session) {
    final connected = session != null && session.connectionState == GoogleCastConnectState.ConnectionStateConnected;
    if (connected) {
      _emit(CastPlaybackEvent(
        isMuted: session.currentDeviceMuted,
        volume: session.currentDeviceVolume.toDouble(),
      ));
      return;
    }
    // The television was switched off, or somebody else took it over.
    if (_device != null) {
      _device = null;
      _emit(const CastPlaybackEvent(disconnected: true));
    }
  }

  @override
  void dispose() {
    _media.cancel();
    _ticks.cancel();
    _sessions.cancel();
    _events.close();
  }
}
