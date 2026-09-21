import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_downloader/features/reels/data/reels_service.dart';
import 'package:youtube_downloader/features/reels/presentation/providers/reels_feed_provider.dart';

/// The feed must never dead-end under the finger and must never keep a reel
/// that cannot play: it loads ahead of the swipe, follows a thin page with
/// one more at once, hops over the pages that come back empty, and drops a
/// dead short out of the list, out of the page kept on the device and into
/// a list that outlives the launch.

Reel _reel(String id) => Reel(
      id: id,
      title: 'Reel $id',
      author: kReelTrailerAuthor,
      channelId: null,
      description: '',
      duration: null,
      viewCount: null,
      likeCount: null,
      uploadDate: null,
    );

ReelsPage _page(List<String> ids, {bool hasMore = true, bool failed = false}) => ReelsPage(
      items: [for (final id in ids) _reel(id)],
      hasMore: hasMore,
      failed: failed,
      cursor: const ReelsCursor(),
    );

/// A service that hands out canned pages in order — the last one over and
/// over — and records what it was asked and what was written off.
class _FakeService extends ReelsService {
  _FakeService(this._pages);

  final List<ReelsPage> _pages;
  final List<String> dead = [];
  int calls = 0;

  @override
  Future<ReelsPage> fetchFeed({ReelsPage? after}) async {
    final page = _pages[calls < _pages.length ? calls : _pages.length - 1];
    calls++;
    return page;
  }

  @override
  void markDead(String id) {
    dead.add(id);
    super.markDead(id);
  }
}

