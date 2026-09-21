import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/presentation/widgets/app_search_field.dart';
import '../providers/cinemana_provider.dart';
import '../widgets/cinemana_poster_card.dart';
import '../widgets/cinemana_search_bar.dart';
import 'cinemana_detail_screen.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';
import '../../../viu/data/viu_models.dart';
import '../../../viu/presentation/viu_widgets.dart';

// Cinemana genres mapping (id & Arabic title)
const List<Map<String, dynamic>> cinemanaGenres = [
  {'id': 0, 'title': 'الكل'},
  {'id': 84, 'title': 'اكشن'},
  {'id': 62, 'title': 'دراما'},
  {'id': 70, 'title': 'رعب'},
  {'id': 59, 'title': 'كوميدي'},
  {'id': 77, 'title': 'رومانسي'},
  {'id': 58, 'title': 'سيرة ذاتية'},
  {'id': 78, 'title': 'خيال علمي'},
  {'id': 76, 'title': 'غموض'},
  {'id': 56, 'title': 'مغامرة'},
  {'id': 60, 'title': 'جريمة'},
  {'id': 65, 'title': 'عائلي'},
  {'id': 61, 'title': 'وثائقي'},
  {'id': 68, 'title': 'تاريخي'},
  {'id': 67, 'title': 'خيالي'},
];

class CinemanaCatalogScreen extends ConsumerStatefulWidget {
  final String kind; // 'movies', 'series', 'anime'
  final String? initialOrder;
  final int? initialCategoryId;

  const CinemanaCatalogScreen({
    super.key,
    this.kind = 'movies',
    this.initialOrder,
    this.initialCategoryId,
  });

  @override
  ConsumerState<CinemanaCatalogScreen> createState() => _CinemanaCatalogScreenState();
}

