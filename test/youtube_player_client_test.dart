import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/reels/data/youtube_player_client.dart';

/// A hand-written player response in the shape `/youtubei/v1/player` gives
/// an app client: two muxed formats, video-only formats in every codec,
/// audio-only formats with a dubbed track, one fragmented (OTF) stream, and
/// one whose URL is wrapped in a signature cipher.
const String _playerJson = r'''
{
  "playabilityStatus": {"status": "OK", "playableInEmbed": true},
  "videoDetails": {"videoId": "dQw4w9WgXcQ", "title": "Trailer", "lengthSeconds": "129"},
  "streamingData": {
    "expiresInSeconds": "21540",
    "formats": [
      {"itag": 18, "url": "https://m.test/18?clen=5000&dur=129.1", "mimeType": "video/mp4; codecs=\"avc1.42001E, mp4a.40.2\"",
       "bitrate": 438000, "width": 640, "height": 360, "contentLength": "5000", "approxDurationMs": "129100", "qualityLabel": "360p", "fps": 24},
      {"itag": 22, "url": "https://m.test/22", "mimeType": "video/mp4; codecs=\"avc1.64001F, mp4a.40.2\"",
       "bitrate": 1500000, "width": 1280, "height": 720, "approxDurationMs": "129100", "qualityLabel": "720p"}
    ],
    "adaptiveFormats": [
      {"itag": 137, "url": "https://v.test/137?clen=40000&dur=129.05", "mimeType": "video/mp4; codecs=\"avc1.640028\"",
       "bitrate": 3954000, "width": 1920, "height": 1080, "contentLength": "40000", "approxDurationMs": "129050", "qualityLabel": "1080p", "fps": 24},
      {"itag": 136, "url": "https://v.test/136", "mimeType": "video/mp4; codecs=\"avc1.4d401f\"",
       "bitrate": 2000000, "width": 1280, "height": 720, "contentLength": "20000", "approxDurationMs": "129050", "qualityLabel": "720p"},
      {"itag": 400, "url": "https://v.test/400", "mimeType": "video/mp4; codecs=\"av01.0.12M.08\"",
       "bitrate": 9000000, "width": 3840, "height": 2160, "contentLength": "90000", "approxDurationMs": "129050", "qualityLabel": "2160p"},
      {"itag": 313, "url": "https://v.test/313", "mimeType": "video/webm; codecs=\"vp09.00.51.08\"",
       "bitrate": 8000000, "width": 3840, "height": 2160, "contentLength": "80000", "approxDurationMs": "129050", "qualityLabel": "2160p"},
      {"itag": 248, "url": "https://v.test/248", "mimeType": "video/webm; codecs=\"vp09.00.40.08\"",
       "bitrate": 3000000, "width": 1920, "height": 1080, "contentLength": "30000", "approxDurationMs": "129050", "qualityLabel": "1080p"},
      {"itag": 299, "signatureCipher": "s=AAA&sp=sig&url=https%3A%2F%2Fv.test%2F299", "mimeType": "video/mp4; codecs=\"avc1.64002a\"",
       "bitrate": 6000000, "width": 1920, "height": 1080, "contentLength": "60000", "approxDurationMs": "129050", "qualityLabel": "1080p60", "fps": 60},
      {"itag": 138, "url": "https://v.test/138", "mimeType": "video/mp4; codecs=\"avc1.640033\"", "type": "FORMAT_STREAM_TYPE_OTF",
       "bitrate": 12000000, "width": 3840, "height": 2160, "approxDurationMs": "129050", "qualityLabel": "2160p"},
      {"itag": 140, "url": "https://a.test/140?clen=2000&dur=129.2", "mimeType": "audio/mp4; codecs=\"mp4a.40.2\"",
       "bitrate": 130000, "contentLength": "2000", "approxDurationMs": "129200", "audioQuality": "AUDIO_QUALITY_MEDIUM"},
      {"itag": 139, "url": "https://a.test/139", "mimeType": "audio/mp4; codecs=\"mp4a.40.5\"",
       "bitrate": 48000, "contentLength": "800", "approxDurationMs": "129200"},
      {"itag": 251, "url": "https://a.test/251", "mimeType": "audio/webm; codecs=\"opus\"",
       "bitrate": 160000, "contentLength": "2500", "approxDurationMs": "129200"},
      {"itag": 140, "url": "https://a.test/140-fr", "mimeType": "audio/mp4; codecs=\"mp4a.40.2\"",
       "bitrate": 256000, "contentLength": "4000", "approxDurationMs": "129200",
       "audioTrack": {"displayName": "French", "id": "fr.3", "audioIsDefault": false}}
    ]
  }
}
''';

