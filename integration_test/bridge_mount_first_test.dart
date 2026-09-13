// Diagnostic for the Windows hang: does the video_player bridge open a stream
// when the player view is already on screen while it initializes?
//
//   flutter test integration_test/bridge_mount_first_test.dart -d windows
//
// The bridge only reports "initialized" once it knows the video's size, and
// media_kit only learns the size once something is rendering. The watch
// screens await initialize() before showing the view, which starves it.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';
import 'package:youtube_downloader/features/cinemana/data/services/cinemana_service.dart';

const _ua =
    'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

String _lowest(List<CinemanaStreamFile> files) {
  int res(CinemanaStreamFile f) => int.tryParse(RegExp(r'\d+').firstMatch(f.resolution)?.group(0) ?? '') ?? 99999;
  return ([...files]..sort((a, b) => res(a).compareTo(res(b)))).first.videoUrl;
}

Future<String> _aFilmStream() async {
  final service = CinemanaService();
  for (final film in (await service.fetchMovies()).take(10)) {
    final files = await service.fetchStreamFiles(film.id);
    if (files.isNotEmpty) return _lowest(files);
  }
  throw StateError('no film with a stream');
}

/// The view, remounted whenever the texture id changes. VideoPlayer reads
/// the id once; keying it forces a fresh read the moment one exists.
Widget _view(VideoPlayerController c) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 426,
          height: 240,
          child: KeyedSubtree(key: ValueKey(c.textureId), child: VideoPlayer(c)),
        ),
      ),
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    MediaKit.ensureInitialized();
    VideoPlayerMediaKit.ensureInitialized(windows: true, linux: true, macOS: true);
  });

  testWidgets('initialize completes when the view is mounted first', (tester) async {
    final url = await _aFilmStream();
    final controller = VideoPlayerController.networkUrl(Uri.parse(url), httpHeaders: const {'User-Agent': _ua});

    // The candidate fix: view on screen before initialize is awaited.
    await tester.pumpWidget(_view(controller));

    var done = false;
    Object? failure;
    controller.initialize().then((_) => done = true, onError: (Object e) => failure = e);

    final deadline = DateTime.now().add(const Duration(seconds: 40));
    while (!done && failure == null && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await tester.pumpWidget(_view(controller)); // picks up the texture id once set
    }
    debugPrint('[MOUNTFIRST] done=$done failure=$failure textureId=${controller.textureId} '
        'size=${controller.value.size} duration=${controller.value.duration}');

    expect(failure, isNull);
    expect(done, isTrue, reason: 'initialize still hung with the view mounted first');

    await controller.play();
    final start = controller.value.position;
    for (var i = 0; i < 24; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await tester.pumpWidget(_view(controller));
    }
    debugPrint('[MOUNTFIRST] position ${controller.value.position} of ${controller.value.duration}');
    expect(controller.value.position, greaterThan(start), reason: 'opened but did not advance');
    await controller.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
