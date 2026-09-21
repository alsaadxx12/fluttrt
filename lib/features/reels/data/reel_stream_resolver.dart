import 'dart:async';
import 'dart:math' show min;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:youtube_downloader/features/reels/data/reel_stream_proxy.dart';
import 'package:youtube_downloader/features/reels/data/youtube_player_client.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// The streams a reel plays.
///
/// YouTube's muxed streams (one file carrying both picture and sound) stop
/// at 720p — 360p, in practice, from the clients that answer today. Above
/// that the picture and the sound come as two separate streams, so the
/// reels player takes the best video-only stream and pairs it with the best
/// audio-only one; it falls back to a muxed stream when either is missing,
/// and for a clip longer than [kReelAdaptiveMaxDuration], which YouTube
/// would cut short (see there) — unless the streams come from a client the
/// resolver has seen serve a long clip whole.
class ReelStreams {
  const ReelStreams({
    required this.video,
    required this.audio,
    required this.height,
    required this.muxed,
    this.headers = const {},
    this.source = kReelSourceExplode,
  });

  /// The picture: a video-only stream to play with [audio], or — when
  /// [muxed] — a stream that carries its own sound.
  final Uri video;

  /// The sound to play with [video]; null when [muxed].
  final Uri? audio;

  /// The picture's height in pixels: 1080 for a 1080p landscape stream,
  /// 1920 for a vertical 1080p short (1080×1920).
  final int height;

  /// True when [video] is a muxed stream: the fallback, 720p at most.
  final bool muxed;

  /// The headers every byte request for [video] and [audio] must carry (a
  /// client's own User-Agent); empty for streams that need none. The
  /// resolver registers such streams with the relay itself, headers and
  /// all, so the page keeps handing the relay the plain URL; a muxed stream
  /// that needs headers is handed out as its relay URL, since the page plays
  /// a muxed stream as is.
  final Map<String, String> headers;

  /// Where the streams came from: [kReelSourceExplode], or the name of the
  /// innertube client that served them (see [InnertubeClient.name]).
  final String source;

  @override
  String toString() => 'ReelStreams(${height}p, ${muxed ? 'muxed' : 'video + audio'}, $source)';
}

/// The [ReelStreams.source] of streams resolved through youtube_explode's
/// android client, under the duration gate.
const String kReelSourceExplode = 'youtube_explode';

/// Why resolving a reel's streams ended as it did.
enum ReelResolveReason {
  /// The streams are in hand.
  ok,

  /// YouTube answered about the clip and there is nothing to play: no such
  /// video, no format a player can open, not embeddable, a sign-in wanted.
  /// The clip itself is gone, so a feed may write it off.
  unavailable,

  /// YouTube is refusing the requests for being too many (see
  /// [ReelStreamResolver.throttleBackoff]): nothing was learnt about the
  /// clip, so it must be asked about again rather than written off.
  throttled,

  /// The request itself failed — no network, a dropped connection, a
  /// timeout: likewise nothing was learnt about the clip.
  network,
}

/// What [ReelStreamResolver.resolveDetailed] answers: the streams when there
/// are any, and why when there are none.
class ReelResolveResult {
  const ReelResolveResult(this.reason, {this.streams});

  final ReelResolveReason reason;

  /// What to play; null unless [reason] is [ReelResolveReason.ok].
  final ReelStreams? streams;

  /// True when the clip is gone for good: the caller may drop it.
  bool get unavailable => reason == ReelResolveReason.unavailable;

  /// True when nothing was learnt about the clip — so it must not be
  /// dropped over it; the caller waits and asks again.
  bool get transient => reason == ReelResolveReason.throttled || reason == ReelResolveReason.network;

  @override
  String toString() => 'ReelResolveResult(${reason.name}${streams == null ? '' : ', $streams'})';
}

/// What was learnt while one resolve ran, so a null answer can be read:
/// YouTube saying «no» is not the network being down.
class _Evidence {
  /// A client answered that the clip cannot be played, or offered no format
  /// a player can open as one file.
  bool refused = false;

  /// A request itself failed: a timeout, a dropped connection.
  bool transport = false;

  /// What youtube_explode made of the clip; null while it has not been
  /// asked.
  ReelResolveReason? explode;
}

/// The longest clip played from the video-only + audio-only pair of a
/// client that has not been seen to serve a long clip whole.
///
/// Measured in September 2026 on three trailers of 101–144 s, through the
/// android client (youtube_explode's) and again through the iOS app's
/// client: without a proof-of-origin token YouTube serves an adaptive
/// stream only up to about a minute of media — a request for bytes of the
/// video from 61 s on (of the audio from 68 s on) is refused with 403,
/// however long one waits — while it serves the muxed stream whole. So a
/// clip longer than this takes the muxed stream: the lower picture, but all
/// of it, rather than 1080p that stops a minute in. A 60 s clip's last
/// bytes lie inside what both streams serve, so the gate sits at 60 s — the
/// longest a YouTube Short of the classic kind runs, which is what the feed
/// is made of.
const Duration kReelAdaptiveMaxDuration = Duration(seconds: 60);

