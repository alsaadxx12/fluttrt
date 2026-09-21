/// YouTube's innertube `/youtubei/v1/player` endpoint, asked directly as one
/// of the clients that hand out plain stream URLs (no signature cipher).
///
/// youtube_explode (3.0.0) asks as the android client, and without a
/// proof-of-origin token YouTube refuses that client any adaptive-stream
/// byte past about a minute of media, so a trailer longer than that falls
/// to the 360p muxed stream (see `kReelAdaptiveMaxDuration` in the
/// resolver). Other clients are not all held to that — which ones is
/// measured, never assumed: the probe test prints the matrix, and the
/// resolver verifies a client with a one-byte read deep into a long clip
/// before trusting it for the session.
///
/// Everything here but [YoutubePlayerClient.player] and [probeRange] is
/// pure, so the normaliser and the pickers are tested on a hand-written
/// player response.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';

/// One innertube client identity: what the request says it is and the
/// headers its stream URLs must be fetched with.
class InnertubeClient {
  const InnertubeClient({
    required this.name,
    required this.clientName,
    required this.clientVersion,
    required this.clientId,
    required this.userAgent,
    this.context = const {},
    this.embedUrl,
    this.web = false,
  });

  /// A short label for logs and tests (`ios`, `android_vr`).
  final String name;

  /// `context.client.clientName` and `.clientVersion`.
  final String clientName;
  final String clientVersion;

  /// The numeric id sent as `X-YouTube-Client-Name`.
  final int clientId;
  final String userAgent;

  /// Extra `context.client` fields: device, OS, SDK level.
  final Map<String, Object> context;

  /// `thirdParty.embedUrl`, for the embedded players.
  final String? embedUrl;

  /// A browser-based client: the request carries the website's Origin and
  /// Referer, as the site itself would send them.
  final bool web;

  /// The iOS app. Serves adaptive H.264 up to 1080p and AAC without a
  /// signature cipher (no muxed stream at all); the byte requests carry
  /// the app's User-Agent. Version 19.45.4 is refused outright (HTTP 400,
  /// `FAILED_PRECONDITION`) since at least September 2026; 20.10.4 is
  /// answered.
  static const InnertubeClient ios = InnertubeClient(
    name: 'ios',
    clientName: 'IOS',
    clientVersion: '20.10.4',
    clientId: 5,
    userAgent: 'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)',
    context: {
      'deviceMake': 'Apple',
      'deviceModel': 'iPhone16,2',
      'osName': 'iPhone',
      'osVersion': '18.3.2.22D82',
    },
  );

  /// The Quest (Android VR) app: an android-family client that was for a
  /// while not put behind the proof-of-origin token. Measured in September
  /// 2026 (1.56.21 through 1.71.19): «This video is not available» or a
  /// «confirm you're not a bot» sign-in for every trailer asked.
  static const InnertubeClient androidVr = InnertubeClient(
    name: 'android_vr',
    clientName: 'ANDROID_VR',
    clientVersion: '1.57.29',
    clientId: 28,
    userAgent: 'com.google.android.apps.youtube.vr.oculus/1.57.29 '
        '(Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
    context: {
      'deviceMake': 'Oculus',
      'deviceModel': 'Quest 3',
      'androidSdkVersion': 32,
      'osName': 'Android',
      'osVersion': '12L',
    },
  );

  /// The TV embedded player, as a page embedding a video would use it.
  /// Measured in September 2026: «YouTube is no longer supported in this
  /// application or device» — retired.
  static const InnertubeClient tvEmbedded = InnertubeClient(
    name: 'tv_embedded',
    clientName: 'TVHTML5_SIMPLY_EMBEDDED_PLAYER',
    clientVersion: '2.0',
    clientId: 85,
    userAgent: 'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version',
    embedUrl: 'https://www.youtube.com',
    web: true,
  );

  /// The website's embedded player. Measured in September 2026: «This
  /// video is unavailable» for every trailer asked; its formats would carry
  /// a signature cipher anyway.
  static const InnertubeClient webEmbedded = InnertubeClient(
    name: 'web_embedded',
    clientName: 'WEB_EMBEDDED_PLAYER',
    clientVersion: '1.20250310.01.00',
    clientId: 56,
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/124.0.0.0 Safari/537.36',
    embedUrl: 'https://www.youtube.com',
    web: true,
  );

