import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/sports/data/services/alkass_service.dart';

/// Alkass's site lists nine channels; four and «shoof1» are free, the rest
/// come back with a «blocked» clip in place of a stream. The home row shows
/// only the free ones, in the site's order.
void main() {
  const json = [
    {
      'id': 2,
      'body': 'https://liveeu-gcps.alkassdigital.net/alkass2-p/main.m3u8?hdnts=exp=1790177145~hmac=abc',
      'title': 'Alkass 2',
      'image': 'https://www.alkass.net/images/new-2.png',
      'Sorting': 2,
      'webname': 'two',
      'is_premium': 0,
    },
    {
      'id': 1,
      'body': 'https://liveeu-gcps.alkassdigital.net/alkass1-p/main.m3u8?hdnts=exp=1790177145~hmac=abc',
      'title': 'Alkass 1',
      'image': 'https://www.alkass.net/images/new-1.png',
      'Sorting': 1,
      'webname': 'one',
      'is_premium': 0,
    },
    {
      'id': 5,
      'body': 'https://shoof.alkass.net/assets/blocked.mp4',
      'title': 'Alkass 5',
      'image': 'https://www.alkass.net/images/new-5.png',
      'Sorting': 5,
      'webname': 'blocked_five',
      'is_premium': 12,
    },
    {
      'id': 14,
      'body': 'https://liveakgrns.alkassdigital.net/hls/live/2097037/shoofl/master.m3u8?hdnts=exp=1790177145~hmac=x',
      'title': 'shoof1',
      'image': 'https://www.alkass.net/images/shoof1.png',
      'Sorting': 99,
      'webname': 'shoof1',
      'is_premium': 0,
    },
  ];

  test('only the free channels, in the site\'s order', () {
    final channels = AlkassService.parse(json);
    expect(channels.map((c) => c.webname), ['one', 'two', 'shoof1']);
    expect(channels.every((c) => c.isFree), isTrue);
  });

  test('a premium channel is out even though it has an address of sorts', () {
    final channels = AlkassService.parse(json);
    expect(channels.any((c) => c.id == 5), isFalse);
  });

  test('the names on the cards are Arabic', () {
    final channels = AlkassService.parse(json);
    expect(channels.map((c) => c.arabicTitle), ['الكأس 1', 'الكأس 2', 'شوف 1']);
  });

  test('the token\'s expiry is read from the address', () {
    final channels = AlkassService.parse(json);
    expect(channels.first.expiresAt, DateTime.fromMillisecondsSinceEpoch(1790177145 * 1000, isUtc: true));
    expect(AlkassService.expiryOf('https://a/b.m3u8'), isNull);
  });
}
