import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/casting/services/mkv_remux.dart';
import 'package:youtube_downloader/features/casting/services/mp4_faststart.dart';
import 'package:youtube_downloader/features/casting/services/mp4_tracks.dart';

/// A three-second mp4 written by ffmpeg the way the catalogue writes its
/// films: `ftyp | free | mdat | moov`, H.264 with B-frames (so there is a
/// `ctts` and an edit list), AAC, index last.
final Uint8List fixture = File('test/fixtures/tiny_tail.mp4').readAsBytesSync();

const String srt = '﻿1\r\n'
    '00:00:00,500 --> 00:00:01,200\r\n'
    'مرحبا\r\n'
    '\r\n'
    '2\r\n'
    '00:00:01.400 --> 00:00:02.000\r\n'
    '{\\an8}سطر ثانٍ\r\n'
    'على سطرين\r\n'
    '\r\n'
    '3\r\n'
    '00:00:02,200 --> 00:00:02,900\r\n'
    'الأخير\r\n';

Future<Uint8List?> read(int start, int endInclusive) async =>
    Uint8List.sublistView(fixture, start, endInclusive + 1);

/// The whole served file, put together from the plan and the source.
Uint8List materialise(MkvLayout layout, Uint8List source) {
  final out = Uint8List(layout.length);
  var covered = 0;
  for (final piece in layout.pieces(0, layout.length - 1)) {
    expect(piece.outputOffset, covered, reason: 'pieces must abut');
    final literal = piece.literal;
    if (literal != null) {
      out.setRange(piece.outputOffset, piece.outputOffset + piece.length, literal);
    } else {
      out.setRange(piece.outputOffset, piece.outputOffset + piece.length, source,
          piece.sourceOffset);
    }
    covered += piece.length;
  }
  expect(covered, layout.length);
  return out;
}

/// ffmpeg's own opinion of a file, when ffmpeg is installed here.
Future<ProcessResult?> ffprobe(List<String> args) async {
  try {
    return await Process.run('ffprobe', ['-v', 'error', ...args]);
  } on ProcessException {
    return null;
  }
}

