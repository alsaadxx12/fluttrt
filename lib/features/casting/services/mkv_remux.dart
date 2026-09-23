import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'mp4_tracks.dart';

/// Puts an mp4's video and audio, and a subtitle, inside a Matroska file —
/// without touching a single frame.
///
/// A television that plays the film from an mp4 and shows no subtitle,
/// whatever it is told about a sidecar file and whatever text track is put
/// inside the mp4, shows it the moment the same bytes arrive as `.mkv`
/// with an `S_TEXT/UTF8` track. Measured on a TCL set on 2026-09-22: the
/// tx3g mp4 played mute, the mkv played with the lines under the picture.
///
/// So this describes the mkv the set will be served as a list of pieces:
/// a few megabytes written here (the header, the index, every block's
/// framing) and, between them, byte ranges of the original file. Nothing is
/// downloaded ahead; the server pulls each range as the set reaches it.
class MkvRemux {
  /// The set is told every timestamp in milliseconds.
  static const int _timecodeScale = 1000000;

  /// A cluster is closed at the next keyframe once it is this long.
  static const int _clusterMs = 2000;

  /// Describes the mkv for [movie] with [cues] as its subtitle track.
  ///
  /// Returns null when the film's codecs are not ones Matroska has a name
  /// for, in which case it should be served as the mp4 it is.
  static MkvLayout? plan({
    required Mp4Movie movie,
    required List<SrtCue> cues,
    String language = 'ara',
    MkvFill fill = MkvFill.keep,
  }) {
    final video = movie.video;
    if (video == null) return null;
    final videoCodec = _videoCodecId(video);
    if (videoCodec == null) {
      debugPrint('[cast] mkv: no name for video codec ${video.codec}');
      return null;
    }
    final audio = movie.audio;
    final audioCodec = audio == null ? null : _audioCodecId(audio);
    if (audio != null && audioCodec == null) {
      debugPrint('[cast] mkv: no name for audio codec ${audio.codec}');
      return null;
    }

    final builder = _Builder();
    return builder.build(
      movie: movie,
      video: video,
      videoCodec: videoCodec,
      audio: audio,
      audioCodec: audioCodec,
      cues: cues,
      language: language,
      fill: fill,
    );
  }

  static String? _videoCodecId(Mp4Track track) => switch (track.codec) {
        'avc1' || 'avc3' => 'V_MPEG4/ISO/AVC',
        'hvc1' || 'hev1' => 'V_MPEGH/ISO/HEVC',
        _ => null,
      };

  static String? _audioCodecId(Mp4Track track) => switch (track.codec) {
        'mp4a' => track.codecPrivate == null ? null : 'A_AAC',
        'ac-3' => 'A_AC3',
        'ec-3' => 'A_EAC3',
        _ => null,
      };
}

/// What to do about a film wider than the screen it is shown on.
///
/// A cinema film is about 2.4:1; a television is 16:9. Shown as it is,
/// a fifth of the screen is black bars. The container can say otherwise,
/// and a player that listens fills the screen one of two ways.
enum MkvFill {
  /// The film as it is, bars and all.
  keep,

  /// The sides are cut away so what is left is 16:9: nothing is
  /// distorted, but the edges of the picture are lost. What a television's
  /// own "zoom" mode does.
  crop,

  /// The picture is stretched to 16:9: nothing is lost, everything is a
  /// little taller than it should be.
  stretch,
}

/// One line of a subtitle.
@immutable
class SrtCue {
  const SrtCue(this.startMs, this.endMs, this.text);

  final int startMs;
  final int endMs;
  final String text;

