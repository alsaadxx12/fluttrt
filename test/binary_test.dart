import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Find binaries', () {
    final ytDlp = File('yt-dlp.exe');
    final ffmpeg = File('ffmpeg.exe');
    final node = File(r'C:\Program Files\nodejs\node.exe');

    expect(ytDlp.existsSync(), isTrue, reason: 'yt-dlp.exe must exist in project root');
    expect(ffmpeg.existsSync(), isTrue, reason: 'ffmpeg.exe must exist in project root');
    expect(node.existsSync(), isTrue, reason: 'node.exe must exist');
  });
}
