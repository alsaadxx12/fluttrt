import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/casting/widgets/cast_scan_page.dart';

/// What the receiver page actually encodes into the square, byte for byte:
///
///     JSON.stringify({ v: 1, s: session.id, c: code })
String receiverQr(String sessionId, String code) =>
    jsonEncode({'v': 1, 's': sessionId, 'c': code});

void main() {
  group('CastScanPage.codeIn', () {
    test('reads the code out of the receiver QR', () {
      final qr = receiverQr('c1e9eb31-f9f1-4e49-b790-bbc447ae381c', '224794');
      expect(CastScanPage.codeIn(qr), '224794');
    });

    test('keeps a leading zero', () {
      // The code is text all the way down — through the database, the page
      // and the json — and a code read as 24794 pairs with nothing.
      expect(CastScanPage.codeIn(receiverQr('id', '024794')), '024794');
    });

    test('accepts a bare six digits, with stray whitespace', () {
      expect(CastScanPage.codeIn('224794'), '224794');
      expect(CastScanPage.codeIn('  224794 \n'), '224794');
    });

    test('ignores a QR that is not ours', () {
      // A stray barcode should leave the scanner scanning, not send the
      // viewer a pairing failure for something they never pointed at.
      expect(CastScanPage.codeIn('https://example.com/watch/224794'), isNull);
      expect(CastScanPage.codeIn('WIFI:S:home;T:WPA;P:224794;;'), isNull);
      expect(CastScanPage.codeIn('{not json'), isNull);
      expect(CastScanPage.codeIn(jsonEncode({'v': 1, 's': 'id'})), isNull);
      expect(CastScanPage.codeIn(jsonEncode(['224794'])), isNull);
    });

    test('rejects a code of the wrong length', () {
      expect(CastScanPage.codeIn(receiverQr('id', '2247')), isNull);
      expect(CastScanPage.codeIn(receiverQr('id', '2247945')), isNull);
      expect(CastScanPage.codeIn('22479'), isNull);
    });

    test('rejects nothing at all', () {
      expect(CastScanPage.codeIn(null), isNull);
      expect(CastScanPage.codeIn(''), isNull);
      expect(CastScanPage.codeIn('   '), isNull);
    });
  });
}