/// The least a reel's picture may measure across its shorter side: 1080
/// pixels, «1080p» as YouTube labels it — 1080×1920 for a vertical clip.
const int kReelMinQuality = 1080;

/// The quality of a [width]×[height] picture as YouTube labels it: the
/// shorter side, so 1920×1080 and 1080×1920 are both 1080p. A side of 0
/// (unknown) yields the other side.
int reelQualityOf(int width, int height) {
  if (width <= 0) return height;
  if (height <= 0) return width;
  return min(width, height);
}

/// What a probe of a clip tells: the size of its tallest video-only stream,
/// whether it is upright, how long the clip runs, and — off a client's
/// answer — whose channel it is. Pure; built by [probeReelFormats] from a
/// client's answer or by [probeReelManifest] from youtube_explode's
/// manifest.
class ReelProbe {
  const ReelProbe({required this.width, required this.height, required this.duration, this.author = ''});

  /// The tallest video-only stream's picture, in pixels.
  final int width;
  final int height;

  /// The clip's length as YouTube writes it into the stream URLs; null when
  /// no stream carried it.
  final Duration? duration;

  /// The channel's name as the client's answer gives it; empty off a
  /// manifest, which carries none. The feed reads it for a Short off the
  /// search's Shorts shelf, where YouTube prints no channel.
  final String author;

  /// The tallest video-only stream's height: 1920 for a vertical 1080p
  /// short, 1080 for a landscape 1080p trailer.
  int get maxHeight => height;

  /// The picture's quality as YouTube labels it (see [reelQualityOf]).
  int get quality => reelQualityOf(width, height);

  /// True when the picture is upright: taller than it is wide, so it fills a
  /// phone screen without cropping.
  bool get portrait => height > width;

  /// True when the clip fits YouTube's adaptive budget
  /// ([kReelAdaptiveMaxDuration]), so its 1080p pair plays whole.
  bool get adaptiveOk => duration != null && duration! <= kReelAdaptiveMaxDuration;

  /// The feed's rule: upright, at least [kReelMinQuality] across, and short
  /// enough to play whole at that quality.
  bool get qualifies => portrait && quality >= kReelMinQuality && adaptiveOk;

  @override
  String toString() =>
      'ReelProbe(${width}x$height, ${portrait ? 'portrait' : 'landscape'}, ${duration?.inMilliseconds ?? '?'} ms)';
}

/// [manifest] probed: the tallest video-only stream (any codec, fragmented
/// or not — this measures the clip, not what will be played) and the
/// length written into any stream URL. Null when the manifest carries no
/// video-only stream at all.
ReelProbe? probeReelManifest(StreamManifest manifest) {
  VideoOnlyStreamInfo? tallest;
  for (final s in manifest.videoOnly) {
    if (tallest == null || s.videoResolution.height > tallest.videoResolution.height) tallest = s;
  }
  if (tallest == null) return null;
  Duration? duration;
  for (final s in manifest.streams) {
    duration = reelStreamDuration(s.url);
    if (duration != null) break;
  }
  return ReelProbe(width: tallest.videoResolution.width, height: tallest.videoResolution.height, duration: duration);
}

/// [formats] (a client's answer) probed the same way: the tallest video-only
/// format, cipher or not, and the clip's length — the format's own
/// (`approxDurationMs`, to the millisecond) before [fallback] (the answer's
/// `lengthSeconds`, whole seconds) — with [author], the channel the answer
/// names. Null when there is no video-only format. Pure.
ReelProbe? probeReelFormats(Iterable<YoutubeFormat> formats, {Duration? fallback, String author = ''}) {
  YoutubeFormat? tallest;
  for (final f in formats) {
    if (!f.videoOnly || f.height <= 0) continue;
    if (tallest == null || f.height > tallest.height) tallest = f;
  }
  if (tallest == null) return null;
  return ReelProbe(
    width: tallest.width,
    height: tallest.height,
    duration: tallest.duration ?? fallback,
    author: author,
  );
}

/// The clip's length as YouTube writes it into every stream URL (`dur`, in
/// seconds); null when it is not there.
Duration? reelStreamDuration(Uri url) {
  final s = double.tryParse(url.queryParameters['dur'] ?? '');
  return s == null || s <= 0 ? null : Duration(milliseconds: (s * 1000).round());
}

/// The tallest H.264 picture asked for, by its quality (the shorter side,
/// see [reelQualityOf]): 1440p decodes in hardware on every phone made this
/// decade and already outstrips the screen.
const int kReelMaxHeightAvc = 1440;

