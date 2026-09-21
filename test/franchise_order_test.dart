import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/cinemana/data/cinemana_franchises.dart';
import 'package:youtube_downloader/features/cinemana/data/dynamic_franchises.dart';
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';

CinemanaItem part(String nb, String en, String year, {String kind = '1'}) =>
    CinemanaItem.fromJson({'nb': nb, 'en_title': en, 'ar_title': en, 'year': year, 'kind': kind});

void main() {
  group('a franchise reads newest first', () {
    test('parts come back in reverse release order', () {
      final ordered = DynamicFranchise.ordered([
        part('a', 'Alpha', '1999'),
        part('c', 'Gamma', '2021'),
        part('b', 'Beta', '2008'),
      ]);
      expect(ordered.map((p) => p.id), ['c', 'b', 'a']);
    });

    test('the end of the list is still where the series began', () {
      // Every screen that wants the franchise's first entry — the card's
      // name, the lead — reads the last element, so this has to hold.
      final ordered = DynamicFranchise.ordered([
        part('new', 'Sequel', '2024'),
        part('first', 'Original', '1994'),
      ]);
      expect(ordered.last.id, 'first');
      expect(ordered.first.id, 'new');
    });

    test('a year that will not parse sorts last, not first', () {
      final ordered = DynamicFranchise.ordered([
        part('unknown', 'Unknown', ''),
        part('old', 'Old', '1980'),
        part('new', 'New', '2020'),
      ]);
      expect(ordered.map((p) => p.id), ['new', 'old', 'unknown']);
    });

    test('same year falls back to the title, so the order never wobbles', () {
      final ordered = DynamicFranchise.ordered([
        part('b', 'Beta', '2010'),
        part('a', 'Alpha', '2010'),
      ]);
      expect(ordered.map((p) => p.id), ['a', 'b']);
    });

    test('a part listed twice appears once', () {
      final ordered = DynamicFranchise.ordered([
        part('x', 'Same', '2010'),
        part('x', 'Same', '2010'),
        part('y', 'Other', '2012'),
      ]);
      expect(ordered.map((p) => p.id), ['y', 'x']);
    });
  });

  test('a franchise needs more than two parts to be one', () {
    // A card offering a single title is not a series, and two is a pair.
    expect(DynamicFranchise.minParts, greaterThan(2));
  });

  group('the anime row takes anime only', () {
    CinemanaItem titled(String en, List<String> cats) => CinemanaItem.fromJson({
          'nb': en,
          'en_title': en,
          'ar_title': en,
          'year': '2020',
          'kind': '2',
          'categories': [for (final c in cats) {'en_title': c, 'ar_title': c}],
        });

    test('an animated title belongs', () {
      expect(
        DynamicFranchise.belongsTo(FranchiseSection.anime, titled('Oshi No Ko', ['Animation', 'Drama'])),
        isTrue,
      );
    });

    test('a live-action film of the same name does not', () {
      // This is the bug: the parts of a franchise are found by searching the
      // catalogue for the lead's keywords, and a film often shares a name.
      expect(
        DynamicFranchise.belongsTo(FranchiseSection.anime, titled('Monster', ['Horror', 'Thriller'])),
        isFalse,
      );
    });

    test('the other rows take whatever the search found', () {
      for (final s in [FranchiseSection.films, FranchiseSection.series]) {
        expect(DynamicFranchise.belongsTo(s, titled('Monster', ['Horror'])), isTrue, reason: '$s');
      }
    });
  });
}
