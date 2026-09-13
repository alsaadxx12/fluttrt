import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import '../providers/cinemana_provider.dart';
import '../widgets/cinemana_poster_card.dart';
import 'cinemana_detail_screen.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';

class CinemanaFavoritesScreen extends ConsumerStatefulWidget {
  const CinemanaFavoritesScreen({super.key});

  @override
  ConsumerState<CinemanaFavoritesScreen> createState() => _CinemanaFavoritesScreenState();
}

class _CinemanaFavoritesScreenState extends ConsumerState<CinemanaFavoritesScreen> {
  int _selectedFilter = 0; // 0: All, 1: Movies, 2: Series, 3: Anime

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allFavorites = ref.watch(cinemanaFavoritesProvider);

    final filteredList = allFavorites.where((item) {
      if (_selectedFilter == 1) {
        // Movies only (kind == '1')
        return !item.isSeries;
      } else if (_selectedFilter == 2) {
        // Series (kind == '2' and not anime)
        return item.isSeries && !item.categories.any((c) => c.contains('رسوم') || c.contains('أنمي'));
      } else if (_selectedFilter == 3) {
        // Anime
        return item.categories.any((c) => c.contains('رسوم') || c.contains('أنمي') || c.contains('Animation'));
      }
      return true;
    }).toList();

    return Scaffold(
      // Light mode: white cards on the off-white page (dark mode unchanged).
      backgroundColor: isDark ? const Color(0xFF0F0F13) : AppPalette.of(context).bg,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF14141A) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          color: isDark ? Colors.white : Colors.black87,
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
        title: Row(
          children: [
            const Icon(Icons.favorite_rounded, color: Colors.redAccent, size: 22),
            const SizedBox(width: 8),
            Text(
              'قائمة المفضلة',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : const Color(0xFF111115),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${allFavorites.length}',
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Filter Chips
          if (allFavorites.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  _buildFilterChip(0, 'الكل (${allFavorites.length})', isDark),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    1,
                    'أفلام (${allFavorites.where((i) => !i.isSeries).length})',
                    isDark,
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    2,
                    'مسلسلات (${allFavorites.where((i) => i.isSeries).length})',
                    isDark,
                  ),
                ],
              ),
            ),

          // Content
          Expanded(
            child: filteredList.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E1E26) : const Color(0xFFF5F5FA),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.favorite_border_rounded,
                            size: 42,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'لا توجد عناصر في المفضلة',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'يمكنك حفظ الأفلام والمسلسلات بضغطة واحدة على علامة ❤️',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () => context.go('/cinemana/movies'),
                          icon: const Icon(Icons.movie_filter_rounded, size: 18),
                          label: const Text('تصفح أفلام سينمانا'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.58,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: filteredList.length,
                    itemBuilder: (context, index) {
                      final item = filteredList[index];
                      return CinemanaPosterCard(
                        item: item,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CinemanaDetailScreen(item: item),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(int index, String label, bool isDark) {
    final isSelected = _selectedFilter == index;
    return InkWell(
      onTap: () => setState(() => _selectedFilter = index),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.redAccent
              : (isDark ? const Color(0xFF1E1E26) : const Color(0xFFEEEEF4)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected
                ? Colors.white
                : (isDark ? Colors.white70 : Colors.black87),
          ),
        ),
      ),
    );
  }
}