/// VP9 is only taken when there is no H.264 at all, and no finer than
/// 1080p: software decoding above that stutters on a phone.
const int kReelMaxHeightVp9 = 1080;

/// The quality of a video-only stream, as YouTube labels it.
int _qualityOf(VideoStreamInfo s) => reelQualityOf(s.videoResolution.width, s.videoResolution.height);

bool _isAvc(VideoStreamInfo s) => s.videoCodec.toLowerCase().startsWith('avc1');

bool _isVp9(VideoStreamInfo s) {
  final c = s.videoCodec.toLowerCase();
  return c.startsWith('vp09') || c.startsWith('vp9');
}

/// A stream the player can open as one URL: not a DASH stream made of
/// fragments, not an HLS playlist.
bool _isDirect(StreamInfo s) => s.fragments.isEmpty && s.container != StreamContainer.m3u8;

/// Tallest first; among equals the higher bitrate.
int _byHeightThenBitrate(VideoStreamInfo a, VideoStreamInfo b) {
  final byHeight = b.videoResolution.height.compareTo(a.videoResolution.height);
  return byHeight != 0 ? byHeight : b.bitrate.compareTo(a.bitrate);
}

/// The best video-only stream for a reel: H.264 (`avc1`) in an mp4
/// container — decoded in hardware — as fine as [kReelMaxHeightAvc] allows,
/// then by bitrate; VP9 up to [kReelMaxHeightVp9] only when there is no
/// H.264 at all. The caps are on the quality (the shorter side), so a
/// vertical 1080×1920 stream passes the 1440 cap as a 1080p stream, as it
/// should. Null when neither exists.
VideoOnlyStreamInfo? pickReelVideo(Iterable<VideoOnlyStreamInfo> streams) {
  final direct = streams.where(_isDirect).toList();
  final avc = direct
      .where((s) => _isAvc(s) && s.container == StreamContainer.mp4 && _qualityOf(s) <= kReelMaxHeightAvc)
      .toList()
    ..sort(_byHeightThenBitrate);
  if (avc.isNotEmpty) return avc.first;
  final vp9 = direct.where((s) => _isVp9(s) && _qualityOf(s) <= kReelMaxHeightVp9).toList()
    ..sort(_byHeightThenBitrate);
  return vp9.isNotEmpty ? vp9.first : null;
}

/// The best audio-only stream to go with the picture: AAC (`mp4a`) in an
/// mp4 (m4a) container at the highest bitrate, else Opus (webm). The film's
/// own soundtrack is preferred to a dubbed track when YouTube marks them.
/// Null when there is none.
AudioOnlyStreamInfo? pickReelAudio(Iterable<AudioOnlyStreamInfo> streams) {
  final direct = streams.where(_isDirect).toList();
  final original = direct.where((s) => s.audioTrack == null || s.audioTrack!.audioIsDefault).toList();
  final pool = original.isNotEmpty ? original : direct;
  bool aac(AudioOnlyStreamInfo s) =>
      s.audioCodec.toLowerCase().startsWith('mp4a') && s.container == StreamContainer.mp4;
  bool opus(AudioOnlyStreamInfo s) => s.audioCodec.toLowerCase().startsWith('opus');
  for (final wanted in [aac, opus]) {
    final matches = pool.where(wanted).toList()..sort((a, b) => b.bitrate.compareTo(a.bitrate));
    if (matches.isNotEmpty) return matches.first;
  }
  return null;
}

/// The best muxed stream: tallest, then the higher bitrate. Null when there
/// is none.
MuxedStreamInfo? pickReelMuxed(Iterable<MuxedStreamInfo> streams) {
  final list = streams.where(_isDirect).toList()..sort(_byHeightThenBitrate);
  return list.isNotEmpty ? list.first : null;
}

/// What a reel plays from [manifest]: the best video-only stream paired
/// with the best audio-only one; the best muxed stream when either is
/// missing, or when the clip is longer than [kReelAdaptiveMaxDuration] and
/// there is a muxed stream to take instead; null when there is nothing
/// playable at all. Pure, so it can be tested on a hand-made manifest.
ReelStreams? pickReelStreams(StreamManifest manifest) {
  final video = pickReelVideo(manifest.videoOnly);
  final audio = video == null ? null : pickReelAudio(manifest.audioOnly);
  final muxed = pickReelMuxed(manifest.muxed);
  if (video != null && audio != null) {
    final length = reelStreamDuration(video.url) ?? reelStreamDuration(audio.url);
    final cutShort = length != null && length > kReelAdaptiveMaxDuration;
    if (!cutShort || muxed == null) {
      return ReelStreams(
        video: video.url,
        audio: audio.url,
        height: video.videoResolution.height,
        muxed: false,
      );
    }
  }
  if (muxed == null) return null;
  return ReelStreams(
    video: muxed.url,
    audio: null,
    height: muxed.videoResolution.height,
    muxed: true,
  );
}

