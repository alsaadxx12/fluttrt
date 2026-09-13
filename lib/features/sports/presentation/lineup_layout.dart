import '../data/models/sports_models.dart';

/// Arranges a starting eleven into the rows a pitch is drawn with.
///
/// The feed numbers a formation's rows from the goal outwards, and how many
/// rows there are depends on the shape: a 4-4-2 ends at line 4, a 4-2-3-1
/// puts its lone striker on line 5. Reading a fixed set of lines silently
/// drops whoever sits outside it, which is how an eleven-man side came to be
/// drawn with ten.
///
/// Returns the rows furthest-forward first, so the list can be laid top to
/// bottom with the keeper last. Every starter appears exactly once.
List<List<PlayerLineupItem>> groupStartersByLine(List<PlayerLineupItem> starters) {
  if (starters.isEmpty) return const [];

  final byLine = <int, List<PlayerLineupItem>>{};
  for (final p in starters) {
    (byLine[p.line] ??= []).add(p);
  }
  // Across the pitch, left to right.
  for (final row in byLine.values) {
    row.sort((a, b) => a.fieldSide.compareTo(b.fieldSide));
  }

  // A full side that lands on one single line means the feed gave no usable
  // depth; fall back to a plain 4-3-3 so the pitch reads as a shape rather
  // than one heap. A handful of players on one line is a real row, not a
  // broken feed, so it is left alone.
  if (byLine.length <= 1 && starters.length >= 6) {
    final rest = starters.skip(1).toList();
    byLine
      ..clear()
      ..[1] = starters.take(1).toList()
      ..[2] = rest.take(4).toList()
      ..[3] = rest.skip(4).take(3).toList()
      ..[4] = rest.skip(7).toList();
    byLine.removeWhere((_, v) => v.isEmpty);
  }

  final lines = byLine.keys.toList()..sort();
  return [for (final l in lines.reversed) byLine[l]!];
}
