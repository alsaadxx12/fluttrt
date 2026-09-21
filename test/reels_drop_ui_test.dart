import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_downloader/features/reels/data/reels_service.dart';
import 'package:youtube_downloader/features/reels/presentation/providers/reels_feed_provider.dart';
import 'package:youtube_downloader/features/reels/presentation/providers/reels_mute.dart';
import 'package:youtube_downloader/features/reels/presentation/providers/reels_service_provider.dart';
import 'package:youtube_downloader/features/reels/presentation/screens/reels_screen.dart';

/// The «مشاهد» page over a feed that is fed by hand: a reel dropped while it
/// is the one showing must leave the list without moving the page, so the
/// next reel takes its place under the same index and plays; the swipe past
/// the last reel must land on a page of its own — the one that fetches
/// more, and that says the feed has run out — and a reel landing under that
/// index must become the reel showing.

Reel _reel(String id) => Reel(
      id: id,
      title: 'Reel $id',
      author: kReelTrailerAuthor,
      channelId: null,
      description: '',
      duration: null,
      viewCount: null,
      likeCount: 1234,
      uploadDate: null,
    );

ReelsPage _page(List<String> ids, {bool hasMore = true}) => ReelsPage(
      items: [for (final id in ids) _reel(id)],
      hasMore: hasMore,
      cursor: const ReelsCursor(),
    );

/// Hands out [first], then [next] — the later calls waiting on [gate] while
/// one is set, so the page that fetches more can be looked at mid-flight.
class _FakeService extends ReelsService {
  _FakeService(this.first);

  final ReelsPage first;
  ReelsPage next = _page(const []);
  Completer<void>? gate;
  int calls = 0;

  @override
  Future<ReelsPage> fetchFeed({ReelsPage? after}) async {
    calls++;
    if (calls == 1) return first;
    final held = gate;
    if (held != null) await held.future;
    return next;
  }
}

