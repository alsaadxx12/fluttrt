import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/update/data/update_service.dart';
import 'package:youtube_downloader/features/update/presentation/update_controller.dart';
import 'package:youtube_downloader/features/update/presentation/update_gate.dart';

import 'support/fake_update_service.dart';

/// The app exactly as main.dart builds it: the gate lives in MaterialApp's
/// `builder`, which sits ABOVE the Navigator.
Widget _app(UpdateService service) => ProviderScope(
      overrides: [updateServiceProvider.overrideWithValue(service)],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: UpdateGate(child: child ?? const SizedBox.shrink()),
        ),
        home: const Scaffold(body: Center(child: Text('الصفحة الرئيسية'))),
      ),
    );

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 3)); // the delayed background check
  // The check awaits the service a few times; give each hop a frame.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  testWidgets('an optional update shows the prompt over the app, above the Navigator', (tester) async {
    await tester.pumpWidget(_app(FakeUpdateService(updateInfo())));
    expect(find.text('الصفحة الرئيسية'), findsOneWidget);
    expect(find.text('يتوفر تحديث جديد'), findsNothing, reason: 'nothing before the check runs');

    await _settle(tester);

    // This is what a showDialog from the builder context could never do.
    expect(tester.takeException(), isNull);
    expect(find.text('يتوفر تحديث جديد'), findsOneWidget);
    expect(find.textContaining('1.0.1 (3)'), findsOneWidget, reason: 'current version');
    expect(find.textContaining('1.0.2 (4)'), findsOneWidget, reason: 'new version');
    expect(find.text('تجربة التحديث'), findsOneWidget, reason: 'release notes');
    expect(find.text('تحديث الآن'), findsOneWidget);
    expect(find.text('لاحقًا'), findsOneWidget);
    expect(find.text('الصفحة الرئيسية'), findsOneWidget, reason: 'the app stays behind the card');
  });

  testWidgets('"لاحقًا" puts an optional update off', (tester) async {
    await tester.pumpWidget(_app(FakeUpdateService(updateInfo())));
    await _settle(tester);
    expect(find.text('يتوفر تحديث جديد'), findsOneWidget);

    await tester.tap(find.text('لاحقًا'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('يتوفر تحديث جديد'), findsNothing);
    expect(find.text('الصفحة الرئيسية'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a forced update blocks the app and offers no way out', (tester) async {
    await tester.pumpWidget(_app(FakeUpdateService(updateInfo(force: true))));
    await _settle(tester);

    expect(find.text('يتوفر تحديث جديد'), findsOneWidget);
    expect(find.text('هذا التحديث ضروري لمتابعة استخدام التطبيق'), findsOneWidget);
    expect(find.text('لاحقًا'), findsNothing, reason: 'a forced update cannot be put off');
    expect(find.text('تحديث الآن'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('below minSupportedVersion is forced too', (tester) async {
    await tester.pumpWidget(_app(FakeUpdateService(updateInfo(min: 4))));
    await _settle(tester);
    expect(find.text('هذا التحديث ضروري لمتابعة استخدام التطبيق'), findsOneWidget);
    expect(find.text('لاحقًا'), findsNothing);
  });

  testWidgets('an up-to-date app shows nothing at all', (tester) async {
    await tester.pumpWidget(_app(FakeUpdateService(updateInfo(code: 3), current: 3)));
    await _settle(tester);
    expect(find.text('يتوفر تحديث جديد'), findsNothing);
    expect(find.text('الصفحة الرئيسية'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed check never blocks the app', (tester) async {
    await tester.pumpWidget(_app(FakeUpdateService(null)));
    await _settle(tester);
    expect(find.text('يتوفر تحديث جديد'), findsNothing);
    expect(find.text('الصفحة الرئيسية'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
