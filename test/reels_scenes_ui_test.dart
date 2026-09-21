import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';
import 'package:youtube_downloader/features/reels/data/reel_stream_resolver.dart' show reelQualityOf;
import 'package:youtube_downloader/features/reels/data/reels_service.dart';
import 'package:youtube_downloader/features/reels/presentation/providers/reels_mute.dart';
import 'package:youtube_downloader/features/reels/presentation/screens/reels_screen.dart';
import 'package:youtube_downloader/features/reels/presentation/widgets/reel_widgets.dart';

/// A scene as the feed hands it over: the film's title with its year, the
/// stock author, a like count already known (so the like button asks the
/// network for nothing), and — for one of the catalogue — its entry.
Reel _scene(String id, String title, {CinemanaItem? item}) => Reel(
      id: id,
      title: title,
      author: kReelTrailerAuthor,
      channelId: null,
      description: '',
      duration: null,
      viewCount: null,
      likeCount: 1234,
      uploadDate: null,
      catalogItem: item,
    );

/// A catalogue entry: a film, or — [kind] «2» — a series.
CinemanaItem _item(String kind) => CinemanaItem(
      id: '10',
      arTitle: 'الكثيب',
      enTitle: 'Dune',
      stars: '',
      year: '2024',
      kind: kind,
      arContent: '',
      enContent: '',
    );

final List<Reel> _scenes = [
  _scene('abcdefghijk', 'الكثيب: الجزء الثاني (2024)'),
  _scene('lmnopqrstuv', 'Oppenheimer (2023)'),
];

Widget _app(List<Reel> items) => ProviderScope(
      child: MaterialApp(
        builder: (_, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        home: ReelsScreen(initialItems: items, embedded: true),
      ),
    );

/// Lets every stream lookup the pages start (all refused: there is no
/// network in a widget test) run out, so nothing is left ticking.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 24; i++) {
    await tester.pump(const Duration(seconds: 5));
  }
}

/// A seek bar 390 px wide on an RTL page, standing in for the reel page:
/// the clip 58 s long, a fifth played and half buffered. The page's part —
/// holding the touched fraction — is played here, and every callback is
/// logged as «down 0.50», «move …», «up …» or «cancel».
class _BarHarness {
  final played = ValueNotifier<double>(0.2);
  final buffered = ValueNotifier<double>(0.5);
  final duration = ValueNotifier<Duration>(const Duration(seconds: 58));
  final touched = ValueNotifier<double?>(null);
  final log = <String>[];

  static const double width = 390;

  String _f(double f) => f.toStringAsFixed(2);

  /// The bar alone, logging into [log].
  Widget bar() => ReelSeekBar(
        played: played,
        buffered: buffered,
        duration: duration,
        touched: touched,
        onTouchDown: (f) {
          touched.value = f;
          log.add('down ${_f(f)}');
        },
        onTouchMove: (f) {
          touched.value = f;
          log.add('move ${_f(f)}');
        },
        onTouchUp: (f) {
          touched.value = null;
          log.add('up ${_f(f)}');
        },
        onTouchCancel: () {
          touched.value = null;
          log.add('cancel');
        },
      );

