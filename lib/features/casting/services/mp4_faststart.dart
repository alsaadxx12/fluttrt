import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// Puts an mp4's index at the front, without re-encoding anything.
///
/// An mp4 is a sequence of boxes. Two matter here: `mdat`, which is the
/// video itself, and `moov`, the index that says where every frame is and
/// how to decode it. A player can show nothing at all until it has read
/// `moov`.
///
/// The catalogue's files are written `ftyp | free | mdat | moov` — the index
/// last, after seven hundred megabytes of video. The phone's own player
/// copes by asking for the tail first and then seeking back, which is why a
/// film plays there. A television's DLNA player does not: it asks for
/// `bytes=0-`, streams forward, and will not reach the index until it has
/// pulled the whole file down. That is the black screen.
///
/// So the order is changed on the way through: `ftyp | moov | mdat`. Moving
/// `moov` in front of `mdat` pushes every byte of video later in the file,
/// and `moov` is full of absolute offsets pointing at them — so each one is
/// shifted by exactly as much. Nothing is decoded, nothing is re-encoded;
/// about four megabytes are rewritten and the rest is passed through
/// untouched.
class Mp4FastStart {
  /// Boxes that hold other boxes. Anything else is skipped whole.
  static const Set<String> _containers = {
    'moov', 'trak', 'mdia', 'minf', 'stbl', 'edts', 'mvex',
  };

  /// Reads [length] bytes from [start] of the source.
  ///
  /// Returns null when the source will not answer, which is a reason to
  /// give up rather than to guess.
  static Future<Uint8List?> _read(
    Future<Uint8List?> Function(int start, int endInclusive) fetch,
    int start,
    int length,
  ) =>
      fetch(start, start + length - 1);

  /// Finds the index of the file and reads it, wherever it is.
  ///
  /// Returns null for anything that is not an mp4 with one `mdat` and one
  /// `moov` at the top level, or whose index is too large to hold.
  static Future<Mp4File?> read({
    required Future<Uint8List?> Function(int start, int endInclusive) fetch,
    required int totalSize,
  }) async {
    // The top-level boxes are at the very front; a few hundred bytes is
    // more than enough to walk them.
    final head = await _read(fetch, 0, 1024);
    if (head == null || head.length < 16) return null;

    final boxes = <_Box>[];
    var at = 0;
    while (at + 8 <= head.length) {
      final box = _readHeader(head, at, totalSize);
      if (box == null) break;
      boxes.add(box);
      if (box.end >= totalSize) break;
      // Only the first few are in the window we fetched; the rest are
      // walked by their sizes, which is all that is needed.
      at = box.end;
      if (at > head.length - 8) break;
    }
    if (boxes.isEmpty) return null;

    final ftyp = boxes.firstWhere((b) => b.type == 'ftyp',
        orElse: () => const _Box('', 0, 0));
    final mdat = boxes.firstWhere((b) => b.type == 'mdat',
        orElse: () => const _Box('', 0, 0));
    if (mdat.type.isEmpty || mdat.size <= 0) return null;

    // The index is either among the boxes in front, or it is whatever
    // follows mdat. Anything else and this is a shape not understood here.
    final moovFirst = boxes.indexWhere((b) => b.type == 'moov');
    final mdatAt = boxes.indexOf(mdat);
    final int moovStart;
    if (moovFirst >= 0 && moovFirst < mdatAt) {
      moovStart = boxes[moovFirst].start;
    } else {
      moovStart = mdat.end;
    }
    if (moovStart + 8 > totalSize) return null;
    final moovHeader = await _read(fetch, moovStart, 16);
    if (moovHeader == null || moovHeader.length < 8) return null;
    final moovBox = _readHeader(moovHeader, 0, totalSize - moovStart);
    if (moovBox == null || moovBox.type != 'moov') return null;

    final moovSize = moovBox.size;
    // An index is megabytes at most. Something far larger is not one, and
    // pulling it into memory would be the wrong thing to do on a phone.
    if (moovSize <= 0 || moovSize > 64 * 1024 * 1024) return null;

    final moov = await _read(fetch, moovStart, moovSize);
    if (moov == null || moov.length < moovSize) return null;

    final ftypBytes = ftyp.type.isEmpty
        ? Uint8List(0)
        : (await _read(fetch, ftyp.start, ftyp.size) ?? Uint8List(0));

    return Mp4File(
      ftyp: ftypBytes,
      moov: moov,
      indexFirst: moovStart < mdat.start,
      dataStart: mdat.start + mdat.headerSize,
      dataLength: mdat.size - mdat.headerSize,
      mdatHeader: _mdatHeader(mdat),
    );
  }

  /// Works out how to serve [totalSize] bytes with the index first.
  ///
  /// Returns null when the file needs no rearranging — or when it is not
  /// the shape this understands, in which case it is served as it is.
  static Future<Mp4Layout?> plan({
    required Future<Uint8List?> Function(int start, int endInclusive) fetch,
    required int totalSize,
  }) async {
    final file = await read(fetch: fetch, totalSize: totalSize);
    // Already in the right order: leave it alone.
    if (file == null || file.indexFirst) return null;
    return planFor(file);
  }

  /// The rearranged layout of an already-read [file].
  static Mp4Layout? planFor(Mp4File file) {
    // Where the video data used to begin, and where it will begin once the
    // index sits in front of it. Every offset inside the index moves by the
    // difference.
    final oldDataStart = file.dataStart;
    final newDataStart = file.ftyp.length + file.moov.length + file.mdatHeader.length;
    final delta = newDataStart - oldDataStart;

    final patched = shiftChunkOffsets(file.moov, delta);
    if (patched == null) return null;

    final header = BytesBuilder(copy: false)
      ..add(file.ftyp)
      ..add(patched)
      ..add(file.mdatHeader);

    return Mp4Layout(
      header: header.takeBytes(),
      sourceDataStart: oldDataStart,
      dataLength: file.dataLength,
    );
  }

