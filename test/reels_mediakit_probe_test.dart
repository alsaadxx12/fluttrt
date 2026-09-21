import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:youtube_downloader/features/reels/data/reel_stream_proxy.dart';
import 'package:youtube_downloader/features/reels/data/reel_stream_resolver.dart';

/// Live probe (network + libmpv): the way the reels page drives media_kit —
/// the adaptive streams through the loopback relay, `open(video, play:
/// false)`, then `setAudioTrack(AudioTrack.uri(audio))`, then loop — must
/// really attach the separate audio stream (mpv's `audio-add`) and keep it
/// across the loop; and a long trailer, which the resolver hands over as
/// the muxed stream, must play straight from YouTube. Runs the real libmpv
/// the Windows build ships (`build/windows/x64/libmpv/libmpv-2.dll`)
/// headless, without a VideoController; skipped where that DLL is not
/// built.
///
/// No TestWidgetsFlutterBinding here: it installs a mock HttpClient that
/// fails every real request.
void main() {
  final dll = [Directory.current.path, 'build', 'windows', 'x64', 'libmpv', 'libmpv-2.dll'].join(Platform.pathSeparator);
  final available = Platform.isWindows && File(dll).existsSync();
  final skip = available ? false : 'libmpv-2.dll is not built here';

  test('a short clip: video-only + audio-only through the relay, sound attached, survives a file loop', () async {
    MediaKit.ensureInitialized(libmpv: dll);
    // «Me at the zoo»: 19 s, well inside YouTube's adaptive budget.
    final streams = await ReelStreamResolver.instance.resolve('jNQXAC9IVRw');
    expect(streams, isNotNull);
    expect(streams!.muxed, isFalse, reason: 'no video-only + audio-only pair to test');
    // ignore: avoid_print
    print('streams: $streams');

    for (final mode in [PlaylistMode.single, PlaylistMode.loop]) {
      final r = await _run(streams, mode);
      // ignore: avoid_print
      print('$mode: audio tracks=${r.audioTracks}  audioParams=${r.audioParams}  bitrate=${r.audioBitrate}  '
          'pos=${r.position.inMilliseconds}ms/${r.duration.inMilliseconds}ms  '
          'after loop: pos=${r.afterLoopPosition.inMilliseconds}ms audio=${r.audioAfterLoop}  errors=${r.errors}');
      if (mode == PlaylistMode.single) {
        expect(r.audioTracks, isNotEmpty, reason: 'audio-add attached no track');
        expect(r.audioParams?.sampleRate ?? 0, greaterThan(0), reason: 'no audio is decoding');
        expect(r.position, greaterThan(Duration.zero));
        expect(r.audioAfterLoop, isTrue, reason: 'the external audio was lost at the loop');
        expect(r.errors, isEmpty);
      }
    }
  }, timeout: const Timeout(Duration(minutes: 3)), skip: skip);

  test('a long trailer: the muxed stream, straight from YouTube, plays with its own sound', () async {
    MediaKit.ensureInitialized(libmpv: dll);
    final streams = await ReelStreamResolver.instance.resolve('Way9Dexny3w'); // Dune: Part Two trailer, 144 s
    expect(streams, isNotNull);
    expect(streams!.muxed, isTrue, reason: 'a 144 s clip must not take the pair YouTube cuts short');
    // ignore: avoid_print
    print('streams: $streams');
    final r = await _run(streams, PlaylistMode.single, seekToEnd: false);
    // ignore: avoid_print
    print('muxed: audio tracks=${r.audioTracks}  audioParams=${r.audioParams}  pos=${r.position.inMilliseconds}ms/'
        '${r.duration.inMilliseconds}ms  errors=${r.errors}');
    expect(r.position, greaterThan(Duration.zero));
    expect(r.audioParams?.sampleRate ?? 0, greaterThan(0));
    expect(r.errors, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)), skip: skip);
}

class _Result {
  List<String> audioTracks = const [];
  AudioParams? audioParams;
  double? audioBitrate;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  Duration afterLoopPosition = Duration.zero;
  bool audioAfterLoop = false;
  final List<String> errors = [];
}

/// The reels page's sequence, then a few seconds of playback, then (when
/// [seekToEnd]) a seek to just before the end so the loop happens, and
/// another look at the audio.
Future<_Result> _run(ReelStreams streams, PlaylistMode mode, {bool seekToEnd = true}) async {
  final r = _Result();
  final player = Player(
    configuration: const PlayerConfiguration(vo: 'null', bufferSize: 16 * 1024 * 1024, logLevel: MPVLogLevel.info),
  );
  final errors = player.stream.error.listen(r.errors.add);
  final logs = <String>[];
  final logSub = player.stream.log.listen((l) {
    if (l.prefix == 'cplayer' || l.prefix == 'ffmpeg' || l.prefix == 'stream' || l.level != 'info') {
      logs.add('[${l.prefix}] ${l.level}: ${l.text}');
    }
  });
  try {
    final proxy = ReelStreamProxy.instance;
    ReelStreamProxy.log = (line) => logs.add('[proxy] $line');
    final video = streams.muxed ? streams.video : await proxy.register(streams.video);
    final audio = streams.audio == null ? null : await proxy.register(streams.audio!);
    // Headless: media_kit keeps the video track off (`vid=no`) until a
    // VideoController attaches, which the page does; here it is switched on
    // by hand, so a video-only file has a selected stream and plays.
    await (player.platform as NativePlayer).setProperty('vid', 'auto');
    await player.open(Media(video.toString()), play: false);
    if (audio != null) await player.setAudioTrack(AudioTrack.uri(audio.toString()));
    await player.setPlaylistMode(mode);
    await player.setVolume(0);
    await player.play();
    await Future<void>.delayed(const Duration(seconds: 6));
    for (final l in logs.take(30)) {
      // ignore: avoid_print
      print('    ${l.length > 220 ? l.substring(0, 220) : l}');
    }
    List<String> tracks() =>
        [for (final t in player.state.tracks.audio) if (t.id != 'auto' && t.id != 'no') '${t.id}:${t.title}'];
    r.audioTracks = tracks();
    r.audioParams = player.state.audioParams;
    r.audioBitrate = player.state.audioBitrate;
    r.position = player.state.position;
    r.duration = player.state.duration;

    if (seekToEnd) {
      // To the last second and a half, then past the end.
      await player.seek(r.duration - const Duration(milliseconds: 1500));
      await Future<void>.delayed(const Duration(seconds: 5));
      r.afterLoopPosition = player.state.position;
      r.audioAfterLoop = tracks().isNotEmpty && (player.state.audioParams.sampleRate ?? 0) > 0;
    }
  } finally {
    await errors.cancel();
    await logSub.cancel();
    await player.dispose();
    await ReelStreamProxy.instance.close();
    ReelStreamProxy.log = null;
  }
  return r;
}
