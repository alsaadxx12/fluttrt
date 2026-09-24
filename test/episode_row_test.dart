import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/presentation/widgets/episode_row.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  testWidgets('every episode is a card with its number, the first at the right', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tapped = <int>[];
    await tester.pumpWidget(_wrap(EpisodeRow(
      tiles: [for (var i = 1; i <= 3; i++) EpisodeTile(label: 'الحلقة $i')],
      onTap: tapped.add,
    )));
    await tester.pump();

    expect(find.text('الحلقة 1'), findsOneWidget);
    expect(find.text('الحلقة 3'), findsOneWidget);
    final first = tester.getTopLeft(find.text('الحلقة 1'));
    final second = tester.getTopLeft(find.text('الحلقة 2'));
    expect(first.dx, greaterThan(second.dx), reason: 'the row reads right to left');

    await tester.tap(find.text('الحلقة 2'));
    expect(tapped, [1]);
  });

  testWidgets('the episode playing is ringed in red and the row opens on it', (tester) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(EpisodeRow(
      tiles: [for (var i = 1; i <= 12; i++) EpisodeTile(label: 'الحلقة $i')],
      currentIndex: 9,
      onTap: (_) {},
    )));
    await tester.pump();

    // Scrolled to the tenth: the first is off the edge, the tenth in view.
    expect(find.text('الحلقة 1'), findsNothing);
    expect(find.text('الحلقة 10'), findsOneWidget);

    final card =
        tester.widget<Container>(find.ancestor(of: find.text('الحلقة 10'), matching: find.byType(Container)).first);
    final border = (card.decoration as BoxDecoration).border as Border;
    expect(border.top.color, AppColors.primary);
  });
}
