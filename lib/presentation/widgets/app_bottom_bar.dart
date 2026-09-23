import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';

/// The phone's bottom navigation bar: «الرئيسية», «مشاهد» raised in the centre
/// within an elegant curved arch wave, and «قائمتي».
///
/// Features a smooth upward wave contour around the central play button,
/// ensuring the bar's top border seamlessly slopes and arches with the button
/// without any straight line slicing across it.
class AppBottomBar extends StatelessWidget {
  const AppBottomBar({super.key, required this.location, required this.dark});

  /// The current location; decides which of the three is lit.
  final String location;

  /// Black bar with white icons, for the reels page.
  final bool dark;

  /// The bar's own height, before the bottom safe-area inset.
  static const double barHeight = 64;

  /// Height of the central arch wave that rises up with the play button.
  static const double archHeight = 18;

  /// Span of the central arch wave.
  static const double archWidth = 110;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final Color bg = palette.bg;
    final Color line = Colors.white.withOpacity(0.08);
    const Color inactive = Color(0xFF94A3B8);

    final homeActive = location == '/';
    final reelsActive = location.startsWith('/reels');
    final listActive = location.startsWith('/my-list');

    final totalHeight = barHeight + bottomInset;

    return _ExtendedHitTest(
      extraTop: archHeight + 6,
      child: SizedBox(
        height: totalHeight,
        // Glass, the way iOS draws its tab bar: the page shows through a
        // blur under a tint of its own colour. The clip follows the arch,
        // so the blur stops where the bar does.
        child: ClipPath(
          clipper:
              _CurvedBarClipper(archHeight: archHeight, archWidth: archWidth),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: CustomPaint(
              painter: _CurvedBarPainter(
                backgroundColor: bg.withOpacity(0.72),
                borderColor: line,
                archHeight: archHeight,
                archWidth: archWidth,
              ),
              child: Padding(
                padding: EdgeInsets.only(bottom: bottomInset),
                child: SizedBox(
                  height: barHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _BarItem(
                          icon: Icons.home_rounded,
                          idleIcon: Icons.home_outlined,
                          label: 'الرئيسية',
                          active: homeActive,
                          inactiveColor: inactive,
                          onTap: () => context.go('/'),
                        ),
                      ),
                      Expanded(
                        child: _ReelsItem(
                          active: reelsActive,
                          inactiveColor: inactive,
                          onTap: () => context.go('/reels'),
                        ),
                      ),
                      Expanded(
                        child: _BarItem(
                          icon: Icons.bookmark_rounded,
                          idleIcon: Icons.bookmark_border_rounded,
                          label: 'قائمتي',
                          active: listActive,
                          inactiveColor: inactive,
                          onTap: () => context.go('/my-list'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The bar's outline, arch included, as a clip: the blur behind the bar is
/// cut to the same shape the painter fills.
class _CurvedBarClipper extends CustomClipper<Path> {
  const _CurvedBarClipper({required this.archHeight, required this.archWidth});

  final double archHeight;
  final double archWidth;

  @override
  Path getClip(Size size) => _CurvedBarPainter.outline(size,
      archHeight: archHeight, archWidth: archWidth);

  @override
  bool shouldReclip(covariant _CurvedBarClipper old) =>
      old.archHeight != archHeight || old.archWidth != archWidth;
}

/// Custom painter that draws the bottom navigation bar background and its top border
/// with a continuous, organic upward wave arch in the center cradling the play button.
class _CurvedBarPainter extends CustomPainter {
  const _CurvedBarPainter({
    required this.backgroundColor,
    required this.borderColor,
    required this.archHeight,
    required this.archWidth,
  });

  final Color backgroundColor;
  final Color borderColor;
  final double archHeight;
  final double archWidth;

  /// The closed outline of the bar: flat top with the arch rising in the
  /// middle, down the sides and along the bottom.
  static Path outline(Size size,
      {required double archHeight, required double archWidth}) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final halfArch = archWidth / 2;
    final startX = cx - halfArch;
    final endX = cx + halfArch;
    return Path()
      ..moveTo(0, 0)
      ..lineTo(startX, 0)
      // Left curve sloping smoothly up to peak
      ..cubicTo(
        startX + halfArch * 0.45,
        0,
        cx - halfArch * 0.45,
        -archHeight,
        cx,
        -archHeight,
      )
      // Right curve sloping smoothly down to flat
      ..cubicTo(
        cx + halfArch * 0.45,
        -archHeight,
        endX - halfArch * 0.45,
        0,
        endX,
        0,
      )
      ..lineTo(w, 0)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final cx = w / 2;
    final halfArch = archWidth / 2;
    final startX = cx - halfArch;
    final endX = cx + halfArch;

    // Full closed path for background fill
    final bgPath = outline(size, archHeight: archHeight, archWidth: archWidth);

    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(bgPath, bgPaint);

    // Hairline stroke along the top contoured edge
    final borderPath = Path()
      ..moveTo(0, 0)
      ..lineTo(startX, 0)
      ..cubicTo(
        startX + halfArch * 0.45,
        0,
        cx - halfArch * 0.45,
        -archHeight,
        cx,
        -archHeight,
      )
      ..cubicTo(
        cx + halfArch * 0.45,
        -archHeight,
        endX - halfArch * 0.45,
        0,
        endX,
        0,
      )
      ..lineTo(w, 0);

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawPath(borderPath, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _CurvedBarPainter oldDelegate) {
    return oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.archHeight != archHeight ||
        oldDelegate.archWidth != archWidth;
  }
}

/// Allows hit-testing to reach widgets positioned above y = 0 into the curved arch.
class _ExtendedHitTest extends SingleChildRenderObjectWidget {
  const _ExtendedHitTest({required super.child, required this.extraTop});

  final double extraTop;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderExtendedHitTest(extraTop);

  @override
  void updateRenderObject(
      BuildContext context, _RenderExtendedHitTest renderObject) {
    renderObject.extraTop = extraTop;
  }
}

class _RenderExtendedHitTest extends RenderProxyBox {
  _RenderExtendedHitTest(this.extraTop);

  double extraTop;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final extendedRect = Rect.fromLTRB(0, -extraTop, size.width, size.height);
    if (extendedRect.contains(position)) {
      if (hitTestChildren(result, position: position) ||
          hitTestSelf(position)) {
        result.add(BoxHitTestEntry(this, position));
        return true;
      }
    }
    return false;
  }
}

/// Label style shared by the three items: 11 px, heavy, one line.
/// How long an icon takes to settle after the page changes.
const Duration _switchDuration = Duration(milliseconds: 380);

/// One destination, with no word under it.
///
/// Everything that used to be the label's job is the icon's now: it fills
/// in, rises, grows a little and puts a dot beneath itself. Those four read
/// together as «this is where you are» without a syllable of text — and the
/// text is still there for anyone listening rather than looking.
class _BarItem extends StatefulWidget {
  const _BarItem({
    required this.icon,
    required this.idleIcon,
    required this.label,
    required this.active,
    required this.inactiveColor,
    required this.onTap,
  });

  /// Solid, for the page you are on.
  final IconData icon;

  /// Outlined, for the pages you are not.
  final IconData idleIcon;

  /// Never drawn; spoken.
  final String label;

  final bool active;
  final Color inactiveColor;
  final VoidCallback onTap;

  @override
  State<_BarItem> createState() => _BarItemState();
}

class _BarItemState extends State<_BarItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _switchDuration,
    value: widget.active ? 1 : 0,
  );

  /// The rise and the growth overshoot and come back, so the icon arrives
  /// rather than simply being in a new place.
  ///
  /// Leaving uses the opposite curve. An ease-out on the way back down keeps
  /// the icon hovering for most of the animation and then drops it at the
  /// last moment, which looks like a fault; easing in lets it leave at once
  /// and settle.
  late final Animation<double> _settle = CurvedAnimation(
      parent: _c, curve: Curves.easeOutBack, reverseCurve: Curves.easeInCubic);

  /// Colour and the dot resolve straight, with no overshoot: a colour that
  /// overshoots goes somewhere that is not in the palette.
  late final Animation<double> _tint =
      CurvedAnimation(parent: _c, curve: Curves.easeOut);

  @override
  void didUpdateWidget(covariant _BarItem old) {
    super.didUpdateWidget(old);
    if (widget.active == old.active) return;
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _c.value = widget.active ? 1 : 0;
      return;
    }
    widget.active ? _c.forward() : _c.reverse();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: widget.active,
      label: widget.label,
      child: _Tap(
        onTap: widget.onTap,
        child: SizedBox(
          height: AppBottomBar.barHeight,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final settle = _settle.value.clamp(0.0, 1.2);
              final tint = _tint.value.clamp(0.0, 1.0);
              final color =
                  Color.lerp(widget.inactiveColor, Colors.white, tint)!;

              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Transform.translate(
                    offset: Offset(0, -4 * settle),
                    child: Transform.scale(
                      scale: 1 + 0.16 * settle,
                      child: Icon(
                        // Swapped at the halfway point so the fill appears
                        // while the icon is still on its way up, not after
                        // it has stopped.
                        tint > 0.5 ? widget.icon : widget.idleIcon,
                        size: 26,
                        color: color,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // The marker underneath. It grows out of nothing rather
                  // than fading, which reads as arriving at a place.
                  Transform.scale(
                    scale: tint,
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The centre item: a 52 px play button nestled inside the upward curved
/// arch. It has no word under it either; being the only raised, red, round
/// thing on the bar is label enough, and when it is the page you are on it
/// swells and its glow comes up.
class _ReelsItem extends StatefulWidget {
  const _ReelsItem({
    required this.active,
    required this.inactiveColor,
    required this.onTap,
  });

  final bool active;
  final Color inactiveColor;
  final VoidCallback onTap;

  static const double _disc = 52;

  @override
  State<_ReelsItem> createState() => _ReelsItemState();
}

class _ReelsItemState extends State<_ReelsItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _switchDuration,
    value: widget.active ? 1 : 0,
  );

  late final Animation<double> _t = CurvedAnimation(
      parent: _c, curve: Curves.easeOutBack, reverseCurve: Curves.easeInCubic);

  @override
  void didUpdateWidget(covariant _ReelsItem old) {
    super.didUpdateWidget(old);
    if (widget.active == old.active) return;
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _c.value = widget.active ? 1 : 0;
      return;
    }
    widget.active ? _c.forward() : _c.reverse();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    return Semantics(
      button: true,
      selected: active,
      label: 'مشاهد',
      child: _Tap(
        onTap: widget.onTap,
        child: SizedBox(
          height: AppBottomBar.barHeight,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // Raised play button inside the arch
              Positioned(
                top: -14,
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (context, child) => Transform.scale(
                    scale: 1 + 0.10 * _t.value.clamp(0.0, 1.2),
                    child: child,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFFF2A3A),
                          AppColors.primary,
                          Color(0xFFB80710),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.18),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary
                              .withOpacity(active ? 0.55 : 0.35),
                          blurRadius: active ? 12 : 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const SizedBox(
                      width: _ReelsItem._disc,
                      height: _ReelsItem._disc,
                      child: Center(
                        child: Icon(
                          Icons.play_arrow_rounded,
                          size: 30,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A plain tap target: no ripple, no highlight ring, no hover tint.
class _Tap extends StatelessWidget {
  const _Tap({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: child,
      );
}
