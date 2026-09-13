import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/sports/presentation/widgets/glowing_crest.dart';

/// A 20x20 "crest": [main] fills most of it, [accent] a small corner, the rest transparent.
Future<ui.Image> crest(Color main, {Color? accent, double mainShare = 0.6}) async {
  const n = 20;
  final px = Uint8List(n * n * 4);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      final i = (y * n + x) * 4;
      final inMain = y < n * mainShare;
      final inAccent = !inMain && x < 4 && y < n - 2;
      final c = inMain ? main : (inAccent && accent != null ? accent : null);
      if (c == null) continue;
      px[i] = c.red;
      px[i + 1] = c.green;
      px[i + 2] = c.blue;
      px[i + 3] = 255;
    }
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(px);
  final desc = ui.ImageDescriptor.raw(buffer, width: n, height: n, pixelFormat: ui.PixelFormat.rgba8888);
  final frame = await (await desc.instantiateCodec()).getNextFrame();
  return frame.image;
}

double hue(Color c) => HSLColor.fromColor(c).hue;

void main() {
  test('red crest glows red, blue glows blue', () async {
    final red = await GlowingCrest.crestGlowColor(await crest(const Color(0xFFC8102E)));
    expect(hue(red), anyOf(lessThan(15), greaterThan(345)));
    final blue = await GlowingCrest.crestGlowColor(await crest(const Color(0xFF0068A8)));
    expect(hue(blue), inInclusiveRange(195, 225));
    // brightened enough to glow on the dark card
    expect(HSLColor.fromColor(blue).lightness, greaterThanOrEqualTo(0.45));
  });

  test('white crest with a small colour picks the colour, not white', () async {
    final c = await GlowingCrest.crestGlowColor(
        await crest(Colors.white, accent: const Color(0xFF1FA36B), mainShare: 0.6));
    expect(hue(c), inInclusiveRange(135, 170));
  });

  test('black-and-white crest gets the neutral glow', () async {
    final c = await GlowingCrest.crestGlowColor(await crest(Colors.black, accent: Colors.white));
    expect(c, GlowingCrest.neutralGlow);
  });
}