  /// Reads SubRip text. Tolerant of the things the catalogue's files do:
  /// a byte-order mark, Windows line ends, a dot for the milliseconds, and
  /// `{\an8}`-style styling that a television would print verbatim.
  static List<SrtCue> parse(String srt) {
    final text = srt.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final time = RegExp(
        r'(\d+):(\d{1,2}):(\d{1,2})[,.](\d{1,3})\s*-->\s*(\d+):(\d{1,2}):(\d{1,2})[,.](\d{1,3})');
    final cues = <SrtCue>[];
    for (final block in text.split(RegExp(r'\n\s*\n'))) {
      final lines = block
          .split('\n')
          .map((l) => l.replaceAll('﻿', ''))
          .where((l) => l.trim().isNotEmpty)
          .toList();
      if (lines.isEmpty) continue;
      var at = lines.indexWhere((l) => l.contains('-->'));
      if (at < 0) continue;
      final m = time.firstMatch(lines[at]);
      if (m == null) continue;
      int ms(String h, String mi, String s, String frac) =>
          ((int.parse(h) * 3600 + int.parse(mi) * 60 + int.parse(s)) * 1000) +
          int.parse(frac.padRight(3, '0').substring(0, 3));
      final start = ms(m[1]!, m[2]!, m[3]!, m[4]!);
      final end = ms(m[5]!, m[6]!, m[7]!, m[8]!);
      final body = lines
          .sublist(at + 1)
          .join('\n')
          .replaceAll(RegExp(r'\{\\[^}]*\}'), '')
          .trim();
      if (body.isEmpty || end <= start) continue;
      cues.add(SrtCue(start, end, body));
    }
    cues.sort((a, b) => a.startMs.compareTo(b.startMs));
    return cues;
  }
}

/// A piece of the served file: bytes held here, or a range of the source.
@immutable
class MkvPiece {
  const MkvPiece(this.outputOffset, this.length, {required this.sourceOffset, required this.literal});

  final int outputOffset;
  final int length;

  /// Where the bytes are in the original file; meaningful when [literal] is null.
  final int sourceOffset;

  /// The bytes themselves, when they are not from the source.
  final Uint8List? literal;

  bool get fromSource => literal == null;
}

/// The served mkv, as a plan.
class MkvLayout {
  MkvLayout._({
    required this.length,
    required Uint8List literal,
    required Int64List starts,
    required Int64List where,
    required Uint32List lengths,
    required Uint8List kinds,
    required this.clusterCount,
    required this.subtitleCount,
  })  : _literal = literal,
        _starts = starts,
        _where = where,
        _lengths = lengths,
        _kinds = kinds;

  /// The length of the file as the television will see it.
  final int length;

  final int clusterCount;
  final int subtitleCount;

  final Uint8List _literal;

  /// Output offset of each piece, ascending.
  final Int64List _starts;

  /// For a literal piece, its offset in [_literal]; for a source piece, its
  /// offset in the original file.
  final Int64List _where;
  final Uint32List _lengths;

  /// 0 for literal, 1 for source.
  final Uint8List _kinds;

  int get pieceCount => _starts.length;

  /// The pieces that cover output bytes [from]..[to] inclusive, clipped.
  Iterable<MkvPiece> pieces(int from, int to) sync* {
    if (from > to || from >= length) return;
    var i = _find(from);
    while (i < _starts.length && _starts[i] <= to) {
      final start = _starts[i];
      final end = start + _lengths[i] - 1;
      final a = from > start ? from : start;
      final b = to < end ? to : end;
      final skip = a - start;
      final length = b - a + 1;
      if (_kinds[i] == 0) {
        final at = _where[i] + skip;
        yield MkvPiece(a, length,
            sourceOffset: -1,
            literal: Uint8List.sublistView(_literal, at, at + length));
      } else {
        yield MkvPiece(a, length, sourceOffset: _where[i] + skip, literal: null);
      }
      i++;
    }
  }

  int _find(int offset) {
    var lo = 0;
    var hi = _starts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_starts[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }
}

/// Growable bytes that can be patched after the fact.
class _Bytes {
  Uint8List _buffer = Uint8List(1 << 20);
  int length = 0;

  void _grow(int needed) {
    if (length + needed <= _buffer.length) return;
    var size = _buffer.length * 2;
    while (size < length + needed) {
      size *= 2;
    }
    final bigger = Uint8List(size);
    bigger.setRange(0, length, _buffer);
    _buffer = bigger;
  }

  void add(List<int> bytes) {
    _grow(bytes.length);
    _buffer.setRange(length, length + bytes.length, bytes);
    length += bytes.length;
  }

  void byte(int b) {
    _grow(1);
    _buffer[length++] = b;
  }

  void setUint64(int at, int value) =>
      ByteData.sublistView(_buffer).setUint64(at, value);

  Uint8List take() => Uint8List.sublistView(_buffer, 0, length);
}

class _Builder {
  final _Bytes literal = _Bytes();
  final List<int> starts = <int>[];
  final List<int> where = <int>[];
  final List<int> lengths = <int>[];
  final List<int> kinds = <int>[];

