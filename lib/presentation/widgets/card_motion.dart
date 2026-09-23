/// Motion for the cards on the home page.
///
/// Everything here obeys one rule, learned the hard way on this page: a card
/// is expensive to build and cheap to move. So nothing below ever rebuilds
/// the card — each animation captures it once as `child` and changes only a
/// transform and an opacity, which the compositor applies to a layer that is
/// already rasterised. That is why these can run on every frame of a fling
/// without bringing back the stutter this page used to have.
///
/// Two effects, and they compose:
///
///  * [CardEntrance] — the card drops in from above and settles, staggered
///    along its row. It plays once. A row that scrolls away and comes back
///    does not replay it, because an entrance that repeats stops reading as
///    an entrance and starts reading as a glitch.
///
///  * [CarouselFocus] — while the row scrolls, the card nearest the middle
///    stands at full size and the ones either side sit back a little and
///    lower. It is what gives a flat row of posters a sense of depth.
library;

import 'package:flutter/material.dart';

/// How far a card falls from, and how long it takes to land.
const Duration _fallDuration = Duration(milliseconds: 520);
const double _fallDistance = 34;

/// Positions past this one appear at once.
///
/// A row is a lazy list: cards beyond the first screenful are built as they
/// are scrolled to, and animating those means an entrance that plays under
/// the viewer's thumb, one card at a time, forever. Only what is on screen
/// at the start gets the entrance.
const int _staggerUpTo = 6;

/// Drops a card into place, once.
///
/// [index] is its position in the row and sets the stagger. [group] names
/// the row: the first card of a row to build reports the whole row as done,
/// so recycling it never replays the fall.
class CardEntrance extends StatefulWidget {
  const CardEntrance({
    super.key,
    required this.child,
    required this.index,
    required this.group,
  });

  final Widget child;
  final int index;
  final String group;

  /// Rows that have already made their entrance.
  ///
  /// Static because the widgets themselves do not survive being scrolled
  /// past — the thing that has to be remembered outlives them. It holds a
  /// short string per row and nothing else.
  static final Set<String> _played = <String>{};

  /// Forgets what has played, so a fresh page animates again.
  static void reset() => _played.clear();

  @override
  State<CardEntrance> createState() => _CardEntranceState();
}

class _CardEntranceState extends State<CardEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: _fallDuration);

  /// The fall itself: it travels a little past its resting place and comes
  /// back, which is what makes it read as landing rather than stopping.
  late final Animation<double> _drop =
      CurvedAnimation(parent: _c, curve: Curves.easeOutBack);

  /// Opacity resolves well before the movement does, so the card is legible
  /// while it is still settling instead of arriving as a ghost.
  late final Animation<double> _fade = CurvedAnimation(
    parent: _c,
    curve: const Interval(0, 0.45, curve: Curves.easeOut),
  );

  bool _prepared = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prepared) return;
    _prepared = true;

    final muted = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final deep = widget.index >= _staggerUpTo;
    final seen = CardEntrance._played.contains(widget.group);

    if (muted || deep || seen) {
      _c.value = 1;
      return;
    }

    CardEntrance._played.add(widget.group);
    Future<void>.delayed(
      Duration(milliseconds: 45 * widget.index),
      () {
        if (mounted) _c.forward();
      },
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = _drop.value;
        if (_c.isCompleted) return child!;
        return Opacity(
          opacity: _fade.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, _fallDistance * (1 - t)),
            child: child,
          ),
        );
      },
    );
  }
}

/// Lifts whichever card is nearest the middle of its row.
///
/// The card's place on screen is worked out from the scroll offset and its
/// index rather than from its own geometry: reading a render box every frame
/// would cost more than the effect is worth, and a row of fixed-width cards
/// makes the arithmetic exact anyway.
class CarouselFocus extends StatelessWidget {
  const CarouselFocus({
    super.key,
    required this.child,
    required this.controller,
    required this.index,
    required this.extent,
    required this.width,
    this.leading = 16,
  });

  final Widget child;
  final ScrollController controller;

  /// Position in the row.
  final int index;

  /// One card plus the gap after it.
  final double extent;

  /// The card's own width.
  final double width;

  /// The row's leading padding.
  final double leading;

  /// Size at the edge of the row, relative to the middle of it.
  ///
  /// Scaled from the top edge and never moved down: a card that dropped
  /// ten points sat below the row's clip, and came back with a flat,
  /// cut-off bottom and a hairline of the page showing under it.
  static const double _minScale = 1.0;

  @override
  Widget build(BuildContext context) {
    // No transform at all any more. Scaling the card's raster, however
    // slightly, resampled its bottom edge into a pale hairline under every
    // card away from the middle - on three different rows, on a phone, in
    // three screenshots. The cards now stand still and level; the entrance
    // is the only motion.
    if (_minScale >= 1) return child;
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, child) {
        // Before the row is laid out there is no offset to read, and no
        // reason to transform anything.
        if (!controller.hasClients) return child!;
        final position = controller.position;
        final viewport = position.viewportDimension;
        if (viewport <= 0) return child!;

        final middleOfCard = leading + index * extent + width / 2;
        final middleOfRow = position.pixels + viewport / 2;
        // -1 at one edge of the row, 0 in the middle, 1 at the other.
        final away = ((middleOfCard - middleOfRow) / (viewport / 2)).clamp(-1.0, 1.0);
        final magnitude = away.abs();

        // Eased so the change is gentle around the middle and only becomes
        // noticeable towards the edges; a linear ramp reads as the whole row
        // breathing while it moves.
        final falloff = magnitude * magnitude;
        final scale = 1 - (1 - _minScale) * falloff;

        return Transform.scale(
          scale: scale,
          alignment: Alignment.topCenter,
          child: child,
        );
      },
    );
  }
}
