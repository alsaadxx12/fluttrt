import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/casting/services/mp4_faststart.dart';

/// Builds an mp4 shaped like the catalogue's: index last.
///
/// Small, but structurally real — `ftyp | free | mdat | moov`, with a
/// `moov` holding a track whose `stco` points into `mdat`.
class TinyMp4 {
  TinyMp4._(this.bytes, this.mdatDataStart, this.chunkOffsets);

  final Uint8List bytes;
  final int mdatDataStart;
  final List<int> chunkOffsets;

  /// A box: four bytes of size, four of type, then the payload.
  static Uint8List _box(String type, List<int> payload) {
    final out = Uint8List(8 + payload.length);
    ByteData.view(out.buffer).setUint32(0, out.length);
    out.setRange(4, 8, type.codeUnits);
    out.setRange(8, out.length, payload);
    return out;
  }

  /// `stco`: version+flags, count, then one 32-bit offset per chunk.
  static Uint8List _stco(List<int> offsets) {
    final body = ByteData(8 + offsets.length * 4);
    body.setUint32(0, 0); // version + flags
    body.setUint32(4, offsets.length);
    for (var i = 0; i < offsets.length; i++) {
      body.setUint32(8 + i * 4, offsets[i]);
    }
    return _box('stco', body.buffer.asUint8List());
  }

  static TinyMp4 build({int mediaSize = 2048}) {
    final ftyp = _box('ftyp', List<int>.filled(24, 0));
    final free = _box('free', const []);
    final mdatDataStart = ftyp.length + free.length + 8;

    // Two chunks, at the start and the middle of the media.
    final offsets = [mdatDataStart, mdatDataStart + mediaSize ~/ 2];

    final media = Uint8List.fromList(
      List<int>.generate(mediaSize, (i) => (i * 7) % 251),
    );
    final mdat = _box('mdat', media);

    // moov > trak > mdia > minf > stbl > stco
    final stbl = _box('stbl', _stco(offsets));
    final minf = _box('minf', stbl);
    final mdia = _box('mdia', minf);
    final trak = _box('trak', mdia);
    final moov = _box('moov', trak);

    return TinyMp4._(
      Uint8List.fromList([...ftyp, ...free, ...mdat, ...moov]),
      mdatDataStart,
      offsets,
    );
  }

  /// Reads the offsets back out of a `moov` block.
  static List<int> offsetsIn(Uint8List moov) {
    final out = <int>[];
    for (var i = 0; i + 8 <= moov.length; i++) {
      if (String.fromCharCodes(moov, i, i + 4) != 'stco') continue;
      final view = ByteData.view(moov.buffer, moov.offsetInBytes);
      final count = view.getUint32(i + 8);
      for (var n = 0; n < count; n++) {
        out.add(view.getUint32(i + 12 + n * 4));
      }
    }
    return out;
  }
}

