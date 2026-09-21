import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/presentation/widgets/app_search_field.dart';

Widget _wrap(Widget child, {bool reduceMotion = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: Center(child: SizedBox(width: 320, child: child))),
        ),
      ),
    );

/// The search field's living hint: it names what the app can find, one
/// phrase after another, and steps aside the moment there is text.
void main() {
  testWidgets('the empty field cycles through its hints', (tester) async {
    await tester.pumpWidget(_wrap(const AppSearchField()));
    await tester.pump();
    expect(find.text(AppSearchField.defaultHints[0]), findsOneWidget, reason: 'starts with the first phrase');

    await tester.pump(const Duration(milliseconds: 2700));
    await tester.pumpAndSettle();
    expect(find.text(AppSearchField.defaultHints[1]), findsOneWidget, reason: 'the next phrase has taken its place');
    expect(find.text(AppSearchField.defaultHints[0]), findsNothing, reason: 'the old one has left');
  });

  testWidgets('typing hides the hint, clearing brings it back', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(_wrap(AppSearchField(controller: controller)));
    await tester.pump();
    expect(find.text(AppSearchField.defaultHints[0]), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'ناروتو');
    await tester.pump();
    expect(find.text(AppSearchField.defaultHints[0]), findsNothing, reason: 'no hint over typed text');

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(find.textContaining('ابحث عن'), findsOneWidget, reason: 'the hint is back once the field is empty');
    controller.dispose();
  });

  testWidgets('a page with one job shows its own fixed hint', (tester) async {
    await tester.pumpWidget(_wrap(const AppSearchField(hintText: 'ابحث عن قناة')));
    await tester.pump();
    expect(find.text('ابحث عن قناة'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('ابحث عن قناة'), findsOneWidget, reason: 'a single hint never changes');
  });

  testWidgets('reduced motion keeps one phrase still', (tester) async {
    await tester.pumpWidget(_wrap(const AppSearchField(), reduceMotion: true));
    await tester.pump();
    expect(find.text(AppSearchField.defaultHints[0]), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text(AppSearchField.defaultHints[0]), findsOneWidget);
    expect(find.byType(AnimatedSwitcher), findsNothing);
  });
}
