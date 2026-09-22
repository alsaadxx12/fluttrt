import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/presentation/widgets/card_motion.dart';

/// The offset a card has been pushed to, read off the widget tree.
Offset translationOf(WidgetTester tester, Key key) {
  final box = tester.renderObject<RenderBox>(find.byKey(key));
  return box.localToGlobal(Offset.zero);
}

/// How wide a card actually paints.
///
/// Measured from the rectangle it occupies on screen rather than from a
/// transform matrix: the matrix a card reports to the root comes back as
/// identity here even while the card is visibly scaled, and the point of
/// the test is what the viewer sees.
double paintedWidth(WidgetTester tester, int i) =>
    tester.getRect(find.byKey(ValueKey('card-$i'))).width;

Widget _row({
  required ScrollController controller,
  required int count,
  required String group,
  bool focus = true,
}) {
  return Directionality(
    textDirection: TextDirection.rtl,
    child: MediaQuery(
      data: const MediaQueryData(size: Size(400, 800)),
      child: SizedBox(
        height: 200,
        width: 400,
        child: ListView.separated(
          controller: controller,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: count,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, i) {
            final card = SizedBox(
              key: ValueKey('card-$i'),
              width: 130,
              child: const ColoredBox(color: Color(0xFF123456)),
            );
            return CardEntrance(
              group: group,
              index: i,
              child: focus
                  ? CarouselFocus(
                      controller: controller,
                      index: i,
                      extent: 142,
                      width: 130,
                      child: card,
                    )
                  : card,
            );
          },
        ),
      ),
    ),
  );
}

void main() {
  setUp(CardEntrance.reset);

  group('CardEntrance', () {
    testWidgets('a card starts low and transparent, then settles', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(home: _row(controller: controller, count: 8, group: 'a', focus: false)),
      );
      // The first frame is before the stagger delay has elapsed.
      await tester.pump(const Duration(milliseconds: 16));

      final startedAt = translationOf(tester, const ValueKey('card-0')).dy;
      final opacity = tester.widget<Opacity>(
        find.descendant(of: find.byType(CardEntrance).first, matching: find.byType(Opacity)).first,
      );
      expect(opacity.opacity, lessThan(1.0), reason: 'it should be fading in');

      await tester.pumpAndSettle();
      final endedAt = translationOf(tester, const ValueKey('card-0')).dy;

      expect(startedAt, greaterThan(endedAt), reason: 'it falls from above into place');
    });

    testWidgets('the fall plays once per row, not again on rebuild', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(home: _row(controller: controller, count: 8, group: 'films', focus: false)),
      );
      await tester.pumpAndSettle();

      // The same row again — what a recycled section amounts to.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpWidget(
        MaterialApp(home: _row(controller: controller, count: 8, group: 'films', focus: false)),
      );
      await tester.pump(const Duration(milliseconds: 16));

      // Already in place on the first frame: no Opacity wrapper at all.
      expect(
        find.descendant(of: find.byType(CardEntrance).first, matching: find.byType(Opacity)),
        findsNothing,
        reason: 'a row that has made its entrance should not make it twice',
      );
    });

    testWidgets('honours the system setting for reduced motion', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MediaQuery(
              data: MediaQueryData(size: Size(400, 800), disableAnimations: true),
              child: SizedBox(
                height: 200,
                width: 400,
                child: CardEntrance(
                  group: 'quiet',
                  index: 0,
                  child: SizedBox(
                    key: ValueKey('card-0'),
                    width: 130,
                    child: ColoredBox(color: Color(0xFF123456)),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));

      expect(
        find.descendant(of: find.byType(CardEntrance), matching: find.byType(Opacity)),
        findsNothing,
        reason: 'nothing should move when the viewer has asked for stillness',
      );
    });
  });

  group('CarouselFocus', () {
    testWidgets('the card nearest the middle is the largest', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(home: _row(controller: controller, count: 12, group: 'b')),
      );
      await tester.pumpAndSettle();

      // The test surface is 800 wide, so with 142 to a card the middle of
      // the row falls around the third one.
      expect(paintedWidth(tester, 2), greaterThan(paintedWidth(tester, 0)),
          reason: 'the middle card should stand larger than the edge one');
    });

    testWidgets('scrolling moves the emphasis along the row', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(home: _row(controller: controller, count: 12, group: 'c')),
      );
      await tester.pumpAndSettle();

      // Card 5 is the last one on screen at rest, out at the edge.
      final before = paintedWidth(tester, 5);
      // Three cards along brings it under the middle of the row.
      controller.jumpTo(142 * 3.0);
      await tester.pump();
      final after = paintedWidth(tester, 5);

      expect(after, greaterThan(before),
          reason: 'card 5 was out at the edge and is now near the middle');
    });

    testWidgets('an unattached controller leaves the card alone', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            // Centred so the card keeps its own size: a route hands its
            // child tight constraints, and a SizedBox under those is simply
            // the size of the screen.
            child: Center(
              child: CarouselFocus(
                controller: controller,
                index: 0,
                extent: 142,
                width: 130,
                child: const SizedBox(key: ValueKey('lonely'), width: 130, height: 195),
              ),
            ),
          ),
        ),
      );

      expect(tester.getRect(find.byKey(const ValueKey('lonely'))).width, 130.0);
    });
  });
}