  Widget build() => MaterialApp(
        builder: (_, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: SizedBox(width: width, child: bar())),
        ),
      );

  /// The bar at the foot of the first page of a vertical [PageView] driven
  /// by [pages], as on the reel page.
  Widget paged(PageController pages) => MaterialApp(
        builder: (_, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        home: Scaffold(
          backgroundColor: Colors.black,
          body: PageView(
            controller: pages,
            scrollDirection: Axis.vertical,
            children: [
              for (final name in const ['first', 'second'])
                Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(child: Text(name)),
                    if (name == 'first') Positioned(left: 0, right: 0, bottom: 0, child: bar()),
                  ],
                ),
            ],
          ),
        ),
      );

  void dispose() {
    played.dispose();
    buffered.dispose();
    duration.dispose();
    touched.dispose();
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    reelsMuted.value = false;
  });

  testWidgets('the page is «مشاهد»: the kind pill and the film, no publisher, no comments', (tester) async {
    await tester.pumpWidget(_app(_scenes));
    await tester.pump();

    expect(find.text('مشاهد'), findsOneWidget, reason: 'the title in the top bar');
    expect(find.text('الريلز'), findsNothing);

    expect(find.byIcon(Icons.mode_comment_rounded), findsNothing, reason: 'no comments button');
    expect(find.byIcon(Icons.add_rounded), findsNothing, reason: 'no channel avatar with its «+»');
    expect(find.byIcon(Icons.music_note_rounded), findsNothing, reason: 'no sound line');
    expect(find.textContaining('@'), findsNothing, reason: 'no «@author» line');
    expect(find.textContaining('الصوت الأصلي'), findsNothing);
    expect(find.textContaining(kReelTrailerAuthor), findsWidgets, reason: 'the kind pill «إعلان رسمي»');
    expect(find.text('الكثيب: الجزء الثاني (2024)'), findsOneWidget, reason: 'the film with its year');

    // The like (with its count) and the share stay.
    expect(find.byIcon(Icons.favorite_rounded), findsWidgets);
    expect(find.text('1.2K'), findsWidgets);
    expect(find.text('مشاركة'), findsWidgets);

    await _settle(tester);
  });

  testWidgets('a reel of the catalogue gets its «مشاهدة الفيلم» pill — «مشاهدة المسلسل» for a series; one without an entry gets none',
      (tester) async {
    // Nothing of the catalogue: no pill at all.
    await tester.pumpWidget(_app(_scenes));
    await tester.pump();
    expect(find.text(kReelWatchFilmLabel), findsNothing);
    expect(find.text(kReelWatchSeriesLabel), findsNothing);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    await _settle(tester);

    // A film of the catalogue.
    await tester.pumpWidget(_app([_scene('abcdefghijk', 'الكثيب: الجزء الثاني (2024)', item: _item('1'))]));
    await tester.pump();
    expect(find.text(kReelWatchFilmLabel), findsOneWidget);
    expect(find.text(kReelWatchSeriesLabel), findsNothing);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget, reason: 'the play arrow on the pill');
    final pill = find.ancestor(of: find.text(kReelWatchFilmLabel), matching: find.byType(InkWell));
    expect(pill, findsOneWidget);
    expect(tester.getSize(pill).height, 34);
    final title = tester.getRect(find.text('الكثيب: الجزء الثاني (2024)'));
    expect(tester.getRect(pill).top, greaterThan(title.bottom), reason: 'the pill sits under the title');
    expect(find.text('الكثيب: الجزء الثاني (2024)'), findsOneWidget, reason: 'the title stays');
    expect(find.textContaining(kReelTrailerAuthor), findsWidgets, reason: 'the kind pill stays');
    await _settle(tester);

    // A series of the catalogue.
    await tester.pumpWidget(_app([_scene('abcdefghijk', 'الكثيب (2024)', item: _item('2'))]));
    await tester.pump();
    expect(find.text(kReelWatchSeriesLabel), findsOneWidget);
    expect(find.text(kReelWatchFilmLabel), findsNothing);
    await _settle(tester);
  });

  testWidgets('the speaker in the top bar mutes and unmutes every page for the session', (tester) async {
    await tester.pumpWidget(_app(_scenes));
    await tester.pump();

    expect(reelsMuted.value, isFalse, reason: 'never starts muted');
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    expect(find.byIcon(Icons.volume_off_rounded), findsNothing);

    await tester.tap(find.byIcon(Icons.volume_up_rounded));
    await tester.pump();
    expect(reelsMuted.value, isTrue);
    expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);
    expect(find.byIcon(Icons.volume_up_rounded), findsNothing);

    await tester.tap(find.byIcon(Icons.volume_off_rounded));
    await tester.pump();
    expect(reelsMuted.value, isFalse);
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);

    // A page opened later sees the flag as it was left.
    reelsMuted.value = true;
    await tester.pumpWidget(_app(_scenes));
    await tester.pump();
    expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);

    await _settle(tester);
  });

  testWidgets('the search icon sits beside the speaker, and a pushed page gets its back chevron', (tester) async {
    await tester.pumpWidget(_app(_scenes));
    await tester.pump();
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsNothing, reason: 'embedded: no chevron');

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(home: ReelsScreen(initialItems: _scenes, embedded: false)),
    ));
    await tester.pump();
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);

    await _settle(tester);
  });

  group('reelClock', () {
    test('minutes and seconds, hours only once there are any, never negative', () {
      expect(reelClock(Duration.zero), '0:00');
      expect(reelClock(const Duration(seconds: 12)), '0:12');
      expect(reelClock(const Duration(minutes: 1, seconds: 45)), '1:45');
      expect(reelClock(const Duration(minutes: 12, seconds: 5)), '12:05');
      expect(reelClock(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
      expect(reelClock(const Duration(seconds: -4)), '0:00');
    });
  });

  group('seeking', () {
    test('a seek is held within the clip once its length is known', () {
      const total = Duration(seconds: 90);
      expect(reelClampSeek(const Duration(seconds: 30), total), const Duration(seconds: 30));
      expect(reelClampSeek(const Duration(seconds: -3), total), Duration.zero, reason: 'back past the start');
      expect(reelClampSeek(const Duration(seconds: 95), total), total, reason: 'forward past the end');
      expect(reelClampSeek(total, total), total);
      expect(reelClampSeek(Duration.zero, total), Duration.zero);
    });

    test('with the length still unknown only the start is a bound', () {
      expect(reelClampSeek(const Duration(seconds: 95), Duration.zero), const Duration(seconds: 95));
      expect(reelClampSeek(const Duration(seconds: -1), Duration.zero), Duration.zero);
    });

    test('ten seconds either way from where playback stands stays inside the clip', () {
      const total = Duration(seconds: 60);
      expect(reelClampSeek(const Duration(seconds: 4) - kReelSeekStep, total), Duration.zero);
      expect(reelClampSeek(const Duration(seconds: 55) + kReelSeekStep, total), total);
      expect(reelClampSeek(const Duration(seconds: 20) + kReelSeekStep, total), const Duration(seconds: 30));
    });

    test('a double tap on the left third goes back, on the right third forward, in the middle likes', () {
      const width = 390.0;
      expect(reelSeekZone(10, width), -1);
      expect(reelSeekZone(129, width), -1);
      expect(reelSeekZone(130, width), 0, reason: 'the boundary belongs to the middle');
      expect(reelSeekZone(195, width), 0);
      expect(reelSeekZone(260, width), 0);
      expect(reelSeekZone(261, width), 1);
      expect(reelSeekZone(385, width), 1);
      expect(reelSeekZone(10, 0), 0, reason: 'an unknown width never seeks');
    });
  });

  group('seek bar geometry', () {
    test('the touch strip is 44 px tall, the line 3 px growing to 8, the thumb 16', () {
      expect(kReelSeekBarHeight, 44);
      expect(ReelSeekBarGeometry.stripHeight, 44);
      expect(ReelSeekBarGeometry.line, 3);
      expect(ReelSeekBarGeometry.lineTouched, 8);
      expect(ReelSeekBarGeometry.thumb, 16);
    });

    test('a touch is its share of the strip from the left, held at both ends', () {
      const g = ReelSeekBarGeometry(390);
      expect(g.fractionAt(195), 0.5);
      expect(g.fractionAt(0), 0);
      expect(g.fractionAt(390), 1);
      expect(g.fractionAt(-20), 0, reason: 'a finger past the left end');
      expect(g.fractionAt(500), 1, reason: 'a finger past the right end');
      expect(const ReelSeekBarGeometry(0).fractionAt(100), 0, reason: 'an unknown width sits at the start');
    });

    test('the thumb is centred on the point and never leaves the strip', () {
      const g = ReelSeekBarGeometry(390);
      expect(g.thumbLeft(0.5), 195 - 8);
      expect(g.thumbCentre(0.5), 195);
      expect(g.thumbLeft(0), 0, reason: 'at the start it hugs the left edge');
      expect(g.thumbCentre(0), 8);
      expect(g.thumbLeft(1), 390 - 16, reason: 'at the end it hugs the right edge');
      expect(g.thumbLeft(1.5), 390 - 16, reason: 'a fraction past one is held at the end');
      expect(g.thumbLeft(-1), 0);
      expect(const ReelSeekBarGeometry(10).thumbLeft(0.5), 0, reason: 'a strip narrower than the thumb');
    });

    test('the chip slot is centred over the thumb and held inside the strip', () {
      const g = ReelSeekBarGeometry(390);
      expect(g.chipLeft(0.5, 112), 195 - 56);
      expect(g.chipLeft(0, 112), 0);
      expect(g.chipLeft(0.05, 112), 0, reason: 'near the start it hugs the left edge');
      expect(g.chipLeft(1, 112), 390 - 112);
      expect(g.chipLeft(0.97, 112), 390 - 112, reason: 'near the end it hugs the right edge');
    });
  });

  group('quality chip', () {
    test('the label is the quality with a «p»; nothing while unknown', () {
      expect(reelQualityLabel(1080), '1080p');
      expect(reelQualityLabel(1440), '1440p');
      expect(reelQualityLabel(720), '720p');
      expect(reelQualityLabel(null), isNull);
      expect(reelQualityLabel(0), isNull);
      expect(reelQualityLabel(-1), isNull);
    });

    test('a vertical 1080×1920 clip is «1080p», like a landscape 1920×1080 one', () {
      expect(reelQualityLabel(reelQualityOf(1080, 1920)), '1080p', reason: 'the shorter side, not the height');
      expect(reelQualityLabel(reelQualityOf(1920, 1080)), '1080p');
      expect(reelQualityLabel(reelQualityOf(1440, 2560)), '1440p');
    });

    testWidgets('the chip reads «1080p» (or the actual quality) and is nothing while unknown', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ReelQualityChip(quality: 1080))));
      expect(find.text('1080p'), findsOneWidget);

      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ReelQualityChip(quality: 1440))));
      expect(find.text('1440p'), findsOneWidget);
      expect(find.text('1080p'), findsNothing);

      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ReelQualityChip(quality: null))));
      expect(find.byType(Text), findsNothing);
      expect(tester.getSize(find.byType(ReelQualityChip)), Size.zero);
    });
  });

  group('ReelSeekBar', () {
    /// A point in the strip [dx] from its left edge, at the line.
    Offset at(WidgetTester tester, double dx) =>
        tester.getTopLeft(find.byType(ReelSeekBar)) + Offset(dx, ReelSeekBarGeometry.stripHeight / 2);

    testWidgets('the strip is 44 px tall and a tap seeks to its point, from the left even on an RTL page',
        (tester) async {
      final bar = _BarHarness();
      await tester.pumpWidget(bar.build());
      expect(tester.getSize(find.byType(ReelSeekBar)), const Size(_BarHarness.width, kReelSeekBarHeight));
      expect(find.textContaining('/'), findsNothing, reason: 'no chip while untouched');

      await tester.tapAt(at(tester, 195));
      await tester.pump();
      expect(bar.log, ['down 0.50', 'up 0.50']);
      expect(bar.touched.value, isNull);

      bar.log.clear();
      await tester.tapAt(at(tester, 39));
      await tester.pump();
      expect(bar.log, ['down 0.10', 'up 0.10'], reason: 'the left of the strip is the start of the clip');
      bar.dispose();
    });

    testWidgets('a held finger shows the thumb and «0:12 / 0:58» above it; lifting seeks there', (tester) async {
      final bar = _BarHarness();
      await tester.pumpWidget(bar.build());

      final gesture = await tester.startGesture(at(tester, _BarHarness.width * 12 / 58));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();
      expect(bar.log, ['down 0.21']);
      expect(find.text('0:12 / 0:58'), findsOneWidget);
      final chip = tester.getCenter(find.text('0:12 / 0:58'));
      final thumbLeft = const ReelSeekBarGeometry(_BarHarness.width).thumbLeft(12 / 58);
      final thumbCentre = tester.getTopLeft(find.byType(ReelSeekBar)).dx + thumbLeft + ReelSeekBarGeometry.thumb / 2;
      expect((chip.dx - thumbCentre).abs(), lessThan(1), reason: 'the chip is centred over the thumb');
      expect(chip.dy, lessThan(at(tester, 0).dy), reason: 'the chip sits above the line');

      await gesture.up();
      await tester.pump();
      expect(bar.log, ['down 0.21', 'up 0.21']);
      expect(find.text('0:12 / 0:58'), findsNothing);
      bar.dispose();
    });

    testWidgets('a drag scrubs under the finger and seeks where it lifts; a vertical drag stays a scrub',
        (tester) async {
      final bar = _BarHarness();
      await tester.pumpWidget(bar.build());

      final gesture = await tester.startGesture(at(tester, 100));
      await tester.pump();
      await gesture.moveBy(const Offset(95, 0));
      await tester.pump();
      expect(bar.log, ['down 0.26', 'move 0.50']);
      expect(find.text('0:29 / 0:58'), findsOneWidget);

      await gesture.moveBy(const Offset(-50, 0));
      await tester.pump();
      expect(bar.log.last, 'move 0.37');
      await gesture.moveBy(const Offset(400, 0));
      await tester.pump();
      expect(bar.log.last, 'move 1.00', reason: 'past the right end the finger holds the end');
      await gesture.up();
      await tester.pump();
      expect(bar.log.last, 'up 1.00');
      expect(bar.touched.value, isNull);

      bar.log.clear();
      final upward = await tester.startGesture(at(tester, 100));
      await tester.pump();
      await upward.moveBy(const Offset(0, -40));
      await tester.pump();
      await upward.up();
      await tester.pump();
      expect(bar.log, ['down 0.26', 'move 0.26', 'up 0.26'], reason: 'the strip keeps a drag that starts in it');
      bar.dispose();
    });

    testWidgets('in a vertical PageView a drag from the strip scrubs and never turns the page; one from mid-page does',
        (tester) async {
      final bar = _BarHarness();
      final pages = PageController();
      await tester.pumpWidget(bar.paged(pages));
      final width = tester.getSize(find.byType(ReelSeekBar)).width;
      final strip = tester.getTopLeft(find.byType(ReelSeekBar)) + Offset(width / 10, ReelSeekBarGeometry.stripHeight / 2);

      // Straight up out of the strip, then sideways: still a scrub.
      final gesture = await tester.startGesture(strip);
      await tester.pump();
      await gesture.moveBy(const Offset(0, -200));
      await tester.pump();
      await gesture.moveBy(Offset(width / 10, -100));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(bar.log, ['down 0.10', 'move 0.10', 'move 0.20', 'up 0.20']);
      expect(pages.page, 0, reason: 'the page did not move under the scrub');
      expect(find.text('first'), findsOneWidget);
      expect(find.text('second'), findsNothing);

      // The same swipe from the middle of the page turns it.
      await tester.drag(find.text('first'), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(pages.page, 1);
      expect(find.text('second'), findsOneWidget);
      bar.dispose();
      pages.dispose();
    });
  });
}
