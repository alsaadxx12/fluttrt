import 'dart:async';

import 'package:flutter/material.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';

/// The one search field used on every page.
///
/// A flat white pill, 40 px high, hairline border, no shadow, brand-red
/// search glyph at the start, the text, then either a small spinner (while a
/// search is running), a caller-supplied trailing widget, or a ✕ that clears
/// the field. Pages differ only in what they do with the text; they must not
/// restyle the field, so every screen's search looks identical.
///
/// While the field is empty its hint is alive: it cycles through a few
/// suggestions («ابحث عن فيلم», «مسلسل», «ممثل»…), each sliding gently up
/// into the place of the last. A page with one specific job passes a single
/// [hintText] (or its own [hints]) instead.
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    super.key,
    this.controller,
    this.focusNode,
    this.hintText = 'بحث',
    this.hints,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.onClear,
    this.isLoading = false,
    this.showClear,
    this.trailing,
    this.autofocus = false,
    this.enabled = true,
    this.height = AppSearchField.defaultHeight,
    this.soft = false,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;

  /// A fixed hint. The default 'بحث' means "use the cycling [hints]".
  final String hintText;

  /// The phrases the empty field cycles through. Null with the default
  /// [hintText] uses [defaultHints]; null with a specific [hintText] shows
  /// that text alone.
  final List<String>? hints;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;

  /// Called when the ✕ is tapped. When null the field only clears itself.
  final VoidCallback? onClear;

  /// Shows a small spinner at the end instead of the ✕.
  final bool isLoading;

  /// Force the ✕ on or off. When null it shows whenever the field has text.
  final bool? showClear;

  /// Extra widget at the end (a mode toggle, a filter button). Shown after
  /// the spinner / ✕ slot.
  final Widget? trailing;
  final bool autofocus;
  final bool enabled;

  /// The pill's height; the default is [defaultHeight]. A taller field (48) gets a
  /// slightly larger glyph and text.
  final double height;

  /// Soft look: a barely-there border and a faint shadow instead of the
  /// hairline outline - the home bar's field.
  final bool soft;

  /// Default height of the pill; layouts that reserve room for the field use this.
  static const double defaultHeight = 40;
  static const double defaultRadius = 20;

  /// What the app can find: the hint names one at a time.
  static const List<String> defaultHints = [
    'ابحث عن فيلم',
    'ابحث عن مسلسل',
    'ابحث عن ممثل',
    'ابحث عن أنمي',
    'ابحث عن مباراة',
  ];

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  TextEditingController? _ownController;
  TextEditingController get _controller => widget.controller ?? (_ownController ??= TextEditingController());

  List<String> get _hints {
    final given = widget.hints;
    if (given != null && given.isNotEmpty) return given;
    return widget.hintText == 'بحث' ? AppSearchField.defaultHints : [widget.hintText];
  }

  @override
  void dispose() {
    _ownController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final isDark = p.isDark;
    final fill = isDark ? const Color(0xFF111726).withOpacity(0.96) : Colors.white;
    final border = isDark
        ? Border.all(color: Colors.white.withOpacity(0.12), width: 0.8)
        : Border.all(color: widget.soft ? const Color(0xFFEDF0F5) : p.border, width: 1.0);
    final tall = widget.height >= 46;
    final glyph = tall ? 22.0 : 20.0;
    final textSize = tall ? 14.5 : 14.0;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final hintColor = isDark ? Colors.white38 : const Color(0xFF94A3B8);
    final closeColor = isDark ? Colors.white70 : const Color(0xFF64748B);
    const accent = Color(0xFFE50914);
    final controller = _controller;

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(widget.height / 2),
        border: border,
        boxShadow: widget.soft && !isDark
            ? const [BoxShadow(color: Color(0x0A0F172A), blurRadius: 10, offset: Offset(0, 3))]
            : null,
      ),
      padding: EdgeInsetsDirectional.only(start: tall ? 14 : 12, end: 4),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: accent, size: glyph),
          SizedBox(width: tall ? 10 : 8),
          Expanded(
            child: Stack(
              alignment: AlignmentDirectional.centerStart,
              children: [
                // The living hint sits behind the (transparent-hinted) field
                // and steps aside as soon as there is text.
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (_, value, __) => value.text.isEmpty
                      ? _CyclingHint(hints: _hints, color: hintColor, size: tall ? 13.5 : 13)
                      : const SizedBox.shrink(),
                ),
                TextField(
                  controller: controller,
                  focusNode: widget.focusNode,
                  enabled: widget.enabled,
                  autofocus: widget.autofocus,
                  onTap: widget.onTap,
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                  textInputAction: TextInputAction.search,
                  style: TextStyle(color: textColor, fontSize: textSize, fontWeight: FontWeight.w500),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                    isCollapsed: true,
                  ),
                ),
              ],
            ),
          ),
          if (widget.isLoading)
            const Padding(
              padding: EdgeInsetsDirectional.only(end: 8),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(color: accent, strokeWidth: 2),
              ),
            )
          else
            _ClearButton(
              controller: controller,
              show: widget.showClear,
              color: closeColor,
              onClear: widget.onClear,
            ),
          if (widget.trailing != null) widget.trailing!,
        ],
      ),
    );
  }
}

