import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class WindowCaptionButtons extends StatefulWidget {
  const WindowCaptionButtons({super.key});

  @override
  State<WindowCaptionButtons> createState() => _WindowCaptionButtonsState();
}

class _WindowCaptionButtonsState extends State<WindowCaptionButtons> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    if (_isDesktop) {
      windowManager.addListener(this);
      _checkMaximized();
    }
  }

  @override
  void dispose() {
    if (_isDesktop) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  bool get _isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Future<void> _checkMaximized() async {
    try {
      final max = await windowManager.isMaximized();
      if (mounted && _isMaximized != max) {
        setState(() => _isMaximized = max);
      }
    } catch (_) {}
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
  }

  @override
  void onWindowRestore() {
    if (mounted) setState(() => _isMaximized = false);
  }

  @override
  void onWindowResize() {
    _checkMaximized();
  }

  @override
  void onWindowMove() {
    _checkMaximized();
  }

  Widget _buildMaximizeIcon(bool isMaximized, Color color) {
    if (isMaximized) {
      // Windows 11 style overlapping restore squares
      return SizedBox(
        width: 12,
        height: 12,
        child: Stack(
          children: [
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: 8.5,
                height: 8.5,
                decoration: BoxDecoration(
                  border: Border.all(color: color, width: 1.2),
                ),
              ),
            ),
            Positioned(
              left: 0,
              bottom: 0,
              child: Container(
                width: 8.5,
                height: 8.5,
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF14141A)
                      : Colors.white,
                  border: Border.all(color: color, width: 1.2),
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      // Windows 11 style single maximize square
      return Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 1.2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isDesktop) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark ? Colors.white70 : Colors.black87;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Minimize Button
        _CaptionButton(
          icon: Icons.horizontal_rule_rounded,
          iconSize: 14,
          iconColor: iconColor,
          hoverColor: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.06),
          tooltip: 'تصغير',
          onTap: () => windowManager.minimize(),
        ),
        // Maximize / Restore Button
        _CaptionButton(
          iconWidget: _buildMaximizeIcon(_isMaximized, iconColor),
          hoverColor: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.06),
          tooltip: _isMaximized ? 'استعادة' : 'تكبير',
          onTap: () async {
            try {
              final isMax = await windowManager.isMaximized();
              if (isMax) {
                await windowManager.unmaximize();
                if (mounted) setState(() => _isMaximized = false);
              } else {
                await windowManager.maximize();
                if (mounted) setState(() => _isMaximized = true);
              }
            } catch (_) {}
          },
        ),
        // Close Button (turns red on hover)
        _CaptionButton(
          icon: Icons.close_rounded,
          iconSize: 15,
          iconColor: iconColor,
          hoverColor: const Color(0xFFE81123),
          hoverIconColor: Colors.white,
          tooltip: 'إغلاق',
          onTap: () => windowManager.close(),
        ),
      ],
    );
  }
}

class _CaptionButton extends StatefulWidget {
  final IconData? icon;
  final Widget? iconWidget;
  final double iconSize;
  final Color iconColor;
  final Color hoverColor;
  final Color? hoverIconColor;
  final String tooltip;
  final VoidCallback onTap;

  const _CaptionButton({
    this.icon,
    this.iconWidget,
    this.iconSize = 14,
    this.iconColor = Colors.white,
    required this.hoverColor,
    this.hoverIconColor,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 44,
            height: 38,
            decoration: BoxDecoration(
              color: _isHovered ? widget.hoverColor : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: widget.iconWidget ??
                  Icon(
                    widget.icon,
                    size: widget.iconSize,
                    color: _isHovered && widget.hoverIconColor != null
                        ? widget.hoverIconColor
                        : widget.iconColor,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
