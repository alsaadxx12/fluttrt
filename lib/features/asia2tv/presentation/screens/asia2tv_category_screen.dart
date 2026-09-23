import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_palette.dart';
import '../../../../presentation/widgets/app_search_field.dart';
import '../../data/models/asia2tv_models.dart';
import '../providers/asia2tv_providers.dart';
import '../widgets/asia2tv_card.dart';

class Asia2TvCategoryScreen extends ConsumerStatefulWidget {
  final Asia2TvCategory initialCategory;

  const Asia2TvCategoryScreen({
    super.key,
    this.initialCategory = Asia2TvCategory.korean,
  });

  @override
  ConsumerState<Asia2TvCategoryScreen> createState() => _Asia2TvCategoryScreenState();
}

class _Asia2TvCategoryScreenState extends ConsumerState<Asia2TvCategoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  static const List<Asia2TvCategory> _categories = [
    Asia2TvCategory.korean,
    Asia2TvCategory.japanese,
    Asia2TvCategory.chinese,
    Asia2TvCategory.thai,
    Asia2TvCategory.completed,
  ];

  @override
  void initState() {
    super.initState();
    final initialIndex = _categories.indexOf(widget.initialCategory);
    _tabController = TabController(
      length: _categories.length,
      vsync: this,
      initialIndex: initialIndex != -1 ? initialIndex : 0,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final isSearching = _searchQuery.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: palette.bg,
        elevation: 0,
        toolbarHeight: 0,
        automaticallyImplyLeading: false,
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(isSearching ? 56 : 102),
          child: Column(
            children: [
              // Search box
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: AppSearchField(
                  controller: _searchController,
                  hints: const [
                    'ابحث عن مسلسل',
                    'ابحث عن دراما كورية',
                    'ابحث عن دراما يابانية',
                    'ابحث عن دراما صينية',
                  ],
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  showClear: _searchQuery.isNotEmpty,
                  onClear: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
              ),

              // Categories TabBar (hidden when searching)
              if (!isSearching)
                // Glass tabs with the cards' corners: the chosen one is a
                // brighter sheen, the rest are words on the page.
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  dividerColor: Colors.transparent,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicatorPadding: const EdgeInsets.symmetric(vertical: 6),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 14),
                  indicator: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white.withOpacity(0.30), width: 0.8),
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white54,
                  labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
                  unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.normal),
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    for (final cat in _categories)
                      Tab(text: cat.label),
                  ],
                ),
            ],
          ),
        ),
      ),
      body: isSearching
          ? _buildSearchResults(_searchQuery)
          : TabBarView(
              controller: _tabController,
              children: [
                for (final cat in _categories)
                  _CategoryGridView(category: cat),
              ],
            ),
    );
  }

  Widget _buildSearchResults(String query) {
    final searchAsync = ref.watch(asia2tvSearchProvider(query));

    return searchAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
      error: (err, _) => Center(
        child: Text('خطأ أثناء البحث: $err', style: const TextStyle(color: Colors.white54)),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const Center(
            child: Text('لا توجد نتائج مطابقة لبحثك', style: TextStyle(color: Colors.white54, fontSize: 14)),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 0.66,
            crossAxisSpacing: 12,
            mainAxisSpacing: 16,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return Asia2TvCard(
              item: item,
              width: double.infinity,
              height: 155,
            );
          },
        );
      },
    );
  }
}

class _CategoryGridView extends ConsumerWidget {
  final Asia2TvCategory category;

  const _CategoryGridView({required this.category});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(asia2tvCategoryProvider(category));

    return asyncList.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
      error: (err, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, color: Colors.white38, size: 40),
            const SizedBox(height: 10),
            Text('تعذّر جلب ${category.label}', style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => ref.refresh(asia2tvCategoryProvider(category)),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('إعادة المحاولة', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const Center(
            child: Text('لا تتوفر عناصر في هذا القسم حالياً', style: TextStyle(color: Colors.white54)),
          );
        }

        return RefreshIndicator(
          color: AppColors.primary,
          backgroundColor: const Color(0xFF0E131F),
          onRefresh: () async => ref.refresh(asia2tvCategoryProvider(category).future),
          child: GridView.builder(
            padding: const EdgeInsets.all(14),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.66,
              crossAxisSpacing: 12,
              mainAxisSpacing: 16,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Asia2TvCard(
                item: item,
                width: double.infinity,
                height: 155,
              );
            },
          ),
        );
      },
    );
  }
}
