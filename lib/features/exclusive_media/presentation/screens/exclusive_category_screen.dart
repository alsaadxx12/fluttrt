import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../data/models/exclusive_media_models.dart';
import '../providers/exclusive_media_providers.dart';
import 'exclusive_details_screen.dart';

class ExclusiveCategoryScreen extends ConsumerStatefulWidget {
  final ExclusiveCategory initialCategory;

  const ExclusiveCategoryScreen({
    super.key,
    this.initialCategory = ExclusiveCategory.recent,
  });

  @override
  ConsumerState<ExclusiveCategoryScreen> createState() => _ExclusiveCategoryScreenState();
}

class _ExclusiveCategoryScreenState extends ConsumerState<ExclusiveCategoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  static const List<ExclusiveCategory> _categories = [
    ExclusiveCategory.recent,
    ExclusiveCategory.series,
    ExclusiveCategory.movies,
    ExclusiveCategory.arabicSeries,
    ExclusiveCategory.foreignSeries,
    ExclusiveCategory.turkishSeries,
    ExclusiveCategory.arabicMovies,
    ExclusiveCategory.foreignMovies,
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
    return Scaffold(
      backgroundColor: const Color(0xFF04060A),
      // No toolbar: the search field and the tabs are the whole top of the
      // page, and leaving it is the system back gesture.
      appBar: AppBar(
        backgroundColor: const Color(0xFF04060A),
        elevation: 0,
        toolbarHeight: 0,
        automaticallyImplyLeading: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: Column(
            children: [
              // Search field
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0E1322),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val.trim()),
                    style: const TextStyle(color: Colors.white, fontSize: 13.5),
                    decoration: InputDecoration(
                      hintText: 'ابحث عن أي فيلم أو مسلسل...',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13),
                      prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ),

              // Tabs
              TabBar(
                controller: _tabController,
                isScrollable: true,
                indicatorColor: AppColors.primary,
                indicatorWeight: 3,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white54,
                labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                tabs: _categories.map((c) => Tab(text: c.label)).toList(),
              ),
            ],
          ),
        ),
      ),
      body: _searchQuery.isNotEmpty
          ? _buildSearchResults(_searchQuery)
          : TabBarView(
              controller: _tabController,
              children: _categories.map((cat) => _buildCategoryGrid(cat)).toList(),
            ),
    );
  }

  Widget _buildSearchResults(String query) {
    final searchAsync = ref.watch(exclusiveSearchProvider(query));

    return searchAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
      error: (e, _) => Center(
        child: Text('حدث خطأ أثناء البحث', style: TextStyle(color: Colors.white.withOpacity(0.7))),
      ),
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: Text(
              'لا توجد نتائج مطابقة لـ "$query"',
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14),
            ),
          );
        }
        return _buildItemsGrid(items);
      },
    );
  }

  Widget _buildCategoryGrid(ExclusiveCategory category) {
    final categoryAsync = ref.watch(exclusiveCategoryProvider(category));

    return categoryAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
      error: (err, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, color: Colors.white38, size: 48),
            const SizedBox(height: 12),
            Text('تعذر تحميل هذا القسم', style: TextStyle(color: Colors.white.withOpacity(0.7))),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => ref.refresh(exclusiveCategoryProvider(category)),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('إعادة المحاولة', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: Text(
              'لا توجد عناصر متاحة حالياً',
              style: TextStyle(color: Colors.white.withOpacity(0.5)),
            ),
          );
        }
        return _buildItemsGrid(items);
      },
    );
  }

  Widget _buildItemsGrid(List<ExclusiveMediaItem> items) {
    return GridView.builder(
      padding: const EdgeInsets.all(14),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 14,
        childAspectRatio: 0.66,
      ),
      itemCount: items.length,
      itemBuilder: (context, idx) {
        final item = items[idx];
        return GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ExclusiveDetailsScreen(item: item)),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Poster Card
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (item.posterUrl.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: item.posterUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(color: const Color(0xFF0E1322)),
                        )
                      else
                        Container(color: const Color(0xFF0E1322)),

                      // Rating star at top left
                      if (item.rating != null && item.rating!.isNotEmpty)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star_rounded, color: Color(0xFFFFB800), size: 12),
                                const SizedBox(width: 2),
                                Text(
                                  item.rating!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Quality at top right
                      if (item.quality != null && item.quality!.isNotEmpty)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.85),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              item.quality!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // No title or year under the poster: the poster is the card.
            ],
          ),
        );
      },
    );
  }
}