void main() {
  late Mp4File file;
  late Mp4Movie movie;

  setUpAll(() async {
    file = (await Mp4FastStart.read(fetch: read, totalSize: fixture.length))!;
    movie = Mp4Movie.parse(file.moov)!;
  });

  group('reading the index', () {
    test('finds the index at the back of the file', () {
      expect(file.indexFirst, isFalse);
      expect(String.fromCharCodes(file.moov, 4, 8), 'moov');
    });

    test('knows both tracks and what they are', () {
      final video = movie.video!;
      expect(video.codec, 'avc1');
      expect(video.width, 64);
      expect(video.height, 64);
      expect(video.sampleCount, 30, reason: 'three seconds at ten frames');
      expect(video.codecPrivate, isNotNull, reason: 'avcC is what a decoder starts from');
      expect(video.codecPrivate![0], 1, reason: 'avcC configurationVersion');
      expect(video.compositionOffsets, isNotNull, reason: 'B-frames reorder');

      final audio = movie.audio!;
      expect(audio.codec, 'mp4a');
      expect(audio.sampleRate, 44100);
      expect(audio.channels, 1);
      expect(audio.codecPrivate, isNotNull, reason: 'the AudioSpecificConfig');
      expect(audio.codecPrivate!.length, inInclusiveRange(2, 5));
    });

    test('every sample lies inside the media data', () {
      for (final track in movie.tracks) {
        for (var i = 0; i < track.sampleCount; i++) {
          expect(track.offsets[i], greaterThanOrEqualTo(file.dataStart));
          expect(track.offsets[i] + track.sizes[i],
              lessThanOrEqualTo(file.dataStart + file.dataLength));
        }
      }
    });

    test('keyframes are where the encoder put them', () {
      final video = movie.video!;
      expect(video.isSync(0), isTrue);
      expect(video.isSync(10), isTrue, reason: 'a keyframe every ten frames');
      expect(video.isSync(5), isFalse);
    });

    test('presentation times start at zero and never go backwards in display order', () {
      final video = movie.video!;
      final pts = List<int>.generate(video.sampleCount, video.pts)..sort();
      expect(pts.first, 0);
      expect(pts.toSet().length, video.sampleCount, reason: 'no two frames shown at once');
    });

    test('something that is not an index is refused', () {
      expect(Mp4Movie.parse(Uint8List.fromList(List<int>.filled(64, 7))), isNull);
    });
  });

  group('reading SubRip', () {
    test('reads the file with its quirks', () {
      final cues = SrtCue.parse(srt);
      expect(cues.length, 3);
      expect(cues[0].startMs, 500);
      expect(cues[0].endMs, 1200);
      expect(cues[0].text, 'مرحبا');
      expect(cues[1].startMs, 1400, reason: 'a dot before the milliseconds');
      expect(cues[1].text, 'سطر ثانٍ\nعلى سطرين', reason: 'styling stripped, lines kept');
      expect(cues[2].text, 'الأخير');
    });

    test('is sorted by time whatever the file order', () {
      final cues = SrtCue.parse('1\n00:00:05,000 --> 00:00:06,000\nb\n\n2\n00:00:01,000 --> 00:00:02,000\na\n');
      expect(cues.map((c) => c.text), ['a', 'b']);
    });

    test('drops what cannot be shown', () {
      final cues = SrtCue.parse('1\n00:00:02,000 --> 00:00:01,000\nbackwards\n\n2\n00:00:03,000 --> 00:00:04,000\n{\\an8}\n');
      expect(cues, isEmpty);
    });
  });

  group('the mkv', () {
    late MkvLayout layout;
    late Uint8List mkv;

    setUpAll(() {
      layout = MkvRemux.plan(movie: movie, cues: SrtCue.parse(srt))!;
      mkv = materialise(layout, fixture);
    });

    test('starts with an EBML header and a segment that spans the rest', () {
      expect(mkv.sublist(0, 4), [0x1A, 0x45, 0xDF, 0xA3]);
      final segmentAt = mkv.indexOf(0x18);
      expect(mkv.sublist(segmentAt, segmentAt + 4), [0x18, 0x53, 0x80, 0x67]);
      final size = ByteData.sublistView(mkv, segmentAt + 4, segmentAt + 12).getUint64(0) & 0x00FFFFFFFFFFFFFF;
      expect(segmentAt + 12 + size, mkv.length, reason: 'the segment size is the file, less its head');
    });

    test('carries every frame of the film, untouched', () {
      final video = movie.video!;
      final first = fixture.sublist(video.offsets[0], video.offsets[0] + video.sizes[0]);
      expect(_indexOf(mkv, first), greaterThan(0), reason: 'the first frame, byte for byte');
      final last = video.sampleCount - 1;
      final lastFrame = fixture.sublist(video.offsets[last], video.offsets[last] + video.sizes[last]);
      expect(_indexOf(mkv, lastFrame), greaterThan(0));
    });

    test('has a cluster at every keyframe once two seconds have passed', () {
      expect(layout.clusterCount, 2, reason: 'keyframes at 0, 1, 2 s; a new cluster at 2 s');
      expect(layout.subtitleCount, 3);
    });

    test('every cue points at a cluster, counted from the segment', () {
      final segmentAt = mkv.indexOf(0x18);
      final dataStart = segmentAt + 12;
      // The cues sit in front of the clusters; each CueClusterPosition is
      // eight bytes after 0xF1 0x88.
      var found = 0;
      for (var i = dataStart; i < 4096; i++) {
        if (mkv[i] == 0xF1 && mkv[i + 1] == 0x88) {
          final position = ByteData.sublistView(mkv, i + 2, i + 10).getUint64(0);
          final at = dataStart + position;
          expect(mkv.sublist(at, at + 4), [0x1F, 0x43, 0xB6, 0x75],
              reason: 'a seek lands on this byte; it has to be a cluster');
          found++;
        }
      }
      expect(found, layout.clusterCount);
    });

    test('answers a range from the middle with the same bytes', () {
      final from = mkv.length ~/ 3;
      final to = from + 999;
      final out = Uint8List(1000);
      for (final piece in layout.pieces(from, to)) {
        final at = piece.outputOffset - from;
        final literal = piece.literal;
        if (literal != null) {
          out.setRange(at, at + piece.length, literal);
        } else {
          out.setRange(at, at + piece.length, fixture, piece.sourceOffset);
        }
      }
      expect(out, mkv.sublist(from, to + 1));
    });

    test('a range past the end is empty', () {
      expect(layout.pieces(mkv.length, mkv.length + 10), isEmpty);
    });

    test('ffmpeg reads back three streams, decodes every frame and finds every line',
        () async {
      final dir = await Directory.systemTemp.createTemp('cineball-mkv');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}${Platform.pathSeparator}out.mkv';
      await File(path).writeAsBytes(mkv);

      final streams = await ffprobe(
          ['-show_entries', 'stream=codec_type,codec_name', '-of', 'csv=p=0', path]);
      if (streams == null) {
        markTestSkipped('ffprobe is not installed here');
        return;
      }
      final lines = (streams.stdout as String).trim().split(RegExp(r'\r?\n'));
      expect(lines, ['h264,video', 'aac,audio', 'subrip,subtitle'], reason: streams.stderr as String);

      final packets = await ffprobe([
        '-select_streams', 's', '-show_entries', 'packet=pts_time', '-of', 'csv=p=0', path,
      ]);
      final times = (packets!.stdout as String).trim().split(RegExp(r'\r?\n'));
      expect(times.map((t) => double.parse(t).round()), [1, 1, 2],
          reason: 'three lines at 0.5, 1.4 and 2.2 s');

      final decode = await Process.run('ffmpeg', ['-v', 'error', '-i', path, '-f', 'null', '-']);
      expect(decode.exitCode, 0);
      expect((decode.stderr as String).trim(), isEmpty,
          reason: 'every frame decodes without a complaint');

      final frames = await ffprobe([
        '-select_streams', 'v', '-count_frames', '-show_entries', 'stream=nb_read_frames', '-of', 'csv=p=0', path,
      ]);
      expect((frames!.stdout as String).trim(), '30');
    });
  });

  test('asked to fill a 16:9 screen, a square film is cropped top and bottom', () {
    final layout = MkvRemux.plan(movie: movie, cues: SrtCue.parse(srt), fill: MkvFill.crop)!;
    final mkv = materialise(layout, fixture);
    // 64x64 shown on 16:9: keep 36 rows, cut 14 above and 14 below.
    expect(_indexOf(mkv, Uint8List.fromList([0x54, 0xBB, 0x81, 14])), greaterThan(0),
        reason: 'PixelCropTop');
    expect(_indexOf(mkv, Uint8List.fromList([0x54, 0xAA, 0x81, 14])), greaterThan(0),
        reason: 'PixelCropBottom');
    final plain = MkvRemux.plan(movie: movie, cues: SrtCue.parse(srt))!;
    expect(plain.length, layout.length - 8, reason: 'two four-byte elements more');
  });

  test('a film in a container without a name is left as an mp4', () {
    final odd = Mp4Movie(timescale: 1000, duration: 1000, tracks: [
      Mp4Track(
        id: 1,
        handler: 'vide',
        codec: 'mjpg',
        timescale: 1000,
        width: 1,
        height: 1,
        channels: 0,
        sampleRate: 0,
        codecPrivate: null,
        offsets: Int64List.fromList([0]),
        sizes: Uint32List.fromList([1]),
        dts: Int64List.fromList([0]),
        compositionOffsets: null,
        sync: Uint8List.fromList([1]),
        editShift: 0,
      ),
    ]);
    expect(MkvRemux.plan(movie: odd, cues: const [SrtCue(0, 1, 'x')]), isNull);
  });
}

int _indexOf(Uint8List haystack, Uint8List needle) {
  outer:
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}