/// A height cap that stops nothing: the quality caps are applied here, on
/// the shorter side, before the formats reach the client's picker.
const int _uncapped = 1 << 20;

/// The best video-only + audio-only pair among [formats] (a client's direct
/// formats), by the same policy as [pickReelStreams]; null when either is
/// missing. No duration gate: the caller knows whether the client serves a
/// long clip whole. Pure.
ReelStreams? pickReelPairFromFormats(Iterable<YoutubeFormat> formats, {required InnertubeClient client}) {
  // The client's picker caps by height; a vertical 1080×1920 stream is a
  // 1080p one, so the caps are applied here by quality and lifted there.
  final fit = formats.where((f) {
    if (!f.videoOnly) return true;
    final quality = reelQualityOf(f.width, f.height);
    return f.isAvc ? quality <= kReelMaxHeightAvc : quality <= kReelMaxHeightVp9;
  });
  final video = pickYoutubeVideo(fit, maxAvcHeight: _uncapped, maxVp9Height: _uncapped);
  final audio = video == null ? null : pickYoutubeAudio(formats);
  if (video == null || audio == null) return null;
  return ReelStreams(
    video: video.url!,
    audio: audio.url!,
    height: video.height,
    muxed: false,
    headers: client.streamHeaders,
    source: client.name,
  );
}

/// The best muxed format among [formats] as streams; null when there is
/// none. Pure.
ReelStreams? pickReelMuxedFromFormats(Iterable<YoutubeFormat> formats, {required InnertubeClient client}) {
  final muxed = pickYoutubeMuxed(formats);
  if (muxed == null) return null;
  return ReelStreams(
    video: muxed.url!,
    audio: null,
    height: muxed.height,
    muxed: true,
    headers: client.streamHeaders,
    source: client.name,
  );
}

/// A bounded range request's status (see `probeRange`).
typedef ReelRangeProbe = Future<int> Function(Uri url, {Map<String, String> headers, int start});

/// A stream manifest through youtube_explode.
typedef ReelManifestFetch = Future<StreamManifest> Function(String videoId);

/// Resolves a reel's streams and caches them.
///
/// The innertube clients in [InnertubeClient.candidates] are asked first,
/// in order: a client's video-only + audio-only pair is played whole,
/// without the duration gate, once the client has been seen — this
/// session, by a one-byte read at [verifyAt] of a clip long enough to be
/// read there, both streams — to serve past the minute YouTube otherwise
/// stops at; a client refused there is set aside for the session, and so
/// is one that fails [deadAfter] times in a row. A clip past the gate but
/// too short to be read at [verifyAt] proves nothing (the refusal starts a
/// little past a minute, so a read near the end of a 60 s clip comes back
/// fine) and is left to the gated path. A client trusted this session is
/// asked alone first; the unmeasured ones are asked together, so the
/// retired ones cost one round trip, not one each in turn. What no client
/// serves whole comes through youtube_explode under the gate
/// ([pickReelStreams]); when that is a muxed stream, the tallest muxed
/// stream any client offered is taken instead if it is taller. Streams
/// whose byte requests need headers are registered with the relay here, so
/// the page needs to know nothing about them.
///
/// Resolving costs a round trip or two to YouTube, so the result is kept
/// for [ttl] (YouTube's URLs live a few hours), concurrent asks for the same
/// reel share one request, and [prewarm] resolves the next reels ahead of
/// the swipe. A failure comes back as null, never as an exception.
///
/// [probe] reads a clip's size and length without resolving it — the feed
/// asks it of every candidate short — off the answer of the first client
/// that serves it (which is kept for [ttl], so resolving a reel the feed
/// already probed asks that client nothing more), else off youtube_explode's
/// manifest (kept likewise).
class ReelStreamResolver {
  ReelStreamResolver._()
      : _player = YoutubePlayerClient(),
        _probe = probeRange,
        _manifest = null,
        _clients = InnertubeClient.candidates;

  /// A resolver on stand-ins, for tests: [player] answers the innertube
  /// requests, [probe] the range reads, [manifest] youtube_explode's part,
  /// and [clients] are the candidates in order.
  @visibleForTesting
  ReelStreamResolver.custom({
    YoutubePlayerClient? player,
    ReelRangeProbe? probe,
    ReelManifestFetch? manifest,
    List<InnertubeClient>? clients,
  })  : _player = player ?? YoutubePlayerClient(),
        _probe = probe ?? probeRange,
        _manifest = manifest,
        _clients = clients ?? InnertubeClient.candidates;

  static final ReelStreamResolver instance = ReelStreamResolver._();

  static const Duration ttl = Duration(hours: 3);

