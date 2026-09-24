import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/qitv/data/qitv_models.dart';

void main() {
  test('a free channel without DRM is playable; one with a DRM prefix is not', () {
    final clear = QiChannel.fromJson({
      'id': 99,
      'title': 'QiTV',
      'active': true,
      'drm_prefix': null,
      'stream_path_android': 'https://prod-cdn-live.qi.tv/bpk-tv/qitv1/default/index.mpd',
      'stream_path_ios': 'https://prod-cdn-live.qi.tv/bpk-tv/qitv1/default/index.m3u8',
      'plans': [
        {'id': 1, 'title': 'Free', 'price': 0}
      ],
    });
    final locked = QiChannel.fromJson({
      'id': 101,
      'title': 'Alnasriyah',
      'active': true,
      'drm_prefix': 'alnasriyah',
      'stream_path_android': 'https://prod-cdn-live.qi.tv/bpk-tv/alnasriyah/default/index.mpd',
      'stream_path_ios': 'https://prod-cdn-live.qi.tv/bpk-tv/alnasriyah/default/index.m3u8',
      'plans': [
        {'id': 1, 'title': 'Free', 'price': 0}
      ],
    });
    expect(clear.isFree, isTrue);
    expect(clear.playable, isTrue);
    expect(locked.isFree, isTrue);
    expect(locked.hasDrm, isTrue);
    expect(locked.playable, isFalse);
  });

  test('playable channels sort before the encrypted ones', () {
    final a = QiChannel.fromJson({'id': 1, 'title': 'a', 'active': true, 'drm_prefix': 'a', 'stream_path_ios': 'x'});
    final b = QiChannel.fromJson({'id': 2, 'title': 'b', 'active': true, 'stream_path_ios': 'y'});
    final sorted = sortPlayableFirst([a, b]);
    expect(sorted.first.title, 'b');
  });
}
