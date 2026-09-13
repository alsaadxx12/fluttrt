import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/presentation/widgets/reveal.dart';

/// The child's visibility. A settled Reveal keeps no Opacity layer at all,
/// which is the cheap end state, so its absence reads as fully visible.
double _opacityOf(WidgetTester tester) {
  final layers = tester.widgetList<Opacity>(find.byType(Opacity));
  return layers.isEmpty ? 1.0 : layers.first.opacity;
}

Widget _wrap(Widget child, {bool reduceMotion = false}) => MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Directionality(textDirection: TextDirection.rtl, child: child),
    );

void main() {
  testWidgets('a revealed section fades and rises into place, then settles', (tester) async {
    await tester.pumpWidget(_wrap(const Reveal(child: Text('قسم'))));

    await tester.pump();
    expect(_opacityOf(tester), lessThan(0.2), reason: 'starts invisible');

    await tester.pump(const Duration(milliseconds: 200));
    final mid = _opacityOf(tester);
    expect(mid, greaterThan(0.2));
    expect(mid, lessThan(1.0), reason: 'still on its way in');

    await tester.pumpAndSettle();
    expect(_opacityOf(tester), 1.0, reason: 'ends fully visible');
    expect(find.byType(Opacity), findsNothing, reason: 'no layer is left behind to repaint');
    expect(find.text('قسم'), findsOneWidget);
  });

  testWidgets('later cards start later, within the animated range', (tester) async {
    await tester.pumpWidget(_wrap(
      const Row(children: [
        Reveal(index: 0, child: SizedBox(width: 10)),
        Reveal(index: 4, child: SizedBox(width: 10)),
      ]),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final opacities = tester.widgetList<Opacity>(find.byType(Opacity)).map((o) => o.opacity).toList();
    expect(opacities.first, greaterThan(opacities.last), reason: 'the first card is ahead of the later one');

    await tester.pumpAndSettle();
    expect(find.byType(Opacity), findsNothing, reason: 'both finish and drop their layers');
  });

  testWidgets('a card deep in a list appears at once', (tester) async {
    // Lists recycle their children: animating position 40 would replay the
    // entrance every time that card scrolled back into view, which reads as
    // slow loading and costs a controller and a timer each time.
    await tester.pumpWidget(_wrap(const Reveal(index: 40, child: Text('بطاقة'))));
    await tester.pump();

    expect(_opacityOf(tester), 1.0);
    expect(find.byType(Opacity), findsNothing, reason: 'no animation was ever started');
    expect(find.text('بطاقة'), findsOneWidget);
  });

  testWidgets('reduced motion shows everything at once', (tester) async {
    await tester.pumpWidget(_wrap(const Reveal(index: 9, child: Text('قسم')), reduceMotion: true));
    await tester.pump();
    expect(_opacityOf(tester), 1.0, reason: 'no animation when the platform asks for none');
  });

  testWidgets('an image settles in from oversize to its own size', (tester) async {
    await tester.pumpWidget(_wrap(const RevealImage(child: SizedBox(width: 50, height: 50))));
    await tester.pump();
    final start = tester.widget<Transform>(find.byType(Transform).first).transform.getMaxScaleOnAxis();
    expect(start, greaterThan(1.0), reason: 'starts a hair oversized');

    await tester.pumpAndSettle();
    expect(_opacityOf(tester), 1.0);
    expect(find.byType(Transform), findsNothing, reason: 'settled, so the transform is dropped');
  });

  testWidgets('the shimmer keeps sweeping while content loads, and stops for reduced motion', (tester) async {
    await tester.pumpWidget(_wrap(const Shimmer(
      base: Color(0xFF141926),
      highlight: Color(0xFF1E2636),
      child: SizedBox(width: 100, height: 100),
    )));
    await tester.pump();
    // The sweep is painted as a moving gradient: no offscreen layer per frame.
    expect(find.byType(ShaderMask), findsNothing, reason: 'a shader layer would repaint the whole box every frame');
    final sweeping = tester.widget<DecoratedBox>(find.byType(DecoratedBox).first).decoration as BoxDecoration;
    expect(sweeping.gradient, isNotNull);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);

    // A placeholder that never resolves stops sweeping instead of burning a
    // repaint for the rest of the session.
    await tester.pump(const Duration(seconds: 10));
    final before = tester.widget<DecoratedBox>(find.byType(DecoratedBox).first).decoration;
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<DecoratedBox>(find.byType(DecoratedBox).first).decoration, before,
        reason: 'the sweep has settled');

    await tester.pumpWidget(_wrap(
      const Shimmer(
        base: Color(0xFF141926),
        highlight: Color(0xFF1E2636),
        child: SizedBox(width: 100, height: 100),
      ),
      reduceMotion: true,
    ));
    await tester.pump();
    expect(find.byType(ColoredBox), findsWidgets, reason: 'a plain block instead of a sweep');
  });

  testWidgets('a card presses in under the finger and springs back', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_wrap(Center(
      child: PressScale(onTap: () => taps++, child: const SizedBox(width: 100, height: 100)),
    )));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1.0);

    final gesture = await tester.startGesture(tester.getCenter(find.byType(PressScale)));
    await tester.pump(const Duration(milliseconds: 150)); // past the press deadline
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, lessThan(1.0),
        reason: 'pressed in while held');

    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1.0, reason: 'springs back');
    expect(taps, 1);
  });

  testWidgets('reduced motion keeps the card still but still tappable', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_wrap(
      Center(child: PressScale(onTap: () => taps++, child: const SizedBox(width: 100, height: 100))),
      reduceMotion: true,
    ));
    final gesture = await tester.startGesture(tester.getCenter(find.byType(PressScale)));
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1.0);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(taps, 1);
  });
}