/// The hint that keeps changing: every few seconds the next phrase rises
/// into place while the old one fades out above it. One phrase stays put
/// when the platform asks for reduced motion.
class _CyclingHint extends StatefulWidget {
  const _CyclingHint({required this.hints, required this.color, this.size = 13});

  final List<String> hints;
  final Color color;
  final double size;

  static const Duration every = Duration(milliseconds: 2600);
  static const Duration swap = Duration(milliseconds: 380);

  @override
  State<_CyclingHint> createState() => _CyclingHintState();
}

class _CyclingHintState extends State<_CyclingHint> {
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(_CyclingHint old) {
    super.didUpdateWidget(old);
    if (old.hints != widget.hints) {
      _index = 0;
      _arm();
    }
  }

  void _arm() {
    _timer?.cancel();
    if (widget.hints.length < 2) return;
    _timer = Timer.periodic(_CyclingHint.every, (_) {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % widget.hints.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final text = Text(
      widget.hints[_index],
      key: ValueKey(_index),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: widget.color, fontSize: widget.size),
    );
    if (reduceMotion || widget.hints.length < 2) {
      return IgnorePointer(child: Text(widget.hints.first, maxLines: 1, style: TextStyle(color: widget.color, fontSize: widget.size)));
    }
    return IgnorePointer(
      child: ClipRect(
        child: AnimatedSwitcher(
          duration: _CyclingHint.swap,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (current, previous) => Stack(
            alignment: AlignmentDirectional.centerStart,
            children: [...previous, if (current != null) current],
          ),
          transitionBuilder: (child, animation) {
            // Incoming rises from just below, outgoing drifts up and out.
            final slide = Tween<Offset>(begin: const Offset(0, 0.6), end: Offset.zero).animate(animation);
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(position: slide, child: child),
            );
          },
          child: text,
        ),
      ),
    );
  }
}

/// The ✕ at the end of the pill. Without an explicit [show] it follows the
/// controller's text.
class _ClearButton extends StatelessWidget {
  const _ClearButton({required this.controller, required this.show, required this.color, required this.onClear});

  final TextEditingController controller;
  final bool? show;
  final Color color;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    Widget button(bool visible) {
      if (!visible) return const SizedBox.shrink();
      return IconButton(
        icon: Icon(Icons.close_rounded, color: color, size: 18),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        onPressed: () {
          controller.clear();
          onClear?.call();
        },
      );
    }

    if (show != null) return button(show!);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (_, value, __) => button(value.text.isNotEmpty),
    );
  }
}