void main() {
  group('rearranging a file so the index comes first', () {
    late TinyMp4 file;

    setUp(() => file = TinyMp4.build());

    Future<Uint8List?> read(int start, int end) async {
      if (start >= file.bytes.length) return null;
      final stop = (end + 1).clamp(0, file.bytes.length);
      return Uint8List.sublistView(file.bytes, start, stop);
    }

    test('a file with its index last is rearranged', () async {
      final layout = await Mp4FastStart.plan(
        fetch: read,
        totalSize: file.bytes.length,
      );

      expect(layout, isNotNull);
      final header = layout!.header;

      // ftyp first, then the index, then the media header — the whole point.
      expect(String.fromCharCodes(header, 4, 8), 'ftyp');
      expect(String.fromCharCodes(header, 36, 40), 'moov',
          reason: 'the index should sit immediately after ftyp');
      expect(
        String.fromCharCodes(header, header.length - 4, header.length),
        'mdat',
        reason: 'the media header comes last, and its bytes follow from the source',
      );

      // Not one byte of video is lost or added.
      expect(layout.dataLength, 2048);
      expect(layout.length, header.length + 2048);
    });

    test('every chunk offset moves by exactly the shift', () async {
      final layout = await Mp4FastStart.plan(
        fetch: read,
        totalSize: file.bytes.length,
      );
      expect(layout, isNotNull);

      const moovStart = 32; // straight after ftyp
      final moovEnd = layout!.header.length - 8; // before the mdat header
      final moov = Uint8List.sublistView(layout.header, moovStart, moovEnd);

      final now = TinyMp4.offsetsIn(moov);
      final newDataStart = layout.header.length;
      final shift = newDataStart - file.mdatDataStart;

      expect(now, [for (final o in file.chunkOffsets) o + shift]);
      // And they land inside the media, which is the test that matters:
      // an offset that points at the wrong byte plays as noise.
      for (final offset in now) {
        expect(offset, greaterThanOrEqualTo(newDataStart));
        expect(offset, lessThan(layout.length));
      }
    });

    test('a file already in the right order is left alone', () async {
      // ftyp | moov | mdat — nothing to do.
      final original = file.bytes;
      final ftyp = Uint8List.sublistView(original, 0, 32);
      const mdatStart = 32 + 8;
      const mdatEnd = mdatStart + 8 + 2048;
      final mdat = Uint8List.sublistView(original, mdatStart, mdatEnd);
      final moov = Uint8List.sublistView(original, mdatEnd);
      final reordered = Uint8List.fromList([...ftyp, ...moov, ...mdat]);

      final layout = await Mp4FastStart.plan(
        fetch: (s, e) async => Uint8List.sublistView(
            reordered, s, (e + 1).clamp(0, reordered.length)),
        totalSize: reordered.length,
      );

      expect(layout, isNull, reason: 'rewriting a good file would be waste and risk');
    });

    test('something that is not an mp4 is refused, not mangled', () async {
      final junk = Uint8List.fromList(List<int>.generate(4096, (i) => i % 255));
      final layout = await Mp4FastStart.plan(
        fetch: (s, e) async =>
            Uint8List.sublistView(junk, s, (e + 1).clamp(0, junk.length)),
        totalSize: junk.length,
      );
      expect(layout, isNull);
    });

    test('a truncated index is refused rather than half-written', () {
      final moov = Uint8List.fromList([0, 0, 0, 200, ...'moov'.codeUnits, 1, 2, 3]);
      expect(Mp4FastStart.shiftChunkOffsets(moov, 100), isNull);
    });

    test('the four letters stco inside media data are not mistaken for a box', () {
      // A real index, with the letters buried in a box that is not walked
      // into. Searching for the tag instead of walking the tree would find
      // this and write an offset into the middle of the film.
      final decoy = TinyMp4._box('udta', 'stco'.codeUnits + List<int>.filled(16, 0));
      final stbl = TinyMp4._box('stbl', TinyMp4._stco([100, 200]));
      final minf = TinyMp4._box('minf', stbl);
      final mdia = TinyMp4._box('mdia', minf);
      final trak = TinyMp4._box('trak', mdia);
      final moov = TinyMp4._box('moov', [...decoy, ...trak]);

      final shifted = Mp4FastStart.shiftChunkOffsets(moov, 1000);
      expect(shifted, isNotNull);
      expect(TinyMp4.offsetsIn(shifted!), contains(1100));
      expect(TinyMp4.offsetsIn(shifted), contains(1200));
    });
  });

  group('against the real catalogue file', () {
    test('the index is moved to the front and its offsets still land in the media',
        () async {
      HttpOverrides.global = null;

      final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      Future<String?> get(String url) async {
        try {
          final response = await (await client.getUrl(Uri.parse(url)))
              .close()
              .timeout(const Duration(seconds: 12));
          if (response.statusCode != 200) return null;
          return await response.fold<List<int>>(<int>[], (a, b) => a..addAll(b))
              .then(String.fromCharCodes);
        } catch (_) {
          return null;
        }
      }

      const api = 'https://cinemana.shabakaty.com/api/android';
      final listing = await get('$api/transcoddedFiles/id/3134510');
      if (listing == null) {
        // The catalogue is not reachable from here; the tests above still
        // cover the transform itself.
        return;
      }
      final match = RegExp(r'"videoUrl":"(.*?\.mp4[^"]*)"').firstMatch(listing);
      if (match == null) return;
      final url = match.group(1)!.replaceAll(r'\/', '/');

      var total = 0;
      Future<Uint8List?> range(int start, int end) async {
        try {
          final request = await client.getUrl(Uri.parse(url));
          request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
          request.followRedirects = true;
          final response = await request.close().timeout(const Duration(seconds: 20));
          if (response.statusCode >= 400) return null;
          final header = response.headers.value(HttpHeaders.contentRangeHeader);
          if (header != null && total == 0) {
            total = int.parse(header.split('/').last);
          }
          final bytes = await response.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
          return Uint8List.fromList(bytes);
        } catch (_) {
          return null;
        }
      }

      final probe = await range(0, 1);
      if (probe == null || total == 0) return;

      final layout = await Mp4FastStart.plan(fetch: range, totalSize: total);
      expect(layout, isNotNull,
          reason: 'the catalogue writes its index last; this is the file that '
              'showed a black screen on the television');

      expect(String.fromCharCodes(layout!.header, 4, 8), 'ftyp');
      expect(String.fromCharCodes(layout.header, 36, 40), 'moov');
      expect(layout.length, total - 8,
          reason: 'the free box is dropped and nothing else changes size');

      final moov = Uint8List.sublistView(layout.header, 32, layout.header.length - 8);
      final offsets = TinyMp4.offsetsIn(moov);
      expect(offsets, isNotEmpty, reason: 'a real film has chunks');
      // ignore: avoid_print
      print('REAL FILE: total=$total header=${layout.header.length} '
          'chunks=${offsets.length}');
      for (final offset in offsets) {
        expect(offset, greaterThanOrEqualTo(layout.header.length));
        expect(offset, lessThanOrEqualTo(layout.length));
      }

      client.close(force: true);
    }, timeout: const Timeout(Duration(seconds: 90)));
  });
}