  /// The quick path (no watch page) gets this long; the retry with the
  /// watch page, which is slower, a little more.
  static const Duration timeout = Duration(seconds: 12);
  static const Duration retryTimeout = Duration(seconds: 20);

  /// Where a long clip is read to tell a client that serves it whole from
  /// one that stops at the minute: well past the measured refusal (the
  /// video from 61 s, the audio from 68 s). Only a clip that lasts at least
  /// [verifyMargin] longer than this is measured; a shorter one past the
  /// gate is neither trusted nor measured.
  static const Duration verifyAt = Duration(seconds: 90);

  /// How much of the clip must follow [verifyAt] for the read to land on
  /// media, not on the file's tail.
  static const Duration verifyMargin = Duration(seconds: 3);

  /// How many failures in a row set a client aside for the session.
  static const int deadAfter = 2;

  /// How long youtube_explode is left alone once YouTube has refused it
  /// for too many requests (HTTP 429, [RequestLimitExceededException]): a
  /// probe, or a resolve through it, answers null at once in that time
  /// instead of waiting on another refusal, and the feed knows to say so
  /// rather than to write the clips it could not look at off.
  static const Duration throttleBackoff = Duration(seconds: 90);

  final YoutubePlayerClient _player;
  final ReelRangeProbe _probe;

  /// A stand-in for youtube_explode's manifest fetch; null means the real
  /// one, [_explodeManifest].
  final ReelManifestFetch? _manifest;
  final List<InnertubeClient> _clients;

  final Map<String, _Entry> _cache = {};
  final Map<String, Future<ReelResolveResult>> _inflight = {};

  /// youtube_explode's manifests, kept for [ttl], and the fetches under way.
  final Map<String, _ManifestEntry> _manifests = {};
  final Map<String, Future<StreamManifest>> _manifestInflight = {};

  /// The clients' playable answers, per video and client, kept for [ttl]
  /// (their URLs live as long as the streams'), so a reel probed through a
  /// client is resolved on the same answer.
  final Map<String, _AnswerEntry> _answers = {};

  /// What [probe] found, kept for [ttl] (a failed probe is not kept), and
  /// the probes under way.
  final Map<String, _ProbeEntry> _probes = {};
  final Map<String, Future<ReelProbe?>> _probeInflight = {};

  /// Per client, this session: true once seen to serve a long clip whole,
  /// false once refused past the minute; absent until measured.
  final Map<InnertubeClient, bool> _verdicts = {};

  /// Per client, failures in a row (a request that threw, an answer that was
  /// not playable or carried no direct format).
  final Map<InnertubeClient, int> _failures = {};

  /// Until when youtube_explode is left alone (see [throttleBackoff]).
  DateTime? _throttledUntil;

  /// When YouTube's refusal of youtube_explode for too many requests lifts
  /// (see [throttleBackoff]); null while it is not refusing. A page that is
  /// waiting one out reads this to know when to try again.
  DateTime? get throttledUntil {
    final until = _throttledUntil;
    return until != null && DateTime.now().isBefore(until) ? until : null;
  }

  /// True while YouTube's refusal of youtube_explode for too many requests
  /// still holds (see [throttleBackoff]).
  bool get throttled => throttledUntil != null;

  /// This session's verdict on [client]: true when it served a long clip
  /// whole, false when it was refused, null when not measured yet.
  bool? verdict(InnertubeClient client) => _verdicts[client];

  /// True when [client] has been set aside for the session.
  bool isDead(InnertubeClient client) => (_failures[client] ?? 0) >= deadAfter;

  /// Fresh cached streams for [videoId], or null.
  ReelStreams? cached(String videoId) {
    final e = _cache[videoId];
    if (e == null) return null;
    if (DateTime.now().difference(e.at) > ttl) {
      _cache.remove(videoId);
      return null;
    }
    return e.streams;
  }

  /// Forgets every URL held for [videoId] — the resolved streams, the
  /// clients' answers and youtube_explode's manifest — so the next ask goes
  /// back to YouTube for fresh ones. What was measured about the clip (its
  /// size and length, see [probe]) is kept: that does not go stale.
  ///
  /// A page whose stream broke while it was playing calls it: the URLs it
  /// was handed are what is suspect — YouTube stops honouring them on its
  /// own schedule, which need not be [ttl] — so asking again must not hand
  /// back the very same ones.
  void forget(String videoId) {
    _cache.remove(videoId);
    _manifests.remove(videoId);
    _answers.removeWhere((key, _) => key.startsWith('$videoId|'));
  }

  /// The streams for [videoId], resolving and caching them if needed; null
  /// when they could not be resolved. Concurrent calls for the same id share
  /// one resolution. See [resolveDetailed] for why a null answer came.
  Future<ReelStreams?> resolve(String videoId) async => (await resolveDetailed(videoId)).streams;

