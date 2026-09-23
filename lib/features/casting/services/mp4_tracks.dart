import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// Reads an mp4 index (`moov`) far enough to know where every sample is.
///
/// Nothing here decodes video. It answers one question per sample — where
/// it is, how long it is, and when it is shown — which is all that is
/// needed to put the same bytes inside a different container.
@immutable
class Mp4Movie {
  const Mp4Movie({
    required this.timescale,
    required this.duration,
    required this.tracks,
  });

  /// Ticks per second for [duration].
  final int timescale;

  /// Length of the film in [timescale] ticks.
  final int duration;

  final List<Mp4Track> tracks;

  Duration get length => Duration(
      microseconds: timescale == 0 ? 0 : duration * 1000000 ~/ timescale);

  Mp4Track? get video => tracks.cast<Mp4Track?>().firstWhere(
      (t) => t!.isVideo && t.sampleCount > 0,
      orElse: () => null);

  Mp4Track? get audio => tracks.cast<Mp4Track?>().firstWhere(
      (t) => t!.isAudio && t.sampleCount > 0,
      orElse: () => null);

  /// Parses a whole `moov` box, header included.
  ///
  /// Returns null for anything that does not parse as one: a wrong guess
  /// here would be served as a film that plays as noise.
  static Mp4Movie? parse(Uint8List moov) {
    try {
      return _Parser(moov).movie();
    } catch (e) {
      debugPrint('[cast] mp4 index: $e');
      return null;
    }
  }
}

/// One track of an mp4: its codec, and a table of every sample.
class Mp4Track {
  Mp4Track({
    required this.id,
    required this.handler,
    required this.codec,
    required this.timescale,
    required this.width,
    required this.height,
    required this.channels,
    required this.sampleRate,
    required this.codecPrivate,
    required this.offsets,
    required this.sizes,
    required this.dts,
    required this.compositionOffsets,
    required this.sync,
    required this.editShift,
  });

  final int id;

  /// `vide`, `soun` or whatever else the file says.
  final String handler;

  /// The sample entry's four letters: `avc1`, `hvc1`, `mp4a`, `ac-3`…
  final String codec;

  /// Ticks per second for every timestamp on this track.
  final int timescale;

  final int width;
  final int height;
  final int channels;
  final int sampleRate;

  /// What a decoder needs before the first sample: `avcC` / `hvcC` payload
  /// for video, the AudioSpecificConfig for AAC. Null when there is none.
  final Uint8List? codecPrivate;

  /// Absolute byte offset of each sample in the file.
  final Int64List offsets;
  final Uint32List sizes;

  /// Decode time of each sample, in ticks.
  final Int64List dts;

  /// Presentation minus decode time per sample, in ticks; null when the
  /// track has no reordering.
  final Int32List? compositionOffsets;

  /// One byte per sample: 1 where a decoder can start.
  final Uint8List sync;

  /// Ticks added to every presentation time by the track's edit list.
  final int editShift;

  int get sampleCount => sizes.length;

  bool get isVideo => handler == 'vide';
  bool get isAudio => handler == 'soun';

  /// Presentation time of sample [i], in ticks.
  int pts(int i) => dts[i] + (compositionOffsets?[i] ?? 0) + editShift;

  bool isSync(int i) => sync[i] != 0;
}

class _Parser {
  _Parser(this.bytes) : view = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final ByteData view;

  Mp4Movie movie() {
    final moov = _box(0, bytes.length);
    if (moov == null || moov.type != 'moov') {
      throw const FormatException('not a moov box');
    }

    var timescale = 0;
    var duration = 0;
    final tracks = <Mp4Track>[];

    for (final child in _children(moov)) {
      if (child.type == 'mvhd') {
        final version = view.getUint8(child.payload);
        if (version == 1) {
          timescale = view.getUint32(child.payload + 20);
          duration = view.getUint64(child.payload + 24);
        } else {
          timescale = view.getUint32(child.payload + 12);
          duration = view.getUint32(child.payload + 16);
        }
      } else if (child.type == 'trak') {
        final track = _track(child, timescale);
        if (track != null) tracks.add(track);
      }
    }
    return Mp4Movie(timescale: timescale, duration: duration, tracks: tracks);
  }

