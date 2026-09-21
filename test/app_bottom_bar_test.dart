import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/presentation/widgets/app_bottom_bar.dart';

const _kInactiveLight = Color(0xFF64748B);

Widget _wrap({required String location, bool dark = false}) => MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: AppBottomBar(location: location, dark: dark),
        ),
      ),
    );

Color? _labelColor(WidgetTester tester, String label) => tester.widget<Text>(find.text(label)).style?.color;

Color? _iconColor(WidgetTester tester, IconData icon) => tester.widget<Icon>(find.byIcon(icon)).color;

/// The phone's bottom bar: home, reels raised in the middle, my list.
void main() {
  testWidgets('renders the three destinations with the reels in the centre', (tester) async {
    await tester.pumpWidget(_wrap(location: '/'));

    expect(find.text('الرئيسية'), findsOneWidget);
    expect(find.text('مشاهد'), findsOneWidget);
    expect(find.text('قائمتي'), findsOneWidget);

    final home = tester.getCenter(find.text('الرئيسية')).dx;
    final reels = tester.getCenter(find.text('مشاهد')).dx;
    final list = tester.getCenter(find.text('قائمتي')).dx;
    expect(reels, greaterThan(list), reason: 'the reels sit between the two others');
    expect(reels, lessThan(home), reason: 'right-to-left: home is the first, at the right');

    // The raised red disc with the play arrow is the middle item.
    final bar = tester.getRect(find.byType(AppBottomBar));
    final disc = tester.getCenter(find.byIcon(Icons.play_arrow_rounded));
    expect(disc.dx, moreOrLessEquals(bar.center.dx, epsilon: 1));
    expect(disc.dy, lessThan(tester.getCenter(find.byIcon(Icons.home_rounded)).dy),
        reason: 'the disc is lifted above the other icons');
    expect(_iconColor(tester, Icons.play_arrow_rounded), Colors.white);

    // Bar height: 56 plus a zero bottom inset in the test window.
    expect(bar.height, AppBottomBar.barHeight);
  });

  testWidgets('home is red on "/" and the others are muted', (tester) async {
    await tester.pumpWidget(_wrap(location: '/'));

    expect(find.byIcon(Icons.home_rounded), findsOneWidget, reason: 'filled icon when active');
    expect(find.byIcon(Icons.home_outlined), findsNothing);
    expect(_iconColor(tester, Icons.home_rounded), AppColors.primary);
    expect(_labelColor(tester, 'الرئيسية'), AppColors.primary);

    expect(_labelColor(tester, 'مشاهد'), _kInactiveLight);
    expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget, reason: 'outlined icon when inactive');
    expect(_iconColor(tester, Icons.bookmark_border_rounded), _kInactiveLight);
    expect(_labelColor(tester, 'قائمتي'), _kInactiveLight);
  });

  testWidgets('my list is red on "/my-list"', (tester) async {
    await tester.pumpWidget(_wrap(location: '/my-list'));

    expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
    expect(_iconColor(tester, Icons.bookmark_rounded), AppColors.primary);
    expect(_labelColor(tester, 'قائمتي'), AppColors.primary);

    expect(find.byIcon(Icons.home_outlined), findsOneWidget);
    expect(_iconColor(tester, Icons.home_outlined), _kInactiveLight);
    expect(_labelColor(tester, 'الرئيسية'), _kInactiveLight);
    expect(_labelColor(tester, 'مشاهد'), _kInactiveLight);
  });

  testWidgets('the dark variant paints black and lights the reels label', (tester) async {
    await tester.pumpWidget(_wrap(location: '/reels', dark: true));

    final material = tester.widget<Material>(
      find.descendant(of: find.byType(AppBottomBar), matching: find.byType(Material)).first,
    );
    expect(material.color, Colors.black);

    expect(_labelColor(tester, 'مشاهد'), AppColors.primary, reason: 'reels is the active one');
    expect(_labelColor(tester, 'الرئيسية'), Colors.white70, reason: 'inactive items are white on black');
    expect(_iconColor(tester, Icons.home_outlined), Colors.white70);
    expect(_labelColor(tester, 'قائمتي'), Colors.white70);
    expect(_iconColor(tester, Icons.play_arrow_rounded), Colors.white);
  });

  testWidgets('the light variant paints white', (tester) async {
    await tester.pumpWidget(_wrap(location: '/downloads'));

    final material = tester.widget<Material>(
      find.descendant(of: find.byType(AppBottomBar), matching: find.byType(Material)).first,
    );
    expect(material.color, Colors.white);
    // Nothing is lit on a page that is none of the three.
    expect(_labelColor(tester, 'الرئيسية'), _kInactiveLight);
    expect(_labelColor(tester, 'مشاهد'), _kInactiveLight);
    expect(_labelColor(tester, 'قائمتي'), _kInactiveLight);
  });
}
