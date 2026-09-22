import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/cast_models.dart';
import 'cast_service.dart';
import 'local_stream_server.dart';

/// Casting to a smart television over DLNA.
///
/// Samsung and LG sets do not speak Google Cast — a Chromecast search will
/// never find one, however long it looks. What nearly all of them do speak
/// is UPnP: they announce themselves as a MediaRenderer, and they accept a
/// url and a handful of commands over SOAP. That is what this is.
///
/// Pure Dart, deliberately. The discovery is an SSDP M-SEARCH, whose replies
/// come back unicast to the port they were sent from, so no multicast
/// membership and no native code are needed on either platform.
///
/// The television fetches the stream itself, exactly as a Chromecast does,
/// so a source that refuses a plain request has to go through the relay
/// first. See [CastMediaSource].
class DlnaCastService implements CastService {
  static const String _group = '239.255.255.250';
  static const int _port = 1900;

  static const String _avTransport = 'urn:schemas-upnp-org:service:AVTransport:1';
  static const String _rendering = 'urn:schemas-upnp-org:service:RenderingControl:1';
  static const String _connection =
      'urn:schemas-upnp-org:service:ConnectionManager:1';

  final StreamController<CastPlaybackEvent> _events =
      StreamController<CastPlaybackEvent>.broadcast();

  /// Control endpoints for every renderer found, by device id.
  final Map<String, _Renderer> _found = <String, _Renderer>{};

  _Renderer? _target;
  Timer? _poll;
  double _volumeBeforeMute = 1;

  /// Position requests that have failed in a row. Reset by any answer.
  int _silentPolls = 0;

  /// True once either watchdog has declared the set gone.
  ///
  /// One flag rather than two cancelled timers, because cancelling a timer
  /// does not stop the requests it already sent: with a set that answers
  /// nothing, every poll sits on its timeout for three seconds while the
  /// next fires two seconds in, so several are in the air at once. Each one
  /// that came back after the verdict said «stopped responding» again.
  /// Anything that completes after this is set does nothing at all.
  bool _lost = false;

  /// At most one position request in flight.
  bool _asking = false;

  /// The one-shot check that the set came to fetch the film.
  ///
  /// Held so that whichever of the two watchdogs speaks first can silence
  /// the other: a set that has stopped answering the phone trips both, and
  /// two messages about one fault is one too many.
  Timer? _silence;

  /// After this many misses the set is treated as gone: the remote is told,
  /// and the polling stops instead of logging the same line every two
  /// seconds for the rest of the evening.
  static const int _maxSilentPolls = 5;

  /// Stands between the set and the internet. See [LocalStreamServer].
  final LocalStreamServer _local = LocalStreamServer();

  @override
  CastTransport get transport => CastTransport.dlna;

  @override
  Stream<CastPlaybackEvent> get events => _events.stream;

  // ------------------------------------------------------------ discovery
  @override
  Future<List<CastDevice>> discoverDevices() async {
    final locations = await _search();
    if (locations.isEmpty) return const [];

    // Descriptions are fetched together: a television that is slow to answer
    // should not hold up one that is quick.
    final described = await Future.wait(
      locations.map(_describe),
      eagerError: false,
    );

    _found.clear();
    for (final renderer in described) {
      if (renderer == null) continue;
      _found[renderer.id] = renderer;
    }

    return _found.values
        .map((r) => CastDevice(
              id: r.id,
              name: r.name,
              subtitle: r.model.isEmpty ? 'DLNA' : r.model,
              transport: CastTransport.dlna,
            ))
        .toList(growable: false);
  }

  /// Takes on a renderer by its description url, skipping the search.
  ///
  /// Discovery is the one part of this that needs a real network, and the
  /// part with the least logic in it. Everything after the SSDP reply —
  /// reading the description, finding the control endpoints, every command
  /// — begins here, so this is where a test can get hold of it.
  @visibleForTesting
  Future<List<CastDevice>> debugAdopt(String location) async {
    final renderer = await _describe(location);
    if (renderer == null) return const [];
    _found[renderer.id] = renderer;
    return [
      CastDevice(
        id: renderer.id,
        name: renderer.name,
        subtitle: renderer.model.isEmpty ? 'DLNA' : renderer.model,
        transport: CastTransport.dlna,
      ),
    ];
  }

