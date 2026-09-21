import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/reels/data/reel_stream_proxy.dart';
import 'package:youtube_downloader/features/reels/data/reel_stream_resolver.dart';
import 'package:youtube_downloader/features/reels/data/reels_service.dart';
import 'package:youtube_downloader/features/reels/data/youtube_player_client.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Live probe (network): for real trailers from today's feed, the resolver
/// must follow its policy — a video-only stream taller than the muxed
/// ceiling, paired with an audio-only stream, whole and taller than 360p
/// when an innertube client the resolver verified serves it (see
/// `youtube_player_client_probe_test.dart` for the measurement), else for a
/// clip inside YouTube's adaptive budget ([kReelAdaptiveMaxDuration]); the
/// tallest muxed stream on offer for a longer one — and every URL it hands
/// out must answer a bounded range request the way the relay makes it.
/// Prints what was chosen next to what the manifest offered, so a wrong
/// pick can be placed.
///
/// No TestWidgetsFlutterBinding here: it installs a mock HttpClient that
/// fails every real request.
void main() {
  test('resolver: the pair for short clips (or from a verified client), muxed for long ones, for real trailers',
      () async {
    final service = ReelsService();
    final page = await service.fetchFeed();
    service.dispose();
    expect(page.items.length, greaterThanOrEqualTo(2), reason: 'the feed came back short');
    expect(page.items.every((r) => r.isTrailer), isTrue);

    final yt = YoutubeExplode();
    final resolver = ReelStreamResolver.instance;
    var tall = 0;
    var resolved = 0;
    try {
      for (final reel in page.items) {
        if (resolved >= 2) break;
        final id = reel.id;
        final sw = Stopwatch()..start();
        final streams = await resolver.resolve(id);
        final ms = sw.elapsedMilliseconds;
        if (streams == null) {
          // YouTube refuses some trailers to every client (embedding off,
          // region locks); the page skips those, and so does this probe.
          // ignore: avoid_print
          print('$id  ${reel.title}\n   did not resolve ($ms ms): unplayable on YouTube, skipped');
          continue;
        }
        resolved++;
        expect(identical(await resolver.resolve(id), streams), isTrue, reason: 'second ask is not the cached one');
        expect(resolver.cached(id), same(streams));

        // The manifest as youtube_explode sees it, for the codec detail.
        final manifest = await yt.videos.streamsClient.getManifest(id, requireWatchPage: false);
        final video = pickReelVideo(manifest.videoOnly);
        final audio = pickReelAudio(manifest.audioOnly);
        final length = video == null ? null : reelStreamDuration(video.url);
        int tallest(Iterable<VideoStreamInfo> s) => s.fold(0, (m, e) => math.max(m, e.videoResolution.height));
        final avcHeights = manifest.videoOnly
            .where((s) => s.videoCodec.toLowerCase().startsWith('avc1') && s.fragments.isEmpty)
            .map((s) => '${s.videoResolution.height}p/${s.container.name}')
            .toSet()
            .toList()
          ..sort();
        // ignore: avoid_print
        print('$id  ${reel.title}  (${length?.inSeconds ?? '?'} s)\n'
            '   picked: ${streams.height}p  muxed=${streams.muxed}  audio=${streams.audio != null}  '
            'source=${streams.source}  headers=${streams.headers.keys.toList()}  ($ms ms)\n'
            '   best pair offered: ${video?.videoResolution.height ?? '-'}p codec=${video?.videoCodec ?? '-'} '
            'container=${video?.container.name ?? '-'} + audio ${audio?.audioCodec ?? '-'}/${audio?.container.name ?? '-'} '
            '${audio?.bitrate.kiloBitsPerSecond.toStringAsFixed(0) ?? '-'}kbps\n'
            '   manifest: video-only tallest=${tallest(manifest.videoOnly)}p  muxed tallest=${tallest(manifest.muxed)}p  '
            'avc1 direct=$avcHeights  audio-only=${manifest.audioOnly.length}');

        // A range request the way the relay makes it must be honoured.
        for (final (label, url) in [('video', streams.video), if (streams.audio != null) ('audio', streams.audio!)]) {
          final status = await _rangeStatus(url, headers: streams.headers);
          // ignore: avoid_print
          print('   $label url: HTTP $status  host=${url.host}');
          expect(status, anyOf(200, 206), reason: '$label stream of $id is not fetchable');
        }

        final pairOffered = video != null && audio != null;
        final withinBudget = length != null && length <= kReelAdaptiveMaxDuration;
        final fromClient = streams.source != kReelSourceExplode;
        if (fromClient && !streams.muxed) {
          // A client the resolver verified this session: the pair, whole,
          // above the muxed ceiling — readable at 90 s for a long clip.
          expect(streams.audio, isNotNull);
          expect(streams.height, greaterThan(360), reason: 'a verified client should beat the muxed ceiling');
          expect(streams.height, lessThanOrEqualTo(kReelMaxHeightAvc));
          if (length != null && length > kReelAdaptiveMaxDuration) {
            for (final (label, url) in [('video', streams.video), ('audio', streams.audio!)]) {
              final at = youtubeUrlByteAt(url, const Duration(seconds: 90));
              final status = await _rangeStatus(url, headers: streams.headers, start: at);
              // ignore: avoid_print
              print('   $label at 90 s (byte $at): HTTP $status');
              expect(status, 206, reason: 'the $label stream of a long clip stops before 90 s');
            }
          }
          tall++;
        } else if (pairOffered && (withinBudget || manifest.muxed.isEmpty)) {
          expect(streams.muxed, isFalse, reason: 'a clip inside the budget should play the pair');
          expect(streams.audio, isNotNull);
          expect(streams.height, video.videoResolution.height);
          expect(video.videoCodec.toLowerCase(), startsWith('avc1'), reason: 'H.264 expected when YouTube offers it');
          expect(streams.height, lessThanOrEqualTo(kReelMaxHeightAvc));
          if (!fromClient) {
            // Every manifest fetch is signed afresh, so the URLs differ; the
            // itag (YouTube's stream id) must not.
            expect(streams.video.queryParameters['itag'], video.url.queryParameters['itag']);
          }
          if (streams.height > 720) tall++;
        } else if (pairOffered) {
          expect(streams.muxed, isTrue, reason: 'a clip past the budget must take the muxed stream');
          expect(streams.audio, isNull);
          expect(video.videoResolution.height, greaterThan(streams.height),
              reason: 'the pair YouTube offered (but would cut short) is the taller picture');
          expect(streams.height, greaterThanOrEqualTo(tallest(manifest.muxed)),
              reason: 'the tallest muxed stream on offer, from any client, should be taken');
          // A relay URL stands for a muxed stream that needs headers.
          final upstream = ReelStreamProxy.instance.upstreamOf(streams.video) ?? streams.video;
          final at = youtubeUrlByteAt(upstream, const Duration(seconds: 90));
          final status = await _rangeStatus(streams.video, headers: streams.headers, start: at);
          // ignore: avoid_print
          print('   muxed at 90 s (byte $at): HTTP $status');
          expect(status, 206, reason: 'the muxed stream is not readable at 90 s');
          tall++;
        }
      }
    } finally {
      yt.close();
    }
    expect(resolved, 2, reason: 'fewer than two trailers of the page resolved');
    expect(tall, greaterThanOrEqualTo(1), reason: 'YouTube offered nothing above the muxed ceiling');
  }, timeout: const Timeout(Duration(minutes: 4)));
}

/// The status of a 1 KB range request to [url] from [start], with
/// [headers] (the client's own, when the streams need any) and otherwise
/// dart:io's own user agent — no cookies, no YouTube headers, like the
/// relay on the phone.
Future<int> _rangeStatus(Uri url, {Map<String, String> headers = const {}, int start = 0}) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(url).timeout(const Duration(seconds: 15));
    headers.forEach(req.headers.set);
    req.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-${start + 1023}');
    final res = await req.close().timeout(const Duration(seconds: 15));
    await res.drain<void>();
    return res.statusCode;
  } catch (e) {
    // ignore: avoid_print
    print('   range request failed: $e');
    return -1;
  } finally {
    client.close(force: true);
  }
}
