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
        child: CustomPaint(
          painter: _CurvedBarPainter(
            backgroundColor: bg,
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
    );
  }
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

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final halfArch = archWidth / 2;
    final startX = cx - halfArch;
    final endX = cx + halfArch;

    // Full closed path for background fill
    final bgPath = Path()
      ..moveTo(0, 0)
      ..lineTo(startX, 0)
      // Left curve sloping smoothly up to peak
      ..cubicTo(
        startX + halfArch * 0.45, 0,
        cx - halfArch * 0.45, -archHeight,
        cx, -archHeight,
      )
      // Right curve sloping smoothly down to flat
      ..cubicTo(
        cx + halfArch * 0.45, -archHeight,
        endX - halfArch * 0.45, 0,
        endX, 0,
      )
      ..lineTo(w, 0)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(bgPath, bgPaint);

    // Hairline stroke along the top contoured edge
    final borderPath = Path()
      ..moveTo(0, 0)
      ..lineTo(startX, 0)
      ..cubicTo(
        startX + halfArch * 0.45, 0,
        cx - halfArch * 0.45, -archHeight,
        cx, -archHeight,
      )
      ..cubicTo(
        cx + halfArch * 0.45, -archHeight,
        endX - halfArch * 0.45, 0,
        endX, 0,
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
TextStyle _labelStyle(Color color) => TextStyle(
      color: color,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      height: 1.2,
    );

/// An icon over its label; pure white filled icon with distinct active label.
class _BarItem extends StatelessWidget {
  const _BarItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.inactiveColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final Color inactiveColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: _Tap(
        onTap: onTap,
        child: SizedBox(
          height: AppBottomBar.barHeight,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 26, color: Colors.white),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                style: _labelStyle(
                  active ? AppColors.primary : const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The centre item: a 52 px play button nestled inside the upward curved arch
/// with «مشاهد» underneath it matching the exact baseline of the side items.
class _ReelsItem extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final labelColor = active ? AppColors.primary : inactiveColor;
    return Semantics(
      button: true,
      selected: active,
      label: 'مشاهد',
      child: _Tap(
        onTap: onTap,
        child: SizedBox(
          height: AppBottomBar.barHeight,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // Raised play button inside the arch
              Positioned(
                top: -14,
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
                        color: AppColors.primary.withOpacity(active ? 0.55 : 0.35),
                        blurRadius: active ? 12 : 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const SizedBox(
                    width: _disc,
                    height: _disc,
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
              // Label aligned precisely with the side labels
              Positioned(
                bottom: 11,
                child: Text('مشاهد', maxLines: 1, style: _labelStyle(labelColor)),
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
