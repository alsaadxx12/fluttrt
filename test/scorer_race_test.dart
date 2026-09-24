import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/sports/presentation/screens/tournament_screen.dart';

void main() {
  const runner = 78.0, gap = 10.0, track = 300.0;

  bool overlapFree(List<(int, double)?> spots) {
    for (var i = 0; i < spots.length; i++) {
      for (var j = i + 1; j < spots.length; j++) {
        final a = spots[i], b = spots[j];
        if (a == null || b == null || a.$1 != b.$1) continue;
        if ((a.$2 - b.$2).abs() < runner + gap) return false;
      }
    }
    return true;
  }

  test('the leader stands at the cup, a scorer with half his goals halfway', () {
    final spots = placeRunners([8, 4], lanes: 2, track: track, runner: runner, gap: gap);
    expect(spots[0], (0, 300.0));
    expect(spots[1], (1, 150.0));
  });

  test('runners with the same goals take different lanes', () {
    final spots = placeRunners([5, 5, 5], lanes: 3, track: track, runner: runner, gap: gap);
    expect(spots.map((s) => s!.$1).toSet(), {0, 1, 2});
    expect(spots.every((s) => s!.$2 == 300.0), isTrue);
  });

  test('when every lane is taken at his spot, a runner steps back behind the nearest one', () {
    final spots = placeRunners([5, 5, 5, 5], lanes: 3, track: track, runner: runner, gap: gap);
    expect(spots[3], (0, 300.0 - runner - gap));
    expect(overlapFree(spots), isTrue);
  });

  test('a crowd of close scorers never overlaps', () {
    final spots = placeRunners([5, 4, 4, 4, 3, 3, 3, 2], lanes: 4, track: track, runner: runner, gap: gap);
    expect(overlapFree(spots), isTrue);
    expect(spots.where((s) => s == null), isEmpty);
  });

  test('a runner with no room left on the track is left out rather than drawn on another', () {
    final spots = placeRunners(List.filled(12, 1), lanes: 2, track: 100, runner: runner, gap: gap);
    expect(overlapFree(spots), isTrue);
    expect(spots.where((s) => s == null), isNotEmpty);
  });
}
