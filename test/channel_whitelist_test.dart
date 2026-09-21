import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/sports/data/channel_whitelist.dart';

/// Only beIN Sports and the app's own YASIR TV / Sir TV channels may appear;
/// every other channel the feeds carry is dropped.
void main() {
  test('beIN Sports channels are kept, Latin or Arabic', () {
    for (final n in [
      'beIN Sports 1 HD',
      'beIN Sports 2 HD',
      'beIN Sports 4 HD',
      'bein sports mena 1',
      'BEIN SPORTS MAX',
      'بي إن سبورت 1',
      'بين سبورت',
    ]) {
      expect(ChannelWhitelist.allows(n), isTrue, reason: n);
    }
  });

  test("the app's own YASIR TV / Sir TV channels are kept", () {
    for (final n in [
      'YASIR TV',
      'Yasir Tv HD',
      'yasirtv',
      'YASIR-TV 2',
      'Sir TV',
      'SIR TV HD',
      'sir_tv',
      'ياسر تي في',
      'قناة ياسر',
    ]) {
      expect(ChannelWhitelist.allows(n), isTrue, reason: n);
    }
  });

  test('everything else is dropped', () {
    for (final n in [
      'On Time Sport 1',
      'MBC Action',
      'الجزيرة الإخبارية',
      'سبيستون (Spacetoon)',
      'دبي الرياضية HD',
      'كربلاء الفضائية',
      'Sirius XM',
      'Sir Lancelot',
      '',
    ]) {
      expect(ChannelWhitelist.allows(n), isFalse, reason: n);
    }
  });
}
