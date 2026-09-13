// Diagnostic: opens a real Cinemana stream with media_kit directly, bypassing
// the video_player bridge, and prints libmpv's own log and errors.
//
//   flutter test integration_test/media_kit_probe_test.dart -d windows
//
// Used to tell apart "the stream cannot be opened on this machine" from "the
// bridge never reports that it opened". Look for the [PROBE] lines.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';
import 'package:youtube_downloader/features/cinemana/data/services/cinemana_service.dart';

const _ua =
    'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

String _lowest(List<CinemanaStreamFile> files) {
  int res(CinemanaStreamFile f) => int.tryParse(RegExp(r'\d+').firstMatch(f.resolution)?.group(0) ?? '') ?? 99999;
  return ([...files]..sort((a, b) => res(a).compareTo(res(b)))).first.videoUrl;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(MediaKit.ensureInitialized);

  testWidgets('media_kit opens a Cinemana stream directly', (tester) async {
    final service = CinemanaService();
    String? url;
    for (final film in (await service.fetchMovies()).take(10)) {
      final files = await service.fetchStreamFiles(film.id);
      if (files.isNotEmpty) {
        url = _lowest(files);
        break;
      }
    }
    expect(url, isNotNull, reason: 'no film with a stream to probe');

    final player = Player(configuration: const PlayerConfiguration(logLevel: MPVLogLevel.warn));
    final video = VideoController(player);
    final lines = <String>[];
    final subs = <StreamSubscription<Object?>>[
      player.stream.log.listen((l) => lines.add('mpv ${l.level} ${l.prefix}: ${l.text.trim()}')),
      player.stream.error.listen((e) => lines.add('error: $e')),
    ];

    // The view goes on screen first, the way a player page shows it, so an
    // open that only completes once a frame is drawn is not starved here.
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Video(controller: video),
    ));

    await player.open(Media(url!, httpHeaders: const {'User-Agent': _ua}));

    final deadline = DateTime.now().add(const Duration(seconds: 40));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await tester.pump();
      if (player.state.duration > Duration.zero && player.state.position > const Duration(seconds: 2)) break;
    }

    final s = player.state;
    debugPrint('[PROBE] host=${Uri.parse(url).host}');
    debugPrint('[PROBE] duration=${s.duration} position=${s.position} size=${s.width}x${s.height} '
        'playing=${s.playing} buffering=${s.buffering} completed=${s.completed}');
    if (lines.isEmpty) debugPrint('[PROBE] libmpv logged no warnings or errors');
    for (final l in lines.take(40)) {
      debugPrint('[PROBE] $l');
    }

    for (final sub in subs) {
      await sub.cancel();
    }
    await player.dispose();

    expect(s.duration, greaterThan(Duration.zero), reason: 'media_kit did not open the stream; see [PROBE] lines');
    expect(s.position, greaterThan(Duration.zero), reason: 'opened but playback never advanced');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