  Mp4Track? _track(_Box trak, int movieTimescale) {
    var id = 0;
    var width = 0;
    var height = 0;
    _Box? mdia;
    _Box? elst;

    for (final child in _children(trak)) {
      switch (child.type) {
        case 'tkhd':
          final version = view.getUint8(child.payload);
          final at = child.payload + (version == 1 ? 20 : 12);
          id = view.getUint32(at);
          // Width and height sit at the very end, as 16.16 fixed point.
          width = view.getUint32(child.end - 8) >> 16;
          height = view.getUint32(child.end - 4) >> 16;
        case 'mdia':
          mdia = child;
        case 'edts':
          for (final e in _children(child)) {
            if (e.type == 'elst') elst = e;
          }
      }
    }
    if (mdia == null) return null;

    var timescale = 0;
    var handler = '';
    _Box? stbl;
    for (final child in _children(mdia)) {
      switch (child.type) {
        case 'mdhd':
          final version = view.getUint8(child.payload);
          timescale = view.getUint32(child.payload + (version == 1 ? 20 : 12));
        case 'hdlr':
          handler = _fourcc(child.payload + 8);
        case 'minf':
          for (final m in _children(child)) {
            if (m.type == 'stbl') stbl = m;
          }
      }
    }
    if (stbl == null || timescale == 0) return null;

    _Box? stsd;
    _Box? stts;
    _Box? ctts;
    _Box? stss;
    _Box? stsc;
    _Box? stsz;
    _Box? stco;
    var co64 = false;
    for (final child in _children(stbl)) {
      switch (child.type) {
        case 'stsd':
          stsd = child;
        case 'stts':
          stts = child;
        case 'ctts':
          ctts = child;
        case 'stss':
          stss = child;
        case 'stsc':
          stsc = child;
        case 'stsz':
          stsz = child;
        case 'stco':
          stco = child;
        case 'co64':
          stco = child;
          co64 = true;
      }
    }
    if (stsd == null || stts == null || stsc == null || stsz == null || stco == null) {
      return null;
    }

    // ---- the codec
    final entry = _box(stsd.payload + 8, stsd.end);
    if (entry == null) return null;
    final codec = entry.type;
    var channels = 0;
    var sampleRate = 0;
    Uint8List? codecPrivate;

    if (handler == 'vide') {
      // 8 header + 6 reserved + 2 data reference index + 70 of fixed fields.
      final childrenAt = entry.start + 86;
      if (width == 0) width = view.getUint16(entry.start + 32);
      if (height == 0) height = view.getUint16(entry.start + 34);
      for (final c in _children(_Box(entry.type, entry.start, entry.size, childrenAt - entry.start))) {
        if (c.type == 'avcC' || c.type == 'hvcC') {
          codecPrivate = Uint8List.sublistView(bytes, c.payload, c.end);
        }
      }
    } else if (handler == 'soun') {
      final fields = entry.start + 16;
      final version = view.getUint16(fields);
      channels = view.getUint16(fields + 8);
      sampleRate = view.getUint32(fields + 16) >> 16;
      // QuickTime's later audio entries carry extra fields before the
      // child boxes; the version says how many.
      final extra = version == 1 ? 16 : (version == 2 ? 36 : 0);
      final childrenAt = fields + 20 + extra;
      for (final c in _children(_Box(entry.type, entry.start, entry.size, childrenAt - entry.start))) {
        if (c.type == 'esds') {
          codecPrivate = _audioSpecificConfig(c.payload + 4, c.end);
        }
      }
    }

    // ---- the sample tables
    final sizes = _sizes(stsz);
    final count = sizes.length;
    final offsets = _offsets(stsc, stco, co64, sizes);
    final dts = _decodeTimes(stts, count);
    final composition = ctts == null ? null : _compositionOffsets(ctts, count);
    final sync = Uint8List(count);
    if (stss == null) {
      sync.fillRange(0, count, 1);
    } else {
      final n = view.getUint32(stss.payload + 4);
      var at = stss.payload + 8;
      for (var i = 0; i < n && at + 4 <= stss.end; i++) {
        final sample = view.getUint32(at) - 1;
        if (sample >= 0 && sample < count) sync[sample] = 1;
        at += 4;
      }
    }

    return Mp4Track(
      id: id,
      handler: handler,
      codec: codec,
      timescale: timescale,
      width: width,
      height: height,
      channels: channels,
      sampleRate: sampleRate,
      codecPrivate: codecPrivate,
      offsets: offsets,
      sizes: sizes,
      dts: dts,
      compositionOffsets: composition,
      sync: sync,
      editShift: elst == null ? 0 : _editShift(elst, timescale, movieTimescale),
    );
  }

  Uint32List _sizes(_Box stsz) {
    final uniform = view.getUint32(stsz.payload + 4);
    final count = view.getUint32(stsz.payload + 8);
    final sizes = Uint32List(count);
    if (uniform != 0) {
      sizes.fillRange(0, count, uniform);
    } else {
      var at = stsz.payload + 12;
      for (var i = 0; i < count; i++) {
        sizes[i] = view.getUint32(at);
        at += 4;
      }
    }
    return sizes;
  }

  Int64List _offsets(_Box stsc, _Box stco, bool wide, Uint32List sizes) {
    final chunkCount = view.getUint32(stco.payload + 4);
    final runCount = view.getUint32(stsc.payload + 4);
    final offsets = Int64List(sizes.length);

    var sample = 0;
    var run = 0;
    var runAt = stsc.payload + 8;
    for (var chunk = 0; chunk < chunkCount && sample < sizes.length; chunk++) {
      // stsc runs say "from chunk N on, M samples per chunk".
      while (run + 1 < runCount &&
          view.getUint32(runAt + 12) - 1 <= chunk) {
        run++;
        runAt += 12;
      }
      final perChunk = view.getUint32(runAt + 4);
      var at = wide
          ? view.getUint64(stco.payload + 8 + chunk * 8)
          : view.getUint32(stco.payload + 8 + chunk * 4);
      for (var i = 0; i < perChunk && sample < sizes.length; i++) {
        offsets[sample] = at;
        at += sizes[sample];
        sample++;
      }
    }
    if (sample != sizes.length) {
      throw FormatException('chunk table covers $sample of ${sizes.length} samples');
    }
    return offsets;
  }

