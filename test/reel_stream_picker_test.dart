import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/reels/data/reel_stream_proxy.dart';
import 'package:youtube_downloader/features/reels/data/reel_stream_resolver.dart';
import 'package:youtube_downloader/features/reels/data/youtube_player_client.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// The stream records are built through their JSON constructors: that is
/// the only public way to make one without youtube_explode's private parser,
/// and it keeps the test on the real types the resolver sees.
const Map<String, dynamic> _videoId = {'value': 'dQw4w9WgXcQ'};

/// A video-only stream; landscape (16:9) unless [width] is given.
VideoOnlyStreamInfo _video(
  int tag, {
  required String codec,
  required int height,
  int? width,
  String container = 'mp4',
  int bitrate = 1000000,
  bool fragmented = false,
  double? dur,
}) =>
    VideoOnlyStreamInfo.fromJson({
      'videoId': _videoId,
      'tag': tag,
      'url': 'https://v.test/$tag${dur == null ? '' : '?dur=$dur'}',
      'container': {'name': container},
      'size': {'totalBytes': 1000},
      'bitrate': {'bitsPerSecond': bitrate},
      'videoCodec': codec,
      'qualityLabel': '${height}p',
      'videoQuality': 'unknown',
      'videoResolution': {'width': width ?? height * 16 ~/ 9, 'height': height},
      'framerate': {'framesPerSecond': 30},
      'fragments': fragmented
          ? [
              {'path': '/sq/1'}
            ]
          : <Map<String, dynamic>>[],
      'codec': '${container == 'mp4' ? 'video/mp4' : 'video/webm'}; codecs="$codec"',
    });

AudioOnlyStreamInfo _audio(
  int tag, {
  required String codec,
  String container = 'mp4',
  int bitrate = 128000,
  bool dubbed = false,
  double? dur,
}) =>
    AudioOnlyStreamInfo.fromJson({
      'videoId': _videoId,
      'tag': tag,
      'url': 'https://a.test/$tag${dur == null ? '' : '?dur=$dur'}',
      'container': {'name': container},
      'size': {'totalBytes': 1000},
      'bitrate': {'bitsPerSecond': bitrate},
      'audioCodec': codec,
      'qualityLabel': 'audio',
      'fragments': <Map<String, dynamic>>[],
      'codec': '${container == 'mp4' ? 'audio/mp4' : 'audio/webm'}; codecs="$codec"',
      'audioTrack': dubbed ? {'displayName': 'French', 'id': 'fr', 'audioIsDefault': false} : null,
    });

MuxedStreamInfo _muxed(int tag, {required int height, int bitrate = 800000}) => MuxedStreamInfo.fromJson({
      'videoId': _videoId,
      'tag': tag,
      'url': 'https://m.test/$tag',
      'container': {'name': 'mp4'},
      'size': {'totalBytes': 1000},
      'bitrate': {'bitsPerSecond': bitrate},
      'audioCodec': 'mp4a.40.2',
      'videoCodec': 'avc1.64001F',
      'qualityLabel': '${height}p',
      'videoQuality': 'unknown',
      'videoResolution': {'width': height * 16 ~/ 9, 'height': height},
      'framerate': {'framesPerSecond': 30},
      'codec': 'video/mp4; codecs="avc1.64001F, mp4a.40.2"',
    });

Uri _v(int tag) => Uri.parse('https://v.test/$tag');
Uri _a(int tag) => Uri.parse('https://a.test/$tag');
Uri _m(int tag) => Uri.parse('https://m.test/$tag');