  /// [resolve] with the reason behind a null answer, so a caller can tell a
  /// clip that is gone ([ReelResolveReason.unavailable]) — worth dropping
  /// from a feed for good — from YouTube refusing for now or the network
  /// being down, over which nothing may be dropped.
  Future<ReelResolveResult> resolveDetailed(String videoId) {
    final hit = cached(videoId);
    if (hit != null) return Future.value(ReelResolveResult(ReelResolveReason.ok, streams: hit));
    return _inflight.putIfAbsent(videoId, () => _resolve(videoId))
      ..whenComplete(() => _inflight.remove(videoId));
  }

  Future<ReelResolveResult> _resolve(String videoId) async {
    final note = _Evidence();
    try {
      final fromClients = await _fromClients(videoId, note);
      var picked = fromClients.whole;
      if (picked == null) {
        picked = await _fromExplode(videoId, note);
        final muxed = fromClients.muxed;
        if (muxed != null && (picked == null || (picked.muxed && muxed.height > picked.height))) picked = muxed;
      }
      if (picked == null) return ReelResolveResult(_reasonOf(note));
      picked = await _viaRelay(picked);
      _cache[videoId] = _Entry(picked, DateTime.now());
      return ReelResolveResult(ReelResolveReason.ok, streams: picked);
    } catch (_) {
      // Something outside the two lookups — the relay, say: nothing a clip
      // may be written off for.
      return ReelResolveResult(throttled ? ReelResolveReason.throttled : ReelResolveReason.network);
    }
  }

  /// Why nothing could be resolved. YouTube refusing the requests comes
  /// first: nothing was learnt about the clip then. After it stands
  /// youtube_explode's verdict — it is the one that read the video's own
  /// page — and then the clients', which counts only when every one of them
  /// answered: a request that never arrived says nothing, so the clip keeps
  /// its place and is asked about again.
  ReelResolveReason _reasonOf(_Evidence note) {
    if (throttled) return ReelResolveReason.throttled;
    if (note.explode == ReelResolveReason.unavailable) return ReelResolveReason.unavailable;
    if (note.refused && !note.transport) return ReelResolveReason.unavailable;
    return ReelResolveReason.network;
  }

  /// The candidates in order: the first pair a client is trusted with
  /// (verified this session, or a clip inside the gate), and the tallest
  /// muxed stream any answering client offered. A trusted client is asked
  /// alone first; the unmeasured ones are asked together. What the clients
  /// said is noted in [note], for [_reasonOf].
  Future<({ReelStreams? whole, ReelStreams? muxed})> _fromClients(String videoId, _Evidence note) async {
    final live = _clients.where((c) => _verdicts[c] != false && !isDead(c)).toList();
    ReelStreams? bestMuxed;
    void keepMuxed(List<YoutubeFormat> direct, InnertubeClient client) {
      final muxed = pickReelMuxedFromFormats(direct, client: client);
      if (muxed != null && (bestMuxed == null || muxed.height > bestMuxed!.height)) bestMuxed = muxed;
    }

    for (final client in live.where((c) => _verdicts[c] == true)) {
      final result = await _ask(videoId, client, note);
      if (result == null) continue;
      keepMuxed(result.direct, client);
      final pair = pickReelPairFromFormats(result.direct, client: client);
      if (pair != null) return (whole: pair, muxed: bestMuxed);
    }

    final unmeasured = live.where((c) => _verdicts[c] == null).toList();
    final answers = await Future.wait(unmeasured.map((c) => _ask(videoId, c, note)));
    for (var i = 0; i < unmeasured.length; i++) {
      final client = unmeasured[i];
      final result = answers[i];
      if (result == null) continue;
      final direct = result.direct;
      keepMuxed(direct, client);

      final pair = pickReelPairFromFormats(direct, client: client);
      if (pair == null) continue;
      final length = result.duration;
      if (length == null) continue;
      if (length <= kReelAdaptiveMaxDuration) return (whole: pair, muxed: bestMuxed);

      // A long clip and a client not measured yet: one byte at [verifyAt],
      // video and audio, tells whether the client serves it whole — only
      // on a clip long enough to be read there; a shorter one is left to
      // the gated path, since a read short of the refusal proves nothing.
      if (length < verifyAt + verifyMargin) continue;
      final video = direct.firstWhere((f) => f.url == pair.video);
      final audio = direct.firstWhere((f) => f.url == pair.audio);
      final served = await _servesWhole(client, video, audio, verifyAt);
      if (served == null) continue;
      _verdicts[client] = served;
      if (served) return (whole: pair, muxed: bestMuxed);
    }
    return (whole: null, muxed: bestMuxed);
  }

