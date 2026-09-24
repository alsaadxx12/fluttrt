import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';
import 'package:youtube_downloader/features/cinemana/presentation/screens/cinemana_favorites_screen.dart';
import 'package:youtube_downloader/features/history/presentation/screens/watch_history_screen.dart';

/// «قائمتي»: the favourites and the watch history under one compact header,
/// switched by a flat two-way segment. Both lists stay built side by side so
/// each keeps its scroll position while the other is showing.
class MyListScreen extends ConsumerStatefulWidget {
  const MyListScreen({super.key});

  @override
  ConsumerState<MyListScreen> createState() => _MyListScreenState();
}

class _MyListScreenState extends ConsumerState<MyListScreen> {
  /// 0: «سجل المشاهدة», 1: «المفضلة». The history first: it is the one
  /// that says where the evening left off.
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);

    return Scaffold(
      // By night black, not the page grey: the lists sit on the same ground
      // as the player, and the posters carry the colour.
      backgroundColor: p.isDark ? Colors.black : p.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 4,
                        height: 20,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'قائمتي',
                        style: TextStyle(color: p.text, fontSize: 20, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SegmentedSwitch(
                    index: _tab,
                    labels: const ['سجل المشاهدة', 'المفضلة'],
                    onChanged: (i) => setState(() => _tab = i),
                  ),
                ],
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: const [
                  WatchHistoryBody(),
                  CinemanaFavoritesBody(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two 36 px pills in a light rounded track; the chosen one is white with a
/// hairline border and red text. Flat: no shadow, no slide.
class _SegmentedSwitch extends StatelessWidget {
  const _SegmentedSwitch({
    required this.index,
    required this.labels,
    required this.onChanged,
  });

  final int index;
  final List<String> labels;
  final ValueChanged<int> onChanged;

  static const Color _mutedLight = Color(0xFF64748B);

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final trackColor = p.glassFill();
    final muted = p.isDark ? Colors.white70 : _mutedLight;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: trackColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: _SegmentPill(
                label: labels[i],
                selected: i == index,
                selectedFill: p.glassFill(selected: true),
                border: p.glassFillEdge(selected: true),
                mutedColor: muted,
                onTap: () => onChanged(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _SegmentPill extends StatelessWidget {
  const _SegmentPill({
    required this.label,
    required this.selected,
    required this.selectedFill,
    required this.border,
    required this.mutedColor,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color selectedFill;
  final Color border;
  final Color mutedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? selectedFill : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: selected ? BorderSide(color: border, width: 1) : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 36,
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                  color: selected ? AppColors.primary : mutedColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
