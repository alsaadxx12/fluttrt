import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/features/reels/data/reel_text.dart';
import 'package:youtube_downloader/features/reels/data/reels_service.dart';
import 'package:youtube_downloader/features/reels/presentation/providers/reels_search_provider.dart';
import 'package:youtube_downloader/features/reels/presentation/screens/reels_screen.dart';
import 'package:youtube_downloader/features/reels/presentation/widgets/reel_widgets.dart';
import 'package:youtube_downloader/presentation/widgets/app_search_field.dart';

const Color _kText = Color(0xFF0F172A);
const Color _kMuted = Color(0xFF64748B);
const Color _kFaint = Color(0xFF94A3B8);
const Color _kPill = Color(0xFFF2F2F2);

/// TikTok's search, for films: a white page with the field at the top,
/// recent and trending queries as pills, and results as a two-column grid
/// of vertical thumbnails. A result opens the reels player full-screen on
/// that list.
class ReelsSearchScreen extends ConsumerStatefulWidget {
  const ReelsSearchScreen({super.key});

  /// The fixed «الأكثر رواجاً» suggestions: films and genres.
  static const List<String> trending = [
    'أكشن',
    'رعب',
    'كوميديا',
    'أنمي',
    'Inception',
    'Interstellar',
    'The Dark Knight',
    'Titanic',
    'Marvel',
    'Fast & Furious',
  ];

  @override
  ConsumerState<ReelsSearchScreen> createState() => _ReelsSearchScreenState();
}

class _ReelsSearchScreenState extends ConsumerState<ReelsSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // Coming back to the page shows the last search, with its text.
    final q = ref.read(reelsSearchProvider).query;
    if (q.isNotEmpty) _controller.text = q;
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.maxScrollExtent - pos.pixels < 600) {
      ref.read(reelsSearchProvider.notifier).loadMore();
    }
  }

  void _search(String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    if (_controller.text != q) _controller.text = q;
    FocusScope.of(context).unfocus();
    ref.read(reelsSearchProvider.notifier).search(q);
  }

  void _clear() {
    ref.read(reelsSearchProvider.notifier).clear();
  }

  /// The player over the whole app (the root navigator, so the bottom bar
  /// stays under it), with a back chevron since it was pushed.
  void _open(List<Reel> results, int index) {
    Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute<void>(
        builder: (_) => ReelsScreen(initialItems: results, initialIndex: index, embedded: false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reelsSearchProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(4, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'رجوع',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _kText, size: 22),
                  ),
                  Expanded(
                    child: AppSearchField(
                      controller: _controller,
                      hints: const ['ابحث عن فيلم', 'مشهد شهير', 'إعلان فيلم جديد', 'أنمي'],
                      autofocus: true,
                      isLoading: state.isLoading && state.results.isEmpty,
                      onSubmitted: _search,
                      onClear: _clear,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: state.searched
                  ? _Results(
                      state: state,
                      scroll: _scroll,
                      onOpen: (i) => _open(state.results, i),
                      onRetry: () => _search(state.query),
                    )
                  : _Suggestions(
                      recent: state.recent,
                      onPick: _search,
                      onRemove: (q) => ref.read(reelsSearchProvider.notifier).removeRecent(q),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// «عمليات البحث الأخيرة» and «الأكثر رواجاً», as pills.
class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.recent, required this.onPick, required this.onRemove});

  final List<String> recent;
  final ValueChanged<String> onPick;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (recent.isNotEmpty) ...[
          const _SectionTitle('عمليات البحث الأخيرة'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final q in recent)
                _Pill(
                  text: q,
                  onTap: () => onPick(q),
                  onRemove: () => onRemove(q),
                ),
            ],
          ),
          const SizedBox(height: 22),
        ],
        const _SectionTitle('الأكثر رواجاً'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final q in ReelsSearchScreen.trending)
              _Pill(text: q, trending: true, onTap: () => onPick(q)),
          ],
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(color: _kText, fontSize: 14, fontWeight: FontWeight.w800),
    );
  }
}

/// A light gray pill: the query, a small ✕ for a recent one, a small
/// trending arrow for a suggested one.
class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.onTap, this.onRemove, this.trending = false});

  final String text;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  final bool trending;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _kPill,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: EdgeInsetsDirectional.only(start: 12, end: onRemove != null ? 6 : 12, top: 7, bottom: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (trending) ...[
                const Icon(Icons.trending_up_rounded, size: 14, color: AppColors.primary),
                const SizedBox(width: 5),
              ],
              Text(
                text,
                textDirection: reelTextDirection(text),
                style: const TextStyle(color: _kText, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              if (onRemove != null) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onRemove,
                  child: const Padding(
                    padding: EdgeInsets.all(3),
                    child: Icon(Icons.close_rounded, size: 14, color: _kMuted),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The result grid, or what stands in for it.
class _Results extends StatelessWidget {
  const _Results({required this.state, required this.scroll, required this.onOpen, required this.onRetry});

  final ReelsSearchState state;
  final ScrollController scroll;
  final ValueChanged<int> onOpen;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final results = state.results;
    if (results.isEmpty) {
      if (state.isLoading) {
        return const Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2.4),
          ),
        );
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(state.failed ? Icons.cloud_off_rounded : Icons.search_off_rounded, size: 44, color: _kFaint),
            const SizedBox(height: 10),
            Text(
              state.failed ? 'تعذّر البحث' : 'لا توجد نتائج',
              style: const TextStyle(color: _kMuted, fontSize: 14, fontWeight: FontWeight.w700),
            ),
            if (state.failed)
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                child: const Text('إعادة المحاولة', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const side = 16.0, gap = 8.0;
        final cellWidth = (constraints.maxWidth - side * 2 - gap) / 2;
        // Image (9:16) + 6 + two lines of 13 px.
        final cellHeight = cellWidth * 16 / 9 + 6 + 36;
        return CustomScrollView(
          controller: scroll,
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(side, 4, side, 8),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: gap,
                  crossAxisSpacing: gap,
                  mainAxisExtent: cellHeight,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _ResultCell(
                    reel: results[i],
                    width: cellWidth,
                    onTap: () => onOpen(i),
                  ),
                  childCount: results.length,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 56,
                child: state.isLoading
                    ? const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One result: the vertical thumbnail with the view count on it (when the
/// source carried one) and the title. No channel: a scene belongs to its
/// film, not to whoever posted it.
class _ResultCell extends StatelessWidget {
  const _ResultCell({required this.reel, required this.width, required this.onTap});

  final Reel reel;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final views = reel.viewCount;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AspectRatio(
              aspectRatio: 9 / 16,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ReelPoster(reel: reel, width: width, placeholderColor: const Color(0xFFF1F3F6)),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      height: 44,
                      padding: const EdgeInsetsDirectional.only(start: 6, bottom: 5),
                      alignment: AlignmentDirectional.bottomStart,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x00000000), Color(0x99000000)],
                        ),
                      ),
                      child: views == null
                          ? null
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 14),
                                const SizedBox(width: 2),
                                Text(
                                  formatReelCount(views),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 36,
            child: Text(
              reel.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textDirection: reelTextDirection(reel.title),
              style: const TextStyle(color: _kText, fontSize: 13, fontWeight: FontWeight.w500, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
