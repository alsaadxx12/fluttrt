// Proves the Turkish series, which come from Viu over encrypted HLS rather
// than Cinemana's plain MP4, really play on this machine with the native
// video stack loaded.
//
//   flutter test integration_test/viu_playback_test.dart -d windows
//
// Everything is fetched live from the free tier on each run.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';
import 'package:youtube_downloader/features/viu/data/viu_models.dart';
import 'package:youtube_downloader/features/viu/data/viu_service.dart';

/// The same User-Agent the Viu watch screen sends.
const _ua =
    'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    MediaKit.ensureInitialized();
    VideoPlayerMediaKit.ensureInitialized(windows: true, linux: true, macOS: true);
  });

  testWidgets('a free Turkish series episode plays', (tester) async {
    final service = ViuService();
    final page = await service.fetchFreeShows(ViuCategory.turkish.id, want: 6);
    expect(page.shows, isNotEmpty, reason: 'the free Turkish category returned nothing');

    for (final show in page.shows) {
      final episodes = await service.fetchFreeEpisodes(show.seriesId);
      if (episodes.isEmpty) continue;

      final ViuPlayback playback;
      try {
        playback = await service.fetchPlayback(episodes.first);
      } on ViuException {
        continue; // this one turned out not to be free; try the next series
      }
      if (playback.qualities.isEmpty) continue;

      // Lowest first: the question is whether it plays, not how sharp.
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(playback.qualities.first.url),
        formatHint: VideoFormat.hls,
        httpHeaders: const {'User-Agent': _ua},
      );
      final label = 'viu series ${show.seriesId} episode ${episodes.first.productId}';
      Widget view() => Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: SizedBox(
                width: 426,
                height: 240,
                child: VideoPlayer(controller),
              ),
            ),
          );
      try {
        // As the app now does on desktop: the view is on screen while it opens.
        await tester.pumpWidget(view());
        var done = false;
        Object? failure;
        controller.initialize().then((_) => done = true, onError: (Object e) => failure = e);
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        while (!done && failure == null && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          await tester.pumpWidget(view());
        }
        expect(failure, isNull, reason: '$label: $failure');
        expect(done, isTrue, reason: '$label: the stream did not open');
        expect(controller.value.duration, greaterThan(Duration.zero), reason: '$label: no duration reported');

        await controller.play();
        final start = controller.value.position;
        for (var i = 0; i < 32; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          await tester.pumpWidget(view());
        }
        expect(controller.value.hasError, isFalse, reason: '$label: ${controller.value.errorDescription}');
        expect(controller.value.position, greaterThan(start), reason: '$label: opened but did not advance');
        debugPrint('[PLAYBACK OK] $label  ${controller.value.position} of ${controller.value.duration}');
      } finally {
        await controller.dispose();
      }
      return;
    }
    fail('none of the free Turkish series had a playable episode right now');
  }, timeout: const Timeout(Duration(minutes: 4)));
}
