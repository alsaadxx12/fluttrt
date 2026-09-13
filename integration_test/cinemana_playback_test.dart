// Proves films and series really play on this machine, with the native video
// stack loaded - something the unit tests cannot do.
//
//   flutter test integration_test/cinemana_playback_test.dart -d windows
//
// Streams are fetched fresh from the live catalogue on every run, because the
// links are signed and expire; nothing here is hard-coded.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';
import 'package:youtube_downloader/features/cinemana/data/services/cinemana_service.dart';

/// The same User-Agent the watch screen sends, so the test takes the real path.
const _ua =
    'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

/// The smallest rendition: the question is whether it plays, not how sharp.
String _lowest(List<CinemanaStreamFile> files) {
  int res(CinemanaStreamFile f) => int.tryParse(RegExp(r'\d+').firstMatch(f.resolution)?.group(0) ?? '') ?? 99999;
  return ([...files]..sort((a, b) => res(a).compareTo(res(b)))).first.videoUrl;
}

/// Opens [url] the way the app now does on a desktop: the view is on screen
/// and redrawn while the stream opens. Then checks it opens,
/// knows its length, and that time actually moves.
Future<void> _expectPlays(WidgetTester tester, String url, String label) async {
  final controller = VideoPlayerController.networkUrl(Uri.parse(url), httpHeaders: const {'User-Agent': _ua});
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
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // What main() does on a desktop: without the bridge, video_player has no
    // Windows implementation and every player throws on open.
    MediaKit.ensureInitialized();
    VideoPlayerMediaKit.ensureInitialized(windows: true, linux: true, macOS: true);
  });

  testWidgets('a film plays', (tester) async {
    final service = CinemanaService();
    final films = await service.fetchMovies();
    expect(films, isNotEmpty, reason: 'the catalogue returned no films');

    for (final film in films.take(10)) {
      final files = await service.fetchStreamFiles(film.id);
      if (files.isEmpty) continue;
      await _expectPlays(tester, _lowest(files), 'film "${film.enTitle}"');
      return;
    }
    fail('none of the first ten films had a stream to try');
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('a series episode plays', (tester) async {
    final service = CinemanaService();
    final shows = await service.fetchSeries();
    expect(shows, isNotEmpty, reason: 'the catalogue returned no series');

    for (final show in shows.take(8)) {
      final episodes = await service.fetchEpisodes(show.id);
      if (episodes.isEmpty) continue;
      final files = await service.fetchStreamFiles(episodes.first.id);
      if (files.isEmpty) continue;
      await _expectPlays(tester, _lowest(files), 'series "${show.enTitle}" episode ${episodes.first.episodeNumber}');
      return;
    }
    fail('none of the first eight series had a playable episode');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
