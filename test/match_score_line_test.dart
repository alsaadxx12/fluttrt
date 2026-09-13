import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/sports/presentation/widgets/match_score_line.dart';

// Home 5 - Away 1, laid out the way every match card does it: home first.
Widget _card(TextDirection dir) => Directionality(
      textDirection: dir,
      child: const Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('HOME'),
            SizedBox(width: 20),
            MatchScoreLine(homeScore: 5, awayScore: 1, style: TextStyle(fontSize: 20)),
            SizedBox(width: 20),
            Text('AWAY'),
          ],
        ),
      ),
    );

void main() {
  for (final dir in [TextDirection.rtl, TextDirection.ltr]) {
    testWidgets('home score stays beside the home team ($dir)', (tester) async {
      await tester.pumpWidget(MaterialApp(home: _card(dir)));
      final home = tester.getCenter(find.text('HOME')).dx;
      final away = tester.getCenter(find.text('AWAY')).dx;
      final five = tester.getCenter(find.text('5')).dx;
      final one = tester.getCenter(find.text('1')).dx;
      // Whatever side the home label ends up on, "5" must be nearer to it
      // than "1" is, and "1" nearer to the away label.
      expect((five - home).abs() < (one - home).abs(), isTrue,
          reason: 'home score should sit next to HOME in $dir');
      expect((one - away).abs() < (five - away).abs(), isTrue,
          reason: 'away score should sit next to AWAY in $dir');
      // And in RTL the home side really is the right-hand side.
      if (dir == TextDirection.rtl) expect(home > away, isTrue);
    });
  }
}