/// The notifier with everything it started settled: the read of the device's
/// lists, the first page, and the page a thin first page starts by itself.
Future<ReelsFeedNotifier> _feed(_FakeService service) async {
  final notifier = ReelsFeedNotifier(service);
  await pumpEventQueue();
  return notifier;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('loading ahead', () {
    test('a page that lands short of a full one ahead starts one more — once, never in a loop', () async {
      final service = _FakeService([
        _page(['a', 'b', 'c']),
        _page(['d', 'e', 'f']),
        _page(['g', 'h', 'i']),
      ]);
      final feed = await _feed(service);

      expect(service.calls, 2, reason: 'the first page, then the one it started by itself');
      expect(feed.state.items.map((r) => r.id), ['a', 'b', 'c', 'd', 'e', 'f']);
      expect(feed.state.isLoading, isFalse);

      // The follow-up's own landing starts nothing: the feed must not spin.
      await pumpEventQueue();
      expect(service.calls, 2);

      // A page asked for by hand lands with a page's worth ahead of the
      // reel showing, so nothing follows it either.
      await feed.loadMore();
      await pumpEventQueue();
      expect(service.calls, 3);
      expect(feed.state.items, hasLength(9));
      feed.dispose();
    });

    test('ensureAhead loads while five or fewer reels are left past the one showing', () async {
      final service = _FakeService([_page(['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i'])]);
      final feed = await _feed(service);
      expect(service.calls, 1, reason: 'a full page ahead: nothing follows it');
      expect(feed.state.items, hasLength(9));

      feed.ensureAhead(2);
      await pumpEventQueue();
      expect(service.calls, 1, reason: 'six reels still ahead');

      feed.ensureAhead(4);
      await pumpEventQueue();
      expect(service.calls, greaterThan(1), reason: 'five left: the next page starts');
      feed.dispose();
    });

    test('the end of the feed stops it: nothing is asked for again', () async {
      final service = _FakeService([
        _page(['a', 'b'], hasMore: false),
      ]);
      final feed = await _feed(service);
      expect(service.calls, 1);
      expect(feed.state.hasMore, isFalse);
      expect(feed.state.items.map((r) => r.id), ['a', 'b']);

      await feed.loadMore();
      feed.ensureAhead(1);
      await pumpEventQueue();
      expect(service.calls, 1, reason: 'a feed that has run out asks for nothing more');
      feed.dispose();
    });

    test('empty pages are hopped over, three at a time, and a page with reels on it resumes the feed', () async {
      final service = _FakeService([
        _page(const []),
        _page(const []),
        _page(const []),
        _page(['a', 'b']),
      ]);
      final feed = await _feed(service);

      // Three empty hops in the first load, then the follow-up's first
      // fetch lands the reels.
      expect(service.calls, 4);
      expect(feed.state.items.map((r) => r.id), ['a', 'b']);
      expect(feed.state.isLoading, isFalse);
      expect(feed.state.failed, isFalse);
      feed.dispose();
    });

    test('nothing but empty pages: the hops are bounded, and the feed stays open', () async {
      final service = _FakeService([_page(const [])]);
      final feed = await _feed(service);
      expect(service.calls, 6, reason: 'three hops, then the one follow-up page hops three more');
      expect(feed.state.items, isEmpty);
      expect(feed.state.hasMore, isTrue);
      expect(feed.state.isLoading, isFalse);
      feed.dispose();
    });
  });

  group('dropping a reel that cannot play', () {
    test('it leaves the list, the service’s memory and the device’s kept page, for good', () async {
      final service = _FakeService([
        _page(['a', 'b', 'c'], hasMore: false),
      ]);
      final feed = await _feed(service);
      expect(feed.state.items.map((r) => r.id), ['a', 'b', 'c']);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(ReelsFeedNotifier.cacheKey), contains('"b"'), reason: 'the first page is kept');

      await feed.drop('b');
      expect(feed.state.items.map((r) => r.id), ['a', 'c']);
      expect(service.dead, ['b']);
      expect(service.deadShorts, contains('b'));
      expect(prefs.getStringList(ReelsFeedNotifier.deadKey), ['b']);

      final kept = (jsonDecode(prefs.getString(ReelsFeedNotifier.cacheKey)!) as List)
          .map((m) => (m as Map)['id'])
          .toList();
      expect(kept, ['a', 'c'], reason: 'the dropped reel is out of the kept page too');

      // Dropping what is not there changes nothing, and an empty id is no id.
      await feed.drop('zzz');
      await feed.drop('');
      expect(feed.state.items.map((r) => r.id), ['a', 'c']);
      expect(prefs.getStringList(ReelsFeedNotifier.deadKey), ['b', 'zzz']);
      feed.dispose();
    });

    test('a dropped reel never comes back: not from a fresh page, not from the device', () async {
      SharedPreferences.setMockInitialValues({
        ReelsFeedNotifier.deadKey: ['b'],
        ReelsFeedNotifier.cacheKey: jsonEncode([
          reelToJson(_reel('a')),
          reelToJson(_reel('b')),
        ]),
      });
      final service = _FakeService([
        _page(['b', 'c'], hasMore: false),
      ]);
      final feed = await _feed(service);

      expect(service.dead, ['b'], reason: 'the service is told before the first search');
      expect(feed.state.items.map((r) => r.id), ['a', 'c'], reason: 'neither the kept page nor the fresh one keeps it');
      feed.dispose();
    });

    test('only the newest four hundred are remembered', () async {
      final service = _FakeService([
        _page(const [], hasMore: false),
      ]);
      final feed = await _feed(service);
      for (var i = 0; i < ReelsFeedNotifier.deadCap + 2; i++) {
        await feed.drop('id$i');
      }
      final prefs = await SharedPreferences.getInstance();
      final kept = prefs.getStringList(ReelsFeedNotifier.deadKey)!;
      expect(kept, hasLength(ReelsFeedNotifier.deadCap));
      expect(kept.last, 'id${ReelsFeedNotifier.deadCap + 1}');
      expect(kept.first, 'id2', reason: 'the oldest two fell off');
      feed.dispose();
    });
  });

  group('the service’s memory of a dead short', () {
    test('markDead forgets the short and the title it was found for, and keeps it out of the candidates', () {
      final service = ReelsService();
      const film = ReelFilm(titleEn: 'Dune: Part Two', year: '2024');
      const other = ReelFilm(titleEn: 'Oppenheimer', year: '2023');
      service.shortsFound[film.key] = 'aaaaaaaaaa1';
      service.shortsFound[other.key] = 'aaaaaaaaaa2';

      service.markDead('aaaaaaaaaa1');
      expect(service.deadShorts, {'aaaaaaaaaa1'});
      expect(service.shortsFound.containsKey(film.key), isFalse, reason: 'that title is searched again next time');
      expect(service.shortsFound[other.key], 'aaaaaaaaaa2', reason: 'the other title is untouched');

      service.markDead('');
      expect(service.deadShorts, {'aaaaaaaaaa1'});

      const hits = [
        ReelSearchHit(id: 'aaaaaaaaaa1', title: 'Dune Part Two | Official Trailer', duration: Duration(seconds: 30)),
        ReelSearchHit(id: 'aaaaaaaaaa3', title: 'Dune Part Two | Teaser', duration: Duration(seconds: 30)),
      ];
      expect(
        [for (final h in reelShortCandidates(hits, film, dead: service.deadShorts)) h.id],
        ['aaaaaaaaaa3'],
        reason: 'the dead short is never offered again',
      );
      expect([for (final h in reelShortCandidates(hits, film)) h.id], ['aaaaaaaaaa1', 'aaaaaaaaaa3']);
      service.dispose();
    });
  });
}