  /// Every client the probe measures, in the order the resolver tries them:
  /// the one that answers today first, the retired ones last (the resolver
  /// sets a client aside for the session after it fails twice in a row).
  static const List<InnertubeClient> candidates = [ios, androidVr, webEmbedded, tvEmbedded];

  /// The request body for [videoId].
  Map<String, Object> body(String videoId) => {
        'context': {
          'client': {
            'clientName': clientName,
            'clientVersion': clientVersion,
            ...context,
            'hl': 'en',
            'gl': 'US',
            'utcOffsetMinutes': 0,
          },
          if (embedUrl != null) 'thirdParty': {'embedUrl': embedUrl},
        },
        'videoId': videoId,
        'contentCheckOk': true,
        'racyCheckOk': true,
        'playbackContext': {
          'contentPlaybackContext': {'html5Preference': 'HTML5_PREF_WANTS'},
        },
      };

  /// The headers of the player request.
  Map<String, String> get requestHeaders => {
        'User-Agent': userAgent,
        'Content-Type': 'application/json',
        'X-YouTube-Client-Name': '$clientId',
        'X-YouTube-Client-Version': clientVersion,
        if (web) 'Origin': 'https://www.youtube.com',
        if (web) 'Referer': 'https://www.youtube.com/',
      };

  /// The headers every byte request for this client's streams must carry:
  /// the stream host checks that the User-Agent is the client's own.
  Map<String, String> get streamHeaders => {'User-Agent': userAgent};

  @override
  String toString() => name;
}

/// What a format carries: sound only, picture only, or both.
enum YoutubeFormatKind { audioOnly, videoOnly, muxed }

/// One entry of the player response's `streamingData`, normalised.
class YoutubeFormat {
  const YoutubeFormat({
    required this.itag,
    required this.url,
    required this.mimeType,
    required this.codec,
    required this.audioCodec,
    required this.kind,
    required this.height,
    required this.width,
    required this.bitrate,
    required this.contentLength,
    required this.approxDurationMs,
    required this.hasCipher,
    this.fps,
    this.qualityLabel = '',
    this.audioIsDefault = true,
    this.fragmented = false,
  });

  final int itag;

  /// The plain stream URL; null when the response gave only a cipher.
  final Uri? url;

  /// As YouTube writes it: `video/mp4; codecs="avc1.640028"`.
  final String mimeType;

  /// The first codec of the mime type: the picture's for a video or muxed
  /// format, the sound's for an audio-only one.
  final String codec;

  /// The sound's codec: the second codec of a muxed format, the only one of
  /// an audio-only format, null for a video-only one.
  final String? audioCodec;
  final YoutubeFormatKind kind;

  /// The picture's size; 0 for audio.
  final int height;
  final int width;
  final int bitrate;

  /// The file's length in bytes; 0 when YouTube did not say.
  final int contentLength;

  /// The clip's length; 0 when YouTube did not say.
  final int approxDurationMs;

  /// True when the URL came wrapped in a `signatureCipher` (or `cipher`)
  /// and needs the player's JavaScript to be usable.
  final bool hasCipher;
  final int? fps;
  final String qualityLabel;

  /// False for a dubbed track YouTube marks as not the original.
  final bool audioIsDefault;

  /// A fragmented (OTF / DASH) stream: not one file the player can open.
  final bool fragmented;

  bool get audioOnly => kind == YoutubeFormatKind.audioOnly;
  bool get videoOnly => kind == YoutubeFormatKind.videoOnly;
  bool get muxed => kind == YoutubeFormatKind.muxed;

  /// A URL the player can open as one file: plain, whole, no cipher.
  bool get isDirect => url != null && !hasCipher && !fragmented;

  /// `mp4`, `webm`, ... from the mime type.
  String get container {
    final slash = mimeType.indexOf('/');
    final semi = mimeType.indexOf(';');
    if (slash < 0) return '';
    return mimeType.substring(slash + 1, semi < 0 ? mimeType.length : semi).trim().toLowerCase();
  }