void main() {
  group('pickReelStreams', () {
    test('prefers H.264 in mp4, the tallest up to 1440p, with the best AAC audio', () {
      final picked = pickReelStreams(StreamManifest([
        _video(1, codec: 'avc1.4d401f', height: 720),
        _video(2, codec: 'avc1.640028', height: 1080),
        _video(3, codec: 'avc1.640033', height: 1440),
        _video(4, codec: 'avc1.640034', height: 2160),
        _video(5, codec: 'vp09.00.51.08', height: 2160, container: 'webm'),
        _video(6, codec: 'av01.0.13M.08', height: 2160),
        _audio(10, codec: 'mp4a.40.2', bitrate: 128000),
        _audio(11, codec: 'mp4a.40.5', bitrate: 48000),
        _audio(12, codec: 'opus', container: 'webm', bitrate: 160000),
        _muxed(20, height: 720),
      ]))!;
      expect(picked.video, _v(3), reason: '1440p is the ceiling; 2160p is skipped');
      expect(picked.audio, _a(10), reason: 'AAC at the highest bitrate, over the louder Opus');
      expect(picked.height, 1440);
      expect(picked.muxed, isFalse);
    });

    test('among equal heights the higher bitrate wins', () {
      final picked = pickReelStreams(StreamManifest([
        _video(1, codec: 'avc1.640028', height: 1080, bitrate: 2000000),
        _video(2, codec: 'avc1.640028', height: 1080, bitrate: 4000000),
        _video(3, codec: 'avc1.640028', height: 1080, bitrate: 3000000),
        _audio(10, codec: 'mp4a.40.2', bitrate: 128000),
        _audio(11, codec: 'mp4a.40.2', bitrate: 256000),
      ]))!;
      expect(picked.video, _v(2));
      expect(picked.audio, _a(11));
    });

    test('H.264 720p is taken over VP9 1080p: hardware decoding first', () {
      final picked = pickReelStreams(StreamManifest([
        _video(1, codec: 'avc1.4d401f', height: 720),
        _video(2, codec: 'vp09.00.40.08', height: 1080, container: 'webm'),
        _audio(10, codec: 'mp4a.40.2'),
      ]))!;
      expect(picked.video, _v(1));
      expect(picked.height, 720);
      expect(picked.muxed, isFalse);
    });

    test('VP9 only when there is no H.264, and no taller than 1080p', () {
      final picked = pickReelStreams(StreamManifest([
        _video(1, codec: 'vp09.00.51.08', height: 2160, container: 'webm'),
        _video(2, codec: 'vp09.00.50.08', height: 1440, container: 'webm'),
        _video(3, codec: 'vp09.00.40.08', height: 1080, container: 'webm'),
        _video(4, codec: 'vp09.00.31.08', height: 720, container: 'webm'),
        _video(5, codec: 'av01.0.13M.08', height: 2160),
        _audio(10, codec: 'mp4a.40.2'),
        _muxed(20, height: 720),
      ]))!;
      expect(picked.video, _v(3));
      expect(picked.height, 1080);
      expect(picked.muxed, isFalse);
    });

    test('Opus stands in when there is no AAC', () {
      final picked = pickReelStreams(StreamManifest([
        _video(1, codec: 'avc1.640028', height: 1080),
        _audio(10, codec: 'opus', container: 'webm', bitrate: 70000),
        _audio(11, codec: 'opus', container: 'webm', bitrate: 160000),
      ]))!;
      expect(picked.audio, _a(11));
      expect(picked.muxed, isFalse);
    });

    test('the film’s own soundtrack is preferred to a dubbed track', () {
      final picked = pickReelStreams(StreamManifest([
        _video(1, codec: 'avc1.640028', height: 1080),
        _audio(10, codec: 'mp4a.40.2', bitrate: 256000, dubbed: true),
        _audio(11, codec: 'mp4a.40.2', bitrate: 128000),
      ]))!;
      expect(picked.audio, _a(11));
    });

    test('falls back to the best muxed stream when there is no audio-only stream', () {
      final picked = pickReelStreams(StreamManifest([
        _video(1, codec: 'avc1.640028', height: 1080),
        _muxed(20, height: 360),
        _muxed(21, height: 720, bitrate: 1500000),
        _muxed(22, height: 720, bitrate: 900000),
      ]))!;
      expect(picked.video, _m(21));
      expect(picked.audio, isNull);
      expect(picked.height, 720);
      expect(picked.muxed, isTrue);
    });

    test('falls back to the muxed stream when there is no video-only stream', () {
      final picked = pickReelStreams(StreamManifest([
        _audio(10, codec: 'mp4a.40.2'),
        _muxed(20, height: 360),
        _muxed(21, height: 720),
      ]))!;
      expect(picked.video, _m(21));
      expect(picked.audio, isNull);
      expect(picked.muxed, isTrue);
    });

    test('falls back to the muxed stream when only unusable video-only streams exist', () {
      final picked = pickReelStreams(StreamManifest([
        _video(1, codec: 'av01.0.13M.08', height: 2160),
        _video(2, codec: 'vp09.00.51.08', height: 2160, container: 'webm'),
        _audio(10, codec: 'mp4a.40.2'),
        _muxed(20, height: 720),
      ]))!;
      expect(picked.video, _m(20));
      expect(picked.muxed, isTrue);
    });

    test('a fragmented (DASH) stream cannot be opened as one URL and is skipped', () {
      final picked = pickReelStreams(StreamManifest([
        _video(1, codec: 'avc1.640033', height: 1440, fragmented: true),
        _video(2, codec: 'avc1.640028', height: 1080),
        _audio(10, codec: 'mp4a.40.2'),
      ]))!;
      expect(picked.video, _v(2));
    });

    test('nothing playable is null', () {
      expect(pickReelStreams(StreamManifest(const [])), isNull);
      expect(pickReelStreams(StreamManifest([_audio(10, codec: 'mp4a.40.2')])), isNull);
    });

    test('a clip longer than YouTube’s adaptive budget takes the muxed stream, whole', () {
      final long = kReelAdaptiveMaxDuration.inSeconds + 30.0;
      final picked = pickReelStreams(StreamManifest([
        _video(1, codec: 'avc1.640028', height: 1080, dur: long),
        _audio(10, codec: 'mp4a.40.2', dur: long),
        _muxed(20, height: 360),
      ]))!;
      expect(picked.muxed, isTrue);
      expect(picked.height, 360);
      expect(picked.audio, isNull);

      // The length may sit on the audio URL alone.
      final audioOnlyLength = pickReelStreams(StreamManifest([
        _video(1, codec: 'avc1.640028', height: 1080),
        _audio(10, codec: 'mp4a.40.2', dur: long),
        _muxed(20, height: 360),
      ]))!;
      expect(audioOnlyLength.muxed, isTrue);
    });

    test('a clip within the budget keeps the pair; so does a long one with nothing muxed', () {
      final short = kReelAdaptiveMaxDuration.inSeconds - 10.0;
      final teaser = pickReelStreams(StreamManifest([
        _video(1, codec: 'avc1.640028', height: 1080, dur: short),
        _audio(10, codec: 'mp4a.40.2', dur: short),
        _muxed(20, height: 360),
      ]))!;
      expect(teaser.muxed, isFalse);
      expect(teaser.height, 1080);

      final noMuxed = pickReelStreams(StreamManifest([
        _video(1, codec: 'avc1.640028', height: 1080, dur: 144.1),
        _audio(10, codec: 'mp4a.40.2', dur: 144.2),
      ]))!;
      expect(noMuxed.muxed, isFalse, reason: 'a minute of 1080p beats nothing');
    });
  });

  group('vertical shorts', () {
    test('the caps go by the shorter side: a 1080×1920 stream is a 1080p one and wins', () {
      final picked = pickReelStreams(StreamManifest([
        _video(1, codec: 'avc1.4d401f', height: 1280, width: 720),
        _video(2, codec: 'avc1.640028', height: 1920, width: 1080),
        _video(3, codec: 'vp09.00.40.08', height: 1920, width: 1080, container: 'webm'),
        _audio(10, codec: 'mp4a.40.2'),
        _muxed(20, height: 360),
      ]))!;
      expect(picked.video, _v(2), reason: '1920 tall is not over the 1440 cap: it is 1080 across');
      expect(picked.height, 1920);
      expect(picked.muxed, isFalse);
    });

    test('VP9 upright at 1080×1920 is within its 1080p cap', () {
      final picked = pickReelStreams(StreamManifest([
        _video(1, codec: 'vp09.00.40.08', height: 1920, width: 1080, container: 'webm'),
        _video(2, codec: 'vp09.00.31.08', height: 1280, width: 720, container: 'webm'),
        _audio(10, codec: 'mp4a.40.2'),
      ]))!;
      expect(picked.video, _v(1));
      expect(picked.height, 1920);
    });

    test('reelQualityOf is the shorter side; an unknown side yields the other', () {
      expect(reelQualityOf(1920, 1080), 1080);
      expect(reelQualityOf(1080, 1920), 1080);
      expect(reelQualityOf(720, 1280), 720);
      expect(reelQualityOf(0, 720), 720);
      expect(reelQualityOf(1280, 0), 1280);
    });
  });

  group('probeReelManifest', () {
    test('measures the tallest video-only stream and reads the length off any stream', () {
      final p = probeReelManifest(StreamManifest([
        _video(1, codec: 'avc1.4d401f', height: 720),
        _video(2, codec: 'avc1.640028', height: 1080, dur: 45.5),
        _audio(10, codec: 'mp4a.40.2', dur: 45.6),
        _muxed(20, height: 360),
      ]))!;
      expect(p.width, 1920);
      expect(p.height, 1080);
      expect(p.maxHeight, 1080);
      expect(p.quality, 1080);
      expect(p.portrait, isFalse);
      expect(p.duration, const Duration(milliseconds: 45500));
      expect(p.adaptiveOk, isTrue);
      expect(p.qualifies, isFalse, reason: 'a landscape trailer, however fine, is not upright');
    });

    test('an upright 1080×1920 clip inside the minute qualifies', () {
      final p = probeReelManifest(StreamManifest([
        _video(1, codec: 'avc1.4d401f', height: 1280, width: 720),
        _video(2, codec: 'avc1.640028', height: 1920, width: 1080, dur: 58.2),
        _audio(10, codec: 'mp4a.40.2', dur: 58.3),
      ]))!;
      expect(p.portrait, isTrue);
      expect(p.width, 1080);
      expect(p.height, 1920);
      expect(p.maxHeight, 1920);
      expect(p.quality, 1080);
      expect(p.qualifies, isTrue);
      expect('$p', 'ReelProbe(1080x1920, portrait, 58200 ms)');
    });

    test('upright but only 720 across does not, though it is 1280 tall', () {
      final p = probeReelManifest(StreamManifest([
        _video(1, codec: 'avc1.4d401f', height: 1280, width: 720, dur: 30),
        _audio(10, codec: 'mp4a.40.2', dur: 30),
      ]))!;
      expect(p.portrait, isTrue);
      expect(p.maxHeight, 1280);
      expect(p.quality, 720);
      expect(p.qualifies, isFalse);
    });

    test('the length must fit the adaptive budget: 60 s does, 60.5 s and an unknown length do not', () {
      ReelProbe at(double? dur) => probeReelManifest(StreamManifest([
            _video(1, codec: 'avc1.640028', height: 1920, width: 1080, dur: dur),
            _audio(10, codec: 'mp4a.40.2', dur: dur),
          ]))!;
      expect(kReelAdaptiveMaxDuration, const Duration(seconds: 60));
      expect(at(60).qualifies, isTrue);
      expect(at(60.5).adaptiveOk, isFalse);
      expect(at(60.5).qualifies, isFalse);
      expect(at(null).duration, isNull);
      expect(at(null).adaptiveOk, isFalse);
      expect(at(null).qualifies, isFalse);
    });

    test('a fragmented stream still measures the clip; no video-only stream is no probe', () {
      final p = probeReelManifest(StreamManifest([
        _video(1, codec: 'avc1.640028', height: 1920, width: 1080, fragmented: true, dur: 30),
        _video(2, codec: 'avc1.4d401f', height: 1280, width: 720, dur: 30),
      ]))!;
      expect(p.height, 1920);
      expect(probeReelManifest(StreamManifest([_audio(10, codec: 'mp4a.40.2'), _muxed(20, height: 360)])), isNull);
      expect(probeReelManifest(StreamManifest(const [])), isNull);
    });
  });

  group('reelStreamDuration', () {
    test('reads YouTube’s dur, in seconds, and nothing else', () {
      expect(reelStreamDuration(Uri.parse('https://v.test/1?clen=5&dur=144.143')), const Duration(milliseconds: 144143));
      expect(reelStreamDuration(Uri.parse('https://v.test/1?dur=0')), isNull);
      expect(reelStreamDuration(Uri.parse('https://v.test/1?dur=x')), isNull);
      expect(reelStreamDuration(Uri.parse('https://v.test/1')), isNull);
    });
  });

  group('ReelStreamResolver', () {
    test('nothing is cached until something was resolved', () {
      expect(ReelStreamResolver.instance.cached('dQw4w9WgXcQ'), isNull);
      expect(ReelStreamResolver.ttl, const Duration(hours: 3));
    });
  });

  group('ReelStreamResolver on innertube clients', () {
    const ios = InnertubeClient.ios;
    const vr = InnertubeClient.androidVr;
    const long = 129;
    const short = 40;
    final proxy = ReelStreamProxy.instance;

    // youtube_explode's answer: a 1080p pair of [dur] seconds and a 360p
    // muxed stream, like the android client gives today.
    ReelManifestFetch explode({double dur = long + 0.1}) => (_) async => StreamManifest([
          _video(137, codec: 'avc1.640028', height: 1080, dur: dur),
          _audio(140, codec: 'mp4a.40.2', dur: dur),
          _muxed(18, height: 360),
        ]);
    Future<StreamManifest> explodeDown(String _) async => throw StateError('youtube_explode is down');

    late _Probe probe;
    setUp(() => probe = _Probe());
    tearDown(() => proxy.close());

    ReelStreamResolver resolver(_FakeInnertube innertube, {ReelManifestFetch? manifest}) => ReelStreamResolver.custom(
          player: YoutubePlayerClient(dio: Dio()..httpClientAdapter = innertube),
          probe: probe.call,
          manifest: manifest ?? explode(),
          clients: const [ios, vr],
        );

    test('a client seen to serve a long clip whole wins: the pair, no gate, its headers, verified once a session',
        () async {
      final innertube = _FakeInnertube({ios.clientId: _player(long, adaptive: _pair('whole'))});
      final r = resolver(innertube);

      final streams = (await r.resolve('aaaaaaaaaaa'))!;
      expect(streams.muxed, isFalse);
      expect(streams.height, 1080);
      expect(streams.audio, isNotNull);
      expect(streams.video.host, 'whole-v.test');
      expect(streams.source, ios.name);
      expect(streams.headers, ios.streamHeaders);
      expect(r.verdict(ios), isTrue);

      // One byte of the video and one of the audio, deep in the clip, with
      // the client's own headers.
      expect(probe.asked.length, 2);
      for (final (url, start, headers) in probe.asked) {
        expect(start, greaterThan(0), reason: '$url was probed at the start');
        expect(headers, ios.streamHeaders);
      }
      expect(probe.asked.first.$2, youtubeUrlByteAt(streams.video, ReelStreamResolver.verifyAt));

      // The streams are registered with the relay, headers and all; the
      // page registering them again keeps the headers.
      final local = await proxy.register(streams.video);
      expect(proxy.headersOf(local), ios.streamHeaders);
      expect(proxy.headersOf(await proxy.register(streams.audio!)), ios.streamHeaders);

      // The verdict holds for the session: the next reel is not probed.
      final next = (await r.resolve('bbbbbbbbbbb'))!;
      expect(next.muxed, isFalse);
      expect(probe.asked.length, 2);
      expect(innertube.asks[ios.clientId], 2);
      expect(r.cached('aaaaaaaaaaa'), same(streams));
    });

    test('a clip forgotten after its stream broke is resolved off a fresh answer, not off what is held', () async {
      final innertube = _FakeInnertube({ios.clientId: _player(long, adaptive: _pair('whole'))});
      final r = resolver(innertube);

      final streams = (await r.resolve('aaaaaaaaaaa'))!;
      expect(r.cached('aaaaaaaaaaa'), same(streams));
      final asked = innertube.asks[ios.clientId]!;

      r.forget('aaaaaaaaaaa');
      expect(r.cached('aaaaaaaaaaa'), isNull, reason: 'the URLs that broke are not handed out again');

      // Nor is the client's kept answer, which carries the very same URLs:
      // YouTube itself is asked once more.
      expect(await r.resolve('aaaaaaaaaaa'), isNotNull);
      expect(innertube.asks[ios.clientId], greaterThan(asked));
    });

    test('a client refused past the minute is set aside; the gate stands and the tallest muxed stream wins',
        () async {
      final innertube = _FakeInnertube({
        ios.clientId: _player(long, adaptive: _pair('gated')),
        vr.clientId: _player(long, formats: [_muxedJson(22, height: 720, host: 'vr-m.test')]),
      });
      final r = resolver(innertube);

      final streams = (await r.resolve('aaaaaaaaaaa'))!;
      expect(r.verdict(ios), isFalse);
      expect(probe.asked.length, 1, reason: 'the refused video stream settles it; the audio is not asked');
      expect(streams.muxed, isTrue);
      expect(streams.audio, isNull);
      expect(streams.height, 720, reason: 'taller than youtube_explode’s 360p muxed stream');
      expect(streams.source, vr.name);
      expect(streams.headers, vr.streamHeaders);
      // A muxed stream that needs headers is handed out as its relay URL.
      expect(streams.video.host, '127.0.0.1');
      expect(proxy.upstreamOf(streams.video), Uri.parse('https://vr-m.test/22?clen=9000&dur=129.1'));
      expect(proxy.headersOf(streams.video), vr.streamHeaders);

      // The next reel skips the refused client altogether.
      await r.resolve('bbbbbbbbbbb');
      expect(innertube.asks[ios.clientId], 1);
      expect(innertube.asks[vr.clientId], 2);
      expect(probe.asked.length, 1);
    });

    test('a clip past the gate but too short to be read at 90 s proves nothing: the gate stands, no verdict', () async {
      // YouTube refuses the video from 61 s and the audio from 68 s: a read
      // near the end of a 63 s clip comes back 206 and would wrongly trust
      // the client for the session.
      final innertube = _FakeInnertube({ios.clientId: _player(63, adaptive: _pair('gated'))});
      final r = resolver(innertube);
      final streams = (await r.resolve('aaaaaaaaaaa'))!;
      expect(streams.source, kReelSourceExplode);
      expect(streams.muxed, isTrue);
      expect(streams.height, 360);
      expect(r.verdict(ios), isNull);
      expect(probe.asked, isEmpty, reason: 'nothing to learn from a read short of the refusal');

      // The next clip is long enough: measured at 90 s exactly, and refused.
      innertube.answers[ios.clientId] = _player(long, adaptive: _pair('gated'));
      await r.resolve('bbbbbbbbbbb');
      expect(probe.asked.length, 1);
      expect(probe.asked.single.$2, youtubeUrlByteAt(probe.asked.single.$1, ReelStreamResolver.verifyAt));
      expect(r.verdict(ios), isFalse);
    });

    test('a client short of the margin past 90 s is not measured either', () async {
      final justShort = ReelStreamResolver.verifyAt.inSeconds + ReelStreamResolver.verifyMargin.inSeconds - 1;
      final innertube = _FakeInnertube({ios.clientId: _player(justShort, adaptive: _pair('whole'))});
      final r = resolver(innertube);
      expect((await r.resolve('aaaaaaaaaaa'))!.source, kReelSourceExplode);
      expect(probe.asked, isEmpty);
      innertube.answers[ios.clientId] = _player(justShort + 1, adaptive: _pair('whole'));
      expect((await r.resolve('bbbbbbbbbbb'))!.source, ios.name);
      expect(probe.asked.length, 2);
    });

    test('the unmeasured clients are asked together; a trusted client is asked alone', () async {
      final innertube = _FakeInnertube({ios.clientId: _player(long, adaptive: _pair('whole'))});
      final r = resolver(innertube);
      await r.resolve('aaaaaaaaaaa');
      expect(innertube.maxInFlight, 2, reason: 'ios and android_vr, both unmeasured, should be asked at once');
      expect(innertube.asks[vr.clientId], 1);
      expect(r.verdict(ios), isTrue);

      innertube.maxInFlight = 0;
      await r.resolve('bbbbbbbbbbb');
      expect(innertube.maxInFlight, 1, reason: 'the trusted client answers alone');
      expect(innertube.asks[ios.clientId], 2);
      expect(innertube.asks[vr.clientId], 1, reason: 'not asked while the trusted client answers');
    });

    test('a short clip takes the client’s pair without a probe', () async {
      final innertube = _FakeInnertube({ios.clientId: _player(short, adaptive: _pair('gated'))});
      final streams = (await resolver(innertube).resolve('aaaaaaaaaaa'))!;
      expect(streams.muxed, isFalse);
      expect(streams.height, 1080);
      expect(streams.source, ios.name);
      expect(probe.asked, isEmpty);
    });

    test('a client that keeps failing is left alone after two tries; youtube_explode answers', () async {
      final innertube = _FakeInnertube({
        ios.clientId: {
          'playabilityStatus': {'status': 'LOGIN_REQUIRED', 'reason': 'Sign in to confirm you’re not a bot'},
        },
        // android_vr has no answer at all: HTTP 400.
      });
      final r = resolver(innertube);
      for (final id in ['aaaaaaaaaaa', 'bbbbbbbbbbb', 'ccccccccccc']) {
        final streams = (await r.resolve(id))!;
        expect(streams.source, kReelSourceExplode);
        expect(streams.muxed, isTrue, reason: 'a long clip under the gate');
        expect(streams.height, 360);
        expect(streams.headers, isEmpty);
      }
      expect(innertube.asks[ios.clientId], ReelStreamResolver.deadAfter);
      expect(innertube.asks[vr.clientId], ReelStreamResolver.deadAfter);
      expect(r.isDead(ios), isTrue);
      expect(r.isDead(vr), isTrue);
      expect(probe.asked, isEmpty);
    });

    test('a dropped connection during the check is no verdict: this reel falls back, the next is checked again',
        () async {
      final innertube = _FakeInnertube({ios.clientId: _player(long, adaptive: _pair('down'))});
      final r = resolver(innertube);
      final streams = (await r.resolve('aaaaaaaaaaa'))!;
      expect(streams.source, kReelSourceExplode);
      expect(streams.muxed, isTrue);
      expect(r.verdict(ios), isNull);
      expect(probe.asked.length, 1);
      await r.resolve('bbbbbbbbbbb');
      expect(probe.asked.length, 2);
    });

    test('a pair inside the gate from youtube_explode is kept over a client’s muxed stream', () async {
      final innertube = _FakeInnertube({
        vr.clientId: _player(short, formats: [_muxedJson(22, height: 720, host: 'vr-m.test')]),
      });
      final streams = (await resolver(innertube, manifest: explode(dur: short + 0.1)).resolve('aaaaaaaaaaa'))!;
      expect(streams.muxed, isFalse);
      expect(streams.height, 1080);
      expect(streams.source, kReelSourceExplode);
    });

    test('a client’s muxed stream stands in when youtube_explode has nothing', () async {
      final innertube = _FakeInnertube({
        vr.clientId: _player(long, formats: [_muxedJson(22, height: 720, host: 'vr-m.test')]),
      });
      final streams = (await resolver(innertube, manifest: explodeDown).resolve('aaaaaaaaaaa'))!;
      expect(streams.muxed, isTrue);
      expect(streams.height, 720);
      expect(streams.source, vr.name);
    });

    test('nothing from any client and nothing from youtube_explode is null', () async {
      final r = resolver(_FakeInnertube({}), manifest: explodeDown);
      expect(await r.resolve('aaaaaaaaaaa'), isNull);
      expect(r.cached('aaaaaaaaaaa'), isNull);
    });

    test('probe: one manifest fetch shared and kept; resolving afterwards fetches nothing more', () async {
      var fetches = 0;
      Future<StreamManifest> vertical(String _) async {
        fetches++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return StreamManifest([
          _video(137, codec: 'avc1.640028', height: 1920, width: 1080, dur: 41.2),
          _video(136, codec: 'avc1.4d401f', height: 1280, width: 720, dur: 41.2),
          _audio(140, codec: 'mp4a.40.2', dur: 41.3),
          _muxed(18, height: 360),
        ]);
      }

      final r = resolver(_FakeInnertube({}), manifest: vertical);
      expect(r.cachedProbe('aaaaaaaaaaa'), isNull);
      final (p1, p2, ok) = await (r.probe('aaaaaaaaaaa'), r.probe('aaaaaaaaaaa'), r.qualifies('aaaaaaaaaaa')).wait;
      expect(fetches, 1, reason: 'concurrent asks share one fetch');
      expect(p1, same(p2));
      expect(p1!.portrait, isTrue);
      expect(p1.quality, 1080);
      expect(p1.duration, const Duration(milliseconds: 41200));
      expect(ok, isTrue);
      expect(r.cachedProbe('aaaaaaaaaaa'), same(p1));
      expect(await r.probe('aaaaaaaaaaa'), same(p1));
      expect(fetches, 1);

      // The clients answer nothing here: youtube_explode's turn, on the
      // manifest the probe already fetched.
      final streams = (await r.resolve('aaaaaaaaaaa'))!;
      expect(fetches, 1, reason: 'the manifest is kept for the resolve');
      expect(streams.source, kReelSourceExplode);
      expect(streams.muxed, isFalse);
      expect(streams.height, 1920, reason: 'the upright 1080p pair, not the 720p one');
      expect(streams.video.path, _v(137).path);
      expect(probe.asked, isEmpty);
    });

    test('probe: a client that answers measures the clip, and its answer serves the resolve: one ask in all',
        () async {
      var fetches = 0;
      Future<StreamManifest> explodeCounted(String _) async {
        fetches++;
        throw StateError('should not be asked');
      }

      final innertube = _FakeInnertube({ios.clientId: _player(41, adaptive: _upright('whole', 41.2))});
      final r = resolver(innertube, manifest: explodeCounted);
      final p = (await r.probe('aaaaaaaaaaa'))!;
      expect(p.width, 1080);
      expect(p.height, 1920);
      expect(p.portrait, isTrue);
      expect(p.quality, 1080);
      expect(p.duration, const Duration(milliseconds: 41200), reason: 'the format’s own length, to the millisecond');
      expect(p.qualifies, isTrue);
      expect(innertube.asks[ios.clientId], 1);
      expect(fetches, 0, reason: 'youtube_explode is not needed');
      expect(r.cachedProbe('aaaaaaaaaaa'), same(p));

      final streams = (await r.resolve('aaaaaaaaaaa'))!;
      expect(innertube.asks[ios.clientId], 1, reason: 'the answer the probe got serves the resolve');
      expect(streams.source, ios.name);
      expect(streams.muxed, isFalse);
      expect(streams.height, 1920);
      expect(fetches, 0);
      expect(probe.asked, isEmpty, reason: 'a short clip needs no range check');
    });

    test('probe: a landscape trailer through a client does not qualify; a client that fails gives way to youtube_explode',
        () async {
      final innertube = _FakeInnertube({ios.clientId: _player(long, adaptive: _pair('whole'))});
      final r = resolver(innertube);
      final p = (await r.probe('aaaaaaaaaaa'))!;
      expect(p.width, 1920);
      expect(p.height, 1080);
      expect(p.portrait, isFalse);
      expect(p.qualifies, isFalse);

      expect(innertube.asks[ios.clientId], 1);

      // No client answers at all: youtube_explode's manifest measures it.
      final silent = _FakeInnertube({});
      final fallback = (await resolver(silent).probe('bbbbbbbbbbb'))!;
      expect(fallback.height, 1080, reason: 'the landscape pair of the stand-in manifest');
      expect(fallback.duration, const Duration(milliseconds: 129100), reason: 'the manifest’s own dur, not a client’s');
      expect(silent.asks[ios.clientId], 1, reason: 'the client was tried first');
    });

    test('probe: a manifest that cannot be fetched is no probe, not kept, and does not qualify', () async {
      final r = resolver(_FakeInnertube({}), manifest: explodeDown);
      expect(await r.probe('aaaaaaaaaaa'), isNull);
      expect(r.cachedProbe('aaaaaaaaaaa'), isNull);
      expect(await r.qualifies('aaaaaaaaaaa'), isFalse);
      expect(r.throttled, isFalse, reason: 'a plain failure is not YouTube refusing for too many requests');
    });

    test('YouTube refusing for too many requests throttles youtube_explode: nothing more is asked for a while',
        () async {
      var fetches = 0;
      Future<StreamManifest> refused(String _) async {
        fetches++;
        throw RequestLimitExceededException('429');
      }

      final r = resolver(_FakeInnertube({}), manifest: refused);
      expect(r.throttled, isFalse);
      expect(await r.probe('aaaaaaaaaaa'), isNull);
      expect(fetches, 1);
      expect(r.throttled, isTrue);
      expect(ReelStreamResolver.throttleBackoff, const Duration(seconds: 90));

      // Neither a probe nor a resolve through youtube_explode asks again.
      expect(await r.probe('bbbbbbbbbbb'), isNull);
      expect(await r.qualifies('ccccccccccc'), isFalse);
      expect(await r.resolve('ddddddddddd'), isNull);
      expect(fetches, 1, reason: 'left alone while the refusal holds');
      expect(r.cachedProbe('aaaaaaaaaaa'), isNull);
      expect(r.throttledUntil, isNotNull);
      expect(
        r.throttledUntil!.difference(DateTime.now()),
        lessThanOrEqualTo(ReelStreamResolver.throttleBackoff),
        reason: 'the page waits on it and tries again',
      );
    });

    group('why a resolve came back with nothing', () {
      // A client that answers, and says the clip cannot be played.
      Map<String, dynamic> unplayable() => {
            'playabilityStatus': {'status': 'UNPLAYABLE', 'reason': 'This video is unavailable'},
            'videoDetails': {'lengthSeconds': '30'},
          };

      test('streams in hand: ok', () async {
        final r = resolver(_FakeInnertube({ios.clientId: _player(short, adaptive: _pair('whole'))}));
        final result = await r.resolveDetailed('aaaaaaaaaaa');
        expect(result.reason, ReelResolveReason.ok);
        expect(result.streams, isNotNull);
        expect(result.unavailable, isFalse);
        expect(result.transient, isFalse);
        expect((await r.resolve('aaaaaaaaaaa'))!.source, ios.name, reason: 'the old call still hands out streams');
        expect(
          (await r.resolveDetailed('aaaaaaaaaaa')).reason,
          ReelResolveReason.ok,
          reason: 'the cached streams answer the same way',
        );
      });

      test('youtube_explode saying the video is unplayable: unavailable, whatever the clients did', () async {
        Future<StreamManifest> gone(String _) async => throw VideoUnplayableException('gone');
        final r = resolver(_FakeInnertube({}), manifest: gone);
        final result = await r.resolveDetailed('aaaaaaaaaaa');
        expect(result.reason, ReelResolveReason.unavailable);
        expect(result.streams, isNull);
        expect(result.unavailable, isTrue);
        expect(result.transient, isFalse);
      });

      test('a manifest with nothing a player can open: unavailable', () async {
        // Video-only, no audio and no muxed stream: nothing to play.
        Future<StreamManifest> bare(String _) async =>
            StreamManifest([_video(137, codec: 'avc1.640028', height: 1080, dur: 30)]);
        expect((await resolver(_FakeInnertube({}), manifest: bare).resolveDetailed('aaaaaaaaaaa')).reason,
            ReelResolveReason.unavailable);
      });

      test('every client answering «unplayable» is YouTube’s own verdict: unavailable', () async {
        Future<StreamManifest> down(String _) async => throw const SocketException('no route');
        final answers = {ios.clientId: unplayable(), vr.clientId: unplayable()};
        final result = await resolver(_FakeInnertube(answers), manifest: down).resolveDetailed('aaaaaaaaaaa');
        expect(result.reason, ReelResolveReason.unavailable);
      });

      test('a request that never arrived: network — nothing is written off over it', () async {
        Future<StreamManifest> down(String _) async => throw const SocketException('no route');
        // The fake answers HTTP 400 for a client it has nothing for: the
        // request failed, so nothing was learnt.
        final result = await resolver(_FakeInnertube({}), manifest: down).resolveDetailed('aaaaaaaaaaa');
        expect(result.reason, ReelResolveReason.network);
        expect(result.transient, isTrue);
        expect(result.unavailable, isFalse);
      });

      test('YouTube refusing for too many requests: throttled, with the time it lifts', () async {
        Future<StreamManifest> refused(String _) async => throw RequestLimitExceededException('429');
        final r = resolver(_FakeInnertube({}), manifest: refused);
        final result = await r.resolveDetailed('aaaaaaaaaaa');
        expect(result.reason, ReelResolveReason.throttled);
        expect(result.transient, isTrue);
        expect(r.throttledUntil, isNotNull);
        expect(
          (await r.resolveDetailed('bbbbbbbbbbb')).reason,
          ReelResolveReason.throttled,
          reason: 'while the refusal holds nothing else is written off either',
        );
      });
    });
  });

  group('ReelStreamProxy headers', () {
    final proxy = ReelStreamProxy.instance;
    tearDown(() => proxy.close());

    test('the registered headers ride on every slice; re-registering keeps them, an empty map clears them',
        () async {
      final seen = <String?>[];
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      upstream.listen((req) async {
        seen.add(req.headers.value(HttpHeaders.userAgentHeader));
        final res = req.response;
        res.statusCode = HttpStatus.partialContent;
        res.headers.set(HttpHeaders.contentRangeHeader, 'bytes 0-0/1');
        res.headers.contentLength = 1;
        res.add([7]);
        await res.close();
      });
      try {
        final url = Uri(scheme: 'http', host: upstream.address.address, port: upstream.port, path: '/v', queryParameters: {'itag': '137'});
        Future<void> fetch(Uri local) async {
          final client = HttpClient();
          try {
            final req = await client.getUrl(local);
            req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
            final res = await req.close();
            await res.drain<void>();
          } finally {
            client.close(force: true);
          }
        }

        final local = await proxy.register(url, headers: const {'User-Agent': 'the-app/1.0'});
        expect(proxy.headersOf(local), {'User-Agent': 'the-app/1.0'});
        await fetch(local);
        expect(seen, ['the-app/1.0']);

        expect(await proxy.register(url), local);
        expect(proxy.headersOf(local), {'User-Agent': 'the-app/1.0'}, reason: 'registering again keeps the headers');
        await fetch(local);
        expect(seen.last, 'the-app/1.0');

        await proxy.register(url, headers: const {});
        expect(proxy.headersOf(local), isEmpty);
        await fetch(local);
        expect(seen.last, isNot('the-app/1.0'));
      } finally {
        await upstream.close(force: true);
      }
    });
  });
}

