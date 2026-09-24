import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:youtube_downloader/core/constants/app_palette.dart';
import 'package:youtube_downloader/core/network/image_cache.dart';
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';
import 'package:youtube_downloader/features/cinemana/presentation/providers/cinemana_provider.dart';
import 'package:youtube_downloader/features/cinemana/presentation/screens/cinemana_detail_screen.dart';
import 'package:youtube_downloader/presentation/widgets/app_search_field.dart';

/// The search page.
///
/// Search used to live on the home page as a field in the top bar with an
/// overlay of results over the page. The bar now carries only a search
/// button, which opens this; the home page is lighter for it, and a search
/// gets the whole screen instead of a sheet laid over a page still scrolling
/// underneath.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  List<CinemanaItem> _results = [];
  bool _isLoading = false;
  String? _errorMessage;
  Timer? _debounce;
  CancelToken? _cancelToken;

  /// True once a search has actually been asked for, so an untouched page
  /// shows an invitation rather than "no results".
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    // The page exists to be typed into, so the keyboard comes up with it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _focusNode.canRequestFocus) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _cancelToken?.cancel('disposed');
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Live search with a 400 ms debounce; the previous request is cancelled so
  /// a slow answer can never overwrite a newer one.
  void _onQueryChanged(String query) {
    _debounce?.cancel();
    _cancelToken?.cancel('new query');
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _results = const [];
        _isLoading = false;
        _errorMessage = null;
        _searched = false;
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _searched = true;
    });
    _cancelToken = CancelToken();
    _debounce = Timer(const Duration(milliseconds: 400), () => _run(q));
  }

  void _searchNow(String query) {
    _debounce?.cancel();
    _cancelToken?.cancel('instant search');
    final q = query.trim();
    if (q.isEmpty) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _searched = true;
    });
    _cancelToken = CancelToken();
    _run(q);
  }

  Future<void> _run(String q) async {
    if (!mounted) return;
    try {
      final results = await ref.read(cinemanaServiceProvider).search(q, cancelToken: _cancelToken);
      if (!mounted) return;
      setState(() {
        _results = results;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      // A cancelled request is a newer search taking over, not a failure.
      if (!mounted || (e is DioException && CancelToken.isCancel(e))) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'تعذر الاتصال بالخادم، يُرجى التأكد من اتصال الإنترنت والمحاولة ثانيةً.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              // The field alone: no back button (the system gesture leaves),
              // and no taller than the fields on every other page.
              child: Row(
                children: [
                  Expanded(
                    child: AppSearchField(
                      controller: _controller,
                      focusNode: _focusNode,
                      soft: true,
                      hints: const [
                        'ابحث عن فيلم، مسلسل، أو أنمي',
                        'ابحث عن ممثل',
                        'ابحث عن مباراة',
                      ],
                      onChanged: _onQueryChanged,
                      onSubmitted: _searchNow,
                      isLoading: _isLoading,
                      showClear: _controller.text.isNotEmpty,
                      onClear: () {
                        _controller.clear();
                        _onQueryChanged('');
                      },
                    ),
                  ),
                ],
              ),
            ),
            if (_searched && !_isLoading && _errorMessage == null && _results.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Row(
                  children: [
                    Text(
                      'نتائج البحث (${_results.length})',
                      style: TextStyle(color: p.text, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            Expanded(child: _buildBody(p)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(AppPalette p) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFE50914)));
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Color(0xFFE50914), size: 40),
              const SizedBox(height: 10),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: p.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: () => _searchNow(_controller.text),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('إعادة المحاولة'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE50914),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (!_searched) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'ابحث عن فيلم، مسلسل، أنمي أو مباراة',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.textMuted, fontSize: 13.5),
              ),
            ],
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'لم يتم العثور على نتائج لـ "${_controller.text.trim()}"',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.textMuted, fontSize: 13),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) => _ResultTile(item: _results[i], palette: p),
    );
  }
}

class _ResultTile extends StatelessWidget {
  final CinemanaItem item;
  final AppPalette palette;
  const _ResultTile({required this.item, required this.palette});

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final poster = item.bestPosterUrl.isNotEmpty ? item.bestPosterUrl : (item.imgUrl ?? item.imgThumbUrl);
    final dpr = MediaQuery.of(context).devicePixelRatio;

    return GestureDetector(
      onTap: () => Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(builder: (_) => CinemanaDetailScreen(item: item)),
      ),
      // Glass, like the cards on the home page: the page shows through a
      // deep blur and a faint white sheen, under a thin light edge.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAliasWithSaveLayer,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            height: 85,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [p.glassTop, p.glassBottom],
              ),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: p.glassEdge, width: 0.8),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    width: 55,
                    height: 70,
                    child: (poster != null && poster.isNotEmpty)
                        ? CachedNetworkImage(
                            imageUrl: poster,
                            cacheManager: appImageCache,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.high,
                            memCacheWidth: (55 * dpr).round(),
                            fadeInDuration: Duration.zero,
                            fadeOutDuration: Duration.zero,
                            placeholderFadeInDuration: Duration.zero,
                            useOldImageOnUrlChange: true,
                            placeholder: (_, __) => ColoredBox(color: p.cardAlt),
                            errorWidget: (_, __, ___) => ColoredBox(
                              color: p.cardAlt,
                              child: Icon(Icons.movie_outlined, color: p.textFaint),
                            ),
                          )
                        : ColoredBox(
                            color: p.cardAlt,
                            child: Icon(Icons.movie_outlined, color: p.textFaint),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.text, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded, color: Color(0xFFFFB800), size: 14),
                          const SizedBox(width: 3),
                          Text(
                            item.stars.isNotEmpty ? item.stars : '8.0',
                            style: TextStyle(color: p.text, fontSize: 11.5, fontWeight: FontWeight.bold),
                          ),
                          if (item.year.isNotEmpty) ...[
                            Text(' • ', style: TextStyle(color: p.textFaint)),
                            Text(item.year, style: TextStyle(color: p.textMuted, fontSize: 11)),
                          ],
                          if (item.categories.isNotEmpty) ...[
                            Text(' • ', style: TextStyle(color: p.textFaint)),
                            Flexible(
                              child: Text(
                                item.categories.first,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: p.textMuted, fontSize: 11),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_left_rounded, color: p.textFaint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
