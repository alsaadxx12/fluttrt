import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/cinemana/data/cinemana_franchises.dart';
import 'package:youtube_downloader/features/cinemana/data/dynamic_franchises.dart';
import 'package:youtube_downloader/features/cinemana/data/services/cinemana_service.dart';

/// Live probe (network): the endless franchise feeds must actually yield
/// cards. If popular films rarely have detectable related parts, the films
/// row would sit empty — this catches that before a build.
void main() {
  // No TestWidgetsFlutterBinding here: it installs a mock HttpClient that
  // fails every real request with 400, which the service swallows into [].
  // This probe needs the real network, like the repo's other live tests.

  test('anime feed: first page yields anime series cards', () async {
    final s = CinemanaService();
    final page = await s.fetchContent(kind: 'anime', orderby: 'views', videoKind: 2, page: 0);
    // ignore: avoid_print
    print('anime page0: ${page.length} series (e.g. ${page.take(3).map((e) => e.displayTitle).join(' | ')})');
    expect(page.length, greaterThan(10));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('films feed: popular films with related parts exist and dedupe', () async {
    final s = CinemanaService();
    final page = await s.fetchContent(kind: 'movies', orderby: 'views', page: 0);
    expect(page.isNotEmpty, isTrue);
    var withParts = 0;
    final names = <String>[];
    for (final it in page.take(12)) {
      final rel = await s.fetchFranchiseParts(it);
      if (rel.isNotEmpty) {
        withParts++;
        names.add('${DynamicFranchise.nameOf(it)} (+${rel.length})');
      }
    }
    // ignore: avoid_print
    print('films page0: $withParts/12 have related parts -> $names');
    expect(withParts, greaterThan(0), reason: 'the films row would be empty');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('curated seed resolves for films and anime', () async {
    final s = CinemanaService();
    for (final section in [FranchiseSection.films, FranchiseSection.anime]) {
      final curated = FilmFranchise.inSection(section);
      final first = await s.fetchFranchise(curated.first);
      // ignore: avoid_print
      print('$section seed "${curated.first.name}": ${first.length} parts');
      expect(first.isNotEmpty, isTrue);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
