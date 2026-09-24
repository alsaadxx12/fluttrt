import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';
import 'package:youtube_downloader/presentation/widgets/app_bottom_bar.dart';

Widget _wrap({required String location, bool dark = true}) => MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: AppBottomBar(location: location, dark: dark),
        ),
      ),
    );

Color? _iconColor(WidgetTester tester, IconData icon) =>
    tester.widget<Icon>(find.byIcon(icon)).color;

/// Whether the destination reached by [icon] is showing its marker dot.
///
/// The dot is scaled from nothing rather than faded, so an inactive one is
/// present in the tree at zero size. Measuring what it paints is the only
/// honest way to ask whether it is there to be seen.
bool _marked(WidgetTester tester, IconData icon) {
  final column = find.ancestor(of: find.byIcon(icon), matching: find.byType(Column));
  final dot = find.descendant(of: column.first, matching: find.byType(Container));
  if (dot.evaluate().isEmpty) return false;
  return tester.getRect(dot.first).width > 1;
}

void main() {
  testWidgets('renders the three destinations with the reels in the centre',
      (tester) async {
    await tester.pumpWidget(_wrap(location: '/'));

    // No words on the bar at all — the icons carry it.
    expect(find.text('الرئيسية'), findsNothing);
    expect(find.text('مشاهد'), findsNothing);
    expect(find.text('قائمتي'), findsNothing);

    final home = tester.getCenter(find.byIcon(Icons.home_rounded)).dx;
    final reels = tester.getCenter(find.byIcon(Icons.play_arrow_rounded)).dx;
    final list = tester.getCenter(find.byIcon(Icons.bookmark_border_rounded)).dx;
    expect(reels, greaterThan(list),
        reason: 'the reels sit between the two others');
    expect(reels, lessThan(home),
        reason: 'right-to-left: home is the first, at the right');

    final bar = tester.getRect(find.byType(AppBottomBar));
    final disc = tester.getCenter(find.byIcon(Icons.play_arrow_rounded));
    expect(disc.dx, moreOrLessEquals(bar.center.dx, epsilon: 1));
    expect(disc.dy, lessThan(tester.getCenter(find.byIcon(Icons.home_rounded)).dy),
        reason: 'the disc is lifted above the other icons into the arch');
    expect(_iconColor(tester, Icons.play_arrow_rounded), Colors.white);

    expect(bar.height, AppBottomBar.barHeight);
  });

  testWidgets('the words are gone from the bar but not from a screen reader',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(location: '/'));

    expect(find.bySemanticsLabel('الرئيسية'), findsOneWidget);
    expect(find.bySemanticsLabel('مشاهد'), findsOneWidget);
    expect(find.bySemanticsLabel('قائمتي'), findsOneWidget);

    handle.dispose();
  });

  testWidgets('the page you are on is the solid, marked icon', (tester) async {
    await tester.pumpWidget(_wrap(location: '/'));
    await tester.pumpAndSettle();

    // Solid for the page you are on, outlined for the one you are not.
    expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_rounded), findsNothing);

    // The page's ink: white by night, navy by day (the test app is light).
    expect(_iconColor(tester, Icons.home_rounded), const AppPalette.light().text);
    expect(_marked(tester, Icons.home_rounded), isTrue);
    expect(_marked(tester, Icons.bookmark_border_rounded), isFalse);
  });

  testWidgets('moving to my list moves the marker with it', (tester) async {
    await tester.pumpWidget(_wrap(location: '/my-list'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
    expect(find.byIcon(Icons.home_outlined), findsOneWidget);
    expect(find.byIcon(Icons.home_rounded), findsNothing);

    expect(_marked(tester, Icons.bookmark_rounded), isTrue);
    expect(_marked(tester, Icons.home_outlined), isFalse);
  });

  testWidgets('the icon settles into place rather than jumping', (tester) async {
    await tester.pumpWidget(_wrap(location: '/'));
    await tester.pumpAndSettle();
    final resting = tester.getRect(find.byIcon(Icons.home_rounded));

    // Switch away. One frame later it is on its way down but has not yet
    // reached the halfway point where the solid icon gives way to the
    // outline, so it is still the filled one — moved, not swapped.
    await tester.pumpWidget(_wrap(location: '/my-list'));
    await tester.pump(const Duration(milliseconds: 80));
    final moving = tester.getRect(find.byIcon(Icons.home_rounded));

    expect(moving.top, isNot(moreOrLessEquals(resting.top, epsilon: 0.01)),
        reason: 'it should be animating, not snapping');

    await tester.pumpAndSettle();
    final settled = tester.getRect(find.byIcon(Icons.home_outlined));
    expect(settled.top, greaterThan(resting.top),
        reason: 'the icon it lit drops back down when it loses the page');
  });

  testWidgets('reels swells when it is the page you are on', (tester) async {
    await tester.pumpWidget(_wrap(location: '/'));
    await tester.pumpAndSettle();
    final idle = tester.getRect(find.byIcon(Icons.play_arrow_rounded)).width;

    await tester.pumpWidget(_wrap(location: '/reels'));
    await tester.pumpAndSettle();
    final active = tester.getRect(find.byIcon(Icons.play_arrow_rounded)).width;

    expect(active, greaterThan(idle));
    expect(_iconColor(tester, Icons.play_arrow_rounded), Colors.white);
  });

  testWidgets('nothing moves when the viewer has asked for stillness',
      (tester) async {
    Widget quiet(String location) => MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: Scaffold(
                body: const SizedBox.expand(),
                bottomNavigationBar:
                    AppBottomBar(location: location, dark: true),
              ),
            ),
          ),
        );

    await tester.pumpWidget(quiet('/'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(quiet('/my-list'));
    await tester.pump(const Duration(milliseconds: 16));

    // Already where it belongs on the very next frame.
    expect(_marked(tester, Icons.bookmark_rounded), isTrue);
    expect(_marked(tester, Icons.home_outlined), isFalse);
  });

  testWidgets('CustomPaint is present with curved arch wave painter',
      (tester) async {
    await tester.pumpWidget(_wrap(location: '/'));

    expect(
      find.descendant(
        of: find.byType(AppBottomBar),
        matching: find.byType(CustomPaint),
      ),
      findsWidgets,
    );
  });
}
