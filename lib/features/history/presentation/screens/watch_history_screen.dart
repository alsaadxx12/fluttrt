import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';
import 'package:youtube_downloader/core/network/image_cache.dart';
import 'package:youtube_downloader/features/cinemana/presentation/screens/cinemana_detail_screen.dart';
import 'package:youtube_downloader/features/history/data/watch_history_entry.dart';
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

/// The last ten things the user watched, newest first, each with the
/// minute it was left at — and a search box that looks through everything
/// the history holds, not only those ten.
///
/// No header of its own, so it can sit under the page's title or inside
/// «قائمتي». A tap opens the title, which picks up from that minute; a long
/// press offers to take it out of the history.
class WatchHistoryBody extends ConsumerStatefulWidget {
  const WatchHistoryBody({super.key});

  @override
  ConsumerState<WatchHistoryBody> createState() => _WatchHistoryBodyState();
}

class _WatchHistoryBodyState extends ConsumerState<WatchHistoryBody> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Flat white sheet with the title and one action: «إزالة من السجل».
  void _showItemActions(BuildContext context, WatchHistoryEntry entry) {
    HapticFeedback.selectionClick();
    final p = AppPalette.of(context);
    final item = entry.item;
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
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (entry.episodeLabel.isNotEmpty) entry.episodeLabel,
                      if (entry.hasPosition) 'وصلت إلى ${historyClock(entry.position)}',
                      if (item.year.isNotEmpty) item.year,
                    ].join(' · '),
                    style: TextStyle(color: p.textMuted, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
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

  void _open(WatchHistoryEntry entry) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => CinemanaDetailScreen(item: entry.item)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final all = ref.watch(watchHistoryProvider);
    final searching = _query.trim().isNotEmpty;
    final entries = searching
        ? all.where((e) => e.matches(_query)).toList()
        : all.take(WatchHistoryNotifier.shown).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (all.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    onChanged: (v) => setState(() => _query = v),
                    textInputAction: TextInputAction.search,
                    style: TextStyle(color: p.text, fontSize: 14, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'ابحث في سجل المشاهدة',
                      hintStyle: TextStyle(color: p.textFaint, fontSize: 13.5),
                      prefixIcon: Icon(Icons.search_rounded, color: p.textMuted, size: 20),
                      suffixIcon: searching
                          ? IconButton(
                              icon: Icon(Icons.close_rounded, color: p.textMuted, size: 18),
                              onPressed: () {
                                _search.clear();
                                setState(() => _query = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: p.cardAlt,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'مسح السجل',
                  onPressed: () => ref.read(watchHistoryProvider.notifier).clear(),
                  icon: Icon(Icons.delete_sweep_rounded, color: p.textMuted, size: 22),
                ),
              ],
            ),
          ),
        if (all.isNotEmpty && !searching)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 4),
            child: Text(
              'آخر ${entries.length} ${entries.length == 1 ? 'عنوان' : 'عناوين'} شاهدتها',
              style: TextStyle(color: p.textFaint, fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
          ),
        Expanded(
          child: all.isEmpty
              ? const _Empty(
                  icon: Icons.history_rounded,
                  title: 'لم تشاهد شيئاً بعد',
                  line: 'ما تشاهده يظهر هنا مع دقيقة التوقف',
                )
              : entries.isEmpty
                  ? const _Empty(
                      icon: Icons.search_off_rounded,
                      title: 'لا نتائج',
                      line: 'لا عنوان في السجل يطابق ما كتبت',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _HistoryRow(
                        entry: entries[i],
                        onTap: () => _open(entries[i]),
                        onLongPress: () => _showItemActions(context, entries[i]),
                      ),
                    ),
        ),
      ],
    );
  }
}

/// One title: poster, name, episode, the minute it was left at with a bar
/// under it, and when.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry, required this.onTap, required this.onLongPress});

  final WatchHistoryEntry entry;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final item = entry.item;
    final progress = entry.progress;
    final where = entry.hasPosition
        ? (entry.duration != null
            ? 'وصلت إلى ${historyClock(entry.position)} من ${historyClock(entry.duration!)}'
            : 'وصلت إلى ${historyClock(entry.position)}')
        : 'لم تبدأ بعد';

    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 64,
                  height: 92,
                  child: item.bestPosterUrl.isEmpty
                      ? ColoredBox(
                          color: p.cardAlt,
                          child: Icon(Icons.movie_rounded, color: p.textFaint),
                        )
                      : CachedNetworkImage(
                        memCacheWidth: 320,
                          imageUrl: item.bestPosterUrl,
                          cacheManager: appImageCache,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => ColoredBox(color: p.cardAlt),
                          errorWidget: (_, __, ___) => ColoredBox(color: p.cardAlt),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.text, fontSize: 14.5, fontWeight: FontWeight.w800),
                    ),
                    if (entry.episodeLabel.isNotEmpty || item.year.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (entry.episodeLabel.isNotEmpty) entry.episodeLabel,
                          if (item.year.isNotEmpty) item.year,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          entry.hasPosition ? Icons.play_circle_fill_rounded : Icons.play_circle_outline_rounded,
                          size: 15,
                          color: entry.hasPosition ? const Color(0xFFE50914) : p.textFaint,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            where,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: entry.hasPosition ? p.text : p.textFaint,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress ?? (entry.hasPosition ? null : 0),
                        minHeight: 4,
                        backgroundColor: p.cardAlt,
                        color: const Color(0xFFE50914),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      historyAgo(entry.watchedAt),
                      style: TextStyle(color: p.textFaint, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.line});
  final IconData icon;
  final String title;
  final String line;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: p.textFaint),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(color: p.textMuted, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              line,
              textAlign: TextAlign.center,
              style: TextStyle(color: p.textFaint, fontSize: 12.5, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

/// «1:02:03» or «42:10».
String historyClock(Duration d) {
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final m = d.inMinutes.remainder(60);
  final h = d.inHours;
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

/// «قبل 5 دقائق», «أمس», «قبل 3 أيام».
String historyAgo(DateTime at) {
  final diff = DateTime.now().difference(at);
  if (diff.inMinutes < 1) return 'الآن';
  if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} ${diff.inMinutes == 1 ? 'دقيقة' : diff.inMinutes <= 10 ? 'دقائق' : 'دقيقة'}';
  if (diff.inHours < 24) return 'قبل ${diff.inHours} ${diff.inHours == 1 ? 'ساعة' : diff.inHours <= 10 ? 'ساعات' : 'ساعة'}';
  if (diff.inDays == 1) return 'أمس';
  if (diff.inDays < 30) return 'قبل ${diff.inDays} ${diff.inDays <= 10 ? 'أيام' : 'يوماً'}';
  return '${at.year}/${at.month.toString().padLeft(2, '0')}/${at.day.toString().padLeft(2, '0')}';
}
