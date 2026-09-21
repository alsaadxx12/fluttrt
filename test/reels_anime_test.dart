import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';
import 'package:youtube_downloader/features/reels/data/reels_service.dart';
import 'package:youtube_downloader/features/reels/presentation/providers/reels_feed_provider.dart';
import 'package:youtube_downloader/features/reels/presentation/screens/reels_screen.dart';

/// The «مشاهد» feed carries the catalogue's newest anime beside its newest
/// films and series: a lane of its own, drawn one slot in four, searched
/// the way an anime's own trailer is named (a «PV», from a studio's or a
/// simulcaster's channel), and told apart on the page — «مشاهدة الأنمي» —
/// and on the device, where the lane is written into the kept page.
ReelFilm _anime(String en, {String ar = '', String? year = '2026'}) =>
    ReelFilm(titleEn: en, titleAr: ar, year: year, isSeries: true, isAnime: true);

CinemanaItem _item(String id, {String kind = '2'}) => CinemanaItem(
      id: id,
      arTitle: 'قاتل الشياطين',
      enTitle: 'Demon Slayer',
      stars: '',
      year: '2026',
      kind: kind,
      arContent: '',
      enContent: '',
      imgUrl: 'https://x/p.jpg',
    );

Reel _reel({ReelLane? lane, CinemanaItem? item}) => Reel(
      id: 'abcdefghijk',
      title: 'قاتل الشياطين (2026)',
      author: kReelTrailerAuthor,
      channelId: null,
      description: '',
      duration: const Duration(seconds: 44),
      viewCount: null,
      likeCount: null,
      uploadDate: null,
      lane: lane,
      catalogItem: item,
    );

