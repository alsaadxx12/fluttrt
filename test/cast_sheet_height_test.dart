import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:youtube_downloader/features/casting/widgets/cast_device_sheet.dart';

/// How tall the cast sheet actually stands.
///
/// Written because getting this wrong is invisible in the code and obvious
/// on a phone: removing `mainAxisSize.min` to make a `Spacer` work turned
/// «at least half the screen» into the whole of it, and the sheet climbed
/// to the top of the display.
void main() {
  // The sheet builds the cast controller, which reaches for Supabase. A
  // client pointed at nowhere is enough: nothing here asks it to talk.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      // The same call main.dart makes, and the same reason for the ignore:
      // the replacement is not in this pinned supabase_flutter yet.
      // ignore: deprecated_member_use
      anonKey: 'test',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
  });

  testWidgets('the sheet is six tenths of the screen, not all of it', (tester) async {
    const screen = Size(400, 800);
    // The view, not the surface: setSurfaceSize resizes what is drawn but
    // leaves MediaQuery reporting the default 800x600, and the sheet sizes
    // itself from MediaQuery. Measuring against the wrong number would have
    // made a correct sheet look wrong.
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => showCastDeviceSheet(context),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    // Pumped rather than settled: the television on the sheet loops for
    // ever, so the tree never goes quiet and pumpAndSettle waits for a
    // stillness that is never coming. Long enough for the sheet to slide
    // up is all this needs.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final sheet = find.byKey(const ValueKey('cast-sheet'));
    final height = tester.getSize(sheet).height;

    expect(height, moreOrLessEquals(screen.height * 0.62, epsilon: 1),
        reason: 'six tenths of the display, so the sheet stops well short of the top');
    expect(height, lessThan(screen.height * 0.7),
        reason: 'it should never climb to the top of the screen');

    // And it sits on the bottom edge, as a bottom sheet does.
    final box = tester.getRect(sheet);
    expect(box.bottom, moreOrLessEquals(screen.height, epsilon: 1));
    expect(box.top, greaterThan(screen.height * 0.35),
        reason: 'its top edge is around the middle of the display');

    // Close it and let the tree go: the sheet starts a search for screens
    // on a repeating timer, and leaving that running outlives the test.
    await tester.pumpWidget(const SizedBox());
    // A search that was already under way keeps its own short timers until
    // it gives up; a few seconds of pumped time lets them run out.
    await tester.pump(const Duration(seconds: 8));
  });
}