  /// The `mdat` box header, rebuilt as it was.
  static Uint8List _mdatHeader(_Box mdat) {
    final out = Uint8List(mdat.headerSize);
    final view = ByteData.view(out.buffer);
    if (mdat.headerSize == 16) {
      view.setUint32(0, 1);
      out.setRange(4, 8, 'mdat'.codeUnits);
      view.setUint64(8, mdat.size);
    } else {
      view.setUint32(0, mdat.size);
      out.setRange(4, 8, 'mdat'.codeUnits);
    }
    return out;
  }

  /// Adds [delta] to every chunk offset inside a `moov` box.
  ///
  /// The offsets live in `stco` (32-bit) and `co64` (64-bit) boxes, buried
  /// several levels down inside each track. They are walked to rather than
  /// searched for: the four letters `stco` will turn up by chance inside
  /// binary data sooner or later, and an offset written into the middle of
  /// a sample table would corrupt the film quietly.
  ///
  /// Returns null if the box does not parse, which is a reason not to serve
  /// a rearranged file at all.
  @visibleForTesting
  static Uint8List? shiftChunkOffsets(Uint8List moov, int delta) {
    final out = Uint8List.fromList(moov);
    final view = ByteData.view(out.buffer);
    final ok = _walk(out, view, 0, out.length, delta);
    return ok ? out : null;
  }

  static bool _walk(Uint8List bytes, ByteData view, int start, int end, int delta) {
    var at = start;
    while (at + 8 <= end) {
      var size = view.getUint32(at);
      final type = String.fromCharCodes(bytes, at + 4, at + 8);
      var headerSize = 8;

      if (size == 1) {
        if (at + 16 > end) return false;
        size = view.getUint64(at + 8);
        headerSize = 16;
      } else if (size == 0) {
        size = end - at;
      }
      if (size < headerSize || at + size > end) return false;

      if (type == 'stco') {
        if (!_shift32(view, at + headerSize, at + size, delta)) return false;
      } else if (type == 'co64') {
        if (!_shift64(view, at + headerSize, at + size, delta)) return false;
      } else if (_containers.contains(type)) {
        if (!_walk(bytes, view, at + headerSize, at + size, delta)) return false;
      }

      at += size;
    }
    return true;
  }

  static bool _shift32(ByteData view, int start, int end, int delta) {
    // version+flags, then the number of entries, then the entries.
    if (start + 8 > end) return false;
    final count = view.getUint32(start + 4);
    var at = start + 8;
    if (at + count * 4 > end) return false;
    for (var i = 0; i < count; i++) {
      final moved = view.getUint32(at) + delta;
      // A 32-bit table cannot hold an offset past four gigabytes. Refusing
      // is right: writing a wrapped offset would produce a file that looks
      // valid and plays as noise.
      if (moved < 0 || moved > 0xFFFFFFFF) return false;
      view.setUint32(at, moved);
      at += 4;
    }
    return true;
  }

  static bool _shift64(ByteData view, int start, int end, int delta) {
    if (start + 8 > end) return false;
    final count = view.getUint32(start + 4);
    var at = start + 8;
    if (at + count * 8 > end) return false;
    for (var i = 0; i < count; i++) {
      view.setUint64(at, view.getUint64(at) + delta);
      at += 8;
    }
    return true;
  }

  static _Box? _readHeader(Uint8List bytes, int at, int limit) {
    if (at + 8 > bytes.length) return null;
    final view = ByteData.view(bytes.buffer, bytes.offsetInBytes);
    var size = view.getUint32(at);
    final type = String.fromCharCodes(bytes, at + 4, at + 8);
    var headerSize = 8;
    if (size == 1) {
      if (at + 16 > bytes.length) return null;
      size = view.getUint64(at + 8);
      headerSize = 16;
    } else if (size == 0) {
      size = limit - at;
    }
    if (size < headerSize) return null;
    return _Box(type, at, size, headerSize);
  }
}

/// An mp4 as found: its index, read whole, and where its media data is.
@immutable
class Mp4File {
  const Mp4File({
    required this.ftyp,
    required this.moov,
    required this.indexFirst,
    required this.dataStart,
    required this.dataLength,
    required this.mdatHeader,
  });

  final Uint8List ftyp;

  /// The whole `moov` box, header included, untouched.
  final Uint8List moov;

  /// Whether the index already comes before the media data.
  final bool indexFirst;

  /// Where the media data begins in the file, and how much there is.
  final int dataStart;
  final int dataLength;

  /// The `mdat` box header, as it was.
  final Uint8List mdatHeader;
}

/// How to serve a rearranged file: a header to send first, then a stretch
/// of the original.
@immutable
class Mp4Layout {
  const Mp4Layout({
    required this.header,
    required this.sourceDataStart,
    required this.dataLength,
  });

  /// `ftyp`, the rewritten index, and the `mdat` header — sent before
  /// anything is fetched.
  final Uint8List header;

  /// Where the video data starts in the original file.
  final int sourceDataStart;

  /// How much of it there is.
  final int dataLength;

  /// The length of the file as the television will see it.
  int get length => header.length + dataLength;
}

@immutable
class _Box {
  const _Box(this.type, this.start, this.size, [this.headerSize = 8]);

  final String type;
  final int start;
  final int size;
  final int headerSize;

  int get end => start + size;
}
