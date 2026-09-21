/// The letterbox gate inside the short search: a candidate that clears the
/// probe and the official check is still dropped when its portrait
/// thumbnail turns out to be a 16:9 picture between black bands, and a
/// detector that cannot answer never costs the feed a short.
///
/// Offline: the catalogue, YouTube's search, the stream probe and the
/// detector are all stand-ins.
library;

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';
import 'package:youtube_downloader/features/cinemana/data/services/cinemana_service.dart';
import 'package:youtube_downloader/features/reels/data/reel_letterbox.dart';
import 'package:youtube_downloader/features/reels/data/reel_stream_resolver.dart';
import 'package:youtube_downloader/features/reels/data/reels_service.dart';

/// One catalogue title, the one the stand-in catalogue answers with.
const CinemanaItem _dune = CinemanaItem(
  id: '77',
  arTitle: 'الكثيب',
  enTitle: 'Dune',
  stars: '',
  year: '2024',
  kind: '1',
  arContent: '',
  enContent: '',
);

class _StubCinemana extends CinemanaService {
  @override
  Future<List<CinemanaItem>> search(String query, {int page = 0, CancelToken? cancelToken}) async => const [_dune];
}

/// YouTube's search, stubbed: every query answers the same hits, so the
/// order the service probes them in is the order they are listed here.
class _StubSearch extends ReelShortsSearch {
  _StubSearch(this.hits);

  final List<ReelSearchHit> hits;
  int calls = 0;

  @override
  Future<ReelSearchAnswer> search(String query, {String? continuation}) async {
    calls++;
    return (hits: hits, continuation: null);
  }
}

/// Every probe qualifies (upright, 1080p, short), so the letterbox gate is
/// the only thing that can turn a candidate away.
class _StubResolver extends ReelStreamResolver {
  _StubResolver() : super.custom();

  final probed = <String>[];

  @override
  Future<ReelProbe?> probe(String videoId) async {
    probed.add(videoId);
    return const ReelProbe(width: 1080, height: 1920, duration: Duration(seconds: 40), author: 'Warner Bros. Pictures');
  }

  @override
  ReelProbe? cachedProbe(String videoId) => null;

  @override
  bool get throttled => false;

  @override
  Future<void> prewarm(Iterable<String> videoIds, {int concurrency = 2}) async {}
}

/// The detector, stubbed: [answers] per id, anything else answers false.
class _StubLetterbox extends ReelLetterbox {
  _StubLetterbox(this.answers);

  final Map<String, bool?> answers;
  final asked = <String>[];
  var closed = false;

  @override
  Future<bool?> isLetterboxed(String videoId, {Duration timeout = const Duration(seconds: 6)}) async {
    asked.add(videoId);
    return answers[videoId] ?? false;
  }

  @override
  void close() => closed = true;
}

ReelSearchHit _hit(String id) => ReelSearchHit(
      id: id,
      title: 'Dune Official Trailer #shorts',
      author: 'Warner Bros. Pictures',
      duration: const Duration(seconds: 40),
      short: true,
      frameWidth: 1080,
      frameHeight: 1920,
    );

/// A hit that never gets as far as the gate: a fan edit of the same film.
ReelSearchHit _fanHit(String id) => ReelSearchHit(
      id: id,
      title: 'Dune fan made trailer',
      author: 'Some Guy',
      duration: const Duration(seconds: 40),
      short: true,
      frameWidth: 1080,
      frameHeight: 1920,
    );

void main() {
  group('letterbox gate in the short search', () {
    test('a letterboxed official candidate is skipped and the next one taken', () async {
      final search = _StubSearch([_hit('aaaaaaaaaaa'), _hit('bbbbbbbbbbb')]);
      final detector = _StubLetterbox({'aaaaaaaaaaa': true, 'bbbbbbbbbbb': false});
      final service = ReelsService(
        shorts: search,
        cinemana: _StubCinemana(),
        resolver: _StubResolver(),
        letterbox: detector,
      );
      addTearDown(service.dispose);

      final page = await service.search('dune');

      expect(page.items.map((r) => r.id), ['bbbbbbbbbbb']);
      expect(detector.asked, ['aaaaaaaaaaa', 'bbbbbbbbbbb'],
          reason: 'both official candidates were measured, in the candidates\' order');
    });

    test('a film whose only official candidate is letterboxed yields no reel', () async {
      final detector = _StubLetterbox({'aaaaaaaaaaa': true});
      final service = ReelsService(
        shorts: _StubSearch([_hit('aaaaaaaaaaa')]),
        cinemana: _StubCinemana(),
        resolver: _StubResolver(),
        letterbox: detector,
      );
      addTearDown(service.dispose);

      final page = await service.search('dune');

      expect(page.items, isEmpty);
      expect(detector.asked, contains('aaaaaaaaaaa'));
    });

    test('a detector that answers null does not block the short', () async {
      final detector = _StubLetterbox({'aaaaaaaaaaa': null});
      final service = ReelsService(
        shorts: _StubSearch([_hit('aaaaaaaaaaa')]),
        cinemana: _StubCinemana(),
        resolver: _StubResolver(),
        letterbox: detector,
      );
      addTearDown(service.dispose);

      final page = await service.search('dune');

      expect(page.items.map((r) => r.id), ['aaaaaaaaaaa'],
          reason: 'not knowing is no evidence against the short',
      );
      expect(detector.asked, ['aaaaaaaaaaa']);
    });

    test('no thumbnail is fetched for a hit the official check turns away', () async {
      final detector = _StubLetterbox({});
      final service = ReelsService(
        shorts: _StubSearch([_fanHit('ccccccccccc'), _hit('aaaaaaaaaaa')]),
        cinemana: _StubCinemana(),
        resolver: _StubResolver(),
        letterbox: detector,
      );
      addTearDown(service.dispose);

      final page = await service.search('dune');

      expect(page.items.map((r) => r.id), ['aaaaaaaaaaa']);
      expect(detector.asked, ['aaaaaaaaaaa'], reason: 'the fan clip cost no thumbnail fetch');
    });

    test('dispose closes the detector', () {
      final detector = _StubLetterbox({});
      ReelsService(
        shorts: _StubSearch(const []),
        cinemana: _StubCinemana(),
        resolver: _StubResolver(),
        letterbox: detector,
      ).dispose();

      expect(detector.closed, isTrue);
    });
  });
}
