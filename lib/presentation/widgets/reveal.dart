import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// How the home page introduces itself: nothing snaps into place, it rises
/// and fades in, one piece after the next.
///
/// Two rules keep it from becoming noise. The stagger is capped, so the
/// tenth section does not wait a second for its turn; and when the platform
/// asks for reduced motion the child is simply there, with no animation at
/// all.
class Reveal extends StatefulWidget {
  final Widget child;

  /// Position in its group: each step adds [step] to the start delay.
  final int index;

  /// Delay per position.
  final Duration step;

  /// Longest start delay, however high [index] climbs.
  final Duration maxDelay;

  final Duration duration;

  /// How far it travels up, in logical pixels.
  final double offset;

  /// A little growth alongside the fade; 1.0 keeps the size fixed.
  final double fromScale;

  /// Positions past this one appear at once, with no controller and no
  /// timer. A scrolling list recycles its children, so animating deep
  /// positions replays the entrance every time a card comes back into view.
  final int animateUpTo;

  const Reveal({
    super.key,
    required this.child,
    this.index = 0,
    this.step = const Duration(milliseconds: 65),
    this.maxDelay = const Duration(milliseconds: 480),
    this.duration = const Duration(milliseconds: 420),
    this.offset = 18,
    this.fromScale = 1,
    this.animateUpTo = 6,
  });

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.index > widget.animateUpTo || (MediaQuery.maybeOf(context)?.disableAnimations ?? false)) {
      _c.value = 1;
      return;
    }
    final delayMs = (widget.step.inMilliseconds * widget.index).clamp(0, widget.maxDelay.inMilliseconds);
    if (delayMs == 0) {
      _c.forward();
    } else {
      Future.delayed(Duration(milliseconds: delayMs), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      // The child is built once; only the transform and opacity change.
      child: widget.child,
      builder: (context, child) {
        final t = _t.value;
        if (t >= 1) return child!;
        final scale = widget.fromScale == 1 ? 1.0 : widget.fromScale + (1 - widget.fromScale) * t;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, widget.offset * (1 - t)),
            child: scale == 1.0 ? child : Transform.scale(scale: scale, child: child),
          ),
        );
      },
    );
  }
}

/// A picture that arrives instead of appearing: it fades up from its
/// placeholder with a touch of settle, so a grid of posters fills in like a
/// shelf rather than a spreadsheet.
class RevealImage extends StatefulWidget {
  final Widget child;
  final Duration duration;
  const RevealImage({super.key, required this.child, this.duration = const Duration(milliseconds: 320)});

  @override
  State<RevealImage> createState() => _RevealImageState();
}

class _RevealImageState extends State<RevealImage> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.status == AnimationStatus.dismissed) {
      if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
        _c.value = 1;
      } else {
        _c.forward();
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = CurvedAnimation(parent: _c, curve: Curves.easeOut);
    return AnimatedBuilder(
      animation: t,
      child: widget.child,
      builder: (context, child) {
        if (t.value >= 1) return child!;
        return Opacity(
          opacity: t.value,
          // Settles from a hair oversized: depth rather than movement.
          child: Transform.scale(scale: 1.03 - 0.03 * t.value, child: child),
        );
      },
    );
  }
}

/// The quiet sweep of light across a placeholder while its content loads.
class Shimmer extends StatefulWidget {
  final Widget child;
  final Color base;
  final Color highlight;
  const Shimmer({super.key, required this.child, required this.base, required this.highlight});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  Timer? _stop;

  @override
  void initState() {
    super.initState();
    _c.repeat();
    // A placeholder that never resolves must not sweep for the rest of the
    // session; after a few passes it settles into a plain block.
    _stop = Timer(const Duration(seconds: 9), () {
      if (mounted) _c.stop();
    });
  }

  @override
  void dispose() {
    _stop?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      return ColoredBox(color: widget.base, child: widget.child);
    }
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final x = _c.value * 2 - 0.5; // sweeps from off one edge to the other
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(x - 0.6, -0.3),
              end: Alignment(x + 0.6, 0.3),
              colors: [widget.base, widget.highlight, widget.base],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
          child: child,
        );
      },
    );
  }
}

/// A card that answers the finger: it presses in under the touch and springs
/// back when released, so tapping feels like pushing something real.
class PressScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  /// How far it presses in. 0.96 is felt without being seen.
  final double pressedScale;

  const PressScale({super.key, required this.child, this.onTap, this.pressedScale = 0.96});

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;
  bool _hovered = false;
  bool _focused = false;

  void _set(void Function() change) {
    if (mounted) setState(change);
  }

  /// A pointer over the card, or the remote sitting on it, both mean the
  /// same thing: this is what you are about to open. So both lift it.
  bool get _highlighted => _hovered || _focused;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final scale = _down && !reduced
        ? widget.pressedScale
        : (_highlighted && !reduced ? 1.04 : 1.0);

    return FocusableActionDetector(
      onShowFocusHighlight: (v) => _set(() => _focused = v),
      onShowHoverHighlight: (v) => _set(() => _hovered = v),
      // The select key on a remote does what a tap does.
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap?.call();
            return null;
          },
        ),
      },
      child: GestureDetector(
        // The whole card area answers the touch, not only the painted parts,
        // so a tap on a gap inside it still opens the title.
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => _set(() => _down = true),
        onTapUp: (_) => _set(() => _down = false),
        onTapCancel: () => _set(() => _down = false),
        child: AnimatedScale(
          scale: scale,
          duration: Duration(milliseconds: _down ? 90 : 220),
          curve: _down ? Curves.easeOut : Curves.easeOutBack,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              // A ring only while it is the one in hand.
              border: Border.all(
                color: _highlighted ? const Color(0xFFE50914) : Colors.transparent,
                width: 2,
              ),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Turns the mouse wheel into sideways motion for a horizontal row.
///
/// A vertical wheel over a row of cards should move the cards, the way a
/// trackpad swipe does. The list gets its own controller, and a wheel tick is
/// added to the offset. Press-and-drag is handled separately, by the app's
/// scroll behavior; this is only the wheel.
class WheelScroll extends StatefulWidget {
  final Widget Function(ScrollController controller) builder;
  const WheelScroll({super.key, required this.builder});

  @override
  State<WheelScroll> createState() => _WheelScrollState();
}

class _WheelScrollState extends State<WheelScroll> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_controller.hasClients) return;
    // A horizontal wheel already scrolls a horizontal list; only the vertical
    // wheel needs redirecting.
    final delta = event.scrollDelta.dy.abs() >= event.scrollDelta.dx.abs()
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    if (delta == 0) return;
    final target = (_controller.offset + delta).clamp(
      _controller.position.minScrollExtent,
      _controller.position.maxScrollExtent,
    );
    _controller.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _onSignal,
      child: widget.builder(_controller),
    );
  }
}
