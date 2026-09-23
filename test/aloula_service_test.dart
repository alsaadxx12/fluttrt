import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/sports/data/services/aloula_service.dart';

/// KSA Sports 1's master playlist names three renditions, each with a
/// day-long token of its own; the sharpest is handed to the player so the
/// picture is 1080p from the first second.
void main() {
  const master = 'https://live.kwikmotion.com/ksasports1live/ksasports1.smil/playlist_dvr.m3u8?hdnts=exp=1~hmac=x';
  const text = '#EXTM3U\n#EXT-X-VERSION:3\n'
      '#EXT-X-STREAM-INF:BANDWIDTH=1331017,RESOLUTION=854x480\nksasports1publish/ksasports1_480p/hdntl=exp=9~hmac=y/chunks_dvr.m3u8\n'
      '#EXT-X-STREAM-INF:BANDWIDTH=4796083,RESOLUTION=1920x1080\nksasports1publish/ksasports1_source/hdntl=exp=9~hmac=y/chunks_dvr.m3u8\n'
      '#EXT-X-STREAM-INF:BANDWIDTH=994976,RESOLUTION=640x360\nksasports1publish/ksasports1_360p/hdntl=exp=9~hmac=y/chunks_dvr.m3u8\n';

  test('the rendition with the most bandwidth, resolved against the master', () {
    expect(
      AloulaService.pickSharpest(text, master),
      'https://live.kwikmotion.com/ksasports1live/ksasports1.smil/ksasports1publish/ksasports1_source/hdntl=exp=9~hmac=y/chunks_dvr.m3u8',
    );
  });

  test('a rendition without a token of its own is not handed over alone', () {
    const bare = '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nhd/chunks.m3u8\n';
    expect(AloulaService.pickSharpest(bare, master), isNull);
  });

  test('the row record opens on the platform\'s own page and is free', () {
    final c = AloulaService().sports1();
    expect(c.pageUrl, contains('aloula.sba.sa'));
    expect(c.isFree, isTrue);
    expect(c.arabicTitle, 'الرياضية 1');
  });
}
