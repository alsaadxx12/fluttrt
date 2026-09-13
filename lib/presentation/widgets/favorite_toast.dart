import 'package:flutter/material.dart';

/// A short heart notice for adding to / removing from favourites: a small
/// floating card with a heart that pops, white on dark in dark mode and
/// black on white in light mode. A new one replaces the one showing.
void showFavoriteToast(BuildContext context, {required bool added}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _FavoriteToast.current?.remove();
  final isDark = Theme.of(context).brightness == Brightness.dark;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _FavoriteToast(
      added: added,
      isDark: isDark,
      onDone: () {
        if (_FavoriteToast.current == entry) _FavoriteToast.current = null;
        if (entry.mounted) entry.remove();
      },
    ),
  );
  _FavoriteToast.current = entry;
  overlay.insert(entry);
}

class _FavoriteToast extends StatefulWidget {
  static OverlayEntry? current;

  final bool added;
  final bool isDark;
  final VoidCallback onDone;

  const _FavoriteToast({required this.added, required this.isDark, required this.onDone});

  @override
  State<_FavoriteToast> createState() => _FavoriteToastState();
}

class _FavoriteToastState extends State<_FavoriteToast> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  )..forward().whenComplete(widget.onDone);

  // in 0-12%, hold, out 85-100%
  late final Animation<double> _fade = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOut)), weight: 12),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 73),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)), weight: 15),
  ]).animate(_c);

  // the heart pops: small -> overshoot -> settle
  late final Animation<double> _heart = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.4, end: 1.25).chain(CurveTween(curve: Curves.easeOut)), weight: 14),
    TweenSequenceItem(tween: Tween(begin: 1.25, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 10),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 76),
  ]).animate(_c);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final added = widget.added;
    final isDark = widget.isDark;
    final bg = isDark ? const Color(0xFF1B2232) : Colors.white;
    final fg = isDark ? Colors.white : const Color(0xFF0F172A);
    final bottom = MediaQuery.of(context).padding.bottom + 96;

    return Positioned(
      left: 0,
      right: 0,
      bottom: bottom,
      child: IgnorePointer(
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.25), end: Offset.zero)
                  .animate(CurvedAnimation(parent: _c, curve: const Interval(0, 0.14, curve: Curves.easeOut))),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(18, 11, 18, 11),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFE3E8F1)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.45 : 0.14),
                        blurRadius: 22,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ScaleTransition(
                        scale: _heart,
                        child: Icon(
                          added ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          color: added ? const Color(0xFFE50914) : fg.withOpacity(0.55),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        added ? 'أُضيف إلى المفضلة' : 'أُزيل من المفضلة',
                        style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w800),
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
