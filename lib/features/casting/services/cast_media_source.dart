import 'package:youtube_downloader/features/cinemana/data/cinemana_subtitles.dart';
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';
import 'package:youtube_downloader/features/cinemana/data/services/cinemana_service.dart';

import '../models/cast_models.dart';

/// Turns a catalogue title into something another screen can play.
///
/// The stream is resolved here, at the moment casting starts, and travels
/// only in the command that carries it — it is never stored, so nothing
/// outside this session can replay it.
class CastMediaSource {
  const CastMediaSource(this._service);

  final CinemanaService _service;

  /// The best stream the catalogue offers for [item], as a [CastMedia].
  ///
  /// Returns null when the title has no direct stream — the same case the
  /// player shows «لا تتوفر روابط تشغيل مباشرة».
  Future<CastMedia?> forItem(
    CinemanaItem item, {
    CinemanaEpisode? episode,
    Duration position = Duration.zero,
    int maxHeight = maxCastHeight,
  }) async {
    final videoId = episode?.id ?? item.id;
    final streams = await _service.fetchStreamFiles(videoId);
    if (streams.isEmpty) return null;

    // Fetched beside the stream, not after it: the other screen has no
    // catalogue of its own and cannot go looking for a subtitle later.
    // Arabic first, English if that is all there is, and no subtitle at all
    // is not a reason to refuse to cast.
    CinemanaSubtitleSources subtitles = const CinemanaSubtitleSources();
    try {
      subtitles = await _service.fetchSubtitleSources(videoId);
    } catch (_) {}
    final subtitleUrl = subtitles.ar ?? subtitles.en;
    final subtitleLabel = subtitles.ar != null ? 'العربية' : 'English';

    final best = pickBest(streams, maxHeight: maxHeight);
    final episodeName = episode == null
        ? ''
        : (episode.arTitle.trim().isNotEmpty
            ? episode.arTitle.trim()
            : (episode.enTitle.trim().isNotEmpty
                ? episode.enTitle.trim()
                : 'الحلقة ${episode.episodeNumber}'));
    final title = episode == null ? item.displayTitle : '${item.displayTitle} — $episodeName';

    return CastMedia(
      mediaId: videoId,
      title: title,
      description: item.arContent.isNotEmpty ? item.arContent : item.enContent,
      posterUrl: item.bestPosterUrl,
      streamUrl: best.videoUrl,
      contentType: best.videoUrl.toLowerCase().contains('.m3u8')
          ? 'application/x-mpegURL'
          : 'video/mp4',
      subtitleUrl: subtitleUrl,
      subtitleLabel: subtitleUrl == null ? null : subtitleLabel,
      position: position,
    );
  }

  /// The relay that fetches a stream on the receiver's behalf.
  ///
  /// Measured, not assumed: the sports servers answer Netlify's edge (200),
  /// and refuse a browser that cannot forge a Referer. So the address the
  /// other screen is given points here, and the headers are added on the
  /// way out. See netlify/edge-functions/relay.ts.
  static const String _relay = 'https://cineball.netlify.app/relay';

  /// Wraps [url] so a screen other than the phone can actually fetch it.
  static String relayed(String url) =>
      '$_relay?u=${Uri.encodeComponent(url)}';

  /// True when [url] belongs to a source that refuses a plain request.
  ///
  /// The catalogue's own CDN serves anyone and is left alone — sending it
  /// through the relay would put every byte of every film through our own
  /// bandwidth for no gain at all.
  static bool needsRelay(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    return host.contains('boomstreaming.com') || host.contains('korax90.co');
  }

  /// A live channel, which has a url already and no duration to speak of.
  static CastMedia forLive({
    required String id,
    required String title,
    required String streamUrl,
    String posterUrl = '',
  }) =>
      CastMedia(
        mediaId: id,
        title: title,
        streamUrl: needsRelay(streamUrl) ? relayed(streamUrl) : streamUrl,
        posterUrl: posterUrl,
        contentType: 'application/x-mpegURL',
        isLive: true,
      );

  /// The most a screen at the other end should be asked to take.
  ///
  /// Not the sharpest on offer, which is what this used to pick. The
  /// catalogue's 4K files are not a little larger than its 1080p ones —
  /// for one film here, 16.14 GB against 1.32, twelve times the size and
  /// the bitrate to match. Nothing about that survives the trip: the phone
  /// has to pull all of it down, push all of it back out over wifi, and the
  /// television's own player has to decode it, which a great many of them
  /// simply cannot.
  ///
  /// 1080p is the highest every receiver here handles and the highest a
  /// phone can realistically carry, so that is the ceiling.
  static const int maxCastHeight = 1080;

  /// The sharpest stream that is not more than the far screen can take.
  static CinemanaStreamFile pickBest(
    List<CinemanaStreamFile> streams, {
    int maxHeight = maxCastHeight,
  }) {
    int rank(CinemanaStreamFile s) {
      final text = '${s.resolution} ${s.name}';
      final digits = RegExp(r'(\d{3,4})').firstMatch(text)?.group(1);
      return int.tryParse(digits ?? '') ?? 0;
    }

    // The best that fits under the ceiling.
    CinemanaStreamFile? best;
    for (final s in streams) {
      if (rank(s) > maxHeight) continue;
      if (best == null || rank(s) > rank(best)) best = s;
    }
    if (best != null) return best;

    // Everything is above the ceiling — a catalogue that offers nothing but
    // 4K. Then the smallest of them is the kindest thing to send.
    var smallest = streams.first;
    for (final s in streams) {
      if (rank(s) < rank(smallest)) smallest = s;
    }
    return smallest;
  }
}