  /// Where the next piece begins, counted from the first cluster.
  int cursor = 0;

  /// (timecode, offset from the first cluster) of every cluster.
  final List<int> clusterTimes = <int>[];
  final List<int> clusterOffsets = <int>[];

  void _literalPiece(List<int> bytes) {
    if (bytes.isEmpty) return;
    final last = starts.length - 1;
    // Adjacent literals are one piece: a cluster header and the first
    // block's framing, for instance.
    if (last >= 0 && kinds[last] == 0 && where[last] + lengths[last] == literal.length) {
      lengths[last] += bytes.length;
    } else {
      starts.add(cursor);
      where.add(literal.length);
      lengths.add(bytes.length);
      kinds.add(0);
    }
    literal.add(bytes);
    cursor += bytes.length;
  }

  void _sourcePiece(int offset, int length) {
    if (length <= 0) return;
    starts.add(cursor);
    where.add(offset);
    lengths.add(length);
    kinds.add(1);
    cursor += length;
  }

  MkvLayout? build({
    required Mp4Movie movie,
    required Mp4Track video,
    required String videoCodec,
    required Mp4Track? audio,
    required String? audioCodec,
    required List<SrtCue> cues,
    required String language,
    required MkvFill fill,
  }) {
    const videoTrack = 1;
    const audioTrack = 2;
    final subtitleTrack = audio == null ? 2 : 3;

    // ---- timestamps, in milliseconds, with each track starting at or
    // after zero (an edit list can put the first frame slightly before it).
    final videoDts = _ms(video.dts, video.timescale, 0);
    var shift = 0;
    for (var i = 0; i < video.sampleCount; i++) {
      final pts = video.pts(i);
      if (pts < shift) shift = pts;
    }
    final videoPts = Int64List(video.sampleCount);
    for (var i = 0; i < video.sampleCount; i++) {
      videoPts[i] = (video.pts(i) - shift) * 1000 ~/ video.timescale;
    }
    Int64List? audioPts;
    if (audio != null) {
      var audioShift = 0;
      for (var i = 0; i < audio.sampleCount; i++) {
        final pts = audio.pts(i);
        if (pts < audioShift) audioShift = pts;
      }
      audioPts = Int64List(audio.sampleCount);
      for (var i = 0; i < audio.sampleCount; i++) {
        audioPts[i] = (audio.pts(i) - audioShift) * 1000 ~/ audio.timescale;
      }
    }

    // ---- the clusters: every sample of every track, in time order.
    var v = 0;
    var a = 0;
    var s = 0;
    var clusterStart = -1;
    var clusterSizeAt = -1;
    var clusterBegan = 0;

    void closeCluster() {
      if (clusterSizeAt < 0) return;
      final size = cursor - clusterBegan - 12;
      literal.setUint64(clusterSizeAt, (1 << 56) | size);
      clusterSizeAt = -1;
    }

    void openCluster(int timecode) {
      closeCluster();
      clusterStart = timecode;
      clusterTimes.add(timecode);
      clusterOffsets.add(cursor);
      clusterBegan = cursor;
      final head = BytesBuilder(copy: false)
        ..add(const [0x1F, 0x43, 0xB6, 0x75])
        ..add(Uint8List(8)) // patched when the cluster closes
        ..add(_element(0xE7, _uint(timecode)));
      final bytes = head.takeBytes();
      // The size sits right after the four id bytes of this literal.
      _literalPiece(bytes);
      clusterSizeAt = literal.length - bytes.length + 4;
    }

    void block(int track, int timecode, bool key, int sourceOffset, int size) {
      if (clusterSizeAt < 0 ||
          timecode - clusterStart > 32767 ||
          timecode - clusterStart < -32768) {
        openCluster(timecode);
      }
      final rel = timecode - clusterStart;
      // SimpleBlock: id, size, track, a signed 16-bit time, flags — then the
      // frame itself, straight from the source.
      final sizeBytes = _vint(4 + size);
      final n = sizeBytes.length;
      final head = Uint8List(5 + n);
      head[0] = 0xA3;
      head.setRange(1, 1 + n, sizeBytes);
      head[1 + n] = 0x80 | track;
      head[2 + n] = (rel >> 8) & 0xFF;
      head[3 + n] = rel & 0xFF;
      head[4 + n] = key ? 0x80 : 0x00;
      _literalPiece(head);
      _sourcePiece(sourceOffset, size);
    }

    void subtitle(SrtCue cue) {
      final text = utf8.encode(cue.text);
      if (clusterSizeAt < 0 ||
          cue.startMs - clusterStart > 32767 ||
          cue.startMs - clusterStart < -32768) {
        openCluster(cue.startMs);
      }
      final rel = cue.startMs - clusterStart;
      final inner = BytesBuilder(copy: false)
        ..addByte(0x80 | subtitleTrack)
        ..add(_int16(rel))
        ..addByte(0x00)
        ..add(text);
      final group = BytesBuilder(copy: false)
        ..add(_element(0xA1, inner.takeBytes()))
        ..add(_element(0x9B, _uint(cue.endMs - cue.startMs)));
      _literalPiece(_element(0xA0, group.takeBytes()));
    }

    while (v < video.sampleCount ||
        (audio != null && a < audio.sampleCount) ||
        s < cues.length) {
      final vt = v < video.sampleCount ? videoDts[v] : null;
      final at = audio != null && a < audio.sampleCount ? _msOf(audio.dts[a], audio.timescale) : null;
      final st = s < cues.length ? cues[s].startMs : null;

      if (vt != null && (at == null || vt <= at) && (st == null || vt <= st)) {
        final key = video.isSync(v);
        if (key && clusterSizeAt >= 0 && vt - clusterStart >= MkvRemux._clusterMs) {
          openCluster(vt);
        }
        if (clusterSizeAt < 0) openCluster(vt);
        block(videoTrack, videoPts[v], key, video.offsets[v], video.sizes[v]);
        v++;
      } else if (at != null && (st == null || at <= st)) {
        if (clusterSizeAt < 0) openCluster(at);
        block(audioTrack, audioPts![a], true, audio!.offsets[a], audio.sizes[a]);
        a++;
      } else {
        subtitle(cues[s]);
        s++;
      }
    }
    closeCluster();
    if (clusterTimes.isEmpty) return null;

    // ---- what goes in front of the clusters, all of it fixed-width where
    // a position is written, so the positions can be worked out at once.
    final ebml = _element4(const [0x1A, 0x45, 0xDF, 0xA3], (BytesBuilder()
          ..add(_element2(const [0x42, 0x86], _uint(1)))
          ..add(_element2(const [0x42, 0xF7], _uint(1)))
          ..add(_element2(const [0x42, 0xF2], _uint(4)))
          ..add(_element2(const [0x42, 0xF3], _uint(8)))
          ..add(_element2(const [0x42, 0x82], ascii.encode('matroska')))
          ..add(_element2(const [0x42, 0x87], _uint(4)))
          ..add(_element2(const [0x42, 0x85], _uint(2))))
        .takeBytes());

    final info = _element4(const [0x15, 0x49, 0xA9, 0x66], (BytesBuilder()
          ..add(_element3(const [0x2A, 0xD7, 0xB1], _uint(MkvRemux._timecodeScale)))
          ..add(_element2(const [0x4D, 0x80], utf8.encode('CINEBALL')))
          ..add(_element2(const [0x57, 0x41], utf8.encode('CINEBALL')))
          ..add(_element2(const [0x44, 0x89], _float(movie.length.inMilliseconds.toDouble()))))
        .takeBytes());

    final tracks = BytesBuilder()
      ..add(_trackEntry(
        number: videoTrack,
        type: 1,
        codecId: videoCodec,
        codecPrivate: video.codecPrivate,
        language: 'und',
        forced: false,
        extra: _element1(0xE0, _videoElement(video.width, video.height, fill)),
      ));
    if (audio != null) {
      tracks.add(_trackEntry(
        number: audioTrack,
        type: 2,
        codecId: audioCodec!,
        codecPrivate: audio.codecPrivate,
        language: 'und',
        forced: false,
        extra: _element1(0xE1, (BytesBuilder()
              ..add(_element1(0xB5, _float(audio.sampleRate.toDouble())))
              ..add(_element1(0x9F, _uint(audio.channels == 0 ? 2 : audio.channels))))
            .takeBytes()),
      ));
    }
    tracks.add(_trackEntry(
      number: subtitleTrack,
      type: 0x11,
      codecId: 'S_TEXT/UTF8',
      codecPrivate: null,
      language: language,
      // Forced as well as default: a set that honours only one of the two
      // flags still turns the track on by itself.
      forced: true,
      extra: Uint8List(0),
    ));
    final tracksElement = _element4(const [0x16, 0x54, 0xAE, 0x6B], tracks.takeBytes());

    // Positions are counted from the first byte after the segment header.
    const seekHeadLength = 4 + 1 + 3 * 21;
    const infoAt = seekHeadLength;
    final tracksAt = infoAt + info.length;
    final cuesAt = tracksAt + tracksElement.length;
    final cuesLength = 4 + 8 + clusterTimes.length * 23;
    final clustersAt = cuesAt + cuesLength;

    final seekHead = _element4(const [0x11, 0x4D, 0x9B, 0x74], (BytesBuilder()
          ..add(_seek(const [0x15, 0x49, 0xA9, 0x66], infoAt))
          ..add(_seek(const [0x16, 0x54, 0xAE, 0x6B], tracksAt))
          ..add(_seek(const [0x1C, 0x53, 0xBB, 0x6B], cuesAt)))
        .takeBytes());
    assert(seekHead.length == seekHeadLength);

    final cuesBody = BytesBuilder(copy: false);
    for (var i = 0; i < clusterTimes.length; i++) {
      cuesBody
        ..add(const [0xBB, 0x95])
        ..add(const [0xB3, 0x84])
        ..add(_uint32(clusterTimes[i]))
        ..add(const [0xB7, 0x8D])
        ..add([0xF7, 0x81, videoTrack])
        ..add(const [0xF1, 0x88])
        ..add(_uint64(clustersAt + clusterOffsets[i]));
    }
    final cuesElement = (BytesBuilder(copy: false)
          ..add(const [0x1C, 0x53, 0xBB, 0x6B])
          ..add(_uint64((1 << 56) | (clusterTimes.length * 23)))
          ..add(cuesBody.takeBytes()))
        .takeBytes();
    assert(cuesElement.length == cuesLength);

    final segmentBody = clustersAt + cursor;
    final front = BytesBuilder(copy: false)
      ..add(ebml)
      ..add(const [0x18, 0x53, 0x80, 0x67])
      ..add(_uint64((1 << 56) | segmentBody))
      ..add(seekHead)
      ..add(info)
      ..add(tracksElement)
      ..add(cuesElement);
    final frontBytes = front.takeBytes();

    // ---- everything the clusters counted from zero moves behind the front.
    final count = starts.length + 1;
    final outStarts = Int64List(count);
    final outWhere = Int64List(count);
    final outLengths = Uint32List(count);
    final outKinds = Uint8List(count);
    outStarts[0] = 0;
    outWhere[0] = literal.length;
    outLengths[0] = frontBytes.length;
    outKinds[0] = 0;
    literal.add(frontBytes);
    for (var i = 0; i < starts.length; i++) {
      outStarts[i + 1] = starts[i] + frontBytes.length;
      outWhere[i + 1] = where[i];
      outLengths[i + 1] = lengths[i];
      outKinds[i + 1] = kinds[i];
    }

    return MkvLayout._(
      length: frontBytes.length + cursor,
      literal: literal.take(),
      starts: outStarts,
      where: outWhere,
      lengths: outLengths,
      kinds: outKinds,
      clusterCount: clusterTimes.length,
      subtitleCount: cues.length,
    );
  }