class _CinemanaCatalogScreenState extends ConsumerState<CinemanaCatalogScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    if (widget.initialOrder != null || widget.initialCategoryId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final notifier = ref.read(cinemanaSectionProvider(widget.kind).notifier);
        notifier.applyFilters(
          order: widget.initialOrder,
          categoryId: widget.initialCategoryId,
        );
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      ref.read(cinemanaSectionProvider(widget.kind).notifier).loadMore();
    }
  }

  String get _screenTitle {
    switch (widget.kind) {
      case 'series':
        return 'مسلسلات';
      case 'anime':
        return 'أنمي';
      default:
        return 'أفلام';
    }
  }

  Color get _accentColor {
    switch (widget.kind) {
      case 'series':
        return const Color(0xFF448AFF);
      case 'anime':
        return const Color(0xFFFF9100);
      default:
        return const Color(0xFFFF334B);
    }
  }

  /// The order the section starts with (anime opens on most-watched), so the
  /// filter button only lights up when the user changed something.
  String get _defaultOrder => widget.kind == 'anime' ? 'views' : 'desc';

  bool _hasActiveFilter(CinemanaSectionState s) =>
      s.selectedOrder != _defaultOrder ||
      s.selectedYear != null ||
      s.selectedRating != null ||
      (s.selectedCategoryId != null && s.selectedCategoryId != 0);

  void _showFilterSheet(
    BuildContext context,
    CinemanaSectionState sectionState,
    CinemanaSectionNotifier sectionNotifier,
    bool isDark,
  ) {
    final palette = AppPalette.of(context);
    final sortOptions = [
      {'label': 'المضاف حديثًا', 'order': 'desc', 'icon': Icons.schedule_rounded},
      {'label': 'الأحدث إصدارًا', 'order': 'release', 'icon': Icons.new_releases_outlined},
      {'label': 'الأكثر مشاهدة', 'order': 'views', 'icon': Icons.visibility_rounded},
      {'label': 'الرائج', 'order': 'trending', 'icon': Icons.trending_up_rounded},
      {'label': 'الأعلى تقييماً', 'order': 'stars', 'icon': Icons.star_rounded},
      {'label': 'الاسم أبجديًا', 'order': 'name', 'icon': Icons.sort_by_alpha_rounded},
    ];

    final years = ['الكل', '2026', '2025', '2024', '2023', '2022', '2021', '2020'];
    final ratings = [
      {'label': 'الكل', 'value': 0.0},
      {'label': '8.0+ ⭐', 'value': 8.0},
      {'label': '7.0+ ⭐', 'value': 7.0},
      {'label': '6.0+ ⭐', 'value': 6.0},
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF141724) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.85,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle bar
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white24 : Colors.black12,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Header Row: Title & Reset Button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.tune_rounded, color: _accentColor, size: 22),
                            const SizedBox(width: 8),
                            Text(
                              'فلاتر المحتوى',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                        TextButton.icon(
                          onPressed: () {
                            sectionNotifier.resetFilters();
                            Navigator.pop(ctx);
                          },
                          icon: const Icon(Icons.restart_alt_rounded, size: 18),
                          label: const Text('إعادة ضبط الكل'),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFE50914),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),

                    // Scrollable Options
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. Sort Order
                            Text(
                              'ترتيب النتائج',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white70 : const Color(0xFF475569),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: sortOptions.map((opt) {
                                final isSelected = sectionState.selectedOrder == opt['order'];
                                return ChoiceChip(
                                  label: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        opt['icon'] as IconData,
                                        size: 15,
                                        color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(opt['label'] as String),
                                    ],
                                  ),
                                  selected: isSelected,
                                  selectedColor: _accentColor,
                                  backgroundColor: isDark ? const Color(0xFF1E2538) : palette.card,
                                  side: isDark ? null : BorderSide(color: isSelected ? _accentColor : palette.border),
                                  labelStyle: TextStyle(
                                    color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                                    fontSize: 12,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  ),
                                  onSelected: (_) {
                                    sectionNotifier.setOrder(opt['order'] as String);
                                    Navigator.pop(ctx);
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 20),

                            // 2. Year Filter
                            Text(
                              'سنة الإنتاج',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white70 : const Color(0xFF475569),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: years.map((y) {
                                  final isSelected = (y == 'الكل' && sectionState.selectedYear == null) ||
                                      sectionState.selectedYear == y;
                                  return Padding(
                                    padding: const EdgeInsetsDirectional.only(end: 8),
                                    child: ChoiceChip(
                                      label: Text(y),
                                      selected: isSelected,
                                      selectedColor: _accentColor,
                                      backgroundColor: isDark ? const Color(0xFF1E2538) : palette.card,
                                      side: isDark ? null : BorderSide(color: isSelected ? _accentColor : palette.border),
                                      labelStyle: TextStyle(
                                        color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                                        fontSize: 12,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                      ),
                                      onSelected: (_) {
                                        sectionNotifier.applyFilters(
                                          year: y == 'الكل' ? null : y,
                                          clearYear: y == 'الكل',
                                        );
                                        Navigator.pop(ctx);
                                      },
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                            const SizedBox(height: 20),

                            // 3. Min Rating Filter
                            Text(
                              'التقييم الأدنى',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white70 : const Color(0xFF475569),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: ratings.map((r) {
                                final val = r['value'] as double;
                                final isSelected = (val == 0.0 && sectionState.selectedRating == null) ||
                                    sectionState.selectedRating == val;
                                return ChoiceChip(
                                  label: Text(r['label'] as String),
                                  selected: isSelected,
                                  selectedColor: _accentColor,
                                  backgroundColor: isDark ? const Color(0xFF1E2538) : palette.card,
                                  side: isDark ? null : BorderSide(color: isSelected ? _accentColor : palette.border),
                                  labelStyle: TextStyle(
                                    color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                                    fontSize: 12,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  ),
                                  onSelected: (_) {
                                    sectionNotifier.applyFilters(
                                      minRating: val == 0.0 ? null : val,
                                      clearRating: val == 0.0,
                                    );
                                    Navigator.pop(ctx);
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 20),

                            // 4. Genres Filter
                            Text(
                              'التصنيف',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white70 : const Color(0xFF475569),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: cinemanaGenres.map((genre) {
                                final int id = genre['id'] as int;
                                final String title = genre['title'] as String;
                                final isSelected = (id == 0 && (sectionState.selectedCategoryId == null || sectionState.selectedCategoryId == 0)) ||
                                    sectionState.selectedCategoryId == id;
                                return ChoiceChip(
                                  label: Text(title),
                                  selected: isSelected,
                                  selectedColor: _accentColor,
                                  backgroundColor: isDark ? const Color(0xFF1E2538) : palette.card,
                                  side: isDark ? null : BorderSide(color: isSelected ? _accentColor : palette.border),
                                  labelStyle: TextStyle(
                                    color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                                    fontSize: 12,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  ),
                                  onSelected: (_) {
                                    sectionNotifier.setCategory(id == 0 ? null : id);
                                    Navigator.pop(ctx);
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),

                    // Close Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accentColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'تم',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// What this catalogue can find, named one at a time in the search hint.
  List<String> get _searchHints {
    switch (widget.kind) {
      case 'series':
        return const ['ابحث عن مسلسل', 'ابحث عن ممثل', 'ابحث عن مسلسل تركي'];
      case 'anime':
        return const ['ابحث عن أنمي', 'مثال: ناروتو', 'مثال: ون بيس'];
      default:
        return const ['ابحث عن فيلم', 'ابحث عن ممثل', 'ابحث عن مخرج'];
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = AppPalette.of(context);
    final sectionState = ref.watch(cinemanaSectionProvider(widget.kind));
    final sectionNotifier = ref.read(cinemanaSectionProvider(widget.kind).notifier);
    final filterActive = _hasActiveFilter(sectionState);

    return Scaffold(
      // Pure white page. There is no app bar: the strip below is the whole
      // top of the page, and leaving it is the system back gesture.
      backgroundColor: isDark ? const Color(0xFF0F0F13) : palette.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Search field with the filter button beside it. Plain widgets
            // only: no splash, no animated container.
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              child: Row(
                children: [
                  Expanded(
                    child: CinemanaSearchBar(
                      hints: _searchHints,
                      initialQuery: sectionState.searchQuery,
                      onSearchSubmitted: (query) {
                        sectionNotifier.search(query);
                      },
                      onClear: () {
                        sectionNotifier.clearSearch();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _showFilterSheet(
                      context,
                      sectionState,
                      sectionNotifier,
                      isDark,
                    ),
                    child: Semantics(
                      button: true,
                      label: 'الفلاتر',
                      child: Container(
                        width: AppSearchField.defaultHeight,
                        height: AppSearchField.defaultHeight,
                        decoration: BoxDecoration(
                          // Flat white button, hairline border only; red once
                          // a filter is set.
                          color: isDark ? const Color(0xFF1B1B22) : palette.card,
                          borderRadius: BorderRadius.circular(AppSearchField.defaultRadius),
                          border: Border.all(
                            color: filterActive
                                ? _accentColor
                                : (isDark ? const Color(0xFF2C2C38) : palette.border),
                            width: 1,
                          ),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(
                              Icons.tune_rounded,
                              color: filterActive
                                  ? _accentColor
                                  : (isDark ? Colors.white70 : Colors.black87),
                              size: 20,
                            ),
                            if (filterActive)
                              PositionedDirectional(
                                top: 8,
                                end: 8,
                                child: Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: _accentColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                triggerMode: RefreshIndicatorTriggerMode.anywhere,
                backgroundColor: palette.card,
                color: const Color(0xFFE50914),
                strokeWidth: 2.4,
                onRefresh: () => sectionNotifier.refresh(),
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  cacheExtent: 600,
                  slivers: [
                    // Anime sub-kind switch, search summary or genre chips.
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Anime Section: Sub-kind divider (Series vs Movies)
                            if (widget.kind == 'anime') ...[
                              Container(
                                height: 38,
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  // Light mode: flat white segmented control, hairline border only.
                                  color: isDark ? const Color(0xFF1B1B22) : palette.card,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isDark ? const Color(0xFF2C2C38) : palette.border,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: InkWell(
                                        onTap: () => sectionNotifier.setAnimeSubKind(2),
                                        borderRadius: BorderRadius.circular(10),
                                        child: Container(
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: sectionState.animeSubKind == 2
                                                ? const Color(0xFFFF9100)
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            'مسلسلات الأنمي',
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.bold,
                                              color: sectionState.animeSubKind == 2
                                                  ? Colors.white
                                                  : (isDark ? Colors.white70 : Colors.black87),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: InkWell(
                                        onTap: () => sectionNotifier.setAnimeSubKind(1),
                                        borderRadius: BorderRadius.circular(10),
                                        child: Container(
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: sectionState.animeSubKind == 1
                                                ? const Color(0xFFFF9100)
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            'أفلام الأنمي',
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.bold,
                                              color: sectionState.animeSubKind == 1
                                                  ? Colors.white
                                                  : (isDark ? Colors.white70 : Colors.black87),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            if (sectionState.searchQuery.isNotEmpty) ...[
                              if (widget.kind == 'anime') const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'نتائج البحث عن: "${sectionState.searchQuery}"',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? Colors.white70 : Colors.black87,
                                          ),
                                        ),
                                        if (sectionState.hiddenSearchCount > 0)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 2),
                                            child: Text(
                                              'تم إخفاء ${sectionState.hiddenSearchCount} نتيجة خارج قسم $_screenTitle',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: isDark ? Colors.white38 : Colors.black45,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => sectionNotifier.clearSearch(),
                                    icon: const Icon(Icons.close_rounded, size: 14),
                                    label: const Text('إلغاء البحث', style: TextStyle(fontSize: 12)),
                                    style: TextButton.styleFrom(
                                      foregroundColor: AppColors.primary,
                                      padding: EdgeInsets.zero,
                                    ),
                                  ),
                                ],
                              ),
                            ] else if (widget.kind != 'anime') ...[
                              // Genres Row (اكشن، دراما، رعب...) - not on the anime page.
                              SizedBox(
                                height: 34,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: cinemanaGenres.length,
                                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                                  itemBuilder: (context, index) {
                                    final genre = cinemanaGenres[index];
                                    final int id = genre['id'] as int;
                                    final String title = genre['title'] as String;
                                    final isSelected = (id == 0 &&
                                            (sectionState.selectedCategoryId == null ||
                                                sectionState.selectedCategoryId == 0)) ||
                                        sectionState.selectedCategoryId == id;

                                    return InkWell(
                                      onTap: () => sectionNotifier.setCategory(id == 0 ? null : id),
                                      borderRadius: BorderRadius.circular(17),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14),
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? _accentColor
                                              : (isDark
                                                  ? const Color(0xFF1E1E26)
                                                  : palette.card),
                                          borderRadius: BorderRadius.circular(17),
                                          border: Border.all(
                                            color: isSelected
                                                ? _accentColor
                                                : (isDark
                                                    ? const Color(0xFF2C2C38)
                                                    : palette.border),
                                            width: 1,
                                          ),
                                        ),
                                        child: Text(
                                          title,
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
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    // Content Grid
                    // Turkish drama, from the licensed free catalogue the app
                    // already carries. Plays natively like everything else here:
                    // no web page, no pop-ups, no outbound links.
                    if (widget.kind == 'series' && sectionState.searchQuery.isEmpty) ...[
                      const SliverToBoxAdapter(child: SizedBox(height: 6)),
                      const SliverToBoxAdapter(child: ViuHomeSection(category: ViuCategory.turkish)),
                      const SliverToBoxAdapter(child: SizedBox(height: 14)),
                    ],

                    if (sectionState.isLoading || sectionState.isSearchLoading)
                      const SliverFillRemaining(
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppColors.primary,
                          ),
                        ),
                      )
                    else if (sectionState.displayItems.isEmpty)
                      SliverFillRemaining(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_off_rounded,
                                size: 48,
                                color: isDark ? Colors.white30 : Colors.black26,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'لا توجد عناصر لعرضها',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white70 : Colors.black54,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: () => sectionNotifier.refresh(),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _accentColor,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('إعادة المحاولة'),
                              ),
                            ],
                          ),
                        ),
                      )
                    else ...[
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        sliver: SliverGrid(
                          // Three across on a phone; on a wide window as many as fit
                          // at a poster's natural size, instead of three giant ones.
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: (MediaQuery.of(context).size.width / 190).floor().clamp(3, 9),
                            childAspectRatio: 0.58,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 14,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final item = sectionState.displayItems[index];
                              return CinemanaPosterCard(
                                item: item,
                                onTap: () {
                                  Navigator.of(context, rootNavigator: true).push(
                                    MaterialPageRoute(
                                      builder: (_) => CinemanaDetailScreen(item: item),
                                    ),
                                  );
                                },
                              );
                            },
                            childCount: sectionState.displayItems.length,
                          ),
                        ),
                      ),

                      // Bottom Loader for infinite pagination
                      if (sectionState.isLoadingMore)
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        )
                      else
                        const SliverToBoxAdapter(
                          child: SizedBox(height: 40),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
