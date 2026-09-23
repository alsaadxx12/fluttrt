import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/casting/controllers/cast_controller.dart';
import 'package:youtube_downloader/features/casting/models/cast_models.dart';
import 'package:youtube_downloader/features/casting/services/cast_media_source.dart';
import 'package:youtube_downloader/features/casting/services/link_speed.dart';
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';

CastDevice _cast(String name) =>
    CastDevice(id: 'cast:$name', name: name, transport: CastTransport.googleCast);
CastDevice _dlna(String name) =>
    CastDevice(id: 'dlna:$name', name: name, transport: CastTransport.dlna);

void main() {
  group('one list from two searches', () {
    test('a set that answers both searches is listed once, as Cast', () {
      final list = CastController.merged(
        [_cast('Living Room TV')],
        [_dlna('[TV] Living Room TV'), _dlna('Smart TV Pro')],
      );
      expect(list.map((d) => d.id), ['cast:Living Room TV', 'dlna:Smart TV Pro']);
    });

    test('with no Cast device the DLNA list is untouched', () {
      final list = CastController.merged(const [], [_dlna('Smart TV Pro')]);
      expect(list.single.transport, CastTransport.dlna);
    });

    test('names are matched loosely: case, brackets and punctuation aside', () {
      final list = CastController.merged(
        [_cast('samsung 7 series (55)')],
        [_dlna('[TV] Samsung 7 Series (55)')],
      );
      expect(list, hasLength(1));
      expect(list.single.transport, CastTransport.googleCast);
    });
  });

  group('the ceiling a link earns', () {
    test('a fast link gets 1080p, a slow one 480p', () {
      expect(LinkSpeed.ceilingFor(1e6), 1080); // 8 Mbit/s
      expect(LinkSpeed.ceilingFor(350e3), 720); // 2.8 Mbit/s
      expect(LinkSpeed.ceilingFor(120e3), 480); // ~1 Mbit/s
    });

    test('is spelled out in Mbit/s', () {
      expect(LinkSpeed.describe(262500), '2.1 Mbit/s');
      expect(LinkSpeed.describe(2e6), '16 Mbit/s');
    });
  });

  group('measuring the link', () {
    late HttpServer server;

    setUp(() async {
      LinkSpeed.forget();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    });

    tearDown(() => server.close(force: true));

    test('reads a sample of the film itself and reports bytes per second', () async {
      HttpOverrides.global = null;
      server.listen((request) async {
        final body = List<int>.filled(300 * 1024, 7);
        request.response
          ..statusCode = HttpStatus.partialContent
          ..headers.contentLength = body.length
          ..add(body);
        await request.response.close();
      });

      final speed = await LinkSpeed.measure(
        'http://127.0.0.1:${server.port}/film.mp4',
        client: HttpClient(),
      );
      expect(speed, isNotNull);
      expect(speed!, greaterThan(0));
    });

    test('a film that cannot be fetched yields no measurement, not a wrong one', () async {
      HttpOverrides.global = null;
      server.listen((request) async {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final speed = await LinkSpeed.measure(
        'http://127.0.0.1:${server.port}/gone.mp4',
        client: HttpClient(),
      );
      expect(speed, isNull);
    });
  });

  group('choosing a stream', () {
    const streams = [
      CinemanaStreamFile(name: '480p', resolution: '480p', container: 'mp4', videoUrl: 'u480'),
      CinemanaStreamFile(name: '720p', resolution: '720p', container: 'mp4', videoUrl: 'u720'),
      CinemanaStreamFile(name: '1080p', resolution: '1080p', container: 'mp4', videoUrl: 'u1080'),
    ];

    test('reads the height out of the name', () {
      expect(CastMediaSource.heightOf(streams[1]), 720);
    });

    test('the ceiling picks the sharpest that fits', () {
      expect(CastMediaSource.pickBest(streams, maxHeight: 720).videoUrl, 'u720');
      expect(CastMediaSource.pickBest(streams, maxHeight: 480).videoUrl, 'u480');
      expect(CastMediaSource.pickBest(streams).videoUrl, 'u1080');
    });
  });
}