  static Int64List _ms(Int64List ticks, int timescale, int shift) {
    final out = Int64List(ticks.length);
    for (var i = 0; i < ticks.length; i++) {
      out[i] = (ticks[i] + shift) * 1000 ~/ timescale;
    }
    return out;
  }

  static int _msOf(int ticks, int timescale) => ticks * 1000 ~/ timescale;

  /// The Video element: the frame's size, and, when asked, how to show it
  /// on a 16:9 screen without bars.
  static Uint8List _videoElement(int width, int height, MkvFill fill) {
    final body = BytesBuilder()
      ..add(_element1(0xB0, _uint(width)))
      ..add(_element1(0xBA, _uint(height)));
    if (width <= 0 || height <= 0) return body.takeBytes();

    // Wider than 16:9 by more than a rounding error, or narrower.
    final wide = width * 9 > height * 16 + 8;
    final narrow = width * 9 + 8 < height * 16;
    if (fill == MkvFill.crop && wide) {
      final keep = height * 16 ~/ 9;
      final cut = (width - keep) ~/ 2;
      body
        ..add(_element2(const [0x54, 0xCC], _uint(cut))) // PixelCropLeft
        ..add(_element2(const [0x54, 0xDD], _uint(width - keep - cut))); // PixelCropRight
    } else if (fill == MkvFill.crop && narrow) {
      final keep = width * 9 ~/ 16;
      final cut = (height - keep) ~/ 2;
      body
        ..add(_element2(const [0x54, 0xBB], _uint(cut))) // PixelCropTop
        ..add(_element2(const [0x54, 0xAA], _uint(height - keep - cut))); // PixelCropBottom
    } else if (fill == MkvFill.stretch && (wide || narrow)) {
      final displayWidth = wide ? width : height * 16 ~/ 9;
      final displayHeight = wide ? width * 9 ~/ 16 : height;
      body
        ..add(_element2(const [0x54, 0xB0], _uint(displayWidth))) // DisplayWidth
        ..add(_element2(const [0x54, 0xBA], _uint(displayHeight))) // DisplayHeight
        ..add(_element2(const [0x54, 0xB2], _uint(0))); // DisplayUnit: pixels
    }
    return body.takeBytes();
  }

