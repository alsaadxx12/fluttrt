import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/casting/models/cast_models.dart';
import 'package:youtube_downloader/features/casting/services/cast_service.dart';
import 'package:youtube_downloader/features/casting/services/dlna_cast_service.dart';

/// A stand-in media renderer, so the service can be driven end to end
/// without a television in the room.
///
/// It answers the two things a real one does: a device description over
/// HTTP, and SOAP on the control endpoints. Every action it is asked for is
/// recorded, which is what the assertions read.
class FakeRenderer {
  FakeRenderer._(this._server);

  final HttpServer _server;
  final List<String> actions = <String>[];
  final List<String> bodies = <String>[];

  /// The two questions asked while connecting: one to prove the set can be
  /// reached, one to learn what it can play. Neither is part of playing a
  /// film, so neither belongs in an assertion about it.
  static const Set<String> _handshake = {'GetTransportInfo', 'GetProtocolInfo'};

  /// What the set was actually asked to do.
  List<String> get commands =>
      [for (final a in actions) if (!_handshake.contains(a)) a];

  List<String> get commandBodies => [
        for (var i = 0; i < actions.length; i++)
          if (!_handshake.contains(actions[i])) bodies[i],
      ];

  static Future<FakeRenderer> start({String name = 'شاشة الصالة'}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final renderer = FakeRenderer._(server);
    renderer._serve(name);
    return renderer;
  }

  String get location => 'http://127.0.0.1:${_server.port}/desc.xml';

  void _serve(String name) {
    // With no charset the response encodes as latin-1, and writing an Arabic
    // name through that throws inside the handler — the response is never
    // closed and the client waits out its whole timeout for a reply that is
    // never coming. That looked exactly like a broken service.
    _server.listen((request) async {
      if (request.method == 'GET') {
        request.response
          ..headers.contentType = ContentType('text', 'xml', charset: 'utf-8')
          ..write('''<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <device>
    <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
    <friendlyName>$name</friendlyName>
    <manufacturer>Acme</manufacturer>
    <modelName>Smart TV</modelName>
    <UDN>uuid:tv-in-the-living-room</UDN>
    <serviceList>
      <service>
        <serviceType>urn:schemas-upnp-org:service:ConnectionManager:1</serviceType>
        <controlURL>/cm/control</controlURL>
      </service>
      <service>
        <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
        <controlURL>/avt/control</controlURL>
      </service>
      <service>
        <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
        <controlURL>/rc/control</controlURL>
      </service>
    </serviceList>
  </device>
</root>''');
        await request.response.close();
        return;
      }

      // utf-8, not the platform's codepage: the service sends utf-8 and
      // decoding it as windows-1256 here would read its perfectly good
      // title back as rubbish and blame the service for it.
      final body = await utf8.decoder.bind(request.cast<List<int>>()).join();
      final action = request.headers.value('soapaction') ?? '';
      actions.add(action.split('#').last.replaceAll('"', ''));
      bodies.add(body);

      request.response
        ..headers.contentType = ContentType('text', 'xml', charset: 'utf-8')
        ..write('''<?xml version="1.0"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
  <s:Body>
    <u:GetPositionInfoResponse>
      <TrackDuration>01:30:02</TrackDuration>
      <RelTime>00:12:34</RelTime>
    </u:GetPositionInfoResponse>
  </s:Body>
</s:Envelope>''');
      await request.response.close();
    });
  }

  Future<void> stop() => _server.close(force: true);
}