  /// Asks the network for media renderers and collects where they live.
  ///
  /// Sent more than once because this is UDP and a single packet going
  /// missing would mean a television that simply never appears.
  Future<Set<String>> _search({
    Duration listenFor = const Duration(seconds: 4),
  }) async {
    final locations = <String>{};
    RawDatagramSocket? socket;

    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      final message = <int>[
        ...'M-SEARCH * HTTP/1.1\r\n'
            'HOST: $_group:$_port\r\n'
            'MAN: "ssdp:discover"\r\n'
            'MX: 2\r\n'
            'ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n'
            '\r\n'
            .codeUnits,
      ];

      final target = InternetAddress(_group);
      final done = Completer<void>();

      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final packet = socket?.receive();
        if (packet == null) return;
        final location = _headerValue(
          String.fromCharCodes(packet.data),
          'location',
        );
        if (location != null && location.startsWith('http')) {
          locations.add(location);
        }
      }, onError: (Object e) => debugPrint('[cast] ssdp: $e'));

      for (var i = 0; i < 3; i++) {
        socket.send(message, target, _port);
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }

      Timer(listenFor, () {
        if (!done.isCompleted) done.complete();
      });
      await done.future;
    } catch (e) {
      // A network that refuses multicast is a network with no televisions
      // on it as far as this is concerned.
      debugPrint('[cast] ssdp search failed: $e');
    } finally {
      socket?.close();
    }

    return locations;
  }

  static String? _headerValue(String response, String name) {
    for (final line in response.split('\r\n')) {
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      if (line.substring(0, colon).trim().toLowerCase() != name) continue;
      return line.substring(colon + 1).trim();
    }
    return null;
  }

  /// Reads a renderer's description and finds the endpoints worth keeping.
  Future<_Renderer?> _describe(String location) async {
    try {
      final xml = await _get(location);
      if (xml == null) return null;

      final name = _tag(xml, 'friendlyName') ?? 'تلفاز';
      final model = _tag(xml, 'modelName') ?? '';
      final udn = _tag(xml, 'UDN') ?? location;

      final control = _controlUrl(xml, _avTransport, location);
      // Without AVTransport there is nothing to send a film to; a renderer
      // that only does RenderingControl is a volume knob.
      if (control == null) return null;

      return _Renderer(
        id: udn,
        name: name,
        model: model,
        avTransport: control,
        renderingControl: _controlUrl(xml, _rendering, location),
        connectionManager: _controlUrl(xml, _connection, location),
      );
    } catch (e) {
      debugPrint('[cast] describe $location: $e');
      return null;
    }
  }

  /// The control url of [serviceType], resolved against [base].
  ///
  /// Read out of the one `<service>` block that names the service, because
  /// a renderer lists several and their control urls all look alike.
  static String? _controlUrl(String xml, String serviceType, String base) {
    for (final block in _blocks(xml, 'service')) {
      if (!block.contains(serviceType)) continue;
      final control = _tag(block, 'controlURL');
      if (control == null) continue;
      return Uri.parse(base).resolve(control).toString();
    }
    return null;
  }

  static Iterable<String> _blocks(String xml, String tag) sync* {
    final open = '<$tag>';
    final close = '</$tag>';
    var at = 0;
    while (true) {
      final start = xml.indexOf(open, at);
      if (start < 0) return;
      final end = xml.indexOf(close, start);
      if (end < 0) return;
      yield xml.substring(start + open.length, end);
      at = end + close.length;
    }
  }

  static String? _tag(String xml, String tag) {
    final start = xml.indexOf('<$tag>');
    if (start < 0) return null;
    final end = xml.indexOf('</$tag>', start);
    if (end < 0) return null;
    return xml.substring(start + tag.length + 2, end).trim();
  }

  // ------------------------------------------------------------ connecting
  @override
  Future<void> connect(CastDevice device) async {
    final renderer = _found[device.id];
    if (renderer == null) {
      throw const CastException('لم يعد التلفاز ظاهرًا على الشبكة');
    }
    // Actually speak to it before saying it is connected.
    //
    // This used to just write the address down, so «تم الربط» meant no more
    // than «it answered a multicast question a moment ago» — and a device
    // can answer that while refusing every connection after it. Windows
    // Media Player does exactly that: it announces itself to the whole
    // network and then lets only the machines on its own allowed list
    // through the firewall. Discovery works, the connection appears to
    // succeed, and every command quietly times out behind a black screen.
    //
    // One real question here turns that into a sentence somebody can act
    // on, and it names the device so it can be found in its own settings.
    try {
      await _soap(renderer.avTransport, _avTransport, 'GetTransportInfo',
          '<InstanceID>0</InstanceID>').timeout(const Duration(seconds: 8));
    } on CastException {
      rethrow;
    } catch (e) {
      debugPrint('[cast] ${renderer.name} did not answer: $e');
      throw CastException(
        '«${renderer.name}» يظهر على الشبكة لكنه يرفض الاتصال — اسمح لهذا '
        'الهاتف في إعدادات مشاركة الوسائط على ذلك الجهاز',
      );
    }

    _target = renderer;
    unawaited(_reportWhatItAccepts(renderer));
  }

  /// Asks the set what it can actually play, and writes it down.
  ///
  /// Every UPnP renderer answers GetProtocolInfo with the list of formats
  /// it accepts, and the DLNA profile names in it say how far its decoder
  /// goes — `AVC_MP4_MP_HD_1080i` and the like. It is the difference
  /// between knowing why a film shows black and guessing at it, and there
  /// is no other way to find out from here.
  ///
  /// Nothing is decided on it yet; it is logged so the next black screen
  /// has an answer waiting.
  Future<void> _reportWhatItAccepts(_Renderer renderer) async {
    final control = renderer.connectionManager;
    if (control == null) return;
    try {
      final reply = await _soap(
        control, _connection, 'GetProtocolInfo', '',
      );
      final sink = _tag(reply ?? '', 'Sink') ?? '';
      if (sink.isEmpty) {
        debugPrint('[cast] ${renderer.name} lists no formats');
        return;
      }
      final video = sink
          .split(',')
          .where((f) => f.contains('video/'))
          .toList();
      debugPrint('[cast] ${renderer.name} accepts ${video.length} video formats');
      // The profile names are what matter, and there can be hundreds, so
      // only the distinct ones are worth the log.
      final profiles = <String>{};
      for (final format in video) {
        final at = format.indexOf('DLNA.ORG_PN=');
        if (at < 0) continue;
        profiles.add(format.substring(at + 12).split(';').first);
      }
      debugPrint('[cast] profiles: ${profiles.take(40).join(", ")}');
    } catch (e) {
      debugPrint('[cast] GetProtocolInfo: $e');
    }
  }

  @override
  Future<void> disconnect() async {
    _poll?.cancel();
    _poll = null;
    _silence?.cancel();
    _silence = null;
    // The addresses handed out stop working the moment casting does; one
    // that outlived its film would be a signed url left lying about.
    _local.clear();
    final renderer = _target;
    _target = null;
    if (renderer == null) return;
    try {
      await _soap(renderer.avTransport, _avTransport, 'Stop',
          '<InstanceID>0</InstanceID>');
    } catch (_) {}
  }

  // -------------------------------------------------------------- playback
  @override
  Future<void> loadMedia(CastMedia media) async {
    final renderer = _target;
    if (renderer == null) throw const CastException('لا يوجد جهاز متصل');

    final mime = media.contentType ??
        (media.isHls ? 'application/x-mpegURL' : 'video/mp4');

    // The set fetches through the phone rather than straight from the CDN.
    // It cannot do the https the catalogue serves, and it will not follow
    // the redirect the CDN answers with — handed the real address it opens
    // its player, fails without a word and drops back out.
    //
    // If the phone cannot put up a server, the original address is used
    // anyway: on a set that does cope with https it still works, and a
    // stream that might play beats one that certainly will not.
    final served =
        await _local.publish(media.streamUrl, contentType: mime) ?? media.streamUrl;

    // DLNA.ORG_OP=01 says byte-seeking is available, which is what gives the
    // television a scrubber instead of a bare play button. The flags mark it
    // as a stream that can be played as it arrives.
    final protocol = 'http-get:*:$mime:'
        'DLNA.ORG_OP=01;DLNA.ORG_CI=0;'
        'DLNA.ORG_FLAGS=01700000000000000000000000000000';

    // Without this block a television shows the url as the title, and some
    // refuse a stream whose kind they have not been told.
    final didl = '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">'
        '<item id="0" parentID="-1" restricted="1">'
        '<dc:title>${_escape(media.title)}</dc:title>'
        '<upnp:class>object.item.videoItem</upnp:class>'
        '<res protocolInfo="${_escape(protocol)}">${_escape(served)}</res>'
        '</item></DIDL-Lite>';

    await _soap(
      renderer.avTransport,
      _avTransport,
      'SetAVTransportURI',
      '<InstanceID>0</InstanceID>'
      '<CurrentURI>${_escape(served)}</CurrentURI>'
      '<CurrentURIMetaData>${_escape(didl)}</CurrentURIMetaData>',
    );

    await play();

    if (!media.isLive && media.position > Duration.zero) {
      // Seeking before the set has loaded the stream is refused, so it waits
      // a moment rather than starting the film over from the beginning.
      unawaited(Future<void>.delayed(const Duration(milliseconds: 1200), () {
        seek(media.position).catchError((Object _) {});
      }));
    }

    _startPolling();
    _watchForSilence();
  }

  /// Says something when the television never comes to collect the film.
  ///
  /// The set accepts the command either way, so from the phone's side a
  /// black screen and a playing film look identical. The one thing that
  /// tells them apart is whether anything ever asked the phone's server for
  /// the stream — and if nothing did, the two are not on speaking terms,
  /// which is almost always a router keeping its wifi clients apart or a
  /// phone still on mobile data.
  void _watchForSilence() {
    if (!_local.isRunning) return;
    _silence?.cancel();
    _silence = Timer(const Duration(seconds: 12), () {
      _silence = null;
      if (_events.isClosed || _target == null || _lost) return;
      if (_local.wasFetched) return;
      // The poll would only go on to say the same thing in other words.
      _lost = true;
      _poll?.cancel();
      _poll = null;
      _events.add(const CastPlaybackEvent(
        error: 'التلفاز لم يستطع الوصول إلى الهاتف — تأكّد أنهما على نفس شبكة الواي فاي',
      ));
    });
  }

  @override
  Future<void> play() => _transport('Play', '<InstanceID>0</InstanceID><Speed>1</Speed>');

  @override
  Future<void> pause() => _transport('Pause', '<InstanceID>0</InstanceID>');

  @override
  Future<void> seek(Duration position) => _transport(
        'Seek',
        '<InstanceID>0</InstanceID><Unit>REL_TIME</Unit>'
        '<Target>${_clock(position)}</Target>',
      );

  @override
  Future<void> stop() async {
    _poll?.cancel();
    _poll = null;
    _silence?.cancel();
    _silence = null;
    await _transport('Stop', '<InstanceID>0</InstanceID>');
  }

  @override
  Future<void> setVolume(double volume) async {
    final renderer = _target;
    final control = renderer?.renderingControl;
    if (control == null) return;
    final value = (volume.clamp(0.0, 1.0) * 100).round();
    if (value > 0) _volumeBeforeMute = volume.clamp(0.0, 1.0);
    try {
      await _soap(control, _rendering, 'SetVolume',
          '<InstanceID>0</InstanceID><Channel>Master</Channel>'
          '<DesiredVolume>$value</DesiredVolume>');
    } catch (e) {
      debugPrint('[cast] volume: $e');
    }
  }

  @override
  Future<void> setMuted(bool muted) async {
    final renderer = _target;
    final control = renderer?.renderingControl;
    // Unlike Cast, UPnP has a mute of its own; the remembered level is only
    // needed when a set turns out not to implement it.
    if (control == null) return setVolume(muted ? 0 : _volumeBeforeMute);
    try {
      await _soap(control, _rendering, 'SetMute',
          '<InstanceID>0</InstanceID><Channel>Master</Channel>'
          '<DesiredMute>${muted ? 1 : 0}</DesiredMute>');
    } catch (_) {
      await setVolume(muted ? 0 : _volumeBeforeMute);
    }
  }

  Future<void> _transport(String action, String body) async {
    final renderer = _target;
    if (renderer == null) throw const CastException('لا يوجد جهاز متصل');
    await _soap(renderer.avTransport, _avTransport, action, body);
  }

  // ---------------------------------------------------------- where it got to
  /// UPnP has no way to tell the phone anything; it only answers questions.
  /// So the position is asked for, every couple of seconds — often enough
  /// for a progress bar, rarely enough to leave the television alone.
  void _startPolling() {
    _poll?.cancel();
    _silentPolls = 0;
    _lost = false;
    _asking = false;
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _askPosition());
  }

  Future<void> _askPosition() async {
    final renderer = _target;
    if (renderer == null || _events.isClosed || _lost || _asking) return;
    _asking = true;
    try {
      final reply = await _soap(renderer.avTransport, _avTransport,
          'GetPositionInfo', '<InstanceID>0</InstanceID>');
      // The verdict may have come in while this was waiting.
      if (_lost || _events.isClosed) return;
      if (reply == null) return;

      final position = _parseClock(_tag(reply, 'RelTime'));
      final duration = _parseClock(_tag(reply, 'TrackDuration'));

      _silentPolls = 0;
      _events.add(CastPlaybackEvent(
        position: position,
        // A live stream reports no duration, and reporting zero would make
        // the remote's scrubber jump to the end.
        duration: (duration?.inSeconds ?? 0) > 0 ? duration : null,
      ));
    } catch (e) {
      if (_lost || _events.isClosed) return;
      _silentPolls++;
      debugPrint('[cast] position ($_silentPolls/$_maxSilentPolls): $e');
      if (_silentPolls < _maxSilentPolls) return;
      // Five misses in a row is ten seconds of a set that has stopped
      // talking to this phone. Say so once and stop asking — and stop the
      // other watchdog too, or it says it again a moment later.
      _lost = true;
      _poll?.cancel();
      _poll = null;
      _silence?.cancel();
      _silence = null;
      _events.add(const CastPlaybackEvent(
        error: 'التلفاز توقّف عن الاستجابة للهاتف — أعد تشغيل التلفاز أو أعد الاتصال بالشبكة',
      ));
    } finally {
      _asking = false;
    }
  }

  // ------------------------------------------------------------------ plumbing
  /// One client per service rather than one per process, so it can be shut
  /// with the service — and so a test gets a client made under its own
  /// conditions instead of whatever the first caller left behind.
  // Three seconds, not six. Every set on the network is described in
  // parallel, but the sheet shows nothing until the slowest answers — and a
  // set that has stopped answering the phone (which happens) held the whole
  // list back for the full six. Three is still generous for a LAN.
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 3);

  Future<String?> _get(String url) async {
    final request = await _http.getUrl(Uri.parse(url));
    final response = await request.close().timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;
    final chunks = <int>[];
    await for (final chunk in response) {
      chunks.addAll(chunk);
      // A description is a couple of kilobytes; anything larger is not one.
      if (chunks.length > 512 * 1024) break;
    }
    return _decode(chunks);
  }

  /// Bytes to text, without throwing away a reply over one character.
  ///
  /// Descriptions are utf-8 in practice and a set named in Arabic is
  /// unreadable any other way — widening byte for byte turns «شاشة الصالة»
  /// into mojibake. But a handful of renderers answer in latin-1, and a
  /// strict utf-8 decode on those throws, which would lose the whole reply.
  /// So: utf-8 first, latin-1 if that fails.
  static String _decode(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes, allowInvalid: true);
    }
  }

  Future<String?> _soap(
    String control,
    String service,
    String action,
    String body,
  ) async {
    final envelope = '<?xml version="1.0"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        '<s:Body><u:$action xmlns:u="$service">$body</u:$action></s:Body>'
        '</s:Envelope>';

    final request = await _http.postUrl(Uri.parse(control));
    request.headers.set('Content-Type', 'text/xml; charset="utf-8"');
    request.headers.set('SOAPAction', '"$service#$action"');
    // utf8.encode, not codeUnits: a Dart string's code units are utf-16,
    // and handing those to a byte sink truncates every Arabic character to
    // rubbish. The film's title travels in here.
    request.add(utf8.encode(envelope));

    final response = await request.close().timeout(const Duration(seconds: 10));
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
    }
    final text = _decode(bytes);

    if (response.statusCode >= 400) {
      throw CastException('رفض التلفاز الأمر (${response.statusCode})');
    }
    return text;
  }

  static String _escape(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  /// UPnP wants `H:MM:SS`, and will not take anything else.
  static String _clock(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  static Duration? _parseClock(String? text) {
    if (text == null) return null;
    final parts = text.split(':');
    if (parts.length != 3) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final s = int.tryParse(parts[2].split('.').first);
    if (h == null || m == null || s == null) return null;
    return Duration(hours: h, minutes: m, seconds: s);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _silence?.cancel();
    _events.close();
    _http.close(force: true);
    unawaited(_local.stop());
  }
}

/// One media renderer, and where to reach its services.
@immutable
class _Renderer {
  const _Renderer({
    required this.id,
    required this.name,
    required this.model,
    required this.avTransport,
    required this.renderingControl,
    required this.connectionManager,
  });

  final String id;
  final String name;
  final String model;

  /// Loading, playing, pausing, seeking.
  final String avTransport;

  /// Volume and mute; a few renderers do without it.
  final String? renderingControl;

  /// Where to ask what the set can play.
  final String? connectionManager;
}
