import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_palette.dart';
import '../../data/models/asia2tv_models.dart';
import '../providers/asia2tv_providers.dart';
import '../widgets/asia2tv_card.dart';

class Asia2TvCategoryScreen extends ConsumerStatefulWidget {
  final Asia2TvCategory initialCategory;

  const Asia2TvCategoryScreen({
    super.key,
    this.initialCategory = Asia2TvCategory.newEpisodes,
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
    Asia2TvCategory.newEpisodes,
    Asia2TvCategory.korean,
    Asia2TvCategory.japanese,
    Asia2TvCategory.chinese,
    Asia2TvCategory.thai,
    Asia2TvCategory.movies,
    Asia2TvCategory.kshow,
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Row(
          children: [
            Icon(Icons.tv_rounded, color: AppColors.primary, size: 22),
            SizedBox(width: 8),
            Text(
              'الدراما الآسيوية • Asia2TV',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(isSearching ? 60 : 108),
          child: Column(
            children: [
              // Search Input Box
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  style: const TextStyle(color: Colors.white, fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: 'بحث في مسلسلات وأفلام Asia2TV...',
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFF0E131F),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.white12, width: 0.8),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.white12, width: 0.8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.primary, width: 1.2),
                    ),
                  ),
                ),
              ),

              // Categories TabBar (hidden when searching)
              if (!isSearching)
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  indicatorColor: AppColors.primary,
                  indicatorWeight: 2.5,
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
            childAspectRatio: 0.52,
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
              childAspectRatio: 0.52,
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