  static Uint8List _trackEntry({
    required int number,
    required int type,
    required String codecId,
    required Uint8List? codecPrivate,
    required String language,
    required bool forced,
    required Uint8List extra,
  }) {
    final body = BytesBuilder()
      ..add(_element1(0xD7, _uint(number)))
      ..add(_element2(const [0x73, 0xC5], _uint(number)))
      ..add(_element1(0x83, _uint(type)))
      ..add(_element1(0x88, _uint(1)))
      ..add(_element2(const [0x55, 0xAA], _uint(forced ? 1 : 0)))
      ..add(_element1(0x9C, _uint(0)))
      ..add(_element3(const [0x22, 0xB5, 0x9C], ascii.encode(language)))
      ..add(_element1(0x86, ascii.encode(codecId)));
    if (codecPrivate != null && codecPrivate.isNotEmpty) {
      body.add(_element2(const [0x63, 0xA2], codecPrivate));
    }
    body.add(extra);
    return _element1(0xAE, body.takeBytes());
  }

  static Uint8List _seek(List<int> id, int position) => _element2(
      const [0x4D, 0xBB],
      (BytesBuilder()
            ..add(_element2(const [0x53, 0xAB], id))
            ..add(const [0x53, 0xAC, 0x88])
            ..add(_uint64(position)))
          .takeBytes());

