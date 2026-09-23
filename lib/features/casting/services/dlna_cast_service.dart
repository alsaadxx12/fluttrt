import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../models/cast_models.dart';
import 'cast_service.dart';
import 'local_stream_server.dart';
import 'mkv_remux.dart';

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
  /// Sweeps in a row a known set has failed to answer.
  final Map<String, int> _misses = <String, int>{};

  /// A set is dropped from the list after this many sweeps without it.
  ///
  /// One missed sweep is nothing — a multicast reply goes astray on a busy
  /// wifi all the time — and a list that emptied on every miss was a set
  /// that vanished from under the viewer's finger, with «لم يعد ظاهرًا»
  /// for a device that was on and playing.
  static const int _maxMisses = 3;

  @override
  Future<List<CastDevice>> discoverDevices() async {
    final locations = await _search();

    // Descriptions are fetched together: a television that is slow to answer
    // should not hold up one that is quick.
    final described = locations.isEmpty
        ? const <_Renderer?>[]
        : await Future.wait(locations.map(_describe), eagerError: false);

    final seen = <String>{};
    for (final renderer in described) {
      if (renderer == null) continue;
      seen.add(renderer.id);
      _misses.remove(renderer.id);
      // What the set said it could play is remembered across sweeps; the
      // set has not changed its mind since it was asked.
      renderer.acceptsMatroska ??= _found[renderer.id]?.acceptsMatroska;
      _found[renderer.id] = renderer;
      // A set that restarted comes back on a new port; the one being talked
      // to follows it there rather than going on knocking at the old one.
      final target = _target;
      if (target != null && target.id == renderer.id &&
          target.avTransport != renderer.avTransport) {
        _target = renderer;
      }
    }
    for (final id in _found.keys.toList()) {
      if (seen.contains(id)) continue;
      final misses = (_misses[id] ?? 0) + 1;
      if (misses >= _maxMisses && id != _target?.id) {
        _found.remove(id);
        _misses.remove(id);
      } else {
        _misses[id] = misses;
      }
    }

    return _found.values
        .map((r) => CastDevice(
              id: r.id,
              name: r.name,
              subtitle: r.model.isEmpty ? 'DLNA' : r.model,
              brand: r.maker,
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
        brand: renderer.maker,
        transport: CastTransport.dlna,
      ),
    ];
  }

  /// What the network is asked for.
  ///
  /// The renderer type first, which is the direct question. Then the root
  /// device, because a few sets — LG among them, and some of the Android
  /// televisions Haier and others sell — answer only for their root and
  /// keep the renderer as an embedded device inside it. Their description
  /// lists the same AVTransport service, so [_describe] finds it either
  /// way; the router and the printer that answer too are read and dropped.
  static const List<String> _searchTargets = [
    'urn:schemas-upnp-org:device:MediaRenderer:1',
    'upnp:rootdevice',
  ];

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

      final messages = [
        for (final st in _searchTargets)
          'M-SEARCH * HTTP/1.1\r\n'
              'HOST: $_group:$_port\r\n'
              'MAN: "ssdp:discover"\r\n'
              'MX: 2\r\n'
              'ST: $st\r\n'
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
        for (final message in messages) {
          socket.send(message, target, _port);
        }
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
      final maker = '${_tag(xml, 'manufacturer') ?? ''} $model'.trim();
      final udn = _tag(xml, 'UDN') ?? location;

      final control = _controlUrl(xml, _avTransport, location);
      // Without AVTransport there is nothing to send a film to; a renderer
      // that only does RenderingControl is a volume knob.
      if (control == null) return null;

      return _Renderer(
        id: udn,
        name: name,
        model: model,
        maker: maker,
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
      throw const CastException('لم يعد التلفاز ظاهرًا على الشبكة', code: 404);
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
    //
    // Asked three times before it is called a refusal. A set that has just
    // been switched on answers its first question late or not at all, and
    // one question with one timeout was «يرفض الاتصال» for a television
    // that was merely slow.
    try {
      await _retrying(
        () => _soap(renderer.avTransport, _avTransport, 'GetTransportInfo',
            '<InstanceID>0</InstanceID>').timeout(const Duration(seconds: 6)),
        what: 'GetTransportInfo on ${renderer.name}',
      );
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
    // Waited for, briefly, rather than left to run: whether the film goes
    // as an mkv with its subtitle or as a plain mp4 depends on the answer,
    // and the film is usually sent the moment this returns.
    if (renderer.acceptsMatroska == null) {
      await _reportWhatItAccepts(renderer)
          .timeout(const Duration(seconds: 4), onTimeout: () {});
    }
  }

  /// How many times a command is sent before its failure is believed.
  static const int _tries = 3;

  /// Runs [run], and again after a pause when what went wrong is the kind
  /// of thing that goes right the second time.
  ///
  /// A refusal — a UPnP error, a 4xx — is not tried again; the set has
  /// answered. A timeout, a dropped socket or a «not now» (701) is.
  Future<T> _retrying<T>(
    Future<T> Function() run, {
    required String what,
    Duration pause = const Duration(seconds: 1),
  }) async {
    for (var attempt = 1;; attempt++) {
      try {
        return await run();
      } catch (e) {
        if (attempt >= _tries || !_transient(e)) rethrow;
        debugPrint('[cast] $what ($attempt/$_tries): $e');
        await Future<void>.delayed(pause * attempt);
      }
    }
  }

  static bool _transient(Object e) =>
      e is TimeoutException ||
      e is SocketException ||
      e is HttpException ||
      (e is CastException && e.retryable);

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
      // Whether a Matroska file is worth sending. A set that names the
      // format plays it; one that lists formats and leaves it out will
      // refuse it, and is handed the mp4 straight away rather than after a
      // failed try; one that says `*` has not said.
      final lower = sink.toLowerCase();
      renderer.acceptsMatroska = lower.contains('matroska') || lower.contains('mkv')
          ? true
          : (lower.contains(':*:*') ? null : false);
      debugPrint('[cast] ${renderer.name} plays matroska: ${renderer.acceptsMatroska ?? "unknown"}');
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
    _generation++;
    _poll?.cancel();
    _poll = null;
    _silence?.cancel();
    _silence = null;
    // The addresses handed out stop working the moment casting does; one
    // that outlived its film would be a signed url left lying about.
    _local.clear();
    final renderer = _target;
    if (renderer == null) return;
    try {
      await _soap(renderer.avTransport, _avTransport, 'Stop',
          '<InstanceID>0</InstanceID>').timeout(const Duration(seconds: 4));
      await _clearScreen();
    } catch (_) {}
    _target = null;
  }

  // -------------------------------------------------------------- playback
  /// Which sending of a film is the current one.
  ///
  /// Bumped by every load, stop and disconnect. The watchers a load leaves
  /// behind — the one that checks the set actually started, the one that
  /// falls back to the mp4 — compare against it and stand down when the
  /// film they were watching has been replaced.
  int _generation = 0;

  /// How long the set is given to start before it is judged to have
  /// refused the film.
  ///
  /// Generous, because on a slow connection the phone's first window
  /// takes a while to arrive from the CDN and the set sits in
  /// TRANSITIONING honestly while it waits. A set that has rejected the
  /// file says STOPPED long before this; the limit is for the one that
  /// says nothing at all.
  static const Duration _confirmFor = Duration(seconds: 45);

  @override
  Future<void> loadMedia(CastMedia media) async {
    final renderer = _target;
    if (renderer == null) throw const CastException('لا يوجد جهاز متصل');
    final generation = ++_generation;

    final mime = media.contentType ??
        (media.isHls ? 'application/x-mpegURL' : 'video/mp4');

    // The set fetches through the phone rather than straight from the CDN.
    // It cannot do the https the catalogue serves, and it will not follow
    // the redirect the CDN answers with — handed the real address it opens
    // its player, fails without a word and drops back out.
    //
    // The subtitle goes with it. A television's player shows no sidecar
    // subtitle, whatever it is told about one; what it does show is a
    // subtitle track inside a Matroska file, so the server is handed the
    // text and puts the film inside one — unless the set has said it plays
    // no Matroska, in which case the mp4 goes and the subtitle stays.
    final clock = Stopwatch()..start();
    // Started now and waited for later, inside the server, once the film's
    // index has been read: the two downloads overlap instead of queueing.
    final wantsSubtitle = !media.isLive &&
        !media.isHls &&
        media.subtitleUrl != null &&
        renderer.acceptsMatroska != false;
    final subtitle = wantsSubtitle ? _subtitleText(media.subtitleUrl!) : null;

    final plan = _Plan(
      media: media,
      mime: mime,
      subtitle: subtitle,
      withSubtitle: wantsSubtitle,
    );
    await _start(renderer, plan, generation, clock: clock);
  }

  /// Publishes the film in the form [plan] currently calls for, hands the
  /// set the address and starts it.
  ///
  /// When the set refuses the address outright and there is a plainer form
  /// to offer — the mp4 without its subtitle — that is offered instead,
  /// here and now. A refusal that comes later, after the set has looked at
  /// the file, is caught by [_confirm].
  Future<void> _start(
    _Renderer renderer,
    _Plan plan,
    int generation, {
    Stopwatch? clock,
  }) async {
    while (true) {
      if (generation != _generation) return;
      final media = plan.media;
      final timer = clock ?? (Stopwatch()..start());
      final before = timer.elapsedMilliseconds;

      // If the phone cannot put up a server, the original address is used
      // anyway: on a set that does cope with https it still works, and a
      // stream that might play beats one that certainly will not.
      //
      // The film is told to fill the screen: a cinema film is wider than
      // the set, and left alone a fifth of the screen is black bars. The
      // sides are cropped to 16:9 - the set's own "zoom" - which the user
      // chose over a stretched picture.
      final served = await _local.publish(
            media.streamUrl,
            contentType: plan.mime,
            subtitleFuture: plan.withSubtitle ? plan.subtitle : null,
            fill: MkvFill.crop,
          ) ??
          media.streamUrl;
      if (generation != _generation) return;
      final publishTook = timer.elapsedMilliseconds - before;
      // The server's word on what it ended up serving is the extension.
      plan.servedMkv = served.endsWith('.mkv');
      final servedMime = plan.servedMkv ? 'video/x-matroska' : plan.mime;

      // The same features the server puts in its replies: a set that
      // compares the two refuses a film whose description and delivery
      // disagree. OP=01 is what gives the television a scrubber.
      final protocol = 'http-get:*:$servedMime:${LocalStreamServer.dlnaFeatures}';

      // Size and duration where they are known. A Samsung reads the size
      // before it reads a byte of the film, and shows «cannot play» for a
      // resource that has none; LG sets draw the scrubber from the
      // duration.
      final res = StringBuffer('<res protocolInfo="${_escape(protocol)}"');
      final length = _local.lastLength;
      if (length != null) res.write(' size="$length"');
      final duration = media.duration;
      if (!media.isLive && duration != null && duration > Duration.zero) {
        res.write(' duration="${_clock(duration)}.000"');
      }
      res.write('>${_escape(served)}</res>');

      // Without this block a television shows the url as the title, and some
      // refuse a stream whose kind they have not been told.
      final didl = '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
          'xmlns:dc="http://purl.org/dc/elements/1.1/" '
          'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" '
          'xmlns:dlna="urn:schemas-dlna-org:metadata-1-0/">'
          '<item id="0" parentID="-1" restricted="1">'
          '<dc:title>${_escape(media.title)}</dc:title>'
          '<upnp:class>object.item.videoItem</upnp:class>'
          '$res'
          '</item></DIDL-Lite>';

      try {
        await _retrying(
          () => _soap(
            renderer.avTransport,
            _avTransport,
            'SetAVTransportURI',
            '<InstanceID>0</InstanceID>'
            '<CurrentURI>${_escape(served)}</CurrentURI>'
            '<CurrentURIMetaData>${_escape(didl)}</CurrentURIMetaData>',
          ),
          what: 'SetAVTransportURI',
        );
      } on CastException catch (e) {
        if (plan.canFallBack && !e.retryable) {
          debugPrint('[cast] ${renderer.name} refused the mkv (${e.message}); '
              'sending the mp4 without its subtitle');
          plan.withSubtitle = false;
          continue;
        }
        rethrow;
      } catch (e) {
        debugPrint('[cast] SetAVTransportURI: $e');
        throw const CastException(
          'التلفاز لم يستجب — تأكّد أنه ما زال على نفس الشبكة',
          retryable: true,
        );
      }
      if (generation != _generation) return;

      // Play, and again when the set says «not now»: 701 is what a set
      // answers when Play arrives before it has finished looking at the
      // address it was just handed, and the same Play a second later is
      // taken.
      try {
        await _retrying(play, what: 'Play', pause: const Duration(milliseconds: 1200));
      } on CastException {
        rethrow;
      } catch (e) {
        debugPrint('[cast] Play: $e');
        throw const CastException('التلفاز لم يستجب لأمر التشغيل', retryable: true);
      }
      // Where the seconds before the picture went, so the next «it is slow»
      // can be answered with a number rather than a guess.
      debugPrint('[cast] timings: publish (index, subtitle, plan) ${publishTook}ms, '
          'commands ${timer.elapsedMilliseconds - before - publishTook}ms, '
          'Play sent at ${timer.elapsedMilliseconds}ms');
      plan.playSentAt = DateTime.now();

      if (!media.isLive && media.position > Duration.zero) {
        // Seeking before the set has loaded the stream is refused, so it waits
        // a moment rather than starting the film over from the beginning.
        unawaited(Future<void>.delayed(const Duration(milliseconds: 1200), () {
          if (generation != _generation) return;
          seek(media.position).catchError((Object _) {});
        }));
      }

      _startPolling();
      _watchForSilence();
      unawaited(_confirm(renderer, plan, generation));
      return;
    }
  }

  /// Watches the first minute of a film and acts when the set gives up on
  /// it.
  ///
  /// The set takes the address and says nothing more; whether it then
  /// played the film or quietly threw it away is only visible by asking.
  /// PLAYING, twice, is a film on the screen. STOPPED, twice, a few
  /// seconds after Play, is a set that looked at the file and put it down
  /// — which, for an mkv, means the mp4 is sent instead; for the mp4, that
  /// the set cannot play this film and someone should be told so, in
  /// words, rather than left with a black screen and a remote that says
  /// «playing».
  Future<void> _confirm(_Renderer renderer, _Plan plan, int generation) async {
    final started = DateTime.now();
    var stoppedReads = 0;
    var playingReads = 0;
    while (DateTime.now().difference(started) < _confirmFor) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (generation != _generation || _lost || _events.isClosed || _target == null) {
        return;
      }
      String state;
      try {
        final reply = await _soap(renderer.avTransport, _avTransport,
            'GetTransportInfo', '<InstanceID>0</InstanceID>');
        state = _tag(reply ?? '', 'CurrentTransportState') ?? '';
      } catch (_) {
        // The position poll counts the silences; this only counts states.
        continue;
      }
      if (state == 'PLAYING' || state == 'PAUSED_PLAYBACK') {
        if (playingReads == 0) {
          final sent = plan.playSentAt;
          debugPrint('[cast] ${renderer.name} reports $state'
              '${sent == null ? '' : ' ${DateTime.now().difference(sent).inMilliseconds}ms after Play'}');
        }
        if (++playingReads >= 2) return;
        continue;
      }
      playingReads = 0;
      if (state == 'STOPPED' || state == 'NO_MEDIA_PRESENT') {
        // Right after SetAVTransportURI a set is STOPPED, honestly: it has
        // not been told to play yet, or has only just been. The verdict
        // needs a few seconds and two readings.
        if (DateTime.now().difference(started) < const Duration(seconds: 5)) continue;
        if (++stoppedReads < 2) continue;
        await _gaveUp(renderer, plan, generation, 'stopped');
        return;
      }
      // TRANSITIONING: still trying. Waiting is the right thing.
    }
    if (generation != _generation || _lost || _events.isClosed) return;
    await _gaveUp(renderer, plan, generation, 'never started');
  }

  /// The set did not play what it was sent. Sends the plainer form if
  /// there is one, and says so if there is not.
  Future<void> _gaveUp(_Renderer renderer, _Plan plan, int generation, String how) async {
    // A set that never came for the film has a different problem, and the
    // silence watchdog has already named it.
    if (!_local.wasFetched) return;
    if (plan.canFallBack) {
      debugPrint('[cast] ${renderer.name} $how on the mkv; '
          'sending the mp4 without its subtitle');
      plan.withSubtitle = false;
      try {
        await _start(renderer, plan, generation);
      } on CastException catch (e) {
        if (!_events.isClosed) _events.add(CastPlaybackEvent(error: e.message));
      } catch (e) {
        debugPrint('[cast] fallback: $e');
        if (!_events.isClosed) {
          _events.add(const CastPlaybackEvent(error: 'تعذّر إرسال الفيلم إلى التلفاز'));
        }
      }
      return;
    }
    debugPrint('[cast] ${renderer.name} $how on the ${plan.servedMkv ? "mkv" : "mp4"}');
    if (_events.isClosed) return;
    _events.add(const CastPlaybackEvent(
      error: 'التلفاز لم يستطع تشغيل هذا الفيلم — جرّب جودة أقل من زر الجودة في نافذة البث',
    ));
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
    final generation = _generation;
    _silence = Timer(const Duration(seconds: 12), () {
      _silence = null;
      if (_events.isClosed || _target == null || _lost) return;
      if (generation != _generation) return;
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
    _generation++;
    _poll?.cancel();
    _poll = null;
    _silence?.cancel();
    _silence = null;
    // Nothing more is served: an address that outlives its film is a
    // door left open, and a set still fetching would keep the picture up.
    _local.clear();
    await _transport('Stop', '<InstanceID>0</InstanceID>');
    await _clearScreen();
  }

  /// Takes the film off the set altogether.
  ///
  /// Stop alone leaves many sets sitting in their player on the last frame,
  /// title and scrubber still up, until somebody presses back on the
  /// remote. Handing them an empty address afterwards is what sends them
  /// home. A set that refuses the empty address has already stopped, so a
  /// refusal is not worth a word.
  Future<void> _clearScreen() async {
    final renderer = _target;
    if (renderer == null) return;
    try {
      await _soap(
        renderer.avTransport,
        _avTransport,
        'SetAVTransportURI',
        '<InstanceID>0</InstanceID><CurrentURI></CurrentURI>'
        '<CurrentURIMetaData></CurrentURIMetaData>',
      ).timeout(const Duration(seconds: 4));
    } catch (_) {}
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
    _lastPosition = null;
    _lastMoved = DateTime.now();
    _stallSaid = false;
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _askPosition());
  }

  /// Where the set was at the last poll, and when it last moved.
  Duration? _lastPosition;
  DateTime _lastMoved = DateTime.now();

  /// True once this stall has been reported; reset when the picture moves.
  bool _stallSaid = false;

  /// A picture that has not moved for this long, on a set that says it is
  /// playing, is a link that cannot keep up.
  static const Duration _stallAfter = Duration(seconds: 14);

  /// Says so when the set is stuck buffering.
  ///
  /// Only when the set itself says PLAYING or TRANSITIONING: paused is
  /// paused, and a set that has stopped is the other watchdog's business.
  /// Said once per stall, and only when the film is not already on the
  /// phone in full — a stall with the whole film here is the set's, not
  /// the link's.
  Future<void> _noticeStall(_Renderer renderer, Duration position) async {
    final last = _lastPosition;
    if (last == null || position != last) {
      _lastPosition = position;
      _lastMoved = DateTime.now();
      _stallSaid = false;
      return;
    }
    if (_stallSaid || DateTime.now().difference(_lastMoved) < _stallAfter) return;
    String state;
    try {
      final reply = await _soap(renderer.avTransport, _avTransport,
          'GetTransportInfo', '<InstanceID>0</InstanceID>');
      state = _tag(reply ?? '', 'CurrentTransportState') ?? '';
    } catch (_) {
      return;
    }
    if (state != 'PLAYING' && state != 'TRANSITIONING') return;
    if (_local.isComplete) return;
    _stallSaid = true;
    debugPrint('[cast] ${renderer.name} has not moved for '
        '${DateTime.now().difference(_lastMoved).inSeconds}s at ${_clock(position)}');
    if (!_events.isClosed) _events.add(const CastPlaybackEvent(stalled: true));
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
      if (position != null) unawaited(_noticeStall(renderer, position));
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
      // Recoverable: the controller tries to get the set back — it is
      // usually a wifi hiccup, and the film picks up where it was — before
      // anyone reads this.
      _events.add(const CastPlaybackEvent(
        error: 'التلفاز توقّف عن الاستجابة للهاتف — أعد تشغيل التلفاز أو أعد الاتصال بالشبكة',
        recoverable: true,
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

  /// The subtitle file, as text — or null, in which case the film goes
  /// without rather than not at all.
  Future<String?> _subtitleText(String url) async {
    try {
      final request = await _http.getUrl(Uri.parse(url));
      request.followRedirects = true;
      final response = await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
        // A film's subtitle is a hundred kilobytes; a megabyte is not one.
        if (builder.length > 2 * 1024 * 1024) return null;
      }
      final bytes = builder.takeBytes();
      try {
        return utf8.decode(bytes);
      } on FormatException {
        // Not utf-8: an Arabic file in a Windows code page would come out
        // as noise on the screen, which is worse than no subtitle.
        debugPrint('[cast] subtitle is not utf-8; skipped');
        return null;
      }
    } catch (e) {
      debugPrint('[cast] subtitle: $e');
      return null;
    }
  }

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
      final code = int.tryParse(_tag(text, 'errorCode') ?? '');
      final why = _tag(text, 'errorDescription') ?? '';
      debugPrint('[cast] $action refused: http ${response.statusCode} '
          'upnp ${code ?? "-"} $why');
      // 701, «transition not available», is a set that is between states —
      // still reading the address it was just given — and the same
      // command a moment later is taken. Everything else is an answer.
      throw CastException(
        'رفض التلفاز الأمر (${code ?? response.statusCode})',
        code: code ?? response.statusCode,
        retryable: code == 701,
      );
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

/// One sending of a film: the forms it can take and which is in use.
class _Plan {
  _Plan({
    required this.media,
    required this.mime,
    required this.subtitle,
    required this.withSubtitle,
  });

  final CastMedia media;
  final String mime;

  /// The subtitle text on its way down, or null when there is none.
  final Future<String?>? subtitle;

  /// Whether the film goes as an mkv with its subtitle inside. Turned off
  /// when the set refuses that, after which the mp4 goes alone.
  bool withSubtitle;

  /// What the server actually handed out last time round.
  bool servedMkv = false;

  /// When Play last went out, for the log line that says how long the set
  /// took to start.
  DateTime? playSentAt;

  /// Whether there is a plainer form still to offer.
  bool get canFallBack => withSubtitle && servedMkv;
}

/// One media renderer, and where to reach its services.
class _Renderer {
  _Renderer({
    required this.id,
    required this.name,
    required this.model,
    required this.maker,
    required this.avTransport,
    required this.renderingControl,
    required this.connectionManager,
  });

  final String id;
  final String name;
  final String model;

  /// Manufacturer and model, as the description gave them.
  final String maker;

  /// Loading, playing, pausing, seeking.
  final String avTransport;

  /// Volume and mute; a few renderers do without it.
  final String? renderingControl;

  /// Where to ask what the set can play.
  final String? connectionManager;

  /// What the set said, when asked, about Matroska: true when it names the
  /// format, false when it lists formats and leaves it out, null when it
  /// has not been asked or did not say.
  bool? acceptsMatroska;
}
