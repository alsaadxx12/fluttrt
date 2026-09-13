import 'package:flutter/material.dart';

/// A scoreline that stays glued to the right teams.
///
/// Team rows mirror under RTL (home ends up on the right), but a single
/// `"5 : 1"` string keeps reading left-to-right, so the home score used to
/// land beside the away team - Barcelona's 5 showed up under Feyenoord.
/// Rendering the two numbers as siblings in a [Row] lets the scoreline mirror
/// with the row that holds the crests, in either text direction.
class MatchScoreLine extends StatelessWidget {
  final int? homeScore;
  final int? awayScore;
  final TextStyle style;
  final String separator;

  const MatchScoreLine({
    super.key,
    required this.homeScore,
    required this.awayScore,
    required this.style,
    this.separator = ':',
  });

  @override
  Widget build(BuildContext context) {
    // Digits are direction-neutral; pin each number LTR so "10" never
    // renders as "01" inside an RTL context, while the Row itself mirrors.
    Text number(int? v) => Text(
          '${v ?? 0}',
          textDirection: TextDirection.ltr,
          style: style,
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        number(homeScore),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(separator, style: style),
        ),
        number(awayScore),
      ],
    );
  }
}
