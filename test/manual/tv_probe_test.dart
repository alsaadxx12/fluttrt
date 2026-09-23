import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/casting/services/local_stream_server.dart';
import 'package:youtube_downloader/features/casting/services/mkv_remux.dart';

/// Plays a catalogue film, subtitle and all, on the television in the room —
/// through the app's own server, from this machine.
///
/// Not a unit test: it needs the set switched on and the catalogue
/// reachable, so it does nothing unless asked for by name:
///
///     flutter test test/manual/tv_probe_test.dart --dart-define=TV_PROBE=true
///
/// It proves the Dart implementation on the real set before anyone builds
/// an apk: `state=PLAYING` with the position advancing means the set
/// accepted what the phone will serve. Whether the lines appear under the
/// picture is for the person in the room to say; the first one is at 1:07.
const bool probe = bool.fromEnvironment('TV_PROBE');
const String television = String.fromEnvironment('TV', defaultValue: '192.168.0.131');
const int seconds = int.fromEnvironment('TV_SECONDS', defaultValue: 100);

/// A time to seek to (as `HH:MM:SS`) a dozen seconds in, when given.
const String seekTo = String.fromEnvironment('TV_SEEK');

/// `crop` or `stretch`: how a wide film should fill the 16:9 screen.
const String fillName = String.fromEnvironment('TV_FILL');

const String api = 'https://cinemana.shabakaty.com/api/android';
const String avTransport = 'urn:schemas-upnp-org:service:AVTransport:1';