  bool get isAvc => codec.toLowerCase().startsWith('avc1');
  bool get isVp9 {
    final c = codec.toLowerCase();
    return c.startsWith('vp09') || c.startsWith('vp9');
  }

  bool get isAac => (audioCodec ?? '').toLowerCase().startsWith('mp4a');
  bool get isOpus => (audioCodec ?? '').toLowerCase().startsWith('opus');

  /// The clip's length: `approxDurationMs`, else the `dur` in the URL.
  Duration? get duration {
    if (approxDurationMs > 0) return Duration(milliseconds: approxDurationMs);
    final s = double.tryParse(url?.queryParameters['dur'] ?? '');
    return s == null || s <= 0 ? null : Duration(milliseconds: (s * 1000).round());
  }

  @override
  String toString() => 'itag $itag ${kind.name} ${height > 0 ? '${height}p ' : ''}$codec'
      '${audioCodec != null && !audioOnly ? '+$audioCodec' : ''} ${bitrate ~/ 1000}kbps'
      '${hasCipher ? ' (cipher)' : ''}${fragmented ? ' (fragmented)' : ''}';
}

/// What one client said about one video.
class YoutubePlayerResult {
  const YoutubePlayerResult({
    required this.client,
    required this.status,
    required this.reason,
    required this.formats,
    required this.durationMs,
    this.author = '',
  });

  final InnertubeClient client;

  /// `videoDetails.author`: the channel's name; empty when absent.
  final String author;

  /// `playabilityStatus.status`: `OK`, `UNPLAYABLE`, `LOGIN_REQUIRED`,
  /// `ERROR`, ...; empty when the response had none.
  final String status;

  /// `playabilityStatus.reason`, when there is one.
  final String reason;
  final List<YoutubeFormat> formats;

  /// `videoDetails.lengthSeconds`, in milliseconds; 0 when absent.
  final int durationMs;

  bool get playable => status.toUpperCase() == 'OK';

  /// The formats a player can open as one file.
  List<YoutubeFormat> get direct => formats.where((f) => f.isDirect).toList();

  /// The clip's length from the details, else from any format.
  Duration? get duration {
    if (durationMs > 0) return Duration(milliseconds: durationMs);
    for (final f in formats) {
      final d = f.duration;
      if (d != null) return d;
    }
    return null;
  }

  /// [json] (the decoded player response) as the client's answer. Pure.
  factory YoutubePlayerResult.fromJson(Map<String, dynamic> json, {required InnertubeClient client}) {
    final playability = _map(json['playabilityStatus']);
    final details = _map(json['videoDetails']);
    return YoutubePlayerResult(
      client: client,
      status: '${playability['status'] ?? ''}',
      reason: '${playability['reason'] ?? ''}',
      formats: parseYoutubeFormats(json),
      durationMs: (_int(details['lengthSeconds']) ?? 0) * 1000,
      author: '${details['author'] ?? ''}'.trim(),
    );
  }
}

/// Every format of [playerResponse]'s `streamingData` — `formats` (muxed)
/// and `adaptiveFormats` (video-only or audio-only by mime type) —
/// normalised; entries without an itag or a mime type are dropped, one
/// whose URL is a cipher is kept with `hasCipher` so it can be counted.
/// Pure.
List<YoutubeFormat> parseYoutubeFormats(Map<String, dynamic> playerResponse) {
  final streaming = _map(playerResponse['streamingData']);
  final out = <YoutubeFormat>[];
  void add(Object? list, {required bool adaptive}) {
    if (list is! List) return;
    for (final e in list) {
      final f = _format(_map(e), adaptive: adaptive);
      if (f != null) out.add(f);
    }
  }

  add(streaming['formats'], adaptive: false);
  add(streaming['adaptiveFormats'], adaptive: true);
  return out;
}

