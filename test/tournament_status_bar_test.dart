import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/sports/presentation/screens/tournament_screen.dart';

void main() {
  testWidgets('the tournaments page asks for light status-bar icons over its banner', (tester) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    tester.view.padding = const FakeViewPadding(top: 90);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Builder(
          builder: (context) => AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.dark,
            child: Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  CupertinoPageRoute<void>(builder: (_) => const TournamentScreen()),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    final styles = calls
        .where((c) => c.method == 'SystemChrome.setSystemUIOverlayStyle')
        .map((c) => (c.arguments as Map)['statusBarIconBrightness'])
        .toList();
    expect(styles, isNotEmpty);
    expect(styles.last, 'Brightness.light');
  });
}
