import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';
import 'package:youtube_downloader/features/reels/data/reel_text.dart';
import 'package:youtube_downloader/features/reels/data/reels_service.dart';

Reel _reel(String id, {String title = '', String author = 'Channel'}) => Reel(
      id: id,
      title: title.isEmpty ? 'Reel $id' : title,
      author: author,
      channelId: 'UC$id',
      description: '',
      duration: null,
      viewCount: 0,
      likeCount: null,
      uploadDate: null,
    );

/// A search hit as YouTube's answer is read: a regular video with a printed
/// length ([seconds] below zero means none was printed: a live stream), or
/// — [short] — one off the Shorts shelf, which prints no length.
ReelSearchHit _hit(String id, String title, {int seconds = 30, String author = 'Channel', bool short = false}) =>
    ReelSearchHit(
      id: id,
      title: title,
      author: author,
      duration: seconds < 0 ? null : Duration(seconds: seconds),
      viewCount: 0,
      short: short,
    );

ReelFilm _film(String title, {String ar = '', String? year = '2024'}) =>
    ReelFilm(titleEn: title, titleAr: ar, year: year, poster: 'https://x/p.jpg');

List<String> _ids(Iterable<Reel> items) => [for (final r in items) r.id];
List<String> _vids(Iterable<ReelSearchHit> items) => [for (final v in items) v.id];

const ReelFilm _dune = ReelFilm(
  titleEn: 'Dune: Part Two',
  titleAr: 'الكثيب: الجزء الثاني',
  year: '2024',
  poster: 'https://image.tmdb.org/t/p/w780/p.jpg',
  overview: 'وصف',
);

