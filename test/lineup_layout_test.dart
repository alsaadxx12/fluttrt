import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/sports/data/models/sports_models.dart';
import 'package:youtube_downloader/features/sports/presentation/lineup_layout.dart';

PlayerLineupItem p(String name, int line, {double side = 50}) =>
    PlayerLineupItem(id: name.hashCode, name: name, isStarter: true, line: line, fieldSide: side);

int countIn(List<List<PlayerLineupItem>> rows) => rows.fold(0, (n, r) => n + r.length);

void main() {
  test('a 4-2-3-1 keeps all eleven, striker included', () {
    // Exactly how the feed numbers this shape: the lone striker sits on
    // line 5, which the old pitch never read.
    final starters = [
      p('GK', 1),
      p('LB', 2, side: 0), p('CB1', 2, side: 33), p('CB2', 2, side: 66), p('RB', 2, side: 100),
      p('DM', 3, side: 20), p('CM', 3, side: 80),
      p('LW', 4, side: 0), p('AM', 4, side: 50), p('RW', 4, side: 100),
      p('ST', 5, side: 50),
    ];

    final rows = groupStartersByLine(starters);

    expect(countIn(rows), 11, reason: 'no player may be dropped');
    expect(rows.first.single.name, 'ST', reason: 'furthest forward is drawn first');
    expect(rows.last.single.name, 'GK', reason: 'the keeper is drawn last');
    expect(rows.length, 5);
  });

  test('a 4-4-2 with no fifth line still works', () {
    final starters = [
      p('GK', 1),
      for (var i = 0; i < 4; i++) p('D$i', 2, side: i * 33),
      for (var i = 0; i < 4; i++) p('M$i', 3, side: i * 33),
      p('F1', 4, side: 35), p('F2', 4, side: 65),
    ];
    final rows = groupStartersByLine(starters);
    expect(countIn(rows), 11);
    expect(rows.length, 4);
    expect(rows.first.length, 2, reason: 'two forwards on top');
  });

  test('players in a row read left to right across the pitch', () {
    final rows = groupStartersByLine([
      p('right', 2, side: 100),
      p('left', 2, side: 0),
      p('middle', 2, side: 50),
    ]);
    expect(rows.single.map((x) => x.name), ['left', 'middle', 'right']);
  });

  test('a feed with no line data still draws a readable shape', () {
    final starters = [for (var i = 0; i < 11; i++) p('P$i', 0)];
    final rows = groupStartersByLine(starters);
    expect(countIn(rows), 11, reason: 'still nobody dropped');
    expect(rows.length, 4, reason: 'falls back to a 4-3-3');
    expect(rows.last.single.name, 'P0', reason: 'the first player stands in as keeper');
  });

  test('an unusual depth is drawn rather than discarded', () {
    final rows = groupStartersByLine([p('GK', 1), p('odd', 9)]);
    expect(countIn(rows), 2);
    expect(rows.first.single.name, 'odd');
  });

  test('an empty lineup is empty, not a crash', () {
    expect(groupStartersByLine(const []), isEmpty);
  });
}
