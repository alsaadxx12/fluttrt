import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/reels/data/reel_stream_proxy.dart';
import 'package:youtube_downloader/features/reels/data/reel_stream_resolver.dart';
import 'package:youtube_downloader/features/reels/data/reels_service.dart';
import 'package:youtube_downloader/features/reels/data/youtube_player_client.dart';

/// Live probe (network): for two real trailers of at least 100 s from
/// today's feed, every innertube client in [InnertubeClient.candidates] is
/// asked for the player response and measured — the tallest direct H.264
/// video-only height, the best audio, the tallest muxed stream (and whether
/// it beats 360p) — and its chosen video and audio streams are read one
/// byte at 0 s and at 90 s of media time, with the client's own headers.
/// The 90 s read is the whole point: YouTube refuses the android client
/// (and, measured in September 2026, the iOS client too) any adaptive byte
/// past about a minute without a proof-of-origin token.
///
/// Each answering client's streams are also read through the relay,
/// registered with the client's headers as the resolver registers them:
/// the relay must read them at 0 s and answer at 90 s as YouTube did.
///
/// Then the resolver is asked for the same trailer, and whatever it hands
/// out must be readable at 90 s: a pair only from a client that passed, the
/// muxed stream otherwise. The matrix is printed in full so the outcome can
/// be read off, client by client.
///
/// No TestWidgetsFlutterBinding here: it installs a mock HttpClient that
/// fails every real request.
void main() {
  test('innertube clients: tallest height and the 0 s / 90 s byte probes, per trailer; the resolver’s pick holds at 90 s',
      () async {
    final service = ReelsService();
    final page = await service.fetchFeed();
    service.dispose();
    expect(page.items.length, greaterThanOrEqualTo(2), reason: 'the feed came back short');

    const at90 = Duration(seconds: 90);
    const minLength = Duration(seconds: 100);
    final client = YoutubePlayerClient();
    final resolver = ReelStreamResolver.instance;
    final relay = ReelStreamProxy.instance;
    // ignore: avoid_print
    ReelStreamProxy.log = (line) => print('         relay: $line');
    // Per client: the trailers on which its pair was readable at 90 s.
    final passes = <InnertubeClient, int>{for (final c in InnertubeClient.candidates) c: 0};
    var measured = 0;
    try {
      for (final reel in page.items) {
        if (measured >= 2) break;
        final id = reel.id;

        final results = <InnertubeClient, YoutubePlayerResult?>{};
        final errors = <InnertubeClient, String>{};
        for (final c in InnertubeClient.candidates) {
          try {
            results[c] = await client.player(id, c).timeout(const Duration(seconds: 15));
          } catch (e) {
            results[c] = null;
            errors[c] = '$e'.split('\n').first;
          }
        }
        final answered = results.values.whereType<YoutubePlayerResult>().toList();
        final duration = answered.map((r) => r.duration).whereType<Duration>().firstOrNull;
        if (duration == null || !answered.any((r) => r.playable && r.direct.isNotEmpty)) {
          // YouTube refuses some trailers to every client (age or region
          // locks, embedding off); the page skips those, and so does this
          // probe — the reasons are printed so a lock can be told from a
          // breakage.
          // ignore: avoid_print
          print('$id  ${reel.title}  (${duration?.inSeconds ?? '?'} s)\n   no client answered with playable streams: skipped\n'
              '${InnertubeClient.candidates.map((c) => '      [${c.name}] ${results[c] == null ? 'request failed: ${errors[c]}' : '${results[c]!.status} ${results[c]!.reason}'}').join('\n')}');
          continue;
        }
        if (duration < minLength) {
          // ignore: avoid_print
          print('$id  ${reel.title}  (${duration.inSeconds} s): shorter than ${minLength.inSeconds} s, skipped');
          continue;
        }
        measured++;
        // ignore: avoid_print
        print('$id  ${reel.title}  (${duration.inSeconds} s)');

        for (final c in InnertubeClient.candidates) {
          final r = results[c];
          if (r == null) {
            // ignore: avoid_print
            print('   [${c.name}] request failed: ${errors[c]}');
            continue;
          }
          final direct = r.direct;
          final ciphered = r.formats.where((f) => f.hasCipher).length;
          int tallest(bool Function(YoutubeFormat) which) => direct.where(which).fold(0, (m, f) => math.max(m, f.height));
          final tallestAvc = tallest((f) => f.videoOnly && f.isAvc);
          final tallestMuxed = tallest((f) => f.muxed);
          final video = pickYoutubeVideo(direct, maxAvcHeight: kReelMaxHeightAvc, maxVp9Height: kReelMaxHeightVp9);
          final audio = pickYoutubeAudio(direct);
          final muxed = pickYoutubeMuxed(direct);
          // ignore: avoid_print
          print('   [${c.name}] status=${r.status}${r.reason.isEmpty ? '' : ' (${r.reason})'}  '
              'formats=${r.formats.length} direct=${direct.length} cipher=$ciphered  '
              'tallest avc1 video-only=${tallestAvc}p  muxed=${tallestMuxed}p${tallestMuxed > 360 ? ' (beats 360p)' : ''}  '
              'best audio=${audio == null ? '-' : '${audio.audioCodec} ${audio.bitrate ~/ 1000}kbps'}');
          if (!r.playable || direct.isEmpty) continue;

          final statuses = <String, int>{};
          for (final (label, f) in [('video', video), ('audio', audio)]) {
            if (f == null) continue;
            for (final at in [Duration.zero, at90]) {
              final s = await probeRange(f.url!, headers: c.streamHeaders, start: youtubeByteAt(f, at));
              statuses['$label@${at.inSeconds}'] = s;
            }
            // ignore: avoid_print
            print('      $label ${f.height > 0 ? '${f.height}p ' : ''}itag ${f.itag}: '
                '0 s -> HTTP ${statuses['$label@0']}   90 s -> HTTP ${statuses['$label@90']}');
          }
          if (muxed != null) {
            // The page plays a muxed stream as is (no headers), so it is
            // read the plain way too.
            final plain0 = await probeRange(muxed.url!, start: 0);
            final plain90 = await probeRange(muxed.url!, start: youtubeByteAt(muxed, at90));
            final own90 = await probeRange(muxed.url!, headers: c.streamHeaders, start: youtubeByteAt(muxed, at90));
            // ignore: avoid_print
            print('      muxed ${muxed.height}p itag ${muxed.itag}: plain UA 0 s -> HTTP $plain0, 90 s -> HTTP $plain90; '
                'client UA 90 s -> HTTP $own90');
          }
          final passed = statuses['video@90'] == 206 && statuses['audio@90'] == 206;
          if (passed) passes[c] = passes[c]! + 1;
          // ignore: avoid_print
          print('      90 s probe: ${passed ? 'PASS (video and audio)' : 'refused'}');

          // The same streams through the relay, registered with the
          // client's headers the way the resolver registers them: 1 KB at
          // 0 s must come through, and at 90 s the relay must answer as
          // YouTube did the direct read — 206, or 502 once YouTube refused
          // the slice (the relay gives up rather than crawl).
          for (final (label, f) in [('video', video), ('audio', audio)]) {
            if (f == null) continue;
            final local = await relay.register(f.url!, headers: c.streamHeaders);
            final r0 = await probeRange(local, length: 1024);
            final r90 = await probeRange(local, start: youtubeByteAt(f, at90), length: 1024);
            // ignore: avoid_print
            print('      $label via relay (headers ${relay.headersOf(local).keys.toList()}): 0 s -> HTTP $r0   90 s -> HTTP $r90');
            expect(r0, 206, reason: 'the relay could not read the $label stream of ${c.name} at 0 s');
            expect(r90, statuses['$label@90'] == 206 ? 206 : 502,
                reason: 'the relay’s answer at 90 s for the $label stream of ${c.name} differs from YouTube’s');
          }
        }

        // The resolver on the same trailer: whatever it hands out must be
        // readable at 90 s.
        final sw = Stopwatch()..start();
        final streams = await resolver.resolve(id);
        // ignore: avoid_print
        print('   resolver: ${streams ?? 'nothing'} (${sw.elapsedMilliseconds} ms)  '
            'verdicts: ${InnertubeClient.candidates.map((c) => '${c.name}=${resolver.verdict(c) ?? (resolver.isDead(c) ? 'dead' : '?')}').join(' ')}');
        if (streams == null) continue;
        if (!streams.muxed) {
          final source = InnertubeClient.candidates.where((c) => c.name == streams.source).firstOrNull;
          expect(source, isNotNull, reason: 'a pair for a long clip can only come from a verified client');
          expect(passes[source]!, greaterThan(0), reason: 'the chosen client did not pass the 90 s probe here');
          expect(streams.height, greaterThan(360));
          for (final (label, url) in [('video', streams.video), ('audio', streams.audio!)]) {
            final s = await probeRange(url, headers: streams.headers, start: youtubeUrlByteAt(url, at90));
            // ignore: avoid_print
            print('      resolver $label at 90 s -> HTTP $s');
            expect(s, 206, reason: 'the resolver handed out a $label stream that stops before 90 s');
          }
        } else {
          expect(passes.values.every((n) => n == 0), isTrue,
              reason: 'a client passed the 90 s probe on this trailer but the resolver still took the muxed stream');
          // A relay URL stands for a muxed stream that needs headers; the
          // byte is placed from the upstream's clen/dur either way.
          final upstream = ReelStreamProxy.instance.upstreamOf(streams.video) ?? streams.video;
          final s = await probeRange(streams.video, start: youtubeUrlByteAt(upstream, at90));
          // ignore: avoid_print
          print('      resolver muxed at 90 s -> HTTP $s');
          expect(s, 206, reason: 'the muxed stream is not readable at 90 s');
        }
      }
    } finally {
      client.close();
      ReelStreamProxy.log = null;
      await relay.close();
    }
    expect(measured, 2, reason: 'fewer than two trailers of at least ${minLength.inSeconds} s could be measured');

    final winners = passes.entries.where((e) => e.value > 0).map((e) => '${e.key.name} (${e.value}/$measured)').toList();
    // ignore: avoid_print
    print(winners.isEmpty
        ? 'NO client passes the 90 s probe today: every adaptive stream stops at about a minute without a proof-of-origin token; '
            'the duration gate stays.'
        : 'clients passing the 90 s probe: ${winners.join(', ')}');
  }, timeout: const Timeout(Duration(minutes: 6)));
}
