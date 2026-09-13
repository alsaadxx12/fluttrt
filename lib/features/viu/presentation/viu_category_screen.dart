import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/viu_models.dart';
import 'viu_providers.dart';
import 'viu_widgets.dart';
import '../../../core/constants/app_palette.dart';

/// Every free title of a Viu category, loading more as you scroll.
class ViuCategoryScreen extends ConsumerStatefulWidget {
  final ViuCategory category;

  const ViuCategoryScreen({super.key, required this.category});

  @override
  ConsumerState<ViuCategoryScreen> createState() => _ViuCategoryScreenState();
}

class _ViuCategoryScreenState extends ConsumerState<ViuCategoryScreen> {
  final _shows = <ViuShow>[];
  final _seen = <String>{}; // series ids already shown
  final _byTitle = <String, int>{}; // title -> card index
  int _offset = 0;
  bool _hasMore = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final service = ref.read(viuServiceProvider);
    try {
      if (widget.category.isMovies) {
        final movies = await service.fetchFreeMovies();
        _add(movies);
        _hasMore = false;
      } else {
        final page = await service.fetchFreeShows(widget.category.id, offset: _offset, want: 24);
        _add(page.shows);
        _offset = page.nextOffset;
        _hasMore = page.hasMore;
      }
    } catch (_) {
      _error = 'تعذّر تحميل المحتوى';
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Adds a page; a version of a title already on screen (original vs
  /// dubbed, possibly on another page) joins that title's card.
  void _add(List<ViuShow> shows) {
    for (final s in shows) {
      if (!_seen.add(s.seriesId)) continue;
      final i = _byTitle[s.titleKey];
      if (i == null) {
        _byTitle[s.titleKey] = _shows.length;
        _shows.add(s);
      } else {
        _shows[i] = _shows[i].withAlternate(s);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: AppPalette.of(context).bg,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF0D111A) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 0,
        title: Text(widget.category.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
      ),
      body: _shows.isEmpty
          ? Center(
              child: _loading
                  ? const CircularProgressIndicator(color: Color(0xFFE50914))
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error ?? 'لا يوجد محتوى متاح حالياً',
                            style: TextStyle(color: isDark ? Colors.white60 : Colors.black54)),
                        if (_error != null)
                          TextButton(
                            onPressed: () {
                              _hasMore = true;
                              _loadMore();
                            },
                            child: const Text('إعادة المحاولة'),
                          ),
                      ],
                    ),
            )
          : NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.extentAfter < 600) _loadMore();
                return false;
              },
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 10,
                        childAspectRatio: 2 / 3,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => LayoutBuilder(
                          builder: (context, box) => ViuPosterCard(show: _shows[i], width: box.maxWidth),
                        ),
                        childCount: _shows.length,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 24, top: 8),
                      child: Center(
                        child: _loading
                            ? const CircularProgressIndicator(color: Color(0xFFE50914), strokeWidth: 2.5)
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