void main() {
  late FakeRenderer renderer;
  DlnaCastService? service;

  setUp(() async {
    renderer = await FakeRenderer.start();
  });

  tearDown(() async {
    service?.dispose();
    service = null;
    await renderer.stop();
  });

  /// Builds the service where it can actually open a socket.
  ///
  /// flutter_test answers every http request with 400, and it puts that
  /// override back between setUp and the test body — so both the clearing
  /// and the service that holds the client have to happen in here, or the
  /// service ends up with a client that can only ever return 400. The
  /// renderer is on loopback; nothing leaves this machine.
  DlnaCastService given() {
    HttpOverrides.global = null;
    return service = DlnaCastService();
  }

  /// Discovery needs a real network, so the tests reach the renderer by its
  /// description url — the same place discovery ends up.
  Future<CastDevice> found() async {
    final devices = await given().debugAdopt(renderer.location);
    expect(devices, isNotEmpty, reason: 'the description should describe a renderer');
    return devices.first;
  }

  test('reads a renderer description into a device', () async {
    final device = await found();

    expect(device.name, 'شاشة الصالة');
    expect(device.subtitle, 'Smart TV');
    expect(device.transport, CastTransport.dlna);
    expect(device.id, 'uuid:tv-in-the-living-room');
  });

  test('sending a film hands over the url and then plays it', () async {
    final device = await found();
    await service!.connect(device);

    await service!.loadMedia(const CastMedia(
      mediaId: '1',
      title: 'الفاشل',
      streamUrl: 'https://cdn.example.com/film.mp4',
      contentType: 'video/mp4',
    ));

    expect(renderer.commands.take(2), ['SetAVTransportURI', 'Play']);

    final load = renderer.commandBodies.first;
    expect(load, contains('الفاشل'), reason: 'the set shows the title, not the url');
    expect(load, contains('object.item.videoItem'));

    // The set is pointed at the phone, not at the cdn: it cannot do the
    // https the catalogue serves and will not follow its redirect.
    expect(load, contains(RegExp(r'http://\d+\.\d+\.\d+\.\d+:\d+/s/')));
    expect(load, isNot(contains('cdn.example.com')));

    // Byte-seeking declared, or the television offers no scrubber.
    expect(load, contains('DLNA.ORG_OP=01'));
  });

  test('an ampersand is escaped, and a signed url never reaches the set', () async {
    final device = await found();
    await service!.connect(device);

    await service!.loadMedia(const CastMedia(
      mediaId: '1',
      title: 'فيلم & آخر',
      streamUrl: 'https://cdn.example.com/f.mp4?Signature=secret&Expires=99',
      contentType: 'video/mp4',
    ));

    final load = renderer.commandBodies.first;

    // A bare ampersand is not valid xml and a set would refuse the whole
    // envelope over it. The title is where one turns up now.
    expect(load, contains('&amp;amp;'),
        reason: 'the title travels inside an escaped DIDL block');
    expect(load, isNot(contains(RegExp(r'&(?!amp;|lt;|gt;|quot;)'))));

    // The address the set is handed stands for the stream rather than being
    // it, so the signature stays on the phone.
    expect(load, isNot(contains('Signature')));
    expect(load, isNot(contains('secret')));
  });

  test('transport commands reach the renderer', () async {
    final device = await found();
    await service!.connect(device);
    renderer.actions.clear();
    renderer.bodies.clear();

    await service!.play();
    await service!.pause();
    await service!.seek(const Duration(hours: 1, minutes: 2, seconds: 3));
    await service!.stop();

    expect(renderer.commands, ['Play', 'Pause', 'Seek', 'Stop']);
    // UPnP will not take anything but H:MM:SS.
    expect(renderer.commandBodies[2], contains('<Target>1:02:03</Target>'));
  });

  test('volume is sent as a percentage on the rendering service', () async {
    final device = await found();
    await service!.connect(device);
    renderer.actions.clear();
    renderer.bodies.clear();

    await service!.setVolume(0.42);

    expect(renderer.commands, ['SetVolume']);
    expect(renderer.commandBodies.last, contains('<DesiredVolume>42</DesiredVolume>'));
  });

  test('connecting asks the set what it can play', () async {
    final device = await found();
    await service!.connect(device);
    // The probe runs alongside rather than in the way, so give it a moment.
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(renderer.actions, contains('GetProtocolInfo'),
        reason: 'what the set accepts is the difference between knowing why '
            'a film shows black and guessing');
  });

  test('a set that is seen but cannot be reached is refused with a reason',
      () async {
    final device = await found();
    // The renderer stops answering — which is what a device with an
    // allowed-devices list does to a phone that is not on it.
    await renderer.stop();

    await expectLater(
      service!.connect(device),
      throwsA(isA<CastException>().having(
        (e) => e.message, 'message', contains('يرفض الاتصال'))),
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('a set that stops answering is reported once, and polling stops',
      () async {
    final device = await found();
    await service!.connect(device);
    await service!.loadMedia(const CastMedia(
      mediaId: '1',
      title: 'x',
      streamUrl: 'https://cdn.example.com/f.mp4',
      contentType: 'video/mp4',
    ));

    // The set comes for the film, as a working one does. Without this the
    // «never fetched» watchdog fires first and the scenario is a different
    // fault; with it, only the polling has anything to say.
    final served = RegExp(r'<CurrentURI>(.*?)</CurrentURI>')
        .firstMatch(renderer.commandBodies.first)!
        .group(1)!;
    final probe = await HttpClient().getUrl(Uri.parse(served));
    await (await probe.close()).drain<void>();

    // Then the set goes quiet — a phone it has stopped talking to.
    await renderer.stop();

    final errors = <String>[];
    final sub = service!.events.listen((e) {
      if (e.error != null) errors.add(e.error!);
    });
    addTearDown(sub.cancel);

    // Five misses at two seconds each, plus the timeouts inside them.
    await Future<void>.delayed(const Duration(seconds: 30));

    expect(errors, hasLength(1),
        reason: 'said once, not once every two seconds for ever');
    expect(errors.single, contains('توقّف عن الاستجابة'));
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('a device that is no longer there is refused, not guessed at', () async {
    expect(
      () => given().connect(const CastDevice(
        id: 'uuid:gone',
        name: 'تلفاز',
        transport: CastTransport.dlna,
      )),
      throwsA(isA<CastException>()),
    );
  });
}
