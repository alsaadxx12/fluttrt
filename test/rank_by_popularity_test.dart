import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';
import 'package:youtube_downloader/features/cinemana/data/services/cinemana_service.dart';

CinemanaItem _film(String id, String title, String stars) => CinemanaItem.fromJson({
      'nb': id,
      'en_title': title,
      'ar_title': title,
      'year': '2026',
      'stars': stars,
      'kind': '1',
    });

void main() {
  test('the films the world watches come first, in that order; the rest by score', () {
    final films = [
      _film('1', 'A Quiet Documentary', '8.4'),
      _film('2', 'Batman: Knightfall', '7.0'),
      _film('3', 'The Rays & Shadows', '6.1'),
      _film('4', 'Small Film', '5.0'),
      _film('5', 'Another Doc', '7.9'),
    ];
    final ranked = CinemanaService.rankByPopularity(films, ['The Rays and Shadows', 'batman knightfall', 'Unlisted']);
    expect(ranked.map((f) => f.id).toList(), ['3', '2', '1', '5', '4']);
  });

  test('titles match with case, punctuation and spacing set aside', () {
    final films = [_film('9', "Mission: Impossible - Dead Reckoning", '7.2')];
    final ranked = CinemanaService.rankByPopularity(films, ['mission impossible dead reckoning']);
    expect(ranked.first.id, '9');
  });
}
