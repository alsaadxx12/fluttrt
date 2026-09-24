import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/casting/models/cast_models.dart';
import 'package:youtube_downloader/features/casting/services/mkv_remux.dart';

void main() {
  const cues = [SrtCue(500, 1200, 'مرحبا'), SrtCue(1400, 2000, 'سطر\nآخر')];

  test('the usual size leaves the lines exactly as they were', () {
    expect(identical(SrtCue.sized(cues, 1), cues), isTrue);
    expect(identical(SrtCue.sized(cues, 1.004), cues), isTrue);
  });

  test('another size wraps every line in a font tag the set can read', () {
    final big = SrtCue.sized(cues, 1.6);
    expect(big.map((c) => c.text), ['<font size="29">مرحبا</font>', '<font size="29">سطر\nآخر</font>']);
    expect(big.first.startMs, 500);
    expect(big.first.endMs, 1200);
    expect(SrtCue.sized(cues, 0.8).first.text, '<font size="14">مرحبا</font>');
  });

  test('the size goes to the browser with every title and can be changed', () {
    const media = CastMedia(mediaId: 'x', title: 't', streamUrl: 'http://s/x.mp4', subtitleUrl: 'http://s/x.srt');
    expect(media.toCommand()['subtitleScale'], 1);
    expect(media.copyWith(subtitleScale: 1.3).toCommand()['subtitleScale'], 1.3);
    expect(media.copyWith(subtitleScale: 1.3).copyWith(position: const Duration(seconds: 9)).subtitleScale, 1.3);
  });

  test('the sizes offered run from small to huge with the usual one among them', () {
    expect(kSubtitleSizes.map((s) => s.scale).toList(), [0.8, 1, 1.3, 1.6, 2]);
    expect(kSubtitleSizes.any((s) => s.scale == 1 && s.name == 'عادي'), isTrue);
  });
}
