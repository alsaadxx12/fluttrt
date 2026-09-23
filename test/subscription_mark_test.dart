import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';

/// The animation beside «المباريات» in the drawer.
///
/// Checked as a file and as something Lottie will actually accept: an
/// animation that fails to parse falls back to a plain tick, which is a
/// quiet way for an asset to go missing and never be noticed.
void main() {
  const path = 'assets/animations/screencast.json';

  test('the animation is bundled and is a real Lottie file', () {
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: 'the drawer asks for this by name');

    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(json['v'], isNotNull, reason: 'a Lottie file states its version');
    expect(json['layers'], isA<List>());
    expect((json['layers'] as List), isNotEmpty);
    expect(json['w'], isA<num>());
    expect(json['h'], isA<num>());
  });

  test('Lottie parses it into a composition', () async {
    final bytes = await File(path).readAsBytes();
    final composition = await LottieComposition.fromBytes(bytes);

    expect(composition.duration.inMilliseconds, greaterThan(0),
        reason: 'an animation of no length would sit still');
    expect(composition.bounds.width, greaterThan(0));
  });

  test('the cast sheet animation is bundled and parses too', () async {
    const tv = 'assets/animations/live_tv.json';
    expect(File(tv).existsSync(), isTrue,
        reason: 'the cast sheet asks for this by name');

    final composition =
        await LottieComposition.fromBytes(await File(tv).readAsBytes());
    expect(composition.duration.inMilliseconds, greaterThan(0));
    expect(composition.bounds.width, greaterThan(0));

    expect(
      File('lib/features/casting/widgets/cast_device_sheet.dart')
          .readAsStringSync(),
      contains(tv),
    );
  });

  test('every bundled animation is used by something', () {
    // An asset nobody asks for is 200 KB in every install for nothing.
    final used = [
      File('lib/presentation/widgets/app_drawer.dart').readAsStringSync(),
      File('lib/features/casting/widgets/cast_device_sheet.dart')
          .readAsStringSync(),
      File('lib/presentation/widgets/house_notice.dart').readAsStringSync(),
      File('lib/features/sports/presentation/screens/sports_player_screen.dart')
          .readAsStringSync(),
    ].join();

    for (final asset in Directory('assets/animations').listSync()) {
      final name = asset.path.replaceAll(r'\', '/').split('/').last;
      expect(used, contains(name), reason: '$name is bundled but unused');
    }
  });

  test('it is listed in the pubspec, or it will not ship', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('assets/animations/'),
        reason: 'an asset folder that is not declared is not bundled, and the '
            'drawer would quietly fall back to the tick on every phone');
  });
}
