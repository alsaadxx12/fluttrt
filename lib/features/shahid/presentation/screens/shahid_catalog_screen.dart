import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_palette.dart';
import '../../data/shahid_models.dart';
import '../../data/shahid_service.dart';
import '../shahid_providers.dart';
import '../shahid_widgets.dart';

class ShahidCategoryFilter {
  final String label;
  final String rowId;
  const ShahidCategoryFilter(this.label, this.rowId);
}

const kShahidCatalogFilters = [
  ShahidCategoryFilter('الكل (الأكثر رواجاً)', ShahidRows.freeTrendsSeries),
  ShahidCategoryFilter('مسلسلات عربية', ShahidRows.freeArabicSeries),
  ShahidCategoryFilter('مسلسلات خليجية', ShahidRows.freeGulfSeries),
  ShahidCategoryFilter('مسلسلات مصرية', ShahidRows.freeEgyptianSeries),
  ShahidCategoryFilter('مسلسلات تركية', ShahidRows.freeTurkishSeries),
  ShahidCategoryFilter('برامج تلفزيونية', ShahidRows.freeTvShows),
];

class ShahidCatalogScreen extends ConsumerStatefulWidget {
  final String? initialRowId;
  final String? initialTitle;

  const ShahidCatalogScreen({
    super.key,
    this.initialRowId,
    this.initialTitle,
  });

  @override
  ConsumerState<ShahidCatalogScreen> createState() => _ShahidCatalogScreenState();
}

class _ShahidCatalogScreenState extends ConsumerState<ShahidCatalogScreen> {
  late String _selectedRowId;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  final List<ShahidItem> _items = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _currentPage = 0;
  String? _errorMessage;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedRowId = widget.initialRowId ?? ShahidRows.freeTrendsSeries;
    _scrollController.addListener(_onScroll);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 400) {
      if (!_isLoading && _hasMore) {
        _loadNextPage();
      }
    }
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _currentPage = 0;
      _hasMore = true;
      _items.clear();
    });

    try {
      final service = ref.read(shahidServiceProvider);
      final res = await service.fetchPagedRow(_selectedRowId, page: 0, pageSize: 20);
      if (mounted) {
        setState(() {
          _items.addAll(res.items);
          _hasMore = res.hasMore;
          _currentPage = 1;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'تعذر تحميل محتوى شاهد. يُرجى المحاولة ثانيةً.';
        });
      }
    }
  }

  Future<void> _loadNextPage() async {
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);

    try {
      final service = ref.read(shahidServiceProvider);
      final res = await service.fetchPagedRow(_selectedRowId, page: _currentPage, pageSize: 20);
      if (mounted) {
        final existingIds = _items.map((i) => i.id).toSet();
        final fresh = res.items.where((i) => !existingIds.contains(i.id)).toList();
        setState(() {
          _items.addAll(fresh);
          _hasMore = res.hasMore && res.items.isNotEmpty;
          _currentPage++;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _selectCategory(String rowId) {
    if (_selectedRowId == rowId) return;
    setState(() => _selectedRowId = rowId);
    _loadFirstPage();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final filtered = _searchQuery.isEmpty
        ? _items
        : _items.where((it) {
            final q = _searchQuery.trim().toLowerCase();
            return it.title.toLowerCase().contains(q) ||
                it.genres.any((g) => g.toLowerCase().contains(q));
          }).toList();

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
        foregroundColor: isDark ? Colors.white : const Color(0xFF0F172A),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF16A34A),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'شاهد مجاني',
                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              widget.initialTitle ?? 'مسلسلات وأفلام شاهد',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // 1. Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.border),
              ),
              child: TextField(
                controller: _searchController,
                style: TextStyle(color: p.text, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'بحث في مسلسلات شاهد المجانية...',
                  hintStyle: TextStyle(color: p.textMuted, fontSize: 13),
                  prefixIcon: Icon(Icons.search_rounded, color: p.textMuted, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
              ),
            ),
          ),

          // 2. Category Filter Pills
          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              scrollDirection: Axis.horizontal,
              itemCount: kShahidCatalogFilters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final cat = kShahidCatalogFilters[i];
                final isSelected = cat.rowId == _selectedRowId;
                return InkWell(
                  onTap: () => _selectCategory(cat.rowId),
                  borderRadius: BorderRadius.circular(20),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFE50914) : p.card,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? const Color(0xFFE50914) : p.border,
                      ),
                    ),
                    child: Text(
                      cat.label,
                      style: TextStyle(
                        color: isSelected ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF334155)),
                        fontSize: 12.5,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 6),

          // 3. Grid of Content
          Expanded(
            child: _errorMessage != null && _items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 40),
                        const SizedBox(height: 10),
                        Text(_errorMessage!, style: TextStyle(color: p.textMuted)),
                        const SizedBox(height: 14),
                        ElevatedButton(
                          onPressed: _loadFirstPage,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE50914),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  )
                : (_isLoading && _items.isEmpty)
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFE50914),
                          strokeWidth: 2.5,
                        ),
                      )
                    : filtered.isEmpty
                        ? Center(
                            child: Text(
                              _searchQuery.isNotEmpty ? 'لا توجد نتائج مطابقة لبحثك' : 'لا تتوفر أعمال حالياً',
                              style: TextStyle(color: p.textMuted, fontSize: 14),
                            ),
                          )
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final crossAxisCount = (constraints.maxWidth / 140).floor().clamp(2, 7);
                              return GridView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  mainAxisSpacing: 14,
                                  crossAxisSpacing: 12,
                                  childAspectRatio: 0.58,
                                ),
                                itemCount: filtered.length + (_isLoading ? 1 : 0),
                                itemBuilder: (context, i) {
                                  if (i >= filtered.length) {
                                    return const Center(
                                      child: CircularProgressIndicator(
                                        color: Color(0xFFE50914),
                                        strokeWidth: 2.0,
                                      ),
                                    );
                                  }
                                  final item = filtered[i];
                                  return ShahidPosterCard(item: item, width: double.infinity);
                                },
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
