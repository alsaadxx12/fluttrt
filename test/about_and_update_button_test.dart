import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_downloader/core/services/storage_service.dart';
import 'package:youtube_downloader/features/about/presentation/screens/about_screen.dart';
import 'package:youtube_downloader/features/settings/presentation/providers/settings_provider.dart';
import 'package:youtube_downloader/features/update/data/update_service.dart';
import 'package:youtube_downloader/features/update/presentation/update_controller.dart';

import 'support/fake_update_service.dart';

Future<Widget> _about(UpdateService service,
    {int installedCode = 4, String installedName = '1.0.2', Brightness brightness = Brightness.dark}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      storageServiceProvider.overrideWithValue(StorageService(prefs)),
      updateServiceProvider.overrideWithValue(service),
      installedVersionProvider.overrideWith((ref) async => InstalledVersion(
            versionCode: installedCode,
            versionName: installedName,
            packageName: 'com.antigravity.yt.youtube_downloader',
          )),
    ],
    child: MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: const Directionality(textDirection: TextDirection.rtl, child: AboutScreen()),
    ),
  );
}

ProviderContainer _containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(AboutScreen)));

void main() {
  testWidgets('the about page shows the version that is actually installed', (tester) async {
    await tester.pumpWidget(await _about(FakeUpdateService(null), installedCode: 4, installedName: '1.0.2'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('الإصدار 1.0.2 (4)'), findsOneWidget);
    expect(find.textContaining('1.0.0'), findsNothing, reason: 'the old hard-coded version must be gone');
  });

  testWidgets('a different build shows a different number, not a frozen string', (tester) async {
    await tester.pumpWidget(await _about(FakeUpdateService(null), installedCode: 7, installedName: '1.1.0'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('الإصدار 1.1.0 (7)'), findsOneWidget);
    expect(find.text('الإصدار 1.0.2 (4)'), findsNothing);
  });

  testWidgets('with no newer build the page says so and offers a manual check', (tester) async {
    await tester.pumpWidget(await _about(FakeUpdateService(updateInfo(code: 4), current: 4)));
    await tester.pump();
    final c = _containerOf(tester);
    await c.read(updateControllerProvider.notifier).checkForUpdate();
    await tester.pump();

    expect(find.text('أنت على أحدث إصدار'), findsOneWidget);
    expect(find.text('التحقق من التحديثات'), findsOneWidget);
    expect(find.text('تحديث الآن'), findsNothing);
    expect(c.read(updateControllerProvider).hasUpdate, isFalse);
  });

  testWidgets('with a newer build the page offers the update', (tester) async {
    await tester.pumpWidget(await _about(FakeUpdateService(updateInfo(code: 5), current: 4), installedCode: 4));
    await tester.pump();
    final c = _containerOf(tester);
    await c.read(updateControllerProvider.notifier).checkForUpdate();
    await tester.pump();

    expect(c.read(updateControllerProvider).hasUpdate, isTrue);
    expect(find.text('يتوفر تحديث جديد'), findsOneWidget);
    expect(find.text('1.0.2 (5)'), findsOneWidget, reason: 'the new version is named');
    expect(find.text('تحديث الآن'), findsOneWidget);
    expect(find.text('التحقق من التحديثات'), findsNothing);
  });

  test('the update button is live only when a newer build is waiting', () async {
    final container = ProviderContainer(
      overrides: [updateServiceProvider.overrideWithValue(FakeUpdateService(updateInfo(code: 5), current: 4))],
    );
    addTearDown(container.dispose);
    final notifier = container.read(updateControllerProvider.notifier);

    expect(container.read(updateControllerProvider).hasUpdate, isFalse, reason: 'nothing known before the check');
    await notifier.checkForUpdate();
    expect(container.read(updateControllerProvider).hasUpdate, isTrue);

    // "Later" hides the prompt but the button stays live.
    notifier.dismiss();
    expect(container.read(updateControllerProvider).shouldPrompt, isFalse);
    expect(container.read(updateControllerProvider).hasUpdate, isTrue);

    // The button brings the prompt back.
    notifier.showPrompt();
    expect(container.read(updateControllerProvider).shouldPrompt, isTrue);
  });

  test('an up-to-date app leaves the button inactive', () async {
    final container = ProviderContainer(
      overrides: [updateServiceProvider.overrideWithValue(FakeUpdateService(updateInfo(code: 4), current: 4))],
    );
    addTearDown(container.dispose);
    await container.read(updateControllerProvider.notifier).checkNow();
    final state = container.read(updateControllerProvider);
    expect(state.hasUpdate, isFalse);
    expect(state.shouldPrompt, isFalse);
  });

  for (final brightness in Brightness.values) {
    testWidgets('the page lays out on a small phone in ${brightness.name} mode', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(await _about(FakeUpdateService(updateInfo(code: 9), current: 4), brightness: brightness));
      await tester.pump();
      final c = _containerOf(tester);
      await c.read(updateControllerProvider.notifier).checkForUpdate();
      await tester.pump();

      // An overflowing row or column reports itself as an exception here.
      expect(tester.takeException(), isNull);
      expect(find.text('CINEBALL'), findsOneWidget);
      expect(find.text('Ali Alsaady'), findsOneWidget);
      // The page carries no shared top bar and no search field of its own.
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget, reason: 'a way back remains');
      expect(find.text('تجربة التحديث'), findsOneWidget, reason: 'release notes on the card');
      // Plumbing the user has no use for stays out of the page.
      expect(find.textContaining('com.antigravity'), findsNothing);
      expect(find.textContaining('netlify.app'), findsNothing);
    });
  }
}