void main() {
  test('the television plays the remuxed film from the phone server', () async {
    if (!probe) {
      markTestSkipped('run with --dart-define=TV_PROBE=true and the set on');
      return;
    }
    HttpOverrides.global = null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);

    Future<String> get(String url) async {
      final request = await client.getUrl(Uri.parse(url));
      request.followRedirects = true;
      final response = await request.close();
      return response.transform(utf8.decoder).join();
    }

    // ---- the film and its subtitle
    final listing = await get('$api/transcoddedFiles/id/3134510');
    final url = RegExp(r'"resolution":"1080p".*?"videoUrl":"(.*?)"', dotAll: true)
            .firstMatch(listing)
            ?.group(1)
            ?.replaceAll(r'\/', '/') ??
        RegExp(r'"videoUrl":"(.*?)"').firstMatch(listing)!.group(1)!.replaceAll(r'\/', '/');
    final translations = await get('$api/translationFiles/id/3134510');
    final srtUrl = RegExp(r'"arTranslationFilePath":"(.*?)"').firstMatch(translations)!.group(1)!.replaceAll(r'\/', '/');
    final subtitle = await get(srtUrl);
    // ignore: avoid_print
    print('film: $url\nsubtitle: ${subtitle.length} chars');

    // ---- the phone's server, on this machine
    final server = LocalStreamServer();
    addTearDown(server.stop);
    final fill = MkvFill.values.cast<MkvFill?>().firstWhere(
        (f) => f!.name == fillName, orElse: () => null) ?? MkvFill.keep;
    final served = await server.publish(url, contentType: 'video/mp4', subtitle: subtitle, fill: fill);
    expect(served, isNotNull);
    expect(served, endsWith('.mkv'), reason: 'the subtitle should have made it an mkv');
    // ignore: avoid_print
    print('serving $served');

    // ---- the set
    final description = await _describe(client);
    final control = RegExp(r'<service>(.*?)</service>', dotAll: true)
        .allMatches(description.$2)
        .map((m) => m.group(1)!)
        .firstWhere((s) => s.contains(avTransport));
    final controlUrl = Uri.parse(description.$1)
        .resolve(RegExp(r'<controlURL>(.*?)</controlURL>').firstMatch(control)!.group(1)!.trim())
        .toString();

    Future<String> soap(String action, String body) async {
      final request = await client.postUrl(Uri.parse(controlUrl));
      request.headers.set('Content-Type', 'text/xml; charset="utf-8"');
      request.headers.set('SOAPAction', '"$avTransport#$action"');
      request.write('<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
          's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>'
          '<u:$action xmlns:u="$avTransport">$body</u:$action></s:Body></s:Envelope>');
      final response = await request.close();
      return response.transform(utf8.decoder).join();
    }

    String tag(String xml, String name) =>
        RegExp('<$name>(.*?)</$name>', dotAll: true).firstMatch(xml)?.group(1) ?? '?';

    const protocol = 'http-get:*:video/x-matroska:DLNA.ORG_OP=01;DLNA.ORG_CI=0;'
        'DLNA.ORG_FLAGS=01700000000000000000000000000000';
    final didl = '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">'
        '<item id="0" parentID="-1" restricted="1"><dc:title>CINEBALL probe</dc:title>'
        '<upnp:class>object.item.videoItem</upnp:class>'
        '<res protocolInfo="${_escape(protocol)}">${_escape(served!)}</res></item></DIDL-Lite>';

    await soap('SetAVTransportURI',
        '<InstanceID>0</InstanceID><CurrentURI>${_escape(served)}</CurrentURI>'
        '<CurrentURIMetaData>${_escape(didl)}</CurrentURIMetaData>');
    await soap('Play', '<InstanceID>0</InstanceID><Speed>1</Speed>');

    var playing = 0;
    var lastPosition = '';
    final started = DateTime.now();
    while (DateTime.now().difference(started).inSeconds < seconds) {
      await Future<void>.delayed(const Duration(seconds: 4));
      final info = await soap('GetTransportInfo', '<InstanceID>0</InstanceID>');
      final position = await soap('GetPositionInfo', '<InstanceID>0</InstanceID>');
      final state = tag(info, 'CurrentTransportState');
      lastPosition = tag(position, 'RelTime');
      // ignore: avoid_print
      print('t+${DateTime.now().difference(started).inSeconds}s  state=$state  '
          'pos=$lastPosition / ${tag(position, 'TrackDuration')}');
      if (state == 'PLAYING' && lastPosition != '00:00:00') playing++;
      if (seekTo.isNotEmpty && playing == 3) {
        final reply = await soap('Seek', '<InstanceID>0</InstanceID><Unit>REL_TIME</Unit><Target>$seekTo</Target>');
        // ignore: avoid_print
        print('seek to $seekTo -> ${reply.contains('SeekResponse') ? 'accepted' : reply}');
      }
    }
    try {
      await soap('Stop', '<InstanceID>0</InstanceID>');
    } catch (_) {}

    expect(playing, greaterThan(seconds ~/ 4 - 3),
        reason: 'the set should be playing, and moving, for nearly the whole time');
    expect(server.wasFetched, isTrue);
  }, timeout: const Timeout(Duration(minutes: 5)));
}

String _escape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// The set's description url and document: found over SSDP, or at the port
/// it was last seen on when the multicast reply goes astray.
Future<(String, String)> _describe(HttpClient client) async {
  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  const query = 'M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: "ssdp:discover"\r\n'
      'MX: 2\r\nST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n';
  for (var i = 0; i < 3; i++) {
    socket.send(query.codeUnits, InternetAddress('239.255.255.250'), 1900);
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  String? location;
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (location == null && DateTime.now().isBefore(deadline)) {
    final datagram = socket.receive();
    if (datagram == null) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      continue;
    }
    if (datagram.address.address != television) continue;
    location = RegExp(r'^location:\s*(\S+)', caseSensitive: false, multiLine: true)
        .firstMatch(String.fromCharCodes(datagram.data))
        ?.group(1);
  }
  socket.close();
  location ??= 'http://$television:17002/';
  final response = await (await client.getUrl(Uri.parse(location))).close();
  final xml = await response.transform(utf8.decoder).join();
  return (location, xml);
}
