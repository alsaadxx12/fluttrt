import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/cinemana/data/cinemana_subtitles.dart';

void main() {
  test('SRT cues: times in ms, counters and markup dropped', () {
    const srt = '\uFEFF1\r\n'
        '00:00:01,500 --> 00:00:03,020\r\n'
        '<font color="#ffffff">مرحبا</font>\r\n'
        '<i>Hello</i> &amp; bye\r\n'
        '\r\n'
        '2\r\n'
        '0:01:02,5 --> 0:01:04,000 X1:10 X2:20\r\n'
        '{\\an8}Second\r\n';
    final cues = parseSubtitles(srt);
    expect(cues, hasLength(2));
    expect(cues[0].startMs, 1500);
    expect(cues[0].endMs, 3020);
    expect(cues[0].text, 'مرحبا\nHello & bye');
    expect(cues[1].startMs, 62500);
    expect(cues[1].endMs, 64000);
    expect(cues[1].text, 'Second');
  });

  test('cues without blank lines between them stay separate', () {
    const srt = '1\n00:00:01,000 --> 00:00:02,000\nA\n2\n00:00:03,000 --> 00:00:04,000\nB\n';
    final cues = parseSubtitles(srt);
    expect(cues.map((c) => c.text), ['A', 'B']);
  });

  test('WebVTT input and broken cues', () {
    const vtt = 'WEBVTT\n\n00:05.000 --> 00:06.000\nShort form\n\n'
        '00:00:09,000 --> 00:00:08,000\nends before it starts\n\n'
        '00:00:10,000 --> 00:00:11,000\n\n';
    final cues = parseSubtitles(vtt);
    expect(cues, hasLength(1));
    expect(cues.single.startMs, 5000);
    expect(cues.single.text, 'Short form');
  });

  test('placeholder links are not treated as subtitles', () {
    final s = CinemanaSubtitleSources.fromJson({
      'arTranslationFilePath':
          'https://cnth2.shabakaty.com/vascin-translation-files/X_ar_transfile.srt?Expires=1',
      'enTranslationFilePath': 'defaultImages/loading.gif',
      'translations': [
        {'type': 'en', 'extention': 'vtt', 'file': 'https://cnth2.shabakaty.com/x/Y_en.vtt'},
      ],
    });
    expect(s.ar, contains('_ar_transfile.srt'));
    expect(s.en, 'https://cnth2.shabakaty.com/x/Y_en.vtt');
    expect(CinemanaSubtitleSources.fromJson({'enTranslationFilePath': 'defaultImages/loading.gif'}).isEmpty,
        isTrue);
  });
}
