import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_downloader/features/reels/data/reel_stream_resolver.dart';
import 'package:youtube_downloader/features/reels/data/reels_service.dart';
import 'package:youtube_downloader/features/reels/presentation/providers/reel_stream_resolver_provider.dart';
import 'package:youtube_downloader/features/reels/presentation/providers/reels_feed_provider.dart';
import 'package:youtube_downloader/features/reels/presentation/providers/reels_mute.dart';
import 'package:youtube_downloader/features/reels/presentation/providers/reels_service_provider.dart';
import 'package:youtube_downloader/features/reels/presentation/screens/reels_screen.dart';

/// What the «مشاهد» page makes of each answer the resolver can give, driven
/// through the page itself rather than through the resolver's own reason
/// computation (which test/reel_stream_picker_test.dart covers): only the
/// clip YouTube has written off may leave the feed, a refusal to answer for
/// now must hold the poster and ask again, and a request that never arrived
/// must keep the reel and ask again — writing nothing off.

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

ReelsPage _page(List<String> ids) => ReelsPage(
      items: [for (final id in ids) _reel(id)],
      hasMore: false,
      cursor: const ReelsCursor(),
    );

/// One fixed page, so nothing is fetched behind the reels under test.
class _FakeService extends ReelsService {
  _FakeService(this.first);

  final ReelsPage first;

  @override
  Future<ReelsPage> fetchFeed({ReelsPage? after}) async => first;
}

/// A resolver that answers from [answers] instead of YouTube, and counts
/// what it was asked.
class _FakeResolver extends ReelStreamResolver {
  _FakeResolver() : super.custom();

  final Map<String, ReelResolveReason> answers = {};
  final Map<String, int> calls = {};

  /// What [throttledUntil] says while YouTube is refusing.
  DateTime? until;

  /// What a clip that resolves is given: a muxed stream — so nothing is
  /// registered with the relay — pointing nowhere. media_kit has no native
  /// side in a widget test and there is no network behind the video_player
  /// fallback either, so the page cannot open it, which is the case under
  /// test.
  static final ReelStreams unopenable = ReelStreams(
    video: Uri.parse('http://127.0.0.1:1/reel.mp4'),
    audio: null,
    height: 1920,
    muxed: true,
  );

  @override
  DateTime? get throttledUntil => until;

  @override
  Future<ReelResolveResult> resolveDetailed(String videoId) async {
    calls[videoId] = (calls[videoId] ?? 0) + 1;
    final reason = answers[videoId] ?? ReelResolveReason.network;
    return ReelResolveResult(reason, streams: reason == ReelResolveReason.ok ? unopenable : null);
  }

  /// The neighbours are resolved ahead of the swipe; the counts under test
  /// are of the pages' own asks, so the stand-in warms nothing.
  @override
  Future<void> prewarm(Iterable<String> videoIds, {int concurrency = 2}) async {}
}

Widget _app(ReelsService service, ReelStreamResolver resolver) => ProviderScope(
      overrides: [
        reelsServiceProvider.overrideWithValue(service),
        reelStreamResolverProvider.overrideWithValue(resolver),
      ],
      child: MaterialApp(
        builder: (_, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        home: const ReelsScreen(embedded: true),
      ),
    );

/// The ids written off on this device, as they outlive the launch.
Future<List<String>?> _deadIds() async =>
    (await SharedPreferences.getInstance()).getStringList(ReelsFeedNotifier.deadKey);

/// Lets the retries the pages have armed run out, so nothing is left
/// ticking at the end of a test.
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

  Future<void> open(WidgetTester tester, ReelsService service, ReelStreamResolver resolver) async {
    await tester.pumpWidget(_app(service, resolver));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('a clip YouTube has written off leaves the feed; the ones it said nothing about stay', (tester) async {
    final resolver = _FakeResolver()
      ..answers['aaa'] = ReelResolveReason.unavailable
      ..answers['bbb'] = ReelResolveReason.network
      ..answers['ccc'] = ReelResolveReason.throttled;
    await open(tester, _FakeService(_page(['aaa', 'bbb', 'ccc'])), resolver);

    expect(find.text('Reel aaa'), findsNothing, reason: 'the unavailable clip is out of the list');
    expect(await _deadIds(), ['aaa'], reason: 'and written down, so no later launch offers it');
    expect(find.text('Reel bbb'), findsOneWidget, reason: 'the unreachable clip took its place');

    await _settle(tester);
    expect(
      await _deadIds(),
      ['aaa'],
      reason: 'neither the network nor the refusal ever writes a reel off, however often they are retried',
    );
  });

  testWidgets('YouTube refusing the requests holds the poster and asks again when the refusal lifts', (tester) async {
    final resolver = _FakeResolver()
      ..answers['aaa'] = ReelResolveReason.throttled
      ..until = DateTime.now().add(const Duration(seconds: 2));
    await open(tester, _FakeService(_page(['aaa'])), resolver);

    expect(find.text(kReelBusyLabel), findsOneWidget, reason: 'the page says YouTube is busy');
    expect(find.text(kReelFailedLabel), findsNothing, reason: 'nothing has failed: the clip was not asked about');
    expect(find.text('Reel aaa'), findsOneWidget, reason: 'the reel keeps its place');
    expect(resolver.calls['aaa'], 1);

    // A second past the refusal, the page resolves the clip again by itself.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(resolver.calls['aaa'], greaterThan(1));
    expect(await _deadIds(), isNull, reason: 'a refusal to answer writes nothing off');

    await _settle(tester);
  });

  testWidgets('a request that never arrived keeps the reel, offers a retry and asks again', (tester) async {
    final resolver = _FakeResolver()..answers['aaa'] = ReelResolveReason.network;
    await open(tester, _FakeService(_page(['aaa'])), resolver);

    expect(find.text(kReelFailedLabel), findsOneWidget);
    expect(find.text(kReelRetryLabel), findsOneWidget);
    expect(find.text('Reel aaa'), findsOneWidget, reason: 'the reel keeps its place');
    expect(resolver.calls['aaa'], 1);

    // The first backoff (8 s) runs out and the page asks again on its own.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(resolver.calls['aaa'], greaterThan(1));
    expect(await _deadIds(), isNull, reason: 'a request that never arrived writes nothing off');

    await _settle(tester);
  });

  testWidgets('a clip that resolved but whose stream will not play keeps its place', (tester) async {
    // The failure the user hits in a tunnel, or on a URL YouTube has stopped
    // honouring: the clip resolves, the stream is opened and the picture
    // never comes. YouTube said nothing about the clip, so the reel stays.
    final resolver = _FakeResolver()..answers['aaa'] = ReelResolveReason.ok;
    await tester.pumpWidget(_app(_FakeService(_page(['aaa'])), resolver));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Reel aaa'), findsOneWidget);
    expect(find.text(kReelFailedLabel), findsOneWidget);
    expect(await _deadIds(), isNull);

    await _settle(tester);
    expect(await _deadIds(), isNull, reason: 'a stream that would not play is never written off');
    expect(resolver.calls['aaa'], greaterThan(1), reason: 'the page went back for it by itself');
    expect(resolver.calls['aaa'], lessThan(10), reason: 'but not for ever');
  });
}
