import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/presentation/widgets/house_notice.dart';

/// The Lottie inside loops for ever, so nothing here uses pumpAndSettle.
void main() {
  // Every test is a fresh launch of the app.
  setUp(HouseNotice.forgetShown);

  Widget host(HouseNotice notice) => MaterialApp(
        home: Scaffold(
          body: Stack(children: [
            const Center(child: Text('the page')),
            notice,
          ]),
        ),
      );

  testWidgets('covers the page, black to the edges, with the figure in the middle', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const HouseNotice.snacks()));
    await tester.pump(const Duration(seconds: 1));

    // The outermost Material is the backdrop; the button has one of its own.
    final material = tester.widget<Material>(find
        .descendant(of: find.byType(HouseNotice), matching: find.byType(Material))
        .first);
    expect(material.color, Colors.black);
    expect(tester.getSize(find.byType(HouseNotice)), const Size(400, 800),
        reason: 'the whole screen');

    final figure = tester.getRect(find.byType(SizedBox).at(0));
    expect(figure.width, closeTo(248, 1), reason: 'big: 62% of the width');
    expect(figure.center.dx, closeTo(200, 1), reason: 'centred');
  });

  group('each notice says its piece', () {
    testWidgets('snacks, on a film page', (tester) async {
      await tester.pumpWidget(host(const HouseNotice.snacks()));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(HouseNotice.snacksLine), findsOneWidget);
      expect(find.text(HouseNotice.snacksReason), findsOneWidget);
      expect(find.text(HouseNotice.snacksButton), findsOneWidget);
      expect(HouseNotice.snacksLine, contains('شامية'));
      expect(HouseNotice.snacksReason, contains('صحتك'));
    });

    testWidgets('welcome, when the app opens', (tester) async {
      await tester.pumpWidget(host(const HouseNotice.welcome()));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(HouseNotice.welcomeLine), findsOneWidget);
      expect(find.text(HouseNotice.welcomeReason), findsOneWidget);
      expect(HouseNotice.welcomeLine, contains('أسهرك للصبح'));
      expect(HouseNotice.welcomeReason, contains('اغلق التطبيق'));
      expect(tester.widget<HouseNotice>(find.byType(HouseNotice)).animation,
          'assets/animations/enjoying_film.json');
    });

    testWidgets('subscription, on the activation page', (tester) async {
      await tester.pumpWidget(host(const HouseNotice.subscription()));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(HouseNotice.subscriptionLine), findsOneWidget);
      expect(find.text(HouseNotice.subscriptionReason), findsOneWidget);
      expect(HouseNotice.subscriptionLine, contains('وين طوبه'));
      expect(HouseNotice.subscriptionReason, contains('شجابك'));
      expect(tester.widget<HouseNotice>(find.byType(HouseNotice)).animation,
          'assets/animations/funny_emoji.json');
    });
  });

  testWidgets('stays put until someone sends it away', (tester) async {
    var done = false;
    await tester.pumpWidget(host(HouseNotice.welcome(onDone: () => done = true)));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(seconds: 5));
    }
    expect(done, isFalse, reason: 'a minute later it is still there');
    expect(find.text(HouseNotice.welcomeLine), findsOneWidget);
  });

  testWidgets('the button dismisses it and the page underneath is reachable again', (tester) async {
    var done = false;
    await tester.pumpWidget(host(HouseNotice.snacks(onDone: () => done = true)));
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text(HouseNotice.snacksButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(done, isTrue);
    expect(find.text(HouseNotice.snacksLine), findsNothing);
    expect(find.text('the page'), findsOneWidget);
  });

  testWidgets('so does a tap anywhere on it', (tester) async {
    var done = false;
    await tester.pumpWidget(host(HouseNotice.subscription(onDone: () => done = true)));
    await tester.pump(const Duration(seconds: 1));

    await tester.tapAt(const Offset(20, 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(done, isTrue);
  });

  testWidgets('the page underneath cannot be tapped through it', (tester) async {
    await tester.pumpWidget(host(const HouseNotice.snacks()));
    await tester.pump(const Duration(seconds: 1));
    final hit = tester.hitTestOnBinding(tester.getCenter(find.text('the page')));
    expect(hit.path.any((e) => e.target == tester.renderObject(find.text('the page'))), isFalse);
  });

  testWidgets('shown over the whole app, it covers the bottom bar and pops itself off', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => HouseNotice.show(context, const HouseNotice.welcome()),
              child: const Text('open'),
            ),
          ),
          bottomNavigationBar: const SizedBox(height: 56, child: Text('bar')),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text(HouseNotice.welcomeLine), findsOneWidget);
    final hit = tester.hitTestOnBinding(tester.getCenter(find.text('bar')));
    expect(hit.path.any((e) => e.target == tester.renderObject(find.text('bar'))), isFalse,
        reason: 'the bar is under the notice');

    await tester.tap(find.text(HouseNotice.welcomeButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(HouseNotice), findsNothing, reason: 'the route is gone');
    expect(find.text('open'), findsOneWidget);
  });

  group('once per launch', () {
    testWidgets('the film-page joke is shown the first time only', (tester) async {
      await tester.pumpWidget(host(const HouseNotice.snacks()));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(HouseNotice.snacksLine), findsOneWidget);
      expect(HouseNotice.shownThisLaunch('snacks'), isTrue);

      // Out of the film and into another one: a new page, the same launch.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(host(const HouseNotice.snacks()));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(HouseNotice.snacksLine), findsNothing,
          reason: 'funny the first time, a chore the fifth');
      expect(find.text('the page'), findsOneWidget);
    });

    testWidgets('each notice is counted on its own', (tester) async {
      await tester.pumpWidget(host(const HouseNotice.snacks()));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(host(const HouseNotice.subscription()));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(HouseNotice.subscriptionLine), findsOneWidget,
          reason: 'the subscription page has not had its turn yet');
    });

    testWidgets('a notice without a key is shown every time', (tester) async {
      Widget gate() => host(const HouseNotice(
            animation: 'assets/animations/funny_joker.json',
            line: 'x',
            reason: 'y',
            button: 'z',
          ));
      await tester.pumpWidget(gate());
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(gate());
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('x'), findsOneWidget);
    });
  });
}
