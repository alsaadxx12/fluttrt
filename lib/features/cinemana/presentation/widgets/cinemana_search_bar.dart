import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import '../../data/models/cinemana_models.dart';
import '../providers/cinemana_provider.dart';
import '../screens/cinemana_detail_screen.dart';
import 'package:youtube_downloader/core/tv/tv_mode.dart';

class CinemanaSearchBar extends ConsumerStatefulWidget {
  final String? initialQuery;
  final ValueChanged<String> onSearchSubmitted;
  final VoidCallback onClear;
  final String hintText;

  const CinemanaSearchBar({
    super.key,
    this.initialQuery,
    required this.onSearchSubmitted,
    required this.onClear,
    this.hintText = 'بحث في سينمانا (أفلام، مسلسلات، أنمي)...',
  });

  @override
  ConsumerState<CinemanaSearchBar> createState() => _CinemanaSearchBarState();
}

class _CinemanaSearchBarState extends ConsumerState<CinemanaSearchBar> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  Timer? _debounceTimer;
  CancelToken? _cancelToken;
  List<CinemanaItem> _suggestions = [];
  bool _isLoadingSuggestions = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery ?? '');
    _focusNode.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant CinemanaSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialQuery != oldWidget.initialQuery &&
        widget.initialQuery != _controller.text) {
      _controller.text = widget.initialQuery ?? '';
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _cancelToken?.cancel('disposed');
    _removeOverlay();
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String val) {
    _debounceTimer?.cancel();
    _cancelToken?.cancel('new query');
    final query = val.trim();
    if (query.length < 2) {
      _removeOverlay();
      return;
    }

    _cancelToken = CancelToken();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      setState(() => _isLoadingSuggestions = true);
      _showOverlay();

      try {
        final service = ref.read(cinemanaServiceProvider);
        final results = await service.search(query, cancelToken: _cancelToken);
        if (mounted) {
          setState(() {
            _suggestions = results.take(8).toList();
            _isLoadingSuggestions = false;
          });
          _overlayEntry?.markNeedsBuild();
        }
      } catch (_) {
        if (mounted) {
          setState(() => _isLoadingSuggestions = false);
          _overlayEntry?.markNeedsBuild();
        }
      }
    });
  }

  void _showOverlay() {
    if (!mounted || _overlayEntry != null) return;
    try {
      final overlay = Overlay.of(context);
      _overlayEntry = _createOverlayEntry();
      overlay.insert(_overlayEntry!);
    } catch (_) {}
  }

  void _removeOverlay() {
    try {
      _overlayEntry?.remove();
    } catch (_) {}
    _overlayEntry = null;
  }

  OverlayEntry _createOverlayEntry() {
    final renderBox = context.findRenderObject() as RenderBox?;
    final size = renderBox?.size ?? const Size(300, 48);

    return OverlayEntry(
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Positioned(
          width: size.width,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: Offset(0, size.height + 6),
            child: Material(
              elevation: 12,
              borderRadius: BorderRadius.circular(16),
              color: isDark ? const Color(0xFF1E1E26) : Colors.white,
              child: Container(
                constraints: const BoxConstraints(maxHeight: 360),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? Colors.white.withOpacity(0.1) : Colors.black12,
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.45 : 0.15),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: _isLoadingSuggestions
                      ? Container(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: const Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        )
                      : _suggestions.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(16),
                              child: Center(
                                child: Text(
                                  'لا توجد نتائج مطابقة',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark ? Colors.white60 : Colors.black54,
                                  ),
                                ),
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              itemCount: _suggestions.length,
                              separatorBuilder: (_, __) => Divider(
                                height: 1,
                                thickness: 0.8,
                                color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06),
                              ),
                              itemBuilder: (context, index) {
                                final item = _suggestions[index];
                                return InkWell(
                                  onTap: () {
                                    _removeOverlay();
                                    Navigator.of(context, rootNavigator: true).push(
                                      MaterialPageRoute(
                                        builder: (_) => CinemanaDetailScreen(item: item),
                                      ),
                                    );
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    child: Row(
                                      children: [
                                        // Poster thumbnail
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Container(
                                            width: 44,
                                            height: 60,
                                            color: isDark ? const Color(0xFF2B2B38) : const Color(0xFFE0E0E0),
                                            child: item.bestPosterUrl.isNotEmpty
                                                ? Image.network(
                                                    item.bestPosterUrl,
                                                    fit: BoxFit.cover,
                                                    filterQuality: FilterQuality.high,
                                                    errorBuilder: (_, __, ___) => const Icon(
                                                      Icons.movie_outlined,
                                                      size: 20,
                                                      color: Colors.grey,
                                                    ),
                                                  )
                                                : const Icon(
                                                    Icons.movie_outlined,
                                                    size: 20,
                                                    color: Colors.grey,
                                                  ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        // Title & Info
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                item.displayTitle,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: isDark ? Colors.white : Colors.black87,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Row(
                                                children: [
                                                  if (item.year.isNotEmpty) ...[
                                                    Text(
                                                      item.year,
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: isDark ? Colors.white54 : Colors.black45,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                  ],
                                                  if (item.stars.isNotEmpty && item.stars != '0') ...[
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFFFFA000).withOpacity(0.18),
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          const Icon(
                                                            Icons.star_rounded,
                                                            size: 11,
                                                            color: Color(0xFFFFA000),
                                                          ),
                                                          const SizedBox(width: 2),
                                                          Text(
                                                            item.stars,
                                                            style: const TextStyle(
                                                              fontSize: 10,
                                                              fontWeight: FontWeight.bold,
                                                              color: Color(0xFFFFA000),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                  ],
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                    decoration: BoxDecoration(
                                                      color: item.isSeries
                                                          ? const Color(0xFF448AFF).withOpacity(0.15)
                                                          : const Color(0xFFFF5252).withOpacity(0.15),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      item.isSeries ? 'مسلسل' : 'فيلم',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold,
                                                        color: item.isSeries
                                                            ? const Color(0xFF448AFF)
                                                            : const Color(0xFFFF5252),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        Icon(
                                          Icons.chevron_left_rounded,
                                          size: 20,
                                          color: isDark ? Colors.white30 : Colors.black26,
                                        ),
                                      ],
                                    ),
                                  ),
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
  }

  void _submitSearch() {
    _removeOverlay();
    _focusNode.unfocus();
    final q = _controller.text.trim();
    if (q.isNotEmpty) {
      widget.onSearchSubmitted(q);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasFocus = _focusNode.hasFocus;

    return CompositedTransformTarget(
      link: _layerLink,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 48,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1B1B22) : const Color(0xFFF2F3F7),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: hasFocus
                ? AppColors.primary
                : (isDark ? const Color(0xFF2C2C38) : const Color(0xFFDCE0E8)),
            width: hasFocus ? 1.6 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: (hasFocus ? AppColors.primary : Colors.black).withOpacity(
                isDark ? (hasFocus ? 0.35 : 0.2) : (hasFocus ? 0.18 : 0.04),
              ),
              blurRadius: hasFocus ? 10 : 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            const SizedBox(width: 14),
            Icon(
              Icons.search_rounded,
              color: hasFocus
                  ? AppColors.primary
                  : (isDark ? const Color(0xFF9090A0) : const Color(0xFF6C6C7E)),
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                cursorColor: AppColors.primary,
                onChanged: _onChanged,
                onSubmitted: (_) => _submitSearch(),
                textInputAction: TextInputAction.search,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : const Color(0xFF151518),
                ),
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  // The placeholder reads at full strength - same colour as typed
                  // text - rather than the dimmed grey that looked like a
                  // disabled field.
                  hintStyle: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : const Color(0xFF151518),
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (_controller.text.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                color: isDark ? Colors.white54 : Colors.black45,
                onPressed: () {
                  _controller.clear();
                  _removeOverlay();
                  widget.onClear();
                  setState(() {});
                },
              )
            else
              const SizedBox(width: 6),
            // Speaking is the only comfortable way to search from a sofa:
            // a remote spells a title one letter at a time.
            IconButton(
              tooltip: 'البحث بالصوت',
              icon: const Icon(Icons.mic_rounded, size: 20),
              color: isDark ? Colors.white70 : Colors.black54,
              onPressed: _searchByVoice,
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  /// Hands the microphone to the system recogniser and searches for what it
  /// heard. Saying nothing, or a device with no recogniser, simply leaves
  /// the field as it was.
  Future<void> _searchByVoice() async {
    final heard = await VoiceSearch.listen(prompt: widget.hintText);
    if (!mounted || heard == null) return;
    _controller.text = heard;
    _removeOverlay();
    setState(() {});
    widget.onSearchSubmitted(heard);
  }
}
