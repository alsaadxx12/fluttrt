import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';

/// The phone's bottom navigation: «الرئيسية», «مشاهد» raised in the centre
/// and «قائمتي». Flat like the rest of the app — white with a hairline top
/// border, or black with a faint white line over the scenes page — 64 px
/// plus the bottom safe-area inset, no shadow and no touch highlight.
class AppBottomBar extends StatelessWidget {
  const AppBottomBar({super.key, required this.location, required this.dark});

  /// The current location; decides which of the three is lit.
  final String location;

  /// Black bar with white icons, for the reels page.
  final bool dark;

  /// The bar's own height, before the bottom safe-area inset.
  static const double barHeight = 64;

  static const Color _inactiveLight = Color(0xFF64748B);

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final Color bg = dark ? Colors.black : Colors.white;
    final Color line = dark ? Colors.white12 : palette.border;
    final Color inactive = dark ? Colors.white70 : _inactiveLight;

    final homeActive = location == '/';
    final reelsActive = location.startsWith('/reels');
    final listActive = location.startsWith('/my-list');

    return Material(
      color: bg,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: line, width: 1)),
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
                    icon: homeActive ? Icons.home_rounded : Icons.home_outlined,
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
                    icon: listActive ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
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
    );
  }
}

/// Label style shared by the three items: 11 px, heavy, one line.
TextStyle _labelStyle(Color color) => TextStyle(
      color: color,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      height: 1.2,
    );

/// An icon over its label; red when active.
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
    final color = active ? AppColors.primary : inactiveColor;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: _Tap(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 26, color: color),
            const SizedBox(height: 3),
            Text(label, maxLines: 1, style: _labelStyle(color)),
          ],
        ),
      ),
    );
  }
}

/// The centre item: a 52 px red disc with a white play arrow, its top edge
/// rising above the bar, and «مشاهد» under it on the same line as the other
/// labels. The disc keeps the 26 px icon slot in the layout and simply
/// overflows it upward, so the bar stays the same height as everywhere else.
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: _disc,
              height: 26,
              child: OverflowBox(
                minWidth: _disc,
                maxWidth: _disc,
                minHeight: _disc,
                maxHeight: _disc,
                child: Transform.translate(
                  offset: const Offset(0, -14),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(Icons.play_arrow_rounded, size: 30, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text('مشاهد', maxLines: 1, style: _labelStyle(labelColor)),
          ],
        ),
      ),
    );
  }
}

/// A plain tap target: no ripple, no highlight ring, no hover tint — the
/// only feedback is the item turning red once it is the current page.
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