void main() {
  group('the anime lane', () {
    test('is a lane of its own, one slot in four, the films twice a cycle', () {
      expect(ReelLane.values, [ReelLane.film, ReelLane.series, ReelLane.anime]);
      expect(kReelPagePattern, [ReelLane.film, ReelLane.series, ReelLane.film, ReelLane.anime]);
      expect(kReelPagePattern.where((l) => l == ReelLane.film), hasLength(2));
    });

    test('over a page’s eight slots: four films, two series, two anime, newest first in each', () {
      final films = [for (var i = 1; i <= 5; i++) ReelFilm(titleEn: 'f$i')];
      final series = [for (var i = 1; i <= 3; i++) ReelFilm(titleEn: 's$i', isSeries: true)];
      final anime = [for (var i = 1; i <= 3; i++) _anime('a$i')];
      final slot = [0];
      final drawn = <({ReelFilm film, ReelLane lane})>[
        for (var i = 0; i < 8; i++) drawReelFilm(films: films, series: series, anime: anime, slot: slot)!,
      ];
      expect([for (final d in drawn) d.film.titleEn], ['f1', 's1', 'f2', 'a1', 'f3', 's2', 'f4', 'a2']);
      expect(drawn.where((d) => d.lane == ReelLane.film), hasLength(4));
      expect(drawn.where((d) => d.lane == ReelLane.series), hasLength(2));
      expect(drawn.where((d) => d.lane == ReelLane.anime), hasLength(2));
      expect(drawn[3].film.isAnime, isTrue);
      expect(films.map((f) => f.titleEn), ['f5'], reason: 'what is left waits in order');
      expect(series.map((f) => f.titleEn), ['s3']);
      expect(anime.map((f) => f.titleEn), ['a3']);
    });

    test('a dry or empty anime lane is skipped, as the other two are', () {
      final films = [const ReelFilm(titleEn: 'f1'), const ReelFilm(titleEn: 'f2')];
      final slot = [0];
      final drawn = [
        for (var i = 0; i < 2; i++)
          drawReelFilm(films: films, series: [], anime: [], slot: slot)!.film.titleEn,
      ];
      expect(drawn, ['f1', 'f2']);
      expect(drawReelFilm(films: [], series: [], anime: [], slot: slot), isNull);

      final anime = [_anime('a1')];
      final onlyAnime = drawReelFilm(films: [], series: [], anime: anime, slot: [0]);
      expect(onlyAnime?.lane, ReelLane.anime);
      expect(onlyAnime?.film.titleEn, 'a1');
    });

    test('the catalogue’s anime come through as anime; its films and series do not', () {
      final fromAnime = reelFilmsFromCinemana([_item('1')], anime: true);
      expect(fromAnime.single.isAnime, isTrue);
      expect(fromAnime.single.isSeries, isTrue, reason: 'an anime is a series of the catalogue');
      expect(fromAnime.single.item?.id, '1');
      expect(reelFilmsFromCinemana([_item('2')]).single.isAnime, isFalse);
      expect(const ReelFilm(titleEn: 'x').isAnime, isFalse);
    });

    test('the cursor carries the lane: its titles, its page and its misses, and it can run dry', () {
      final cursor = ReelsCursor(
        anime: [_anime('a1'), _anime('a2')],
        animePage: 3,
        animeMisses: 1,
      );
      expect(cursor.anime.map((f) => f.titleEn), ['a1', 'a2']);
      expect(cursor.animePage, 3);
      expect(cursor.animeMisses, 1);
      expect(cursor.animeDry, isFalse);
      expect(cursor.exhausted, isFalse);

      // Handed back in as the next page's seed: it comes out unchanged.
      final again = ReelsCursor(
        anime: cursor.anime,
        animePage: cursor.animePage,
        animeMisses: ReelsCursor.laneMisses,
        filmMisses: ReelsCursor.laneMisses,
        seriesMisses: ReelsCursor.laneMisses,
      );
      expect(again.anime, same(cursor.anime));
      expect(again.animePage, 3);
      expect(again.animeDry, isTrue);
      expect(again.exhausted, isFalse, reason: 'two anime are still waiting');
      expect(
        const ReelsCursor(
          animeMisses: ReelsCursor.laneMisses,
          filmMisses: ReelsCursor.laneMisses,
          seriesMisses: ReelsCursor.laneMisses,
        ).exhausted,
        isTrue,
      );
    });
  });

  group('anime queries', () {
    test('the PV queries, then the Arabic title when it is its own', () {
      expect(reelShortQueries(_anime('Demon Slayer', ar: 'قاتل الشياطين')), [
        'Demon Slayer official trailer #shorts',
        'Demon Slayer pv shorts',
        'Demon Slayer teaser shorts',
        'Demon Slayer anime trailer shorts',
        'قاتل الشياطين إعلان',
        'قاتل الشياطين تريلر',
      ]);
    });

    test('no Arabic title of its own: the four English ones, and never the year', () {
      expect(reelShortQueries(_anime('Demon Slayer', year: '2026')), [
        'Demon Slayer official trailer #shorts',
        'Demon Slayer pv shorts',
        'Demon Slayer teaser shorts',
        'Demon Slayer anime trailer shorts',
      ]);
    });

    test('a film is asked for as before: the year as a trailer, no PV', () {
      const film = ReelFilm(titleEn: 'Dune: Part Two', year: '2024');
      expect(reelShortQueries(film), [
        'Dune: Part Two official trailer #shorts',
        'Dune: Part Two 2024 trailer shorts',
        'Dune: Part Two teaser shorts',
      ]);
    });
  });

  group('an anime’s own trailer', () {
    test('«PV» — and «promotion video» — mark a title as official, as a whole word', () {
      expect(reelHasOfficialMark('Demon Slayer | PV #shorts'), isTrue);
      expect(reelHasOfficialMark('DEMON SLAYER PV 2 #shorts'), isTrue);
      expect(reelHasOfficialMark('Demon Slayer promotion video'), isTrue);
      expect(reelHasOfficialMark('Demon Slayer promo'), isFalse);
      expect(reelHasOfficialMark('Demon Slayer TVPV'), isFalse, reason: '«pv» inside a word is not «pv»');
      expect(reelHasOfficialMark('Demon Slayer #shorts'), isFalse);
    });

    test('the anime studios, labels and networks are official channels', () {
      for (final channel in const [
        'Crunchyroll',
        'Netflix Anime',
        'Aniplex USA',
        'TOHO animation',
        'KADOKAWA anime',
        'TOEI Animation',
        'Muse Asia',
        'Ani-One Asia',
        'Bandai Namco Filmworks',
        'Avex Pictures',
        'Pony Canyon Anime',
        'KING RECORDS',
        'TV Tokyo Anime',
        'MAPPA CHANNEL',
        'WIT STUDIO',
        'ufotable',
        'Studio BONES',
        'MADHOUSE Inc.',
        'Kyoto Animation',
        'A-1 Pictures',
        'CloverWorks',
        'STUDIO TRIGGER',
        'Sunrise',
        'Production I.G',
        'Shueisha',
      ]) {
        expect(reelIsOfficialChannel(channel), isTrue, reason: '$channel is an official channel');
      }
      expect(reelIsOfficialChannel('Anime Edits HD'), isFalse);
      expect(reelIsOfficialChannel('Some Guy'), isFalse);
    });

    test('«AMV» is a fan’s edit, in the title or in the channel', () {
      expect(reelIsFanClip('Demon Slayer AMV 🔥'), isTrue);
      expect(reelIsFanClip('Demon Slayer PV', author: 'Best AMVs'), isTrue);
      expect(reelIsFanClip('Demon Slayer | PV #shorts', author: 'ufotable'), isFalse);
      expect(reelIsOfficialShort('Demon Slayer AMV', author: 'ufotable'), isFalse,
          reason: 'a fan edit, whatever the channel');
      expect(reelIsOfficialShort('Demon Slayer | PV #shorts', author: 'Muse Asia'), isTrue);
      expect(reelIsOfficialShort('Demon Slayer #shorts', author: 'MAPPA CHANNEL'), isTrue,
          reason: 'an official channel needs no tag');
      expect(reelIsOfficialShort('Demon Slayer #shorts', author: 'Some Guy'), isFalse);
    });
  });

  group('the lane on the reel', () {
    test('an anime reel knows it is one; the pill reads «مشاهدة الأنمي»', () {
      final anime = _reel(lane: ReelLane.anime, item: _item('9'));
      expect(anime.lane, ReelLane.anime);
      expect(anime.isAnime, isTrue);
      expect(anime.isSeries, isTrue, reason: 'the catalogue entry is a series');
      expect(kReelWatchAnimeLabel, 'مشاهدة الأنمي');
      expect(kReelWatchSeriesLabel, 'مشاهدة المسلسل');
      expect(kReelWatchFilmLabel, 'مشاهدة الفيلم');

      final series = _reel(lane: ReelLane.series, item: _item('9'));
      expect(series.isAnime, isFalse);
      final film = _reel(lane: ReelLane.film, item: _item('9', kind: '1'));
      expect(film.isAnime, isFalse);
      expect(film.isSeries, isFalse);
    });

    test('with no lane at all the catalogue entry decides, as the reels kept before the lanes have none', () {
      expect(_reel().lane, ReelLane.film, reason: 'no entry either: a film');
      expect(_reel(item: _item('9', kind: '1')).lane, ReelLane.film);
      expect(_reel(item: _item('9')).lane, ReelLane.series);
      expect(_reel(item: _item('9')).isAnime, isFalse);
    });

    test('the lane goes to the device and comes back, through real JSON text', () {
      for (final lane in ReelLane.values) {
        final json = reelToJson(_reel(lane: lane, item: _item('9')));
        expect(json['lane'], lane.name);
        final back = reelFromJson(jsonDecode(jsonEncode(json)) as Map<String, dynamic>);
        expect(back.lane, lane);
        expect(back.isAnime, lane == ReelLane.anime);
        expect(back.catalogItem?.id, '9');
      }
    });

    test('a kept reel with no «lane» key falls back to its entry, and junk is no lane', () {
      final json = reelToJson(_reel(lane: ReelLane.anime, item: _item('9')))..remove('lane');
      expect(reelFromJson(json).lane, ReelLane.series, reason: 'all it knows is that it is a series');
      expect(reelFromJson({'id': 'x'}).lane, ReelLane.film);
      expect(reelFromJson({'id': 'x', 'lane': 'nonsense'}).lane, ReelLane.film);
      expect(reelLaneNamed('anime'), ReelLane.anime);
      expect(reelLaneNamed('series'), ReelLane.series);
      expect(reelLaneNamed('film'), ReelLane.film);
      expect(reelLaneNamed(null), isNull);
      expect(reelLaneNamed(''), isNull);
    });
  });
}
