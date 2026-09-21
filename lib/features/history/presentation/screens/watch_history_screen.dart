import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';
import 'package:youtube_downloader/features/cinemana/presentation/screens/cinemana_detail_screen.dart';
import 'package:youtube_downloader/features/cinemana/presentation/widgets/cinemana_poster_card.dart';
import 'package:youtube_downloader/features/history/presentation/providers/watch_history_provider.dart';

/// «سجل المشاهدة» as its own page: the title over [WatchHistoryBody]. Flat
/// white like every other page; left by the edge swipe or the system back
/// gesture.
class WatchHistoryScreen extends ConsumerWidget {
  const WatchHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 20,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE50914),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'سجل المشاهدة',
                    style: TextStyle(color: p.text, fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
            const Expanded(child: WatchHistoryBody()),
          ],
        ),
      ),
    );
  }
}

/// Everything the user opened to watch, newest first, as a grid of posters,
/// with «مسح السجل» in its own row above. No header of its own, so it can
/// sit under the page's title or inside «قائمتي». A long press on a poster
/// offers to take that title out of the history.
class WatchHistoryBody extends ConsumerWidget {
  const WatchHistoryBody({super.key});

  /// Flat white sheet with the title and one action: «إزالة من السجل».
  void _showItemActions(BuildContext context, WidgetRef ref, CinemanaItem item) {
    HapticFeedback.selectionClick();
    final p = AppPalette.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.bg,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        side: BorderSide(color: p.border),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.text, fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  if (item.year.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.year,
                      style: TextStyle(color: p.textMuted, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: p.border),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: AppColors.primary),
              title: const Text(
                'إزالة من السجل',
                style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                ref.read(watchHistoryProvider.notifier).remove(item.id);
              },
            ),
            ListTile(
              leading: Icon(Icons.close_rounded, color: p.textMuted),
              title: Text('إلغاء', style: TextStyle(color: p.textMuted, fontWeight: FontWeight.w600)),
              onTap: () => Navigator.of(sheetContext).pop(),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final items = ref.watch(watchHistoryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (items.isNotEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 16, end: 8),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: () => ref.read(watchHistoryProvider.notifier).clear(),
                icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                label: const Text('مسح السجل'),
                style: TextButton.styleFrom(foregroundColor: p.textMuted),
              ),
            ),
          ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history_rounded, size: 56, color: p.textFaint),
                      const SizedBox(height: 12),
                      Text(
                        'لم تشاهد شيئاً بعد',
                        style: TextStyle(color: p.textMuted, fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'كل ما تفتحه للمشاهدة يظهر هنا',
                        style: TextStyle(color: p.textFaint, fontSize: 12.5),
                      ),
                    ],
                  ),
                )
              : LayoutBuilder(
                  builder: (context, box) {
                    final columns = (box.maxWidth / 130).floor().clamp(2, 8);
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.58,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final item = items[i];
                        // The card only takes taps; a long press wins the
                        // gesture arena here and offers removal.
                        return GestureDetector(
                          onLongPress: () => _showItemActions(context, ref, item),
                          child: CinemanaPosterCard(
                            item: item,
                            onTap: () => Navigator.of(context, rootNavigator: true).push(
                              MaterialPageRoute(builder: (_) => CinemanaDetailScreen(item: item)),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}