void main() {
  group('noise filter', () {
    test('flags the obvious non-film words, whatever the case', () {
      expect(isFilmNoise('Batman Arkham GAMEPLAY walkthrough'), isTrue);
      expect(isFilmNoise('My Reaction to the Oppenheimer trailer'), isTrue);
      expect(isFilmNoise('Blender tutorial: movie scene'), isTrue);
      expect(isFilmNoise('Unboxing the Dune steelbook'), isTrue);
      expect(isFilmNoise('cinema vlog'), isTrue);
      expect(isFilmNoise('film podcast ep. 12'), isTrue);
      expect(isFilmNoise('asmr movie theatre'), isTrue);
      expect(isFilmNoise('Interstellar theme (Lyrics)'), isTrue);
      expect(isFilmNoise('Official Music Video'), isTrue);
      expect(isFilmNoise('Weapons (2025) REVIEW #shorts'), isTrue);
      expect(isFilmNoise('Weapons ending explained'), isTrue);
      expect(isFilmNoise('Dune recaps #shorts'), isTrue, reason: 'a plural is the same word');
      expect(isFilmNoise('Fans REACT to the trailer'), isTrue);
      expect(isFilmNoise('ردة فعل على فيلم'), isTrue);
    });

    test('leaves film clips alone; a word inside another word is not that word', () {
      expect(isFilmNoise('إعلان فيلم الجوكر'), isFalse);
      expect(isFilmNoise('The Dark Knight — Official Trailer'), isFalse);
      expect(isFilmNoise('Dune: Part Two | Official Trailer'), isFalse);
      expect(isFilmNoise('Dune: Part Two | Official Preview #shorts'), isFalse, reason: '«preview» is not «review»');
      expect(isFilmNoise('Reactor scene #shorts'), isFalse, reason: '«reactor» is not «react»');
      expect(isFilmNoise(''), isFalse);
    });

    test('a news channel is noise whatever its title says; a film channel is not', () {
      expect(isFilmNoise('إلى أي مدى ينتشر إدمان مشاهدة الأفلام', author: 'BBC News عربي'), isTrue);
      expect(isFilmNoise('تقرير عن فيلم', author: 'قناة أخبار الآن'), isTrue);
      expect(isFilmNoise('clip', author: 'Sky News'), isTrue);
      expect(isFilmNoise('Anchorman - News Team Fight Trailer', author: 'Movieclips'), isFalse,
          reason: '«news» in a title is not noise');
      expect(isFilmNoise('trailer', author: 'Netflix India'), isFalse);
    });
  });

  group('reelNormalizeTitle', () {
    test('lower-case, punctuation to spaces, articles dropped when two words remain', () {
      expect(reelNormalizeTitle('Dune: Part Two'), 'dune part two');
      expect(reelNormalizeTitle('DUNE — Part Two #shorts!!'), 'dune part two shorts');
      expect(reelNormalizeTitle('Mission: Impossible – The Final Reckoning'), 'mission impossible final reckoning');
      expect(reelNormalizeTitle('The Batman'), 'the batman', reason: 'one word alone would not name the film');
      expect(reelNormalizeTitle('The'), 'the');
      expect(reelNormalizeTitle(''), '');
    });

    test('«&» reads as «and», which is then dropped like the other articles', () {
      expect(reelNormalizeTitle('Fast & Furious'), 'fast furious');
      expect(reelNormalizeTitle('Fast and Furious'), reelNormalizeTitle('Fast & Furious'));
    });

    test('Latin accents fold to plain letters', () {
      expect(reelNormalizeTitle('Amélie'), 'amelie');
      expect(reelNormalizeTitle('Léon: The Professional'), 'leon professional');
      expect(reelNormalizeTitle('Þór'), 'þor', reason: 'a letter with no plain form stays');
    });

    test('Arabic diacritics go, the alef, ta marbuta and alef maqsura forms unify', () {
      expect(reelNormalizeTitle('الكَثِيب: الجزء الثاني'), 'الكثيب الجزء الثاني');
      expect(reelNormalizeTitle('أفلام'), reelNormalizeTitle('افلام'));
      expect(reelNormalizeTitle('آفاق'), 'افاق');
      expect(reelNormalizeTitle('مدرسة'), 'مدرسه');
      expect(reelNormalizeTitle('مصطفى'), 'مصطفي');
      expect(reelNormalizeTitle('فيـــلم'), 'فيلم', reason: 'the tatweel is dropped');
    });
  });

  group('reelTitleParts', () {
    test('the subtitle parts of a subtitled title that can stand alone: two words, eight letters; never the first',
        () {
      expect(reelTitleParts('Mission: Impossible – The Final Reckoning'), ['final reckoning']);
      expect(reelTitleParts('Dune: Part Two'), isEmpty, reason: '«dune» is one word, «part two» too short');
      expect(reelTitleParts('Spider-Man: Across the Spider-Verse'), ['across spider verse'],
          reason: '«spider man» is the franchise, shared with every other Spider-Man');
      expect(reelTitleParts('Turning Point: Generation 9/11'), ['generation 9 11']);
      expect(reelTitleParts('Oppenheimer'), isEmpty);
      expect(reelTitleParts('The Batman | Official Trailer'), ['official trailer'],
          reason: 'the article stays when it is one of only two words');
    });
  });

  group('reelTitleMatch', () {
    test('the film’s title as whole words, in either language, however it is punctuated', () {
      expect(reelTitleMatches('DUNE PART TWO - Official Trailer #shorts', _dune.names), isTrue);
      expect(reelTitleMatch('DUNE PART TWO - Official Trailer #shorts', _dune.names), 'dune part two');
      expect(reelTitleMatches('dune: part two 🔥 #Shorts', _dune.names), isTrue);
      expect(reelTitleMatches('إعلان فيلم الكثيب الجزء الثاني', _dune.names), isTrue);
      expect(reelTitleMatch('إعلان فيلم الكثيب الجزء الثاني', _dune.names), 'الكثيب الجزء الثاني');
      expect(reelTitleMatches('الكَثيب: الجزء الثاني - مشهد', _dune.names), isTrue);
    });

    test('a word inside another word, another film, or nothing at all is no match', () {
      expect(reelTitleMatches('Sandune part two', _dune.names), isFalse);
      expect(reelTitleMatch('Sandune part two', _dune.names), isNull);
      expect(reelTitleMatches('Dune Awakening gameplay', _dune.names), isFalse);
      expect(reelTitleMatches('Oppenheimer #shorts', _dune.names), isFalse);
      expect(reelTitleMatches('', _dune.names), isFalse);
      expect(reelTitleMatches('Dune Part Two', const ['']), isFalse);
    });

    test('a subtitled title matches whole (articles aside) or by its subtitle; the franchise alone is another film',
        () {
      const names = ['Mission: Impossible – The Final Reckoning'];
      expect(reelTitleMatches('Mission Impossible Final Reckoning #shorts', names), isTrue);
      expect(reelTitleMatches('The Final Reckoning – best scene #shorts', names), isTrue);
      expect(reelTitleMatches('Mission Impossible Fallout #shorts', names), isFalse);
      const turning = ['Turning Point: Generation 9/11', 'نقطة التحوّل: جيل ما بعد 11 سبتمبر'];
      expect(reelTitleMatches('Turning Point: The Vietnam War (2025) | Official Trailer #shorts', turning), isFalse,
          reason: 'the same franchise, another film');
      expect(reelTitleMatches('Turning Point: Generation 9/11 | Official Trailer', turning), isTrue);
      expect(reelTitleMatches('Generation 9/11 — official trailer', turning), isTrue);
      const verse = ['Spider-Man: Across the Spider-Verse'];
      expect(reelTitleMatches('Spider-Man: No Way Home #shorts', verse), isFalse);
      expect(reelTitleMatches('Across the Spider-Verse | trailer', verse), isTrue);
    });

    test('the longest name wins when more than one fits', () {
      const names = ['Dune', 'Dune: Part Two'];
      expect(reelTitleMatch('Dune Part Two official trailer', names), 'dune part two');
      expect(reelTitleMatch('Dune official trailer', names), 'dune');
    });
  });

  group('reelPinsFilm', () {
    test('«trailer», «تريلر», or «إعلان» with «فيلم» or «مسلسل» pin a one-word name; «official» or «teaser» do not', () {
      expect(reelPinsFilm('SAIPAN | Official Trailer'), isTrue);
      expect(reelPinsFilm('Couture (2025) trailer #shorts'), isTrue);
      expect(reelPinsFilm('تريلر سايبان'), isTrue);
      expect(reelPinsFilm('إعلان فيلم الاختيار'), isTrue);
      expect(reelPinsFilm('الإعلان الرسمي لمسلسل الاختيار'), isTrue);
      expect(reelPinsFilm('BATTLE FOR SAIPAN #shorts'), isFalse);
      expect(reelPinsFilm('LEVER COUTURE Fall Winter 2025 2026 Teaser #shorts #couture'), isFalse);
      expect(reelPinsFilm('Couture official #shorts'), isFalse);
      expect(reelPinsFilm('إعلان الاختيار'), isFalse, reason: 'an «إعلان» of anything');
      expect(reelPinsFilm(''), isFalse);
    });
  });

  group('reelShortQueries', () {
    test('official trailer «#shorts», the year as a trailer, a teaser, then the Arabic title with «إعلان» and «تريلر»',
        () {
      expect(reelShortQueries(_dune), [
        'Dune: Part Two official trailer #shorts',
        'Dune: Part Two 2024 trailer shorts',
        'Dune: Part Two teaser shorts',
        'الكثيب: الجزء الثاني إعلان',
        'الكثيب: الجزء الثاني تريلر',
      ]);
    });

    test('no year and no Arabic title: two queries', () {
      expect(reelShortQueries(_film('Film', year: null)), ['Film official trailer #shorts', 'Film teaser shorts']);
    });

    test('an Arabic title that is the English one again adds nothing', () {
      expect(reelShortQueries(const ReelFilm(titleEn: 'Same', titleAr: 'Same')), [
        'Same official trailer #shorts',
        'Same teaser shorts',
      ]);
    });

    test('an Arabic-only film searches by its Arabic title throughout', () {
      expect(reelShortQueries(const ReelFilm(titleEn: '', titleAr: 'فيلم', year: '2025')), [
        'فيلم official trailer #shorts',
        'فيلم 2025 trailer shorts',
        'فيلم teaser shorts',
        'فيلم إعلان',
        'فيلم تريلر',
      ]);
    });
  });

  group('official filter', () {
    test('a title tagged as a trailer, a teaser, official, or the Arabic words', () {
      expect(reelHasOfficialMark('Dune: Part Two | Official Trailer'), isTrue);
      expect(reelHasOfficialMark('Dune Part Two TEASER #shorts'), isTrue);
      expect(reelHasOfficialMark('Dune Part Two official #shorts'), isTrue);
      expect(reelHasOfficialMark('إعلان فيلم الكثيب'), isTrue);
      expect(reelHasOfficialMark('الإعلان الرسمي لفيلم الكثيب'), isTrue, reason: 'an Arabic word with its prefixes');
      expect(reelHasOfficialMark('تريلر مسلسل الاختيار'), isTrue);
      expect(reelHasOfficialMark('اعلان فيلم'), isTrue);
      expect(reelHasOfficialMark('Dune Part Two #shorts'), isFalse);
      expect(reelHasOfficialMark('Dune Part Two trailers'), isTrue, reason: 'a plural is the same word');
      expect(reelHasOfficialMark(''), isFalse);
    });

    test('a channel that reads like a studio, a network or a streaming service', () {
      expect(reelIsOfficialChannel('Warner Bros. Pictures'), isTrue);
      expect(reelIsOfficialChannel('Marvel Entertainment'), isTrue);
      expect(reelIsOfficialChannel('Netflix'), isTrue);
      expect(reelIsOfficialChannel('A24'), isTrue);
      expect(reelIsOfficialChannel('DC'), isTrue);
      expect(reelIsOfficialChannel('HBO Max'), isTrue);
      expect(reelIsOfficialChannel('Prime Video'), isTrue);
      expect(reelIsOfficialChannel('Shahid شاهد'), isTrue);
      expect(reelIsOfficialChannel('Lionsgate Films'), isTrue);
      expect(reelIsOfficialChannel('Neon Film'), isTrue, reason: '«films» finds the singular');
      expect(reelIsOfficialChannel('Some Guy'), isFalse);
      expect(reelIsOfficialChannel('Movieclips'), isFalse);
      expect(reelIsOfficialChannel('Film Podcast'), isTrue, reason: '«dc» inside «podcast» is not «dc», «film» is');
      expect(reelIsOfficialChannel('The Podcast'), isFalse);
      expect(reelIsOfficialChannel(''), isFalse, reason: 'an unknown channel is not an official one');
    });

    test('fan words as whole words; «part » only with a number after it; Arabic anywhere', () {
      expect(reelIsFanClip('dune part two edit 🔥'), isTrue);
      expect(reelIsFanClip('Dune Part Two edits'), isTrue);
      expect(reelIsFanClip('Dune Part Two Trailer REACTION'), isTrue);
      expect(reelIsFanClip('Dune Part Two whatsapp status'), isTrue);
      expect(reelIsFanClip('Dune Part Two scene pack'), isTrue);
      expect(reelIsFanClip('Dune Part Two clip'), isTrue);
      expect(reelIsFanClip('Movie part 3'), isTrue, reason: 'a clip cut into numbered parts');
      expect(reelIsFanClip('Dune: Part Two official trailer'), isFalse, reason: '«Part Two» is the film');
      expect(reelIsFanClip('The Fantastic Four: First Steps'), isFalse, reason: '«fan» inside «fantastic»');
      expect(reelIsFanClip('Dune: Part Two | Official Preview'), isFalse, reason: '«review» inside «preview»');
      expect(reelIsFanClip('Reactor scene'), isFalse, reason: '«react» inside «reactor»');
      expect(reelIsFanClip('Special Edition trailer'), isFalse, reason: '«edit» inside «edition»');
      expect(reelIsFanClip('مقطع مضحك من فيلم الكثيب'), isTrue);
      expect(reelIsFanClip('الترند: الكثيب'), isTrue);
      expect(reelIsFanClip('trailer', author: 'Dune Fan Edits'), isTrue, reason: 'the channel counts too');
      expect(reelIsFanClip('trailer', author: 'Fandango'), isFalse);
      expect(reelIsFanClip(''), isFalse);
    });

    test('the rule: the title’s own trailer — tagged or from an official channel — and no fan word anywhere', () {
      expect(reelIsOfficialShort('Dune Part Two Official Trailer #shorts', author: 'Warner Bros. Pictures'), isTrue);
      expect(reelIsOfficialShort('dune part two edit 🔥', author: 'random clips'), isFalse);
      expect(reelIsOfficialShort('Dune Part Two Trailer REACTION', author: 'Some Guy'), isFalse);
      expect(reelIsOfficialShort('إعلان فيلم الكثيب الجزء الثاني'), isTrue);
      expect(reelIsOfficialShort('Dune Part Two #shorts', author: 'Warner Bros. Pictures'), isTrue,
          reason: 'an official channel needs no tag');
      expect(reelIsOfficialShort('Dune Part Two #shorts', author: 'Some Guy'), isFalse);
      expect(reelIsOfficialShort('Dune Part Two #shorts'), isFalse, reason: 'no tag and no channel');
      expect(reelIsOfficialShort('Dune Part Two Official Trailer', author: 'Dune Fan Edits'), isFalse,
          reason: 'a fan channel, whatever the title says');
      expect(reelIsOfficialShort('Dune Part Two trailer', author: 'Sky News'), isFalse, reason: 'noise');
      expect(reelIsOfficialShort('Dune Part Two trailer explained'), isFalse);
      expect(reelIsOfficialShort('The Fantastic Four: First Steps | Official Trailer', author: 'Marvel Entertainment'),
          isTrue);
      expect(reelIsOfficialShort('Movie part 3 official trailer'), isFalse, reason: 'a numbered part');
      expect(reelIsOfficialShort('تريلر مسلسل الاختيار الرسمي', author: 'Shahid شاهد'), isTrue);
      expect(reelIsOfficialShort('مقطع مضحك من فيلم الكثيب'), isFalse);
    });
  });

  group('ReelSearchHit', () {
    test('may be a Short: listed as one, or printed with a length inside the minute', () {
      expect(_hit('a', 'x', seconds: 60).mayBeShort, isTrue);
      expect(_hit('a', 'x', seconds: 61).mayBeShort, isFalse);
      expect(_hit('a', 'x', seconds: 0).mayBeShort, isFalse);
      expect(_hit('a', 'x', seconds: -1).mayBeShort, isFalse, reason: 'a regular video with no length is live');
      expect(_hit('a', 'x', seconds: -1, short: true).mayBeShort, isTrue, reason: 'the shelf prints no length');
      expect(_hit('a', 'x', seconds: 90, short: true).mayBeShort, isFalse, reason: 'a printed length still counts');
    });
  });

  group('reelShortCandidates', () {
    final hits = [
      _hit('aaaaaaaaaa1', 'Dune Part Two scene', seconds: 40),
      _hit('aaaaaaaaaa2', 'Dune: Part Two | Official Trailer #shorts', seconds: 30),
      _hit('aaaaaaaaaa3', 'Dune Part Two trailer', seconds: 120),
      _hit('aaaaaaaaaa4', 'Dune Part Two trailer reaction', seconds: 30),
      _hit('aaaaaaaaaa5', 'Oppenheimer official trailer #shorts', seconds: 20),
      _hit('aaaaaaaaaa6', 'Dune Part Two trailer live', seconds: -1),
      _hit('aaaaaaaaaa7', 'Dune Part Two trailer edit', seconds: 59),
      _hit('aaaaaaaaaa2', 'Dune: Part Two | Official Trailer #shorts (again)', seconds: 30),
      _hit('aaaaaaaaaa8', 'dune part two', seconds: -1, short: true, author: ''),
      _hit('aaaaaaaaaa9', 'Dune Part Two trailer', seconds: 60, author: 'Sky News'),
      _hit('aaaaaaaaab1', 'Dune Part Two trailer', seconds: 61),
      _hit('aaaaaaaaab2', 'Dune Part Two — the worm', seconds: 60, author: 'Warner Bros. Pictures'),
      _hit('aaaaaaaaab3', 'Dune Part Two — the worm', seconds: 60, author: 'Some Guy'),
      _hit('aaaaaaaaab4', 'Dune Part Two Teaser', seconds: 45),
    ];

    test(
        'official channel first, then the tagged titles, then the unknown channels (for the probe to tell); '
        'a plain clip from a known channel, a fan edit, a reaction, a news channel, a long or live one: dropped',
        () {
      expect(
        _vids(reelShortCandidates(hits, _dune)),
        ['aaaaaaaaab2', 'aaaaaaaaaa2', 'aaaaaaaaab4', 'aaaaaaaaaa8'],
      );
    });

    test('honours the limit', () {
      expect(_vids(reelShortCandidates(hits, _dune, limit: 2)), ['aaaaaaaaab2', 'aaaaaaaaaa2']);
      expect(reelShortCandidates(hits, _dune, limit: 0), isEmpty);
    });

    test('nothing for a film none of the titles carry', () {
      expect(reelShortCandidates(hits, _film('Oppenheimer')), hasLength(1));
      expect(reelShortCandidates(hits, _film('Weapons')), isEmpty);
    });

    test('within a standing a frame shown upright goes first; one shown wider than tall is not probed at all', () {
      const upright = ReelSearchHit(
        id: 'aaaaaaaaac1',
        title: 'Dune Part Two — the worm',
        short: true,
        frameWidth: 1080,
        frameHeight: 1920,
      );
      const wide = ReelSearchHit(
        id: 'aaaaaaaaac2',
        title: 'Dune Part Two Official Trailer #shorts',
        short: true,
        frameWidth: 1920,
        frameHeight: 1080,
      );
      expect(upright.portraitHint, isTrue);
      expect(upright.landscapeHint, isFalse);
      expect(wide.landscapeHint, isTrue);
      expect(const ReelSearchHit(id: 'x', title: 'x').portraitHint, isFalse, reason: 'no frame, no hint');
      expect(
        _vids(reelShortCandidates([...hits, wide, upright], _dune)),
        ['aaaaaaaaab2', 'aaaaaaaaaa2', 'aaaaaaaaab4', 'aaaaaaaaac1', 'aaaaaaaaaa8'],
      );
    });

    test('a one-word name is not enough: the title must say «trailer» (a battle and a fashion show share the name)',
        () {
      final saipan = _film('Saipan', year: '2025');
      final couture = _film('Couture', year: '2025');
      final oneWord = [
        _hit('aaaaaaaaad1', 'BATTLE FOR SAIPAN #shorts', seconds: 30, author: 'Defiant Screen Entertainment'),
        _hit('aaaaaaaaad2', 'SAIPAN | Official Trailer #shorts', seconds: 30, author: 'Some Guy'),
        _hit('aaaaaaaaad3', 'Saipan official #shorts', seconds: 30, author: 'Lionsgate Films'),
        _hit('aaaaaaaaad4', 'LEVER COUTURE Fall Winter 2025 2026 Teaser #shorts #couture', seconds: 30, author: ''),
        _hit('aaaaaaaaad5', 'Couture (2025) Official Trailer #shorts', seconds: 30, author: ''),
        _hit('aaaaaaaaad6', 'إعلان فيلم Couture', seconds: 30, author: ''),
      ];
      expect(_vids(reelShortCandidates(oneWord, saipan)), ['aaaaaaaaad2'],
          reason: 'the war film and the untagged short from a studio are out; the trailer is in');
      expect(_vids(reelShortCandidates(oneWord, couture)), ['aaaaaaaaad5', 'aaaaaaaaad6'],
          reason: 'the fashion show is out');
      expect(_vids(reelShortCandidates(oneWord, _film('Saipan', ar: 'سايبان', year: '2025'))), ['aaaaaaaaad2']);
    });

    test('a hit takes the probe’s channel only when the search printed none', () {
      final shelf = _hit('aaaaaaaaaa8', 'dune part two', seconds: -1, short: true, author: '');
      expect(shelf.withChannel(' Warner Bros. Pictures ').author, 'Warner Bros. Pictures');
      expect(shelf.withChannel('').author, '');
      expect(identical(shelf.withChannel(''), shelf), isTrue);
      final known = _hit('aaaaaaaaaa2', 'x', author: 'Channel');
      expect(identical(known.withChannel('Other'), known), isTrue);
      expect(known.withChannel('Other').author, 'Channel');
      final filled = shelf.withChannel('WB');
      expect(filled.id, shelf.id);
      expect(filled.short, isTrue);
      expect(filled.title, shelf.title);
    });
  });

  group('parseReelDuration', () {
    test('minutes and seconds, hours too; anything else is nothing', () {
      expect(parseReelDuration('0:45'), const Duration(seconds: 45));
      expect(parseReelDuration('3:24'), const Duration(minutes: 3, seconds: 24));
      expect(parseReelDuration('1:02:03'), const Duration(hours: 1, minutes: 2, seconds: 3));
      expect(parseReelDuration(' 1:00 '), const Duration(minutes: 1));
      expect(parseReelDuration('45'), isNull);
      expect(parseReelDuration('LIVE'), isNull);
      expect(parseReelDuration('1:x'), isNull);
      expect(parseReelDuration(''), isNull);
    });
  });

  group('parseReelViewCount', () {
    test('plain, compact and spelt-out counts; none is null', () {
      expect(parseReelViewCount('3,591,250 views'), 3591250);
      expect(parseReelViewCount('2.7M views'), 2700000);
      expect(parseReelViewCount('2.7 million views'), 2700000);
      expect(parseReelViewCount('12K views'), 12000);
      expect(parseReelViewCount('1.1B views'), 1100000000);
      expect(parseReelViewCount('No views'), 0);
      expect(parseReelViewCount('875 views'), 875);
      expect(parseReelViewCount(''), isNull);
      expect(parseReelViewCount('views'), isNull);
    });
  });

  group('parseReelSearch', () {
    final answer = {
      'contents': {
        'twoColumnSearchResultsRenderer': {
          'primaryContents': {
            'sectionListRenderer': {
              'contents': [
                {
                  'itemSectionRenderer': {
                    'contents': [
                      {
                        'videoRenderer': {
                          'videoId': 'ofRdPtkUmJ4',
                          'title': {
                            'runs': [
                              {'text': 'Dune: Part Two (2024) 4K - '},
                              {'text': "Paul's Speech"},
                            ],
                          },
                          'ownerText': {
                            'runs': [
                              {'text': 'Movieclips'},
                            ],
                          },
                          'lengthText': {'simpleText': '3:24'},
                          'viewCountText': {'simpleText': '3,591,250 views'},
                        },
                      },
                      {
                        'reelShelfRenderer': {
                          'items': [
                            {
                              'shortsLockupViewModel': {
                                'entityId': 'shorts-shelf-item-_LoFHSII58M',
                                'accessibilityText':
                                    'Paul Atreides “Silence”🥶Dune:Part 2 #dune2 #shorts, 2.7 million views - play Short',
                                'onTap': {
                                  'innertubeCommand': {
                                    'reelWatchEndpoint': {
                                      'videoId': '_LoFHSII58M',
                                      'thumbnail': {
                                        'thumbnails': [
                                          {'url': 'https://i.ytimg.com/vi/_LoFHSII58M/frame0.jpg', 'width': 1080, 'height': 1920},
                                        ],
                                        'isOriginalAspectRatio': true,
                                      },
                                    },
                                  },
                                },
                                'overlayMetadata': {
                                  'primaryText': {'content': 'Paul Atreides “Silence”🥶Dune:Part 2 #dune2 #shorts'},
                                  'secondaryText': {'content': '2.7M views'},
                                },
                              },
                            },
                            {
                              'shortsLockupViewModel': {
                                'entityId': 'shorts-shelf-item-aaaaaaaaaa1',
                                'accessibilityText': 'From the entity id, 875 views - play Short',
                              },
                            },
                            {
                              'reelItemRenderer': {
                                'videoId': 'aaaaaaaaaa2',
                                'headline': {'simpleText': 'An older shelf item'},
                                'viewCountText': {'simpleText': '12K views'},
                              },
                            },
                            {
                              'shortsLockupViewModel': {'entityId': 'shorts-shelf-item-bad', 'accessibilityText': 'x'},
                            },
                          ],
                        },
                      },
                      {
                        'videoRenderer': {
                          'videoId': 'aaaaaaaaaa3',
                          'title': {'simpleText': 'A live stream'},
                          'longBylineText': {
                            'runs': [
                              {'text': 'Some channel'},
                            ],
                          },
                        },
                      },
                      {
                        'videoRenderer': {'videoId': 'short', 'title': {'simpleText': 'Bad id'}},
                      },
                    ],
                  },
                },
                {
                  'continuationItemRenderer': {
                    'continuationEndpoint': {
                      'continuationCommand': {'token': 'NEXT'},
                    },
                  },
                },
              ],
            },
          },
        },
      },
    };

    test('the Shorts shelf and the regular videos, in order, and the continuation', () {
      final (:hits, :continuation) = parseReelSearch(answer);
      expect(continuation, 'NEXT');
      expect(_vids(hits), ['ofRdPtkUmJ4', '_LoFHSII58M', 'aaaaaaaaaa1', 'aaaaaaaaaa2', 'aaaaaaaaaa3']);

      final clip = hits[0];
      expect(clip.title, "Dune: Part Two (2024) 4K - Paul's Speech");
      expect(clip.author, 'Movieclips');
      expect(clip.duration, const Duration(minutes: 3, seconds: 24));
      expect(clip.viewCount, 3591250);
      expect(clip.short, isFalse);
      expect(clip.mayBeShort, isFalse);

      final short = hits[1];
      expect(short.title, 'Paul Atreides “Silence”🥶Dune:Part 2 #dune2 #shorts');
      expect(short.author, '');
      expect(short.duration, isNull);
      expect(short.viewCount, 2700000);
      expect(short.short, isTrue);
      expect(short.mayBeShort, isTrue);
      expect(short.frameWidth, 1080);
      expect(short.frameHeight, 1920);
      expect(short.portraitHint, isTrue);

      final fromEntity = hits[2];
      expect(fromEntity.title, 'From the entity id', reason: 'the accessibility text minus its tail');
      expect(fromEntity.viewCount, 875);
      expect(fromEntity.short, isTrue);
      expect(fromEntity.frameWidth, 0, reason: 'no frame given');
      expect(fromEntity.portraitHint, isFalse);

      expect(hits[3].title, 'An older shelf item');
      expect(hits[3].viewCount, 12000);
      expect(hits[3].short, isTrue);

      final live = hits[4];
      expect(live.author, 'Some channel');
      expect(live.duration, isNull);
      expect(live.mayBeShort, isFalse);
    });

    test('a continuation answer, and an empty one', () {
      final (:hits, :continuation) = parseReelSearch({
        'onResponseReceivedCommands': [
          {
            'appendContinuationItemsAction': {
              'continuationItems': [
                {
                  'videoRenderer': {
                    'videoId': 'aaaaaaaaaa4',
                    'title': {'simpleText': 'Next'},
                    'lengthText': {'simpleText': '0:30'},
                  },
                },
              ],
            },
          },
        ],
      });
      expect(_vids(hits), ['aaaaaaaaaa4']);
      expect(hits.single.duration, const Duration(seconds: 30));
      expect(continuation, isNull);
      expect(parseReelSearch(const {}).hits, isEmpty);
    });
  });

  group('dedupReels', () {
    test('removes ids already handed out and repeats inside the batch', () {
      final seen = <String>{'old'};
      final out = dedupReels(
        [_reel('old'), _reel('a'), _reel('b'), _reel('a'), _reel('')],
        seen,
      );
      expect(_ids(out), ['a', 'b']);
      expect(seen, {'old', 'a', 'b'});
    });
  });

  group('kReelPagePattern', () {
    test('film, series, film, anime: the newest films twice for every series and every anime', () {
      expect(kReelPagePattern, [ReelLane.film, ReelLane.series, ReelLane.film, ReelLane.anime]);
      expect(ReelLane.values, [ReelLane.film, ReelLane.series, ReelLane.anime]);
      expect(kReelsPageSize, 8);
      expect(kReelShortMaxDuration, const Duration(seconds: 60));
      expect(ReelsService.filmsPerFetch, 24);
      expect(ReelsService.seriesPerFetch, 12);
      expect(ReelsService.animePerFetch, 12);
    });
  });

  group('drawReelFilm', () {
    test('follows the pattern film, series, film, anime, consuming the lanes in place', () {
      final films = [for (var i = 1; i <= 4; i++) _film('f$i')];
      final series = [for (var i = 1; i <= 2; i++) _film('s$i')];
      final anime = [for (var i = 1; i <= 2; i++) _film('a$i')];
      final slot = [0];
      final drawn = <String>[];
      final lanes = <ReelLane>[];
      while (true) {
        final d = drawReelFilm(films: films, series: series, anime: anime, slot: slot);
        if (d == null) break;
        drawn.add(d.film.titleEn);
        lanes.add(d.lane);
      }
      expect(drawn, ['f1', 's1', 'f2', 'a1', 'f3', 's2', 'f4', 'a2']);
      expect(lanes, [
        ReelLane.film,
        ReelLane.series,
        ReelLane.film,
        ReelLane.anime,
        ReelLane.film,
        ReelLane.series,
        ReelLane.film,
        ReelLane.anime,
      ]);
      expect(films, isEmpty);
      expect(series, isEmpty);
      expect(anime, isEmpty);
    });

    test('a page’s worth keeps the interleave, newest first in each lane', () {
      final films = [for (var i = 1; i <= 8; i++) _film('f$i')];
      final series = [for (var i = 1; i <= 4; i++) _film('s$i')];
      final anime = [for (var i = 1; i <= 2; i++) _film('a$i')];
      final slot = [0];
      final drawn = [
        for (var i = 0; i < 9; i++)
          drawReelFilm(films: films, series: series, anime: anime, slot: slot)!.film.titleEn,
      ];
      expect(drawn, ['f1', 's1', 'f2', 'a1', 'f3', 's2', 'f4', 'a2', 'f5']);
      expect(films.map((f) => f.titleEn), ['f6', 'f7', 'f8'], reason: 'the rest waits, in order');
      expect(series.map((f) => f.titleEn), ['s3', 's4']);
      expect(anime, isEmpty);
    });

    test('skips a slot whose lane is empty; null when every lane is', () {
      final series = [_film('s1'), _film('s2')];
      final slot = [0];
      final first = drawReelFilm(films: [], series: series, anime: [], slot: slot);
      expect(first?.film.titleEn, 's1');
      expect(first?.lane, ReelLane.series);
      expect(drawReelFilm(films: [], series: series, anime: [], slot: slot)?.film.titleEn, 's2');
      expect(drawReelFilm(films: [], series: series, anime: [], slot: slot), isNull);
      expect(drawReelFilm(films: [], series: [], anime: [], slot: [0]), isNull);
    });
  });

  group('ReelsCursor', () {
    test('a lane is dry after enough empty fetches; the feed ends when both are', () {
      const fresh = ReelsCursor();
      expect(fresh.filmsDry, isFalse);
      expect(fresh.seriesDry, isFalse);
      expect(fresh.animeDry, isFalse);
      expect(fresh.exhausted, isFalse);
      expect(fresh.filmPage, 0);
      expect(fresh.seriesPage, 0);
      expect(fresh.animePage, 0);
      expect(fresh.anime, isEmpty);
      expect(fresh.filmsSearched, 0);
      expect(fresh.filmsMatched, 0);
      expect(fresh.query, isNull);

      const dry = ReelsCursor(
        filmMisses: ReelsCursor.laneMisses,
        seriesMisses: ReelsCursor.laneMisses,
        animeMisses: ReelsCursor.laneMisses,
      );
      expect(dry.filmsDry, isTrue);
      expect(dry.seriesDry, isTrue);
      expect(dry.animeDry, isTrue);
      expect(dry.exhausted, isTrue);

      // One lane still answering keeps the feed open.
      const oneLeft = ReelsCursor(
        filmMisses: ReelsCursor.laneMisses,
        seriesMisses: ReelsCursor.laneMisses - 1,
        animeMisses: ReelsCursor.laneMisses,
      );
      expect(oneLeft.exhausted, isFalse);
      const animeLeft = ReelsCursor(
        filmMisses: ReelsCursor.laneMisses,
        seriesMisses: ReelsCursor.laneMisses,
        animeMisses: ReelsCursor.laneMisses - 1,
      );
      expect(animeLeft.exhausted, isFalse, reason: 'the anime lane is still answering');
    });

    test('a dry feed with a title still waiting is not exhausted', () {
      final cursor = ReelsCursor(
        filmMisses: ReelsCursor.laneMisses,
        seriesMisses: ReelsCursor.laneMisses,
        animeMisses: ReelsCursor.laneMisses,
        series: [_film('waiting')],
      );
      expect(cursor.exhausted, isFalse);
      final waitingAnime = ReelsCursor(
        filmMisses: ReelsCursor.laneMisses,
        seriesMisses: ReelsCursor.laneMisses,
        animeMisses: ReelsCursor.laneMisses,
        anime: [_film('anime')],
      );
      expect(waitingAnime.exhausted, isFalse);
    });
  });

  group('ReelFilm', () {
    test('shows Arabic, searches English, is known by its English title and year', () {
      expect(_dune.title, 'الكثيب: الجزء الثاني');
      expect(_dune.searchTitle, 'Dune: Part Two');
      expect(_dune.names, ['Dune: Part Two', 'الكثيب: الجزء الثاني']);
      expect(_dune.key, 'dune part two|2024');
      expect(_dune.toString(), 'ReelFilm(الكثيب: الجزء الثاني (2024))');
    });

    test('falls back to the English title, then the original; blanks and repeats are not names', () {
      const en = ReelFilm(titleEn: 'Exhuma', original: '파묘');
      expect(en.title, 'Exhuma');
      expect(en.names, ['Exhuma', '파묘']);
      expect(en.key, 'exhuma|');
      const orig = ReelFilm(titleEn: '', original: '파묘');
      expect(orig.title, '파묘');
      expect(orig.searchTitle, '파묘');
      expect(const ReelFilm(titleEn: 'Same', original: 'Same').names, ['Same']);
    });
  });

  group('reelFilmsFromCinemana', () {
    CinemanaItem item({
      String id = '1',
      String ar = '',
      String en = '',
      String year = '',
      String kind = '1',
      String arContent = '',
      String enContent = '',
      String? medium,
      String? full,
      String? backdrop,
    }) =>
        CinemanaItem(
          id: id,
          arTitle: ar,
          enTitle: en,
          stars: '',
          year: year,
          kind: kind,
          arContent: arContent,
          enContent: enContent,
          imgMediumUrl: medium,
          imgUrl: full,
          backdropUrl: backdrop,
        );

    test('both titles, the year, the full poster first, the synopsis (Arabic first), the kind, the entry itself', () {
      final films = reelFilmsFromCinemana([
        item(
          id: '11',
          ar: ' فيلم ',
          en: ' Film ',
          year: ' 2025 ',
          medium: 'https://x/m.jpg',
          full: 'https://x/f.jpg',
          arContent: ' وصف ',
          enContent: 'desc',
        ),
        item(id: '12', en: 'Medium only', medium: 'https://x/m.jpg', backdrop: 'https://x/b.jpg', enContent: 'desc'),
        item(id: '13', ar: 'خلفية فقط', backdrop: 'https://x/b.jpg', kind: '2'),
        item(id: '14', ar: 'بلا صورة'),
        item(id: '15', year: '2020', medium: 'https://x/m.jpg'),
      ]);
      expect(films, hasLength(4), reason: 'a title with no name is left out');
      final film = films[0];
      expect(film.titleAr, 'فيلم');
      expect(film.titleEn, 'Film');
      expect(film.year, '2025');
      expect(film.poster, 'https://x/f.jpg', reason: 'the full poster is drawn over the whole page');
      expect(film.overview, 'وصف');
      expect(film.isSeries, isFalse);
      expect(film.item?.id, '11');
      expect(film.key, 'film|2025');

      expect(films[1].poster, 'https://x/m.jpg', reason: 'the card size when there is no full one');
      expect(films[1].year, isNull);
      expect(films[1].overview, 'desc');
      expect(films[1].isSeries, isFalse);

      expect(films[2].poster, 'https://x/b.jpg', reason: 'the backdrop when there is nothing else');
      expect(films[2].isSeries, isTrue);
      expect(films[2].item?.id, '13');
      expect(films[2].title, 'خلفية فقط');

      expect(films[3].poster, isNull);
      expect(films[3].item?.id, '14');
    });

    test('a film of the catalogue keeps its entry, so the reel can open it', () {
      const plain = ReelFilm(titleEn: 'x');
      expect(plain.item, isNull);
      expect(plain.isSeries, isFalse);
    });
  });

  group('formatReelCount', () {
    test('plain below a thousand', () {
      expect(formatReelCount(0), '0');
      expect(formatReelCount(999), '999');
      expect(formatReelCount(-3), '0');
    });

    test('thousands as K with one decimal below 10K', () {
      expect(formatReelCount(1000), '1K');
      expect(formatReelCount(1234), '1.2K');
      expect(formatReelCount(9940), '9.9K');
      expect(formatReelCount(9960), '10K');
      expect(formatReelCount(12345), '12K');
      expect(formatReelCount(340000), '340K');
    });

    test('millions and billions', () {
      expect(formatReelCount(3400000), '3.4M');
      expect(formatReelCount(12000000), '12M');
      expect(formatReelCount(1100000000), '1.1B');
    });
  });

  group('reelStartsLatin', () {
    test('Latin opener is Latin, even after digits, emoji or punctuation', () {
      expect(reelStartsLatin('Hello world'), isTrue);
      expect(reelStartsLatin('2024 Best goals'), isTrue);
      expect(reelStartsLatin('🔥 Crazy skills #shorts'), isTrue);
      expect(reelStartsLatin('"Élan" vital'), isTrue);
    });

    test('Arabic opener is not Latin, even with a Latin tag later', () {
      expect(reelStartsLatin('أهداف اليوم #shorts'), isFalse);
      expect(reelStartsLatin('123 مقاطع'), isFalse);
      expect(reelStartsLatin('שלום'), isFalse);
    });

    test('no letters at all is not Latin', () {
      expect(reelStartsLatin(''), isFalse);
      expect(reelStartsLatin('123 !!! 🔥'), isFalse);
    });
  });

  group('reelInitial', () {
    test('first letter, upper-cased, skipping a leading @', () {
      expect(reelInitial('cineball'), 'C');
      expect(reelInitial('@channel'), 'C');
      expect(reelInitial('  محمد'), 'م');
      expect(reelInitial(''), '?');
    });
  });

  group('Reel', () {
    test('every reel is a trailer; thumbnail, fallback and share links are built from the id', () {
      final r = _reel('abc123');
      expect(r.kind, Reel.kindTrailer, reason: 'a trailer unless said otherwise');
      expect(r.isTrailer, isTrue);
      expect(r.thumbnailUrl, 'https://i.ytimg.com/vi/abc123/oardefault.jpg');
      expect(r.fallbackThumbnailUrl, 'https://i.ytimg.com/vi/abc123/hqdefault.jpg');
      expect(r.shareUrl, 'https://youtu.be/abc123');
    });

    test('from a search hit: the short’s own title, channel and view count; the stock author without one', () {
      final r = Reel.fromHit(_hit('aaaaaaaaaa1', 'Dune: Part Two #shorts', seconds: 30, author: 'WB'));
      expect(r.id, 'aaaaaaaaaa1');
      expect(r.title, 'Dune: Part Two #shorts');
      expect(r.author, 'WB');
      expect(r.channelId, isNull);
      expect(r.duration, const Duration(seconds: 30));
      expect(r.viewCount, 0);
      expect(r.likeCount, isNull);
      expect(r.isTrailer, isTrue);
      expect(Reel.fromHit(_hit('aaaaaaaaaa1', 'x', short: true, author: '')).author, kReelTrailerAuthor);
    });

    test('two reels with the same id are the same reel', () {
      expect(_reel('a'), _reel('a', title: 'other'));
      expect({_reel('a'), _reel('a')}.length, 1);
    });

    test('a reel of the catalogue keeps its entry and tells a series from a film; one without has neither', () {
      const film = CinemanaItem(
        id: '77',
        arTitle: 'الكثيب',
        enTitle: 'Dune',
        stars: '',
        year: '2024',
        kind: '1',
        arContent: '',
        enContent: '',
      );
      Reel of(CinemanaItem? item) => Reel(
            id: 'abcdefghijk',
            title: 'الكثيب (2024)',
            author: kReelTrailerAuthor,
            channelId: null,
            description: '',
            duration: null,
            viewCount: null,
            likeCount: null,
            uploadDate: null,
            catalogItem: item,
          );
      expect(of(film).catalogItem, same(film));
      expect(of(film).isSeries, isFalse);
      expect(of(film.copyWith(kind: '2')).isSeries, isTrue);
      expect(of(null).catalogItem, isNull);
      expect(of(null).isSeries, isFalse);
      expect(_reel('a').catalogItem, isNull);
    });

    test('reelTitleWithYear', () {
      expect(reelTitleWithYear('Film', '2024'), 'Film (2024)');
      expect(reelTitleWithYear(' Film ', ''), 'Film');
      expect(reelTitleWithYear('Film', null), 'Film');
    });
  });

  test('search of an empty query is an empty page', () async {
    final service = ReelsService();
    final page = await service.search('   ');
    service.dispose();
    expect(page.items, isEmpty);
    expect(page.hasMore, isFalse);
  });
}