  Int64List _decodeTimes(_Box stts, int count) {
    final dts = Int64List(count);
    final entries = view.getUint32(stts.payload + 4);
    var at = stts.payload + 8;
    var time = 0;
    var sample = 0;
    for (var e = 0; e < entries && sample < count; e++) {
      final n = view.getUint32(at);
      final delta = view.getUint32(at + 4);
      for (var i = 0; i < n && sample < count; i++) {
        dts[sample++] = time;
        time += delta;
      }
      at += 8;
    }
    return dts;
  }

  Int32List _compositionOffsets(_Box ctts, int count) {
    final out = Int32List(count);
    final entries = view.getUint32(ctts.payload + 4);
    var at = ctts.payload + 8;
    var sample = 0;
    for (var e = 0; e < entries && sample < count; e++) {
      final n = view.getUint32(at);
      // Version 1 of the box allows negative offsets; version 0 does not,
      // but a file that writes them anyway is read the way it meant.
      final offset = view.getInt32(at + 4);
      for (var i = 0; i < n && sample < count; i++) {
        out[sample++] = offset;
      }
      at += 8;
    }
    return out;
  }

  /// What the edit list adds to every presentation time.
  ///
  /// An empty edit at the front delays the track; a non-empty one that
  /// starts inside the media trims it. Both are common: the second is how a
  /// file with B-frames says its first frame is shown at zero.
  int _editShift(_Box elst, int timescale, int movieTimescale) {
    final version = view.getUint8(elst.payload);
    final entries = view.getUint32(elst.payload + 4);
    var at = elst.payload + 8;
    var shift = 0;
    for (var e = 0; e < entries; e++) {
      final int segment;
      final int mediaTime;
      if (version == 1) {
        segment = view.getUint64(at);
        mediaTime = view.getInt64(at + 8);
        at += 20;
      } else {
        segment = view.getUint32(at);
        mediaTime = view.getInt32(at + 4);
        at += 12;
      }
      if (mediaTime == -1) {
        if (movieTimescale > 0) shift += segment * timescale ~/ movieTimescale;
        continue;
      }
      shift -= mediaTime;
      break;
    }
    return shift;
  }

  /// Digs the AudioSpecificConfig out of an `esds` box.
  ///
  /// It is three descriptors deep: ES → DecoderConfig → DecoderSpecificInfo,
  /// each a tag, an expandable length, and a body.
  Uint8List? _audioSpecificConfig(int start, int end) {
    var at = start;
    // ES_Descriptor
    if (at >= end || view.getUint8(at) != 0x03) return null;
    at = _descriptorBody(at + 1, end);
    if (at < 0) return null;
    final esFlags = view.getUint8(at + 2);
    at += 3;
    if (esFlags & 0x80 != 0) at += 2; // stream dependence
    if (esFlags & 0x40 != 0) at += 1 + view.getUint8(at); // url
    if (esFlags & 0x20 != 0) at += 2; // OCR
    // DecoderConfigDescriptor
    if (at >= end || view.getUint8(at) != 0x04) return null;
    at = _descriptorBody(at + 1, end);
    if (at < 0) return null;
    at += 13;
    // DecoderSpecificInfo
    if (at >= end || view.getUint8(at) != 0x05) return null;
    var length = 0;
    var p = at + 1;
    for (var i = 0; i < 4 && p < end; i++) {
      final b = view.getUint8(p++);
      length = (length << 7) | (b & 0x7F);
      if (b & 0x80 == 0) break;
    }
    if (p + length > end) return null;
    return Uint8List.sublistView(bytes, p, p + length);
  }

  /// Skips an expandable descriptor length and returns where its body starts.
  int _descriptorBody(int at, int end) {
    for (var i = 0; i < 4 && at < end; i++) {
      final b = view.getUint8(at++);
      if (b & 0x80 == 0) return at;
    }
    return -1;
  }

  String _fourcc(int at) => String.fromCharCodes(bytes, at, at + 4);

  _Box? _box(int at, int limit) {
    if (at + 8 > limit) return null;
    var size = view.getUint32(at);
    final type = _fourcc(at + 4);
    var header = 8;
    if (size == 1) {
      if (at + 16 > limit) return null;
      size = view.getUint64(at + 8);
      header = 16;
    } else if (size == 0) {
      size = limit - at;
    }
    if (size < header || at + size > limit) return null;
    return _Box(type, at, size, header);
  }

  Iterable<_Box> _children(_Box parent) sync* {
    var at = parent.payload;
    while (at + 8 <= parent.end) {
      final child = _box(at, parent.end);
      if (child == null) return;
      yield child;
      at = child.end;
    }
  }
}

@immutable
class _Box {
  const _Box(this.type, this.start, this.size, this.headerSize);

  final String type;
  final int start;
  final int size;
  final int headerSize;

  int get payload => start + headerSize;
  int get end => start + size;
}