  // ---- EBML primitives

  static Uint8List _element(int id, List<int> body) => _element1(id, body);

  static Uint8List _element1(int id, List<int> body) =>
      (BytesBuilder(copy: false)..addByte(id)..add(_vint(body.length))..add(body)).takeBytes();

  static Uint8List _element2(List<int> id, List<int> body) =>
      (BytesBuilder(copy: false)..add(id)..add(_vint(body.length))..add(body)).takeBytes();

  static Uint8List _element3(List<int> id, List<int> body) => _element2(id, body);

  static Uint8List _element4(List<int> id, List<int> body) => _element2(id, body);

  /// A size, in as few bytes as it fits.
  static Uint8List _vint(int value) {
    var length = 1;
    while (length < 8 && value >= (1 << (7 * length)) - 1) {
      length++;
    }
    final out = Uint8List(length);
    var v = value;
    for (var i = length - 1; i >= 0; i--) {
      out[i] = v & 0xFF;
      v >>= 8;
    }
    out[0] |= 1 << (8 - length);
    return out;
  }

  /// An unsigned integer, in as few bytes as it fits.
  static Uint8List _uint(int value) {
    var length = 1;
    while (length < 8 && value >= (1 << (8 * length))) {
      length++;
    }
    final out = Uint8List(length);
    var v = value;
    for (var i = length - 1; i >= 0; i--) {
      out[i] = v & 0xFF;
      v >>= 8;
    }
    return out;
  }

  static Uint8List _uint32(int value) => Uint8List(4)..buffer.asByteData().setUint32(0, value);

  static Uint8List _uint64(int value) => Uint8List(8)..buffer.asByteData().setUint64(0, value);

  static Uint8List _int16(int value) => Uint8List(2)..buffer.asByteData().setInt16(0, value);

  static Uint8List _float(double value) => Uint8List(8)..buffer.asByteData().setFloat64(0, value);
}