Map<String, dynamic> get _player => jsonDecode(_playerJson) as Map<String, dynamic>;

void main() {
  group('parseYoutubeFormats', () {
    test('normalises every format of both lists', () {
      final formats = parseYoutubeFormats(_player);
      expect(formats.length, 13);

      final muxed = formats.firstWhere((f) => f.itag == 18);
      expect(muxed.kind, YoutubeFormatKind.muxed);
      expect(muxed.codec, 'avc1.42001E');
      expect(muxed.audioCodec, 'mp4a.40.2');
      expect(muxed.height, 360);
      expect(muxed.width, 640);
      expect(muxed.bitrate, 438000);
      expect(muxed.contentLength, 5000);
      expect(muxed.approxDurationMs, 129100);
      expect(muxed.duration, const Duration(milliseconds: 129100));
      expect(muxed.container, 'mp4');
      expect(muxed.fps, 24);
      expect(muxed.qualityLabel, '360p');
      expect(muxed.hasCipher, isFalse);
      expect(muxed.isDirect, isTrue);
      expect(muxed.isAvc, isTrue);
      expect(muxed.isAac, isTrue);

      final video = formats.firstWhere((f) => f.itag == 137);
      expect(video.kind, YoutubeFormatKind.videoOnly);
      expect(video.videoOnly, isTrue);
      expect(video.audioCodec, isNull);
      expect(video.height, 1080);
      expect(video.url, Uri.parse('https://v.test/137?clen=40000&dur=129.05'));

      final audio = formats.firstWhere((f) => f.itag == 140 && f.audioIsDefault);
      expect(audio.kind, YoutubeFormatKind.audioOnly);
      expect(audio.codec, 'mp4a.40.2');
      expect(audio.audioCodec, 'mp4a.40.2');
      expect(audio.height, 0);
      expect(audio.container, 'mp4');

      final opus = formats.firstWhere((f) => f.itag == 251);
      expect(opus.isOpus, isTrue);
      expect(opus.container, 'webm');

      final vp9 = formats.firstWhere((f) => f.itag == 248);
      expect(vp9.isVp9, isTrue);
      expect(vp9.isAvc, isFalse);
    });

    test('a ciphered URL is kept, flagged, and never direct', () {
      final f = parseYoutubeFormats(_player).firstWhere((f) => f.itag == 299);
      expect(f.hasCipher, isTrue);
      expect(f.url, Uri.parse('https://v.test/299'), reason: 'the URL inside the cipher is read for the record');
      expect(f.isDirect, isFalse);
    });

    test('a fragmented (OTF) stream is flagged and never direct', () {
      final f = parseYoutubeFormats(_player).firstWhere((f) => f.itag == 138);
      expect(f.fragmented, isTrue);
      expect(f.isDirect, isFalse);
    });

    test('a dubbed track is marked as not the original', () {
      final dubbed = parseYoutubeFormats(_player).firstWhere((f) => f.url?.path == '/140-fr');
      expect(dubbed.audioIsDefault, isFalse);
    });

    test('length and duration fall back to the URL when the fields are missing', () {
      final formats = parseYoutubeFormats({
        'streamingData': {
          'adaptiveFormats': [
            {'itag': 140, 'url': 'https://a.test/140?clen=777&dur=61.5', 'mimeType': 'audio/mp4; codecs="mp4a.40.2"', 'bitrate': 1},
            {'itag': 141, 'url': 'https://a.test/141', 'mimeType': 'audio/mp4; codecs="mp4a.40.2"', 'bitrate': 1},
          ],
        },
      });
      expect(formats[0].contentLength, 777);
      expect(formats[0].duration, const Duration(milliseconds: 61500));
      expect(formats[1].contentLength, 0);
      expect(formats[1].duration, isNull);
    });

    test('entries without an itag or a mime type, and a response without streams, are skipped', () {
      expect(
        parseYoutubeFormats({
          'streamingData': {
            'formats': [
              {'url': 'https://m.test/x', 'mimeType': 'video/mp4'},
              {'itag': 18, 'url': 'https://m.test/18'},
            ],
          },
        }),
        isEmpty,
      );
      expect(parseYoutubeFormats({}), isEmpty);
      expect(parseYoutubeFormats({'streamingData': null}), isEmpty);
    });
  });

  group('YoutubePlayerResult', () {
    test('reads the playability, the length and the formats', () {
      final r = YoutubePlayerResult.fromJson(_player, client: InnertubeClient.ios);
      expect(r.status, 'OK');
      expect(r.playable, isTrue);
      expect(r.reason, isEmpty);
      expect(r.durationMs, 129000);
      expect(r.duration, const Duration(seconds: 129));
      expect(r.client, InnertubeClient.ios);
      expect(r.formats.length, 13);
      expect(r.direct.length, 11, reason: 'the cipher and the OTF stream are not direct');
    });

    test('an unplayable answer carries its reason and no formats', () {
      final r = YoutubePlayerResult.fromJson({
        'playabilityStatus': {'status': 'LOGIN_REQUIRED', 'reason': 'Sign in to confirm you’re not a bot'},
      }, client: InnertubeClient.androidVr);
      expect(r.playable, isFalse);
      expect(r.status, 'LOGIN_REQUIRED');
      expect(r.reason, contains('bot'));
      expect(r.formats, isEmpty);
      expect(r.duration, isNull);
    });

    test('the length falls back to a format when the details carry none', () {
      final r = YoutubePlayerResult.fromJson({
        'playabilityStatus': {'status': 'OK'},
        'streamingData': {
          'adaptiveFormats': [
            {'itag': 140, 'url': 'https://a.test/140', 'mimeType': 'audio/mp4; codecs="mp4a.40.2"', 'approxDurationMs': '5000'},
          ],
        },
      }, client: InnertubeClient.ios);
      expect(r.duration, const Duration(seconds: 5));
    });
  });

  group('pickers', () {
    final formats = parseYoutubeFormats(_player);

    test('video: H.264 mp4 as tall as the ceiling allows, never a cipher, never OTF', () {
      final v = pickYoutubeVideo(formats, maxAvcHeight: 1440, maxVp9Height: 1080)!;
      expect(v.itag, 137, reason: '1080p H.264: 299 is ciphered, 138 is OTF, 400 is AV1');
      expect(pickYoutubeVideo(formats, maxAvcHeight: 720, maxVp9Height: 1080)!.itag, 136);
    });

    test('video: VP9 only when there is no H.264, and no taller than its ceiling', () {
      final noAvc = formats.where((f) => !f.isAvc).toList();
      expect(pickYoutubeVideo(noAvc, maxAvcHeight: 1440, maxVp9Height: 1080)!.itag, 248);
      expect(pickYoutubeVideo(noAvc, maxAvcHeight: 1440, maxVp9Height: 2160)!.itag, 313);
      expect(pickYoutubeVideo(noAvc, maxAvcHeight: 1440, maxVp9Height: 720), isNull);
    });

    test('video: among equal heights the higher bitrate wins', () {
      final v = pickYoutubeVideo([
        _video(1, height: 1080, bitrate: 2000000),
        _video(2, height: 1080, bitrate: 4000000),
        _video(3, height: 1080, bitrate: 3000000),
      ], maxAvcHeight: 1440, maxVp9Height: 1080)!;
      expect(v.itag, 2);
    });

    test('audio: AAC in mp4 at the highest bitrate, the original track over a dub', () {
      final a = pickYoutubeAudio(formats)!;
      expect(a.url?.path, '/140', reason: 'the louder French dub is not the original');
      expect(pickYoutubeAudio(formats.where((f) => f.itag != 140))!.itag, 139);
    });

    test('audio: Opus stands in when there is no AAC', () {
      expect(pickYoutubeAudio(formats.where((f) => !f.isAac))!.itag, 251);
      expect(pickYoutubeAudio(formats.where((f) => f.videoOnly)), isNull);
    });

    test('muxed: the tallest, then the higher bitrate', () {
      expect(pickYoutubeMuxed(formats)!.itag, 22);
      expect(pickYoutubeMuxed(formats.where((f) => f.itag != 22))!.itag, 18);
      expect(pickYoutubeMuxed(formats.where((f) => !f.muxed)), isNull);
    });
  });

  group('youtubeByteAt', () {
    test('places a media time in the file by its share of the length', () {
      final f = parseYoutubeFormats(_player).firstWhere((f) => f.itag == 137);
      // 40000 bytes over 129.05 s.
      expect(youtubeByteAt(f, Duration.zero), 0);
      expect(youtubeByteAt(f, const Duration(seconds: 90)), (40000 * 90000 / 129050).floor());
      expect(youtubeByteAt(f, const Duration(seconds: 500)), 39999, reason: 'never past the last byte');
    });

    test('is 0 when the length or the duration is unknown', () {
      expect(youtubeByteAt(_video(1, height: 720, contentLength: 0), const Duration(seconds: 90)), 0);
      expect(youtubeByteAt(_video(1, height: 720, durationMs: 0), const Duration(seconds: 90)), 0);
    });
  });

  group('InnertubeClient', () {
    test('the request body names the client, the video and the checks', () {
      final body = InnertubeClient.ios.body('dQw4w9WgXcQ');
      final context = body['context'] as Map;
      final client = context['client'] as Map;
      expect(client['clientName'], 'IOS');
      expect(client['clientVersion'], InnertubeClient.ios.clientVersion);
      expect(client['deviceModel'], 'iPhone16,2');
      expect(client['hl'], 'en');
      expect(client['gl'], 'US');
      expect(context.containsKey('thirdParty'), isFalse);
      expect(body['videoId'], 'dQw4w9WgXcQ');
      expect(body['contentCheckOk'], isTrue);
      expect(body['racyCheckOk'], isTrue);
      expect((body['playbackContext'] as Map)['contentPlaybackContext'], {'html5Preference': 'HTML5_PREF_WANTS'});

      final embedded = InnertubeClient.tvEmbedded.body('dQw4w9WgXcQ')['context'] as Map;
      expect(embedded['thirdParty'], {'embedUrl': 'https://www.youtube.com'});
    });

    test('the headers name the client by number and carry its user agent', () {
      final h = InnertubeClient.androidVr.requestHeaders;
      expect(h['X-YouTube-Client-Name'], '28');
      expect(h['X-YouTube-Client-Version'], InnertubeClient.androidVr.clientVersion);
      expect(h['User-Agent'], startsWith('com.google.android.apps.youtube.vr.oculus/'));
      expect(h.containsKey('Origin'), isFalse);
      expect(InnertubeClient.webEmbedded.requestHeaders['Origin'], 'https://www.youtube.com');
      expect(InnertubeClient.ios.streamHeaders, {'User-Agent': InnertubeClient.ios.userAgent});
    });
  });
}

YoutubeFormat _video(int itag, {required int height, int bitrate = 1000000, int contentLength = 1000, int durationMs = 100000}) =>
    YoutubeFormat(
      itag: itag,
      url: Uri.parse('https://v.test/$itag'),
      mimeType: 'video/mp4; codecs="avc1.640028"',
      codec: 'avc1.640028',
      audioCodec: null,
      kind: YoutubeFormatKind.videoOnly,
      height: height,
      width: height * 16 ~/ 9,
      bitrate: bitrate,
      contentLength: contentLength,
      approxDurationMs: durationMs,
      hasCipher: false,
    );
