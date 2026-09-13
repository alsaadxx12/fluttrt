import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  test('Call nextPage 3 times', () async {
    final yt = YoutubeExplode();
    var list = await yt.search.search('مونتير');
    expect(list.isNotEmpty, isTrue);

    var page2 = await list.nextPage();
    expect(page2, isNotNull);
    expect(page2!.isNotEmpty, isTrue);

    var page3 = await page2.nextPage();
    expect(page3, isNotNull);
    expect(page3!.isNotEmpty, isTrue);

    yt.close();
  });
}
