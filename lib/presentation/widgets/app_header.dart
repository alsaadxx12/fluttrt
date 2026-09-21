import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/features/home/presentation/providers/youtube_feed_provider.dart';
import 'package:youtube_downloader/features/home/presentation/providers/video_analyzer_provider.dart';
import 'package:youtube_downloader/features/series/presentation/providers/series_provider.dart';
import 'package:youtube_downloader/features/settings/presentation/providers/settings_provider.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';
import 'package:youtube_downloader/presentation/widgets/app_search_field.dart';
import 'window_caption_buttons.dart';

class AppHeader extends ConsumerStatefulWidget implements PreferredSizeWidget {
  const AppHeader({super.key});

  @override
  ConsumerState<AppHeader> createState() => _AppHeaderState();

  @override
  Size get preferredSize => const Size.fromHeight(62.0);
}

class _AppHeaderState extends ConsumerState<AppHeader> {
  late final TextEditingController _searchController;
  final FocusNode _searchFocusNode = FocusNode();
  final YoutubeExplode _yt = YoutubeExplode();
  final LayerLink _searchLayerLink = LayerLink();
  final GlobalKey _searchBoxKey = GlobalKey();

  OverlayEntry? _suggestionsOverlay;
  List<String> _suggestions = [];
  int _highlightedIndex = -1;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchFocusNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    // Rebuild so the ✕ follows text that was set while the field had focus.
    setState(() {});
    if (_searchFocusNode.hasFocus) {
      final text = _searchController.text.trim();
      if (text.isNotEmpty) {
        _fetchSuggestions(text);
      }
    } else {
      // Focus lost - overlay hidden via TapRegion
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _hideOverlay();
    _yt.close();
    _searchFocusNode.removeListener(_onFocusChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onTextChanged(String val) {
    setState(() {});
    final query = val.trim();
    if (query.isEmpty) {
      _debounceTimer?.cancel();
      _suggestions = [];
      _hideOverlay();
      final hasSeries = ref.read(seriesProvider).query.isNotEmpty;
      final hasFeed = ref.read(youtubeFeedProvider).searchQuery.isNotEmpty;
      if (hasSeries || hasFeed) {
        _clearSearchAndReset();
      }
      return;
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 160), () {
      _fetchSuggestions(query);
    });
  }

  Future<void> _fetchSuggestions(String query) async {
    if (!mounted || !_searchFocusNode.hasFocus) return;
    try {
      final results = await _yt.search.getQuerySuggestions(query);
      if (!mounted || !_searchFocusNode.hasFocus || _searchController.text.trim() != query) return;
      setState(() {
        _suggestions = results;
        _highlightedIndex = -1;
      });
      if (_suggestions.isNotEmpty) {
        _showOverlay();
      } else {
        _hideOverlay();
      }
    } catch (_) {}
  }

  void _showOverlay() {
    if (!mounted) return;
    if (_suggestionsOverlay != null) {
      _suggestionsOverlay!.markNeedsBuild();
      return;
    }

    final overlay = Overlay.of(context, rootOverlay: true);
    _suggestionsOverlay = OverlayEntry(
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final renderBox = _searchBoxKey.currentContext?.findRenderObject() as RenderBox?;
        final width = renderBox?.size.width ?? 540.0;

        return Positioned(
          width: width,
          child: CompositedTransformFollower(
            link: _searchLayerLink,
            showWhenUnlinked: false,
            offset: const Offset(0, 44),
            child: TapRegion(
              groupId: 'youtube_search_group',
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 420),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkCard : AppColors.lightCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withOpacity(0.08)
                          : AppColors.lightBorder,
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.45 : 0.12),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shrinkWrap: true,
                    itemCount: _suggestions.length,
                    itemBuilder: (context, index) {
                      final text = _suggestions[index];
                      final isHighlighted = index == _highlightedIndex;
                      return _SuggestionTile(
                        text: text,
                        isDark: isDark,
                        isHighlighted: isHighlighted,
                        onTap: () => _selectSuggestion(text),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_suggestionsOverlay!);
  }

  void _hideOverlay() {
    _suggestionsOverlay?.remove();
    _suggestionsOverlay = null;
  }

  void _selectSuggestion(String suggestion) {
    _searchController.text = suggestion;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: suggestion.length),
    );
    _hideOverlay();
    _searchFocusNode.unfocus();
    _onSearch();
  }

  bool _isLikelySeriesQuery(String q) {
    final lower = q.toLowerCase();
    return lower.contains('مسلسل') ||
        lower.contains('حلقة') ||
        lower.contains('حلقات') ||
        lower.contains('الحلقة') ||
        lower.contains('الحلقات') ||
        lower.contains('season') ||
        lower.contains('series') ||
        lower.contains('episode');
  }

  void _onSearch() {
    _hideOverlay();
    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      if (query.contains('youtube.com') || query.contains('youtu.be')) {
        ref.read(analyzerProvider.notifier).analyze(query);
      }

      final seriesState = ref.read(seriesProvider);
      final isSeriesWord = _isLikelySeriesQuery(query);

      if (seriesState.isSeriesMode || isSeriesWord) {
        ref.read(seriesProvider.notifier).searchSeries(query);
      } else {
        ref.read(youtubeFeedProvider.notifier).search(query);
      }
      context.go('/');
    }
  }

  void _clearSearchAndReset() {
    _searchController.clear();
    _suggestions.clear();
    _hideOverlay();
    ref.read(seriesProvider.notifier).reset();
    ref.read(youtubeFeedProvider.notifier).clearSearch();
    setState(() {});
    context.go('/');
  }

  void _onReload() {
    final seriesState = ref.read(seriesProvider);
    if (seriesState.isSeriesMode && seriesState.query.isNotEmpty) {
      ref.read(seriesProvider.notifier).searchSeries(seriesState.query);
    } else {
      ref.read(youtubeFeedProvider.notifier).refresh();
    }
  }

  bool get _isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(stringsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = AppPalette.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 700;

    final headerContent = Container(
      height: isMobile ? 56 : 62,
      padding: EdgeInsets.symmetric(horizontal: _isDesktop ? 8 : (isMobile ? 12 : 10)),
      decoration: BoxDecoration(
        color: palette.bg,
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.white.withOpacity(0.08)
                : AppColors.lightBorder,
            width: 1,
          ),
        ),
      ),
      child: isMobile
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Builder(
                  builder: (ctx) => IconButton(
                    icon: const Icon(Icons.menu_rounded, size: 24),
                    tooltip: 'القائمة الجانبية',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                    onPressed: () => Scaffold.of(ctx).openDrawer(),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _buildSearchBox(),
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(width: 8),

                // Brand Logo & Name
                InkWell(
                  onTap: () => context.go('/'),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.asset(
                            'assets/images/app_logo.png',
                            width: 32,
                            height: 32,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 16),

                // Desktop YouTube Search Bar
                Expanded(
                  child: Center(
                    child: _buildSearchBox(),
                  ),
                ),

                const SizedBox(width: 8),

                // Reload / Refresh Search Page Button
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  tooltip: 'إعادة تحميل نتائج البحث',
                  style: IconButton.styleFrom(
                    foregroundColor: isDark ? Colors.white70 : Colors.black87,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: _onReload,
                ),

                const SizedBox(width: 6),

                // Settings Button (Desktop only)
                IconButton(
                  icon: const Icon(Icons.settings_outlined, size: 20),
                  tooltip: strings.navSettings,
                  onPressed: () => context.go('/settings'),
                ),

                // Windows Caption Buttons (Minimize, Maximize, Close)
                if (_isDesktop) ...[
                  Container(
                    height: 24,
                    width: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    color: isDark ? Colors.white12 : palette.border,
                  ),
                  const WindowCaptionButtons(),
                ],
              ],
            ),
    );

    // If on desktop, wrap with DragToMoveArea for smooth window dragging and double-click to maximize/restore
    if (_isDesktop) {
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onDoubleTap: () async {
          try {
            final isMax = await windowManager.isMaximized();
            if (isMax) {
              await windowManager.unmaximize();
            } else {
              await windowManager.maximize();
            }
          } catch (_) {}
        },
        child: DragToMoveArea(child: headerContent),
      );
    }
    return SafeArea(bottom: false, child: headerContent);
  }

  Widget _buildSearchBox() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 580),
      child: TapRegion(
        groupId: 'youtube_search_group',
        onTapOutside: (_) => _hideOverlay(),
        child: CompositedTransformTarget(
          link: _searchLayerLink,
          child: Focus(
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent && _suggestions.isNotEmpty && _suggestionsOverlay != null) {
                if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  setState(() {
                    _highlightedIndex = (_highlightedIndex + 1) % _suggestions.length;
                    _searchController.text = _suggestions[_highlightedIndex];
                    _searchController.selection = TextSelection.fromPosition(
                      TextPosition(offset: _searchController.text.length),
                    );
                  });
                  _suggestionsOverlay?.markNeedsBuild();
                  return KeyEventResult.handled;
                } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  setState(() {
                    _highlightedIndex = (_highlightedIndex - 1 + _suggestions.length) % _suggestions.length;
                    _searchController.text = _suggestions[_highlightedIndex];
                    _searchController.selection = TextSelection.fromPosition(
                      TextPosition(offset: _searchController.text.length),
                    );
                  });
                  _suggestionsOverlay?.markNeedsBuild();
                  return KeyEventResult.handled;
                } else if (event.logicalKey == LogicalKeyboardKey.escape) {
                  _hideOverlay();
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            child: SizedBox(
              key: _searchBoxKey,
              height: AppSearchField.defaultHeight,
              // The shared pill every page uses; submit and clear keep the
              // header's existing search / reset logic.
              child: AppSearchField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                hintText: 'بحث',
                onChanged: _onTextChanged,
                onSubmitted: (_) {
                  _hideOverlay();
                  _searchFocusNode.unfocus();
                  _onSearch();
                },
                onClear: _clearSearchAndReset,
                showClear: _searchController.text.isNotEmpty,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// YouTube Auto-Complete Suggestion Tile matching YouTube desktop styling
class _SuggestionTile extends StatefulWidget {
  final String text;
  final bool isDark;
  final bool isHighlighted;
  final VoidCallback onTap;

  const _SuggestionTile({
    required this.text,
    required this.isDark,
    required this.isHighlighted,
    required this.onTap,
  });

  @override
  State<_SuggestionTile> createState() => _SuggestionTileState();
}

class _SuggestionTileState extends State<_SuggestionTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final active = _isHovered || widget.isHighlighted;
    // The light hover tint must stay a step off white, or the highlighted
    // suggestion would vanish into the white sheet.
    final hoverBg =
        widget.isDark ? const Color(0xFF1B2232) : AppPalette.of(context).skeleton;
    final textColor =
        widget.isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final iconColor =
        widget.isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: active ? hoverBg : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                Icons.search_rounded,
                size: 20,
                color: iconColor,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  widget.text,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: active ? FontWeight.bold : FontWeight.w600,
                    color: textColor,
                    letterSpacing: -0.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