/// Records every range probe; 206 for a host named `whole-…`, 403 past the
/// first byte for `gated-…`, a failed request (-1) for `down-…`.
class _Probe {
  final List<(Uri, int, Map<String, String>)> asked = [];

  Future<int> call(Uri url, {Map<String, String> headers = const {}, int start = 0}) async {
    asked.add((url, start, headers));
    if (url.host.startsWith('down')) return -1;
    if (url.host.startsWith('gated') && start > 0) return 403;
    return 206;
  }
}

/// Stands in for `/youtubei/v1/player`: answers each client (by its
/// `X-YouTube-Client-Name`) with its canned response, HTTP 400 when it has
/// none, counts the asks, and — each answer taking a moment — records how
/// many were in flight at once.
class _FakeInnertube implements HttpClientAdapter {
  _FakeInnertube(this.answers);

  final Map<int, Map<String, dynamic>> answers;
  final Map<int, int> asks = {};
  int _inFlight = 0;
  int maxInFlight = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final name = options.headers.entries
        .where((e) => e.key.toLowerCase() == 'x-youtube-client-name')
        .map((e) => '${e.value}')
        .firstOrNull;
    final id = int.tryParse(name ?? '') ?? -1;
    asks[id] = (asks[id] ?? 0) + 1;
    _inFlight++;
    maxInFlight = math.max(maxInFlight, _inFlight);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    _inFlight--;
    final json = answers[id];
    const headers = {
      'content-type': ['application/json']
    };
    if (json == null) return ResponseBody.fromString('{"error": {"code": 400}}', 400, headers: headers);
    return ResponseBody.fromString(jsonEncode(json), 200, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

/// A player response of [lengthSeconds] with the given formats.
Map<String, dynamic> _player(
  int lengthSeconds, {
  List<Map<String, dynamic>> formats = const [],
  List<Map<String, dynamic>> adaptive = const [],
}) =>
    {
      'playabilityStatus': {'status': 'OK'},
      'videoDetails': {'lengthSeconds': '$lengthSeconds'},
      'streamingData': {'formats': formats, 'adaptiveFormats': adaptive},
    };

/// A 1080p H.264 video-only format and an AAC audio-only one, on hosts
/// `<prefix>-v.test` and `<prefix>-a.test`.
List<Map<String, dynamic>> _pair(String prefix) => [
      {
        'itag': 137,
        'url': 'https://$prefix-v.test/137?clen=40000&dur=129.05',
        'mimeType': 'video/mp4; codecs="avc1.640028"',
        'bitrate': 3954000,
        'width': 1920,
        'height': 1080,
        'contentLength': '40000',
        'approxDurationMs': '129050',
      },
      {
        'itag': 140,
        'url': 'https://$prefix-a.test/140?clen=2000&dur=129.2',
        'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
        'bitrate': 130000,
        'contentLength': '2000',
        'approxDurationMs': '129200',
      },
    ];

/// An upright 1080×1920 H.264 video-only format of [seconds] and an AAC
/// audio-only one, on hosts `<prefix>-v.test` and `<prefix>-a.test`.
List<Map<String, dynamic>> _upright(String prefix, double seconds) => [
      {
        'itag': 137,
        'url': 'https://$prefix-v.test/137?clen=30000&dur=$seconds',
        'mimeType': 'video/mp4; codecs="avc1.640028"',
        'bitrate': 3954000,
        'width': 1080,
        'height': 1920,
        'contentLength': '30000',
        'approxDurationMs': '${(seconds * 1000).round()}',
      },
      {
        'itag': 136,
        'url': 'https://$prefix-v.test/136?clen=15000&dur=$seconds',
        'mimeType': 'video/mp4; codecs="avc1.4d401f"',
        'bitrate': 1500000,
        'width': 720,
        'height': 1280,
        'contentLength': '15000',
        'approxDurationMs': '${(seconds * 1000).round()}',
      },
      {
        'itag': 140,
        'url': 'https://$prefix-a.test/140?clen=2000&dur=$seconds',
        'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
        'bitrate': 130000,
        'contentLength': '2000',
        'approxDurationMs': '${(seconds * 1000).round()}',
      },
    ];

Map<String, dynamic> _muxedJson(int itag, {required int height, required String host}) => {
      'itag': itag,
      'url': 'https://$host/$itag?clen=9000&dur=129.1',
      'mimeType': 'video/mp4; codecs="avc1.64001F, mp4a.40.2"',
      'bitrate': 1500000,
      'width': height * 16 ~/ 9,
      'height': height,
      'contentLength': '9000',
      'approxDurationMs': '129100',
    };