  /// [client]'s answer for [videoId] when it is playable with at least one
  /// direct format — the one given within [ttl] when there is one; null —
  /// and one more failure against the client — when the request threw or
  /// timed out, or the answer was not playable or carried no direct format.
  /// Which of the two it was is noted in [note], when one is given.
  Future<YoutubePlayerResult?> _ask(String videoId, InnertubeClient client, [_Evidence? note]) async {
    final key = '$videoId|${client.name}';
    final kept = _answers[key];
    if (kept != null) {
      if (DateTime.now().difference(kept.at) <= ttl) return kept.result;
      _answers.remove(key);
    }
    try {
      final result = await _player.player(videoId, client).timeout(timeout);
      if (result.playable && result.direct.isNotEmpty) {
        _failures[client] = 0;
        _answers[key] = _AnswerEntry(result, DateTime.now());
        return result;
      }
      // YouTube answered about the clip: it cannot be played, or nothing it
      // offers can be opened as one file.
      note?.refused = true;
    } catch (_) {
      note?.transport = true;
    }
    _failures[client] = (_failures[client] ?? 0) + 1;
    return null;
  }

  /// True when one byte at [at] of both [video] and [audio] comes back
  /// (206), false when YouTube refused either, null when a request itself
  /// failed (no verdict from a dropped connection).
  Future<bool?> _servesWhole(InnertubeClient client, YoutubeFormat video, YoutubeFormat audio, Duration at) async {
    for (final f in [video, audio]) {
      final status = await _probe(f.url!, headers: client.streamHeaders, start: youtubeByteAt(f, at));
      if (status < 0) return null;
      if (status != 206) return false;
    }
    return true;
  }

  /// youtube_explode's answer under the gate; null when it failed, or at
  /// once while YouTube is refusing it (see [throttleBackoff]) and the
  /// manifest is not already kept. What it amounted to is written into
  /// [note]: a manifest with nothing playable in it is YouTube answering
  /// that there is nothing to play, while a refusal or a dropped request
  /// says nothing about the clip.
  Future<ReelStreams?> _fromExplode(String videoId, _Evidence note) async {
    if (throttled && !_manifests.containsKey(videoId)) {
      note.explode = ReelResolveReason.throttled;
      return null;
    }
    try {
      final streams = pickReelStreams(await _manifestFor(videoId));
      note.explode = streams == null ? ReelResolveReason.unavailable : ReelResolveReason.ok;
      return streams;
    } on RequestLimitExceededException {
      note.explode = ReelResolveReason.throttled;
      return null;
    } on VideoUnplayableException {
      // Covers the unavailable and the purchase-only videos, which extend it.
      note.explode = ReelResolveReason.unavailable;
      return null;
    } catch (_) {
      note.explode = ReelResolveReason.network;
      return null;
    }
  }

  /// youtube_explode's manifest for [videoId]: the one fetched within [ttl]
  /// when there is one, else fetched now (concurrent asks share the fetch).
  /// Throws when the fetch failed.
  Future<StreamManifest> _manifestFor(String videoId) {
    final hit = _manifests[videoId];
    if (hit != null) {
      if (DateTime.now().difference(hit.at) <= ttl) return Future.value(hit.manifest);
      _manifests.remove(videoId);
    }
    return _manifestInflight.putIfAbsent(videoId, () {
      final fetch = _fetchManifest(videoId);
      // The fetch may fail: the caller handles that on the fetch itself,
      // so the cleanup's own copy of the error is not left unobserved.
      fetch.whenComplete(() => _manifestInflight.remove(videoId)).ignore();
      return fetch;
    });
  }

  Future<StreamManifest> _fetchManifest(String videoId) async {
    try {
      final manifest = await (_manifest ?? _explodeManifest)(videoId);
      _manifests[videoId] = _ManifestEntry(manifest, DateTime.now());
      return manifest;
    } on RequestLimitExceededException {
      _noteThrottle();
      rethrow;
    }
  }

  /// Marks YouTube's refusal for too many requests: youtube_explode is left
  /// alone for [throttleBackoff] from now.
  void _noteThrottle() => _throttledUntil = DateTime.now().add(throttleBackoff);

  /// The fresh cached probe of [videoId], or null.
  ReelProbe? cachedProbe(String videoId) {
    final e = _probes[videoId];
    if (e == null) return null;
    if (DateTime.now().difference(e.at) > ttl) {
      _probes.remove(videoId);
      return null;
    }
    return e.probe;
  }

  /// The size and length of [videoId]: off the answer of the first client
  /// (in [InnertubeClient.candidates]' order, the ones not set aside) that
  /// serves it (see [probeReelFormats]), else off youtube_explode's manifest
  /// (see [probeReelManifest]). Null when nothing answered within [timeout]
  /// or nothing carried a video-only stream — or, once the clients have
  /// passed, at once while YouTube is refusing youtube_explode (see
  /// [throttleBackoff]), when the caller should read [throttled] rather
  /// than take the null for a measurement. Kept for [ttl]; concurrent asks
  /// share one probe. Never throws.
  Future<ReelProbe?> probe(String videoId) {
    final hit = cachedProbe(videoId);
    if (hit != null) return Future.value(hit);
    return _probeInflight.putIfAbsent(videoId, () => _probeVideo(videoId))
      ..whenComplete(() => _probeInflight.remove(videoId));
  }