Widget _app(ReelsService service) => ProviderScope(
      overrides: [reelsServiceProvider.overrideWithValue(service)],
      child: MaterialApp(
        builder: (_, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        home: const ReelsScreen(embedded: true),
      ),
    );

/// Lets the stream lookups every page starts (all refused: there is no
/// network in a widget test) run out, so nothing is left ticking.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(seconds: 5));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    reelsMuted.value = false;
  });

  PageController pages(WidgetTester tester) => tester.widget<PageView>(find.byType(PageView)).controller!;

  ReelsFeedNotifier notifier(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(ReelsScreen))).read(reelsFeedProvider.notifier);

  /// True when [text] is drawn inside the viewport — the page showing, not
  /// one of the neighbours the PageView keeps built above and below it.
  bool onScreen(WidgetTester tester, String text) {
    final rect = tester.getRect(find.text(text));
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    return rect.top >= 0 && rect.bottom <= screen.height;
  }

  /// The app with the feed loaded and its first page in hand.
  Future<void> open(WidgetTester tester, _FakeService service) async {
    await tester.pumpWidget(_app(service));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('a dropped reel leaves the feed without moving the page: the next one takes its index', (tester) async {
    final service = _FakeService(_page(['aaa', 'bbb', 'ccc'], hasMore: false));
    await open(tester, service);
    expect(find.text('Reel aaa'), findsOneWidget);

    pages(tester).jumpToPage(1);
    await tester.pump();
    await tester.pump();
    expect(pages(tester).page, 1);
    expect(onScreen(tester, 'Reel bbb'), isTrue, reason: 'the second reel is the one showing');

    await notifier(tester).drop('bbb');
    await tester.pump();
    await tester.pump();

    expect(find.text('Reel bbb'), findsNothing, reason: 'it is out of the feed');
    expect(pages(tester).page, 1, reason: 'the page did not move under the drop');
    expect(onScreen(tester, 'Reel ccc'), isTrue, reason: 'the next reel slid into the same index');

    // The last reel of all: dropping it lands on the new last one.
    await notifier(tester).drop('ccc');
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Reel ccc'), findsNothing);
    expect(pages(tester).page, 0);
    expect(onScreen(tester, 'Reel aaa'), isTrue);

    await _settle(tester);
  });

  testWidgets('the page past the last reel fetches more, then becomes the reel that landed', (tester) async {
    final service = _FakeService(_page(['aaa', 'bbb', 'ccc']));
    service.gate = Completer<void>();
    await open(tester, service);

    // Three reels and the page past them.
    expect(tester.widget<PageView>(find.byType(PageView)).childrenDelegate.estimatedChildCount, 4);
    pages(tester).jumpToPage(3);
    await tester.pump();
    await tester.pump();
    expect(find.text(kReelsMoreComingLabel), findsOneWidget, reason: 'the next page is on its way');
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    service.next = _page(['ddd', 'eee']);
    service.gate!.complete();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(find.text(kReelsMoreComingLabel), findsNothing);
    expect(pages(tester).page, 3, reason: 'the index did not move');
    expect(onScreen(tester, 'Reel ddd'), isTrue, reason: 'the reel that landed is the one showing, unswiped');

    await _settle(tester);
  });

  testWidgets('once the feed has run out the page past it says so and offers «تحديث»', (tester) async {
    final service = _FakeService(_page(['aaa', 'bbb', 'ccc']));
    service.gate = Completer<void>();
    service.next = _page(const [], hasMore: false);
    await open(tester, service);

    pages(tester).jumpToPage(3);
    await tester.pump();
    await tester.pump();
    expect(find.text(kReelsMoreComingLabel), findsOneWidget);

    service.gate!.complete();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(find.text(kReelsEndLabel), findsOneWidget);
    expect(find.text(kReelsMoreComingLabel), findsNothing);
    expect(
      tester.widget<PageView>(find.byType(PageView)).childrenDelegate.estimatedChildCount,
      4,
      reason: 'the page stays under the finger that is standing on it',
    );

    final before = service.calls;
    await tester.tap(find.text(kReelsRefreshLabel));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(service.calls, greaterThan(before), reason: '«تحديث» starts the feed over');

    await _settle(tester);
  });

  testWidgets('a feed that runs out while the finger is mid-list still ends on «هذه كل المشاهد حالياً»', (tester) async {
    // The ordinary case: the next page is fetched ahead of the swipe, so the
    // feed runs out (hasMore false) while the finger is still reels away
    // from the end of the list.
    final service = _FakeService(_page(['aaa', 'bbb', 'ccc']));
    service.gate = Completer<void>();
    service.next = _page(const [], hasMore: false);
    await open(tester, service);

    service.gate!.complete();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('Reel aaa'), findsOneWidget, reason: 'still on the first reel');
    expect(
      tester.widget<PageView>(find.byType(PageView)).childrenDelegate.estimatedChildCount,
      3,
      reason: 'nothing past the reels until the swipe reaches the end of them',
    );

    pages(tester).jumpToPage(2);
    await tester.pump();
    await tester.pump();
    expect(
      tester.widget<PageView>(find.byType(PageView)).childrenDelegate.estimatedChildCount,
      4,
      reason: 'the last reel carries the end page under it',
    );

    pages(tester).jumpToPage(3);
    await tester.pump();
    await tester.pump();
    expect(find.text(kReelsEndLabel), findsOneWidget);

    final before = service.calls;
    await tester.tap(find.text(kReelsRefreshLabel));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(service.calls, greaterThan(before), reason: 'the end of the list can be refreshed from');

    await _settle(tester);
  });

  testWidgets('«تحديث» on the end page leaves it: the fresh feed opens on its first reel', (tester) async {
    final service = _FakeService(_page(['aaa', 'bbb', 'ccc'], hasMore: false));
    await open(tester, service);

    // Walk to the last reel — which is what puts the end page there — and
    // onto the end page itself.
    pages(tester).jumpToPage(2);
    await tester.pump();
    await tester.pump();
    pages(tester).jumpToPage(3);
    await tester.pump();
    await tester.pump();
    expect(find.text(kReelsEndLabel), findsOneWidget);

    service.next = _page(['new1', 'new2', 'new3'], hasMore: false);
    await tester.tap(find.text(kReelsRefreshLabel));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(find.text('Reel aaa'), findsNothing, reason: 'the old feed is gone');
    expect(pages(tester).page, 0, reason: 'the button walked the page back to the top');
    expect(onScreen(tester, 'Reel new1'), isTrue, reason: 'the first reel of the fresh feed is the one showing');
    expect(find.text(kReelsEndLabel), findsNothing, reason: 'the end page is not under the finger any more');

    await _settle(tester);
  });

  testWidgets('dropping the last reel while standing on it falls back onto the new last reel', (tester) async {
    final service = _FakeService(_page(['aaa', 'bbb', 'ccc'], hasMore: false));
    await open(tester, service);

    // Standing on the last reel is what puts the end page under it; the drop
    // must take that page away again rather than leave it showing.
    pages(tester).jumpToPage(2);
    await tester.pump();
    await tester.pump();
    expect(onScreen(tester, 'Reel ccc'), isTrue);
    expect(tester.widget<PageView>(find.byType(PageView)).childrenDelegate.estimatedChildCount, 4);

    await notifier(tester).drop('ccc');
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('Reel ccc'), findsNothing);
    expect(pages(tester).page, 1, reason: 'the page fell back by one');
    expect(onScreen(tester, 'Reel bbb'), isTrue, reason: 'the new last reel is the one showing, not the end page');

    await _settle(tester);
  });
}