YoutubeFormat? _format(Map<String, dynamic> e, {required bool adaptive}) {
  final itag = _int(e['itag']);
  final mime = e['mimeType'];
  if (itag == null || mime is! String || mime.isEmpty) return null;
  final codecs = _codecs(mime);
  final isAudio = mime.trim().toLowerCase().startsWith('audio/');
  final kind = !adaptive
      ? YoutubeFormatKind.muxed
      : isAudio
          ? YoutubeFormatKind.audioOnly
          : YoutubeFormatKind.videoOnly;

  final cipher = e['signatureCipher'] ?? e['cipher'];
  final hasCipher = cipher is String && cipher.isNotEmpty;
  Uri? url;
  final plain = e['url'];
  if (plain is String && plain.isNotEmpty) {
    url = Uri.tryParse(plain);
  } else if (hasCipher) {
    url = Uri.tryParse(Uri.splitQueryString(cipher)['url'] ?? '');
  }

  final track = _map(e['audioTrack']);
  final type = '${e['type'] ?? ''}'.toUpperCase();
  return YoutubeFormat(
    itag: itag,
    url: url,
    mimeType: mime,
    codec: codecs.isEmpty ? '' : codecs.first,
    audioCodec: kind == YoutubeFormatKind.videoOnly
        ? null
        : kind == YoutubeFormatKind.audioOnly
            ? (codecs.isEmpty ? null : codecs.first)
            : (codecs.length > 1 ? codecs.last : null),
    kind: kind,
    height: _int(e['height']) ?? 0,
    width: _int(e['width']) ?? 0,
    bitrate: _int(e['bitrate']) ?? _int(e['averageBitrate']) ?? 0,
    contentLength: _int(e['contentLength']) ?? _int(url?.queryParameters['clen']) ?? 0,
    approxDurationMs: _int(e['approxDurationMs']) ?? 0,
    hasCipher: hasCipher,
    fps: _int(e['fps']),
    qualityLabel: '${e['qualityLabel'] ?? ''}',
    audioIsDefault: track.isEmpty ? true : (track['audioIsDefault'] == true),
    fragmented: type.contains('OTF') || url?.pathSegments.contains('sq') == true,
  );
}

/// `avc1.640028, mp4a.40.2` from `video/mp4; codecs="avc1.640028, mp4a.40.2"`.
List<String> _codecs(String mime) {
  final m = RegExp(r'codecs\s*=\s*"?([^";]+)"?', caseSensitive: false).firstMatch(mime);
  if (m == null) return const [];
  return m.group(1)!.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
}

Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : const {};

int? _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? double.tryParse(v)?.toInt();
  return null;
}

/// Tallest first; among equals the higher bitrate.
int _byHeightThenBitrate(YoutubeFormat a, YoutubeFormat b) {
  final byHeight = b.height.compareTo(a.height);
  return byHeight != 0 ? byHeight : b.bitrate.compareTo(a.bitrate);
}

/// The best video-only format: H.264 in mp4 — decoded in hardware — as
/// tall as [maxAvcHeight] allows, then by bitrate; VP9 up to [maxVp9Height]
/// only when there is no H.264 at all. Only direct formats. Null when there
/// is none.
YoutubeFormat? pickYoutubeVideo(
  Iterable<YoutubeFormat> formats, {
  required int maxAvcHeight,
  required int maxVp9Height,
}) {
  final direct = formats.where((f) => f.videoOnly && f.isDirect && f.height > 0).toList();
  final avc = direct.where((f) => f.isAvc && f.container == 'mp4' && f.height <= maxAvcHeight).toList()
    ..sort(_byHeightThenBitrate);
  if (avc.isNotEmpty) return avc.first;
  final vp9 = direct.where((f) => f.isVp9 && f.height <= maxVp9Height).toList()..sort(_byHeightThenBitrate);
  return vp9.isNotEmpty ? vp9.first : null;
}

/// The best audio-only format: AAC in mp4 (m4a) at the highest bitrate,
/// else Opus; the original soundtrack over a dubbed one. Only direct
/// formats. Null when there is none.
YoutubeFormat? pickYoutubeAudio(Iterable<YoutubeFormat> formats) {
  final direct = formats.where((f) => f.audioOnly && f.isDirect).toList();
  final original = direct.where((f) => f.audioIsDefault).toList();
  final pool = original.isNotEmpty ? original : direct;
  bool aac(YoutubeFormat f) => f.isAac && f.container == 'mp4';
  bool opus(YoutubeFormat f) => f.isOpus;
  for (final wanted in [aac, opus]) {
    final matches = pool.where(wanted).toList()..sort((a, b) => b.bitrate.compareTo(a.bitrate));
    if (matches.isNotEmpty) return matches.first;
  }
  return null;
}

