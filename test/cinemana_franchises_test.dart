import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/cinemana/data/cinemana_franchises.dart';
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';

CinemanaItem film(String nb, String en, String year, {String ar = '', String kind = '1'}) =>
    CinemanaItem.fromJson({'nb': nb, 'en_title': en, 'ar_title': ar.isEmpty ? en : ar, 'year': year, 'kind': kind});

FilmFranchise byId(String id) => FilmFranchise.all.firstWhere((f) => f.id == id);

void main() {
  test('every film series has at least three parts', () {
    for (final f in FilmFranchise.inSection(FranchiseSection.films)) {
      expect(f.entries.length, greaterThanOrEqualTo(3), reason: f.name);
    }
  });

  test('series entries take series, film entries take films', () {
    const f = FilmFranchise(
      id: 't',
      name: 't',
      section: FranchiseSection.anime,
      queries: [],
      entries: [
        FranchiseEntry(2002, ['Naruto'], kind: FranchiseKind.series),
        FranchiseEntry(2004, ['Naruto the Movie']),
      ],
    );
    final picked = f.pick([
      film('m', 'Naruto', '2002'), // a film with the series' name: not the series
      film('s', 'Naruto', '2002', kind: '2'),
      film('x', 'Naruto the Movie', '2004', kind: '2'), // a series with the film's name
      film('f', 'Naruto the Movie', '2004'),
    ]);
    expect(picked.map((i) => i.id), ['s', 'f']);
    expect(FilmFranchise.countLabel(picked), 'مسلسل واحد • فيلم واحد');
    expect(FilmFranchise.countLabel([for (var i = 0; i < 12; i++) film('$i', 'x', '2000')]), '12 فيلماً');
    expect(FilmFranchise.countLabel([for (var i = 0; i < 3; i++) film('$i', 'x', '2000', kind: '2')]), '3 مسلسلات');
  });

  test('only the listed films, in release order', () {
    final picked = byId('harry-potter').pick([
      film('3', 'Harry Potter and the Prisoner of Azkaban', '2004'),
      film('1', "Harry Potter and the Sorcerer's Stone", '2001'),
      film('9', 'Dirty Harry', '1971'),
      film('8', 'Miss Potter', '2006'),
      film('7', 'Harry Potter 20th Anniversary: Return to Hogwarts', '2021'),
    ]);
    expect(picked.map((f) => f.id), ['1', '3']);
  });

  test('keyword look-alikes, wrong years and series are left out', () {
    final picked = byId('batman').pick([
      film('1', 'Batman', '1989'),
      film('2', 'Batman: Year One', '2011'),
      film('3', 'The LEGO Batman Movie', '2017'),
      film('4', 'The Dark Knight', '2008'),
      film('5', 'Batman', '1966'), // same title, other film
      film('6', 'The Batman', '2004', kind: '2'), // the cartoon series
      film('7', 'The Batman', '2022'),
    ]);
    expect(picked.map((f) => f.id), ['1', '4', '7']);
    final bond = byId('james-bond').pick([film('a', 'Casino Royale', '1967'), film('b', 'Casino Royale', '2006')]);
    expect(bond.map((f) => f.id), ['b']);
  });

  test('spelling variants match; the original beats a dubbed copy', () {
    final ff = byId('fast-furious').pick([film('1', 'The Fast and the Furious Tokyo Drift', '2006')]);
    expect(ff, hasLength(1));
    final sm = byId('spider-man').pick([
      film('dub', 'سبايدر مان: في عالم العنكبوت', '2018', ar: 'Spider-Man: Into the Spider-Verse'),
      film('orig', 'Spider-Man: Into the Spider-Verse ', '2018'),
    ]);
    expect(sm.map((f) => f.id), ['orig']);
    final alien = byId('alien').pick([film('2', 'Alien 2', '1986', ar: 'Aliens 2'), film('3', 'Alien 3', '1992', ar: 'Alien³')]);
    expect(alien, hasLength(2));
  });
}