  Future<ReelProbe?> _probeVideo(String videoId) async {
    try {
      for (final client in _clients.where((c) => _verdicts[c] != false && !isDead(c))) {
        final result = await _ask(videoId, client);
        if (result == null) continue;
        final probe = probeReelFormats(result.formats, fallback: result.duration, author: result.author);
        if (probe != null) return _keepProbe(videoId, probe);
      }
      if (throttled && !_manifests.containsKey(videoId)) return null;
      final probe = probeReelManifest(await _manifestFor(videoId).timeout(timeout));
      return probe == null ? null : _keepProbe(videoId, probe);
    } catch (_) {
      return null;
    }
  }

  ReelProbe _keepProbe(String videoId, ReelProbe probe) {
    _probes[videoId] = _ProbeEntry(probe, DateTime.now());
    return probe;
  }

  /// True when [videoId] is a clip the feed may show (see
  /// [ReelProbe.qualifies]): upright, at least [kReelMinQuality] across and
  /// no longer than [kReelAdaptiveMaxDuration]. False when it could not be
  /// probed.
  Future<bool> qualifies(String videoId) async => (await probe(videoId))?.qualifies ?? false;

  /// [streams] registered with the relay when their byte requests need
  /// headers: a pair keeps its plain URLs (the page registers them again,
  /// which keeps the headers), a muxed stream — which the page plays as is
  /// — becomes its relay URL.
  Future<ReelStreams> _viaRelay(ReelStreams streams) async {
    if (streams.headers.isEmpty) return streams;
    final proxy = ReelStreamProxy.instance;
    final local = await proxy.register(streams.video, headers: streams.headers);
    final audio = streams.audio;
    if (audio != null) await proxy.register(audio, headers: streams.headers);
    if (!streams.muxed) return streams;
    return ReelStreams(
      video: local,
      audio: null,
      height: streams.height,
      muxed: true,
      headers: streams.headers,
      source: streams.source,
    );
  }

  /// The manifest without the watch page first (fast); once more with it
  /// when that timed out or failed — not when YouTube refused it for too
  /// many requests, which the watch page would meet as well.
  ///
  /// When YouTube is refusing, the refusal takes youtube_explode (which
  /// retries inside) some twenty seconds to report: longer than [timeout],
  /// so the attempt the caller stopped waiting on is left to run on and
  /// still marks the throttle when it ends that way; the client is closed
  /// once every attempt has ended.
  Future<StreamManifest> _explodeManifest(String videoId) async {
    final yt = YoutubeExplode();
    final client = yt.videos.streamsClient;
    var pending = 0;
    Future<StreamManifest> attempt({required bool watchPage}) {
      pending++;
      final f = watchPage ? client.getManifest(videoId) : client.getManifest(videoId, requireWatchPage: false);
      f.then((_) {}, onError: (Object e) {
        if (e is RequestLimitExceededException) _noteThrottle();
      }).ignore();
      f.whenComplete(() {
        if (--pending == 0) yt.close();
      }).ignore();
      return f;
    }

    try {
      return await attempt(watchPage: false).timeout(timeout);
    } on RequestLimitExceededException {
      rethrow;
    } catch (_) {
      if (throttled) rethrow;
      return await attempt(watchPage: true).timeout(retryTimeout);
    }
  }

  /// Resolves several reels ahead of time, [concurrency] at a time, ignoring
  /// failures. Ones already cached or already resolving are skipped.
  Future<void> prewarm(Iterable<String> videoIds, {int concurrency = 2}) async {
    final todo = videoIds
        .where((id) => id.isNotEmpty && cached(id) == null && !_inflight.containsKey(id))
        .toSet()
        .toList();
    for (var i = 0; i < todo.length; i += concurrency) {
      await Future.wait(todo.skip(i).take(concurrency).map(resolve));
    }
  }
}

class _Entry {
  const _Entry(this.streams, this.at);

  final ReelStreams streams;
  final DateTime at;
}

class _ManifestEntry {
  const _ManifestEntry(this.manifest, this.at);

  final StreamManifest manifest;
  final DateTime at;
}

class _ProbeEntry {
  const _ProbeEntry(this.probe, this.at);

  final ReelProbe probe;
  final DateTime at;
}

class _AnswerEntry {
  const _AnswerEntry(this.result, this.at);

  final YoutubePlayerResult result;
  final DateTime at;
}