/// The best muxed format: tallest, then the higher bitrate. Only direct
/// formats. Null when there is none.
YoutubeFormat? pickYoutubeMuxed(Iterable<YoutubeFormat> formats) {
  final list = formats.where((f) => f.muxed && f.isDirect && f.height > 0).toList()..sort(_byHeightThenBitrate);
  return list.isNotEmpty ? list.first : null;
}

/// The byte where [at] of media time falls in a file of [contentLength]
/// bytes that lasts [duration], taking the file as evenly paced (near
/// enough for a range probe): 0 when the length or the duration is unknown,
/// never past the last byte.
int youtubeByteOffset({required int contentLength, required Duration? duration, required Duration at}) {
  if (contentLength <= 0 || duration == null || duration <= Duration.zero) return 0;
  final offset = (contentLength * at.inMilliseconds / duration.inMilliseconds).floor();
  return offset.clamp(0, max(0, contentLength - 1));
}

/// [youtubeByteOffset] for [format].
int youtubeByteAt(YoutubeFormat format, Duration at) =>
    youtubeByteOffset(contentLength: format.contentLength, duration: format.duration, at: at);

/// [youtubeByteOffset] from the `clen` (bytes) and `dur` (seconds) YouTube
/// writes into every stream URL; 0 when either is missing.
int youtubeUrlByteAt(Uri url, Duration at) {
  final clen = int.tryParse(url.queryParameters['clen'] ?? '') ?? 0;
  final dur = double.tryParse(url.queryParameters['dur'] ?? '');
  final duration = dur == null || dur <= 0 ? null : Duration(milliseconds: (dur * 1000).round());
  return youtubeByteOffset(contentLength: clen, duration: duration, at: at);
}

/// The status of a bounded range request for [length] bytes of [url] from
/// [start], sent with [headers] the way the relay sends its slices; -1 when
/// the request itself failed. For the probes and the resolver's check.
Future<int> probeRange(
  Uri url, {
  Map<String, String> headers = const {},
  int start = 0,
  int length = 1,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(url).timeout(timeout);
    headers.forEach(req.headers.set);
    req.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-${start + max(length, 1) - 1}');
    final res = await req.close().timeout(timeout);
    await res.drain<void>().timeout(timeout);
    return res.statusCode;
  } catch (_) {
    return -1;
  } finally {
    client.close(force: true);
  }
}

/// Asks `/youtubei/v1/player` as a given client. One plain [Dio], 12 s
/// timeouts; a failed request throws (a [DioException], a [FormatException]
/// on a body that is not JSON), so the caller decides what a failure means.
class YoutubePlayerClient {
  YoutubePlayerClient({Dio? dio}) : _dio = dio ?? _plainDio();

  static const Duration timeout = Duration(seconds: 12);
  static const String endpoint = 'https://www.youtube.com/youtubei/v1/player';

  final Dio _dio;

  static Dio _plainDio() => Dio(
        BaseOptions(
          connectTimeout: timeout,
          receiveTimeout: timeout,
          sendTimeout: timeout,
          responseType: ResponseType.plain,
        ),
      );

  /// The player response for [videoId] as [client] sees it.
  Future<YoutubePlayerResult> player(String videoId, InnertubeClient client) async {
    final res = await _dio.post<String>(
      endpoint,
      queryParameters: {'prettyPrint': 'false'},
      data: jsonEncode(client.body(videoId)),
      options: Options(headers: client.requestHeaders, responseType: ResponseType.plain),
    );
    final decoded = jsonDecode(res.data ?? '');
    if (decoded is! Map) throw const FormatException('player response is not a JSON object');
    return YoutubePlayerResult.fromJson(Map<String, dynamic>.from(decoded), client: client);
  }

  void close() => _dio.close(force: true);
}
