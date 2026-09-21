import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
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

Color? _labelColor(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label)).style?.color;

Color? _iconColor(WidgetTester tester, IconData icon) =>
    tester.widget<Icon>(find.byIcon(icon)).color;

void main() {
  testWidgets('renders the three destinations with the reels in the centre',
      (tester) async {
    await tester.pumpWidget(_wrap(location: '/'));

    expect(find.text('الرئيسية'), findsOneWidget);
    expect(find.text('مشاهد'), findsOneWidget);
    expect(find.text('قائمتي'), findsOneWidget);

    final home = tester.getCenter(find.text('الرئيسية')).dx;
    final reels = tester.getCenter(find.text('مشاهد')).dx;
    final list = tester.getCenter(find.text('قائمتي')).dx;
    expect(reels, greaterThan(list),
        reason: 'the reels sit between the two others');
    expect(reels, lessThan(home),
        reason: 'right-to-left: home is the first, at the right');

    // The raised play arrow button is in the middle inside the arch.
    final bar = tester.getRect(find.byType(AppBottomBar));
    final disc = tester.getCenter(find.byIcon(Icons.play_arrow_rounded));
    expect(disc.dx, moreOrLessEquals(bar.center.dx, epsilon: 1));
    expect(
        disc.dy, lessThan(tester.getCenter(find.byIcon(Icons.home_rounded)).dy),
        reason: 'the disc is lifted above the other icons into the arch');
    expect(_iconColor(tester, Icons.play_arrow_rounded), Colors.white);

    // Bar height: 64 plus zero bottom inset in test window.
    expect(bar.height, AppBottomBar.barHeight);
  });

  testWidgets('home is active on "/" and labels reflect active state',
      (tester) async {
    await tester.pumpWidget(_wrap(location: '/'));

    expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    expect(_iconColor(tester, Icons.home_rounded), Colors.white);
    expect(_labelColor(tester, 'الرئيسية'), AppColors.primary);

    expect(
        _labelColor(tester, 'مشاهد'), isNot(equals(AppColors.primary)));
    expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
    expect(_iconColor(tester, Icons.bookmark_rounded), Colors.white);
    expect(
        _labelColor(tester, 'قائمتي'), isNot(equals(AppColors.primary)));
  });

  testWidgets('my list is active on "/my-list"', (tester) async {
    await tester.pumpWidget(_wrap(location: '/my-list'));

    expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
    expect(_iconColor(tester, Icons.bookmark_rounded), Colors.white);
    expect(_labelColor(tester, 'قائمتي'), AppColors.primary);

    expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    expect(_iconColor(tester, Icons.home_rounded), Colors.white);
    expect(
        _labelColor(tester, 'الرئيسية'), isNot(equals(AppColors.primary)));
    expect(
        _labelColor(tester, 'مشاهد'), isNot(equals(AppColors.primary)));
  });

  testWidgets('reels is active on "/reels"', (tester) async {
    await tester.pumpWidget(_wrap(location: '/reels'));

    expect(_labelColor(tester, 'مشاهد'), AppColors.primary);
    expect(
        _labelColor(tester, 'الرئيسية'), isNot(equals(AppColors.primary)));
    expect(
        _labelColor(tester, 'قائمتي'), isNot(equals(AppColors.primary)));
    expect(_iconColor(tester, Icons.play_arrow_rounded), Colors.white);
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
