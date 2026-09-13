import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_palette.dart';
import '../../data/models/sports_models.dart';
import '../providers/sports_provider.dart';
import 'sports_player_screen.dart';
import '../../../shahid/data/shahid_models.dart';
import '../../../shahid/presentation/shahid_player_screen.dart';
import 'youtube_live_screen.dart';

class ChannelsScreen extends ConsumerStatefulWidget {
  final String? initialCategory;

  /// Opened in the player as soon as the list is loaded.
  final SportsChannel? initialChannel;

  const ChannelsScreen({super.key, this.initialCategory, this.initialChannel});

  @override
  ConsumerState<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends ConsumerState<ChannelsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'الكل';
  String _searchQuery = '';

  // Rebuilt from the loaded channels, so there is never an empty chip.
  List<String> _categories = const ['الكل'];
  bool _openedInitial = false;
  bool _precached = false;

  void _syncCategories(List<SportsChannel> channels) {
    final seen = <String>[];
    for (final c in channels) {
      if (c.categoryName.isNotEmpty && !seen.contains(c.categoryName)) seen.add(c.categoryName);
    }
    final next = ['الكل', ...seen];
    if (next.join('|') != _categories.join('|')) {
      _categories = next;
      if (!_categories.contains(_selectedCategory)) _selectedCategory = 'الكل';
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialCategory != null && _categories.contains(widget.initialCategory)) {
      _selectedCategory = widget.initialCategory!;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openChannel(BuildContext context, SportsChannel channel) {
    // Channels that broadcast on YouTube play in YouTube's own player.
    if (channel.channelType == 'YOUTUBE_LIVE') {
      final id = Uri.tryParse(channel.channelUrl)?.queryParameters['v'];
      if (id != null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => YoutubeLiveScreen(
              videoId: id,
              title: channel.channelName,
              logoUrl: channel.channelImage,
            ),
          ),
        );
        return;
      }
    }
    // HLS channels play in the native player (no web page, no ads), with the
    // other HLS channels one tap away underneath.
    if (channel.channelUrl.contains('.m3u8')) {
      final all = ref.read(sportsChannelsProvider).valueOrNull ?? [channel];
      final items = all.where((c) => c.channelUrl.contains('.m3u8')).map(_asPlayable).toList();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ShahidPlayerScreen(channel: _asPlayable(channel), channels: items),
        ),
      );
      return;
    }
    final match = SportMatchItem.fromSportsChannel(channel);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SportsPlayerScreen(
          match: match,
          initialSportsChannel: channel,
        ),
      ),
    );
  }

  ShahidItem _asPlayable(SportsChannel c) => ShahidItem(
        id: c.channelId,
        title: c.channelName,
        productType: 'LIVESTREAM',
        // Shahid channels get their stream re-resolved by id on open.
        pageUrl: c.channelType == 'SHAHID' ? 'https://shahid.mbc.net/' : '',
        logoTemplate: c.channelImage.isEmpty ? null : c.channelImage,
        isFree: true,
        streamUrl: c.channelUrl,
      );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final channelsAsync = ref.watch(sportsChannelsProvider);
    final bgColor = isDark ? const Color(0xFF07090E) : const Color(0xFFF1F5F9);
    final cardBg = isDark ? AppPalette.of(context).cardAlt : Colors.white;
    final borderColor = isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFE2E8F0);
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF0B0F19) : Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: titleColor),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFFF2A4A),
                boxShadow: [
                  BoxShadow(color: Color(0xFFFF2A4A), blurRadius: 6, spreadRadius: 1),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'القنوات المباشرة',
              style: TextStyle(
                color: titleColor,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF131826) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                style: TextStyle(color: titleColor, fontSize: 13.5),
                decoration: InputDecoration(
                  hintText: 'ابحث عن قناة (beIN, SSC, الكأس, الجزيرة...)...',
                  hintStyle: TextStyle(
                    color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                    fontSize: 12.5,
                  ),
                  prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFFE50914), size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
              ),
            ),
          ),

          // Category Chips Horizontal Scroll
          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final cat = _categories[index];
                final isSelected = _selectedCategory == cat;
                return GestureDetector(
                  onTap: () => setState(() => _selectedCategory = cat),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFE50914)
                          : (isDark ? const Color(0xFF131826) : Colors.white),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFFE50914)
                            : (isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFCBD5E1)),
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: const Color(0xFFE50914).withOpacity(0.35),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        cat,
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : (isDark ? Colors.white70 : const Color(0xFF475569)),
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 6),

          // Channels Grid
          Expanded(
            child: channelsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: Color(0xFFE50914)),
              ),
              error: (_, __) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Color(0xFFE50914), size: 40),
                    const SizedBox(height: 10),
                    Text(
                      'تعذر تحميل القنوات حالياً',
                      style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => ref.refresh(sportsChannelsProvider),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914)),
                      child: const Text('إعادة المحاولة', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ),
              data: (channels) {
                _syncCategories(channels);
                if (!_precached) {
                  _precached = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) precacheChannelLogos(context, channels);
                  });
                }
                final shared = channelsSharingLogo(channels);
                final wanted = widget.initialChannel;
                if (wanted != null && !_openedInitial) {
                  _openedInitial = true;
                  final match = channels.firstWhere(
                    (c) => c.channelId == wanted.channelId,
                    orElse: () => wanted,
                  );
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _openChannel(context, match);
                  });
                }
                // Filter by category and search query
                final filtered = channels.where((c) {
                  final matchesCat =
                      _selectedCategory == 'الكل' || c.categoryName == _selectedCategory;

                  final matchesQuery = _searchQuery.isEmpty ||
                      c.channelName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                      c.categoryName.toLowerCase().contains(_searchQuery.toLowerCase());

                  return matchesCat && matchesQuery;
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.tv_off_rounded, size: 48, color: isDark ? Colors.white24 : Colors.black26),
                        const SizedBox(height: 12),
                        Text(
                          _searchQuery.isEmpty
                              ? 'لا توجد قنوات في هذا التصنيف'
                              : 'لا توجد نتائج مطابقة لـ "$_searchQuery"',
                          style: TextStyle(
                            color: isDark ? Colors.white60 : Colors.black54,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  color: const Color(0xFFE50914),
                  onRefresh: () async => ref.refresh(sportsChannelsProvider.future),
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    physics: const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 16 / 9,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final channel = filtered[index];
                      return _buildChannelGridCard(context, channel, isDark, cardBg, borderColor, titleColor,
                          caption: shared.contains(channel.channelName) ? channel.channelName : null);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelGridCard(
    BuildContext context,
    SportsChannel channel,
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color titleColor, {
    String? caption,
  }) {
    // The logo is the card: shown whole (contain), no name under it.
    return GestureDetector(
      onTap: () => _openChannel(context, channel),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppPalette.of(context).card : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 1),
          boxShadow: isDark ? null : AppPalette.of(context).cardShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(child: channelTileImage(channel, caption: caption)),
            PositionedDirectional(
              top: 8,
              start: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFE50914),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text(
                  'LIVE',
                  style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A channel's picture on its card: Shahid's branded 16:9 tile fills the card
/// edge to edge (same ratio, so nothing is cut); other channels' logos are
/// shown whole with a little breathing room. Images are kept on disk, so a
/// logo seen once (here, on the home page or under the player) shows at once.
///
/// [caption] names the channel under its logo - used only where several
/// channels share one logo (Karbala's, Al Iraqiya's).
Widget channelTileImage(SportsChannel channel, {String? caption}) {
  Widget buildFallback(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.live_tv_rounded, size: 30, color: Color(0xFFE50914)),
          const SizedBox(height: 6),
          Text(
            channel.channelName,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: p.text,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  if (channel.channelImage.isEmpty) {
    return Builder(builder: buildFallback);
  }
  final isTile = channel.channelType == 'SHAHID';
  final image = CachedNetworkImage(
    imageUrl: channel.channelImage,
    fit: isTile ? BoxFit.cover : BoxFit.contain,
    // Some broadcasters serve 3000px+ logos; decode at card size.
    memCacheWidth: 480,
    fadeInDuration: const Duration(milliseconds: 100),
    placeholder: (_, __) => const SizedBox.shrink(),
    errorWidget: (context, _, ___) => buildFallback(context),
  );
  final picture = isTile
      ? image
      : Padding(
          padding: EdgeInsets.fromLTRB(16, 22, 16, caption == null ? 14 : 30),
          child: image,
        );
  if (caption == null) return picture;
  return Stack(
    fit: StackFit.expand,
    children: [
      picture,
      PositionedDirectional(
        start: 8,
        end: 8,
        bottom: 7,
        child: Builder(
          builder: (context) => Text(
            caption,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppPalette.of(context).textMuted, fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    ],
  );
}

/// Channels whose logo another channel also uses - they get their name
/// under the logo so they can be told apart.
Set<String> channelsSharingLogo(Iterable<SportsChannel> channels) {
  final byLogo = <String, int>{};
  for (final c in channels) {
    if (c.channelImage.isNotEmpty) byLogo[c.channelImage] = (byLogo[c.channelImage] ?? 0) + 1;
  }
  return {
    for (final c in channels)
      if ((byLogo[c.channelImage] ?? 0) > 1) c.channelName,
  };
}

/// Downloads every channel logo into the image cache ahead of time, so the
/// player's channel list and the home row never wait for them.
void precacheChannelLogos(BuildContext context, Iterable<SportsChannel> channels) {
  for (final c in channels) {
    if (c.channelImage.isEmpty) continue;
    precacheImage(
      // Same key CachedNetworkImage(memCacheWidth: 480) looks up.
      ResizeImage.resizeIfNeeded(480, null, CachedNetworkImageProvider(c.channelImage)),
      context,
      onError: (_, __) {},
    );
  }
}
