import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';
import '../widgets/windows_youtube_player.dart';
import '../widgets/mobile_youtube_player.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../home/presentation/widgets/video_download_dialog.dart';
import '../../domain/watch_models.dart';
import '../providers/watch_provider.dart';

class WatchScreen extends ConsumerStatefulWidget {
  const WatchScreen({super.key});

  @override
  ConsumerState<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends ConsumerState<WatchScreen> {
  bool _showPlaylist = true;
  final GlobalKey<WindowsYouTubePlayerState> _windowsPlayerKey = GlobalKey<WindowsYouTubePlayerState>();
  final GlobalKey<MobileYouTubePlayerState> _mobilePlayerKey = GlobalKey<MobileYouTubePlayerState>();
  final ScrollController _playlistScrollController = ScrollController();
  final ScrollController _mobileScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _playlistScrollController.addListener(_onPlaylistScroll);
    _mobileScrollController.addListener(_onMobileScroll);
  }

  void _onPlaylistScroll() {
    if (_playlistScrollController.hasClients &&
        _playlistScrollController.position.pixels >=
            _playlistScrollController.position.maxScrollExtent - 250) {
      ref.read(watchProvider.notifier).loadMorePlaylistItems();
    }
  }

  void _onMobileScroll() {
    if (_mobileScrollController.hasClients &&
        _mobileScrollController.position.pixels >=
            _mobileScrollController.position.maxScrollExtent - 250) {
      ref.read(watchProvider.notifier).loadMorePlaylistItems();
    }
  }

  @override
  void dispose() {
    _playlistScrollController.dispose();
    _mobileScrollController.dispose();
    if (Platform.isAndroid || Platform.isIOS) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  void _setFullscreen(bool fs) async {
    ref.read(watchProvider.notifier).setFullscreen(fs);
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        await windowManager.setFullScreen(fs);
      } catch (_) {}
    } else if (Platform.isAndroid || Platform.isIOS) {
      try {
        if (fs) {
          await SystemChrome.setPreferredOrientations([
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
          await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        } else {
          await SystemChrome.setPreferredOrientations([
            DeviceOrientation.portraitUp,
          ]);
          await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        }
      } catch (_) {}
    }
  }

  void _toggleFullscreen() {
    final isFs = ref.read(watchProvider).isFullscreen;
    final next = !isFs;
    _setFullscreen(next);
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      _windowsPlayerKey.currentState?.toggleFullscreen();
    } else {
      _mobilePlayerKey.currentState?.toggleFullscreen();
    }
  }

  Widget _buildVideoPlayerSurface(
    BuildContext context,
    WatchState watchState,
    WatchNotifier watchNotifier,
    bool isDark,
    WatchPlaylistContext? playlist,
    PlayableItem currentItem,
  ) {
    if (Platform.isAndroid || Platform.isIOS) {
      return _buildMobilePlayerSurface(context, watchState, watchNotifier, isDark, playlist, currentItem);
    }
    return _buildDesktopPlayerSurface(context, watchState, watchNotifier, isDark, playlist, currentItem);
  }

  Widget _buildMobilePlayerSurface(
    BuildContext context,
    WatchState watchState,
    WatchNotifier watchNotifier,
    bool isDark,
    WatchPlaylistContext? playlist,
    PlayableItem currentItem,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: watchState.isFullscreen ? BorderRadius.zero : BorderRadius.circular(AppTheme.borderRadius),
        boxShadow: watchState.isFullscreen
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.6 : 0.25),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // High-performance Mobile YouTube Player using WebView with custom Referer & anti-152 headers
          MobileYouTubePlayer(
            key: _mobilePlayerKey,
            videoId: currentItem.id,
            onFullscreenChanged: (isFs) => _setFullscreen(isFs),
            onEnded: () {
              if (watchState.hasNext) {
                watchNotifier.playNext();
              }
            },
          ),

          // Autoplay Next Episode Countdown Overlay
          if (watchState.autoPlayCountdown != null && watchState.nextItem != null)
            _buildCountdownOverlay(watchState, watchNotifier),
        ],
      ),
    );
  }

  Widget _buildDesktopPlayerSurface(
    BuildContext context,
    WatchState watchState,
    WatchNotifier watchNotifier,
    bool isDark,
    WatchPlaylistContext? playlist,
    PlayableItem currentItem,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: watchState.isFullscreen ? BorderRadius.zero : BorderRadius.circular(AppTheme.borderRadius),
        boxShadow: watchState.isFullscreen
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.6 : 0.25),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Official YouTube Web Player with full Quality Menu (1080p, 720p, Auto) via Edge WebView2
          WindowsYouTubePlayer(
            key: _windowsPlayerKey,
            videoId: currentItem.id,
            onFullscreenChanged: (isFs) => _setFullscreen(isFs),
            onEnded: () {
              if (watchState.hasNext) {
                watchNotifier.playNext();
              }
            },
          ),

          // Autoplay Next Episode Countdown Overlay
          if (watchState.autoPlayCountdown != null && watchState.nextItem != null)
            _buildCountdownOverlay(watchState, watchNotifier),
        ],
      ),
    );
  }

  Widget _buildCountdownOverlay(WatchState watchState, WatchNotifier watchNotifier) {
    return Positioned(
      bottom: 20,
      right: 16,
      left: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.92),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.4),
              blurRadius: 16,
            ),
          ],
        ),
        child: Row(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    value: (watchState.autoPlayCountdown ?? 5) / 5.0,
                    color: AppColors.primary,
                    strokeWidth: 3,
                  ),
                ),
                Text(
                  '${watchState.autoPlayCountdown}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('الحلقة التالية تبدأ تلقائياً:', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  Text(
                    watchState.nextItem!.title,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: () => watchNotifier.playNext(),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('تشغيل الآن', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
              tooltip: 'إلغاء',
              onPressed: () => watchNotifier.cancelAutoPlay(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistItem(
    PlayableItem item,
    int index,
    bool isSelected,
    bool isDark,
    WatchNotifier watchNotifier, {
    bool isMobile = false,
  }) {
    return InkWell(
      onTap: () => watchNotifier.playIndex(index),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(isDark ? 0.22 : 0.10)
              : (isDark ? const Color(0xFF16161F) : Colors.white),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : (isDark ? const Color(0xFF262634) : const Color(0xFFE8E8F0)),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Playing indicator or Episode Number badge
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary
                    : (isDark ? const Color(0xFF242432) : const Color(0xFFEEEEF4)),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: isSelected
                    ? const Icon(Icons.equalizer_rounded, color: Colors.white, size: 17)
                    : Text(
                        '${item.episodeNumber ?? (index + 1)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
              ),
            ),

            const SizedBox(width: 10),

            // Video Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: SizedBox(
                width: isMobile ? 96 : 80,
                height: isMobile ? 54 : 48,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      item.thumbnailUrl,
                      fit: BoxFit.cover,
                      cacheWidth: 240,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey.shade800,
                        child: const Icon(Icons.videocam_rounded, size: 18, color: Colors.white54),
                      ),
                    ),
                    if (item.duration != null)
                      Positioned(
                        bottom: 3,
                        right: 3,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.85),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            Formatters.formatDuration(item.duration),
                            style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 12),

            // Video Title & Author
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.episodeNumber != null ? 'الحلقة ${item.episodeNumber}: ${item.title}' : item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: isMobile ? 12.5 : 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? AppColors.primary : (isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (isSelected)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'تشغيل الآن',
                            style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          item.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final watchState = ref.watch(watchProvider);
    final watchNotifier = ref.read(watchProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobile = MediaQuery.of(context).size.width < 900;

    final currentItem = watchState.currentItem;
    final playlist = watchState.playlistContext;

    if (currentItem == null) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF0F0F13) : const Color(0xFFF8F8FA),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.play_disabled_rounded, size: 54, color: AppColors.darkTextSecondary),
              const SizedBox(height: 14),
              const Text('لم يتم تحديد فيديو للمشاهدة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => context.go('/'),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('العودة للرئيسية'),
              ),
            ],
          ),
        ),
      );
    }

    // Fullscreen Mode: Render ONLY the Video Player taking 100% of the entire screen
    final Widget screenContent;
    if (watchState.isFullscreen) {
      screenContent = Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(
              child: _buildVideoPlayerSurface(context, watchState, watchNotifier, isDark, playlist, currentItem),
            ),
            Positioned(
              top: 16,
              left: 16,
              child: SafeArea(
                child: Material(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(24),
                  child: IconButton(
                    icon: const Icon(Icons.fullscreen_exit_rounded, color: Colors.white, size: 26),
                    tooltip: 'تصغير الشاشة',
                    onPressed: () => _setFullscreen(false),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    } else if (isMobile) {
      // Mobile Layout: Video at the top, Title directly below, compact controls, and Playlist items directly below (swipe back)
      screenContent = Scaffold(
        backgroundColor: isDark ? const Color(0xFF0A0A0E) : const Color(0xFFF5F5F8),
        body: SafeArea(
          bottom: true,
          top: true,
          child: SingleChildScrollView(
            controller: _mobileScrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Sticky/Top Video Player (16:9)
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _buildVideoPlayerSurface(context, watchState, watchNotifier, isDark, playlist, currentItem),
                ),

                // 2. Video Title & Channel Info (Directly below video)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentItem.title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, height: 1.3),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 15,
                            backgroundColor: AppColors.primary.withOpacity(0.15),
                            child: Text(
                              currentItem.author.isNotEmpty ? currentItem.author[0].toUpperCase() : 'Y',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 12),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              currentItem.author,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // 3. Compact Mobile Action Controls Bar (Smaller Next, Previous, Download, Fullscreen)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF16161D) : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark ? const Color(0xFF262633) : const Color(0xFFE8E8F0),
                      ),
                    ),
                    child: Row(
                      children: [
                        // Next Episode button (Compact)
                        if (watchState.hasNext)
                          ElevatedButton.icon(
                            onPressed: () => watchNotifier.playNext(),
                            icon: const Icon(Icons.skip_next_rounded, size: 16),
                            label: Text(
                              watchState.nextItem?.episodeNumber != null
                                  ? 'الحلقة (${watchState.nextItem!.episodeNumber})'
                                  : 'التالي',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),

                        if (watchState.hasPrevious) ...[
                          const SizedBox(width: 6),
                          OutlinedButton(
                            onPressed: () => watchNotifier.playPrevious(),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('السابقة', style: TextStyle(fontSize: 11)),
                          ),
                        ],

                        const Spacer(),

                        // Download Button (Compact)
                        SizedBox(
                          width: 32,
                          height: 32,
                          child: IconButton.filledTonal(
                            padding: EdgeInsets.zero,
                            onPressed: () {
                              VideoDownloadDialog.showById(context, currentItem.id);
                            },
                            icon: const Icon(Icons.download_rounded, size: 17),
                            tooltip: 'تنزيل الفيديو',
                          ),
                        ),

                        const SizedBox(width: 8),

                        // Fullscreen Expand Button (Compact)
                        SizedBox(
                          width: 32,
                          height: 32,
                          child: IconButton.filled(
                            padding: EdgeInsets.zero,
                            onPressed: _toggleFullscreen,
                            icon: const Icon(Icons.fullscreen_rounded, size: 18),
                            tooltip: 'تكبير ملء الشاشة',
                            style: IconButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 4. Playlist / Related items directly without header label (clean list)
                if (playlist != null && playlist.items.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    itemCount: playlist.items.length + (watchState.isLoadingMore ? 1 : 0),
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      if (index == playlist.items.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        );
                      }
                      final item = playlist.items[index];
                      final isSelected = index == playlist.currentIndex;
                      return _buildPlaylistItem(item, index, isSelected, isDark, watchNotifier, isMobile: true);
                    },
                  ),
                ],
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      );
    } else {
      // Desktop / Tablet Layout: Player on Left, Side Playlist Drawer on Right
      screenContent = Scaffold(
        backgroundColor: isDark ? const Color(0xFF0A0A0E) : const Color(0xFFF5F5F8),
        body: Column(
          children: [
            // Top Watch Header Bar
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF14141A) : Colors.white,
                border: Border(
                  bottom: BorderSide(
                    color: isDark ? const Color(0xFF242430) : const Color(0xFFE4E4EC),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Tooltip(
                    message: 'العودة للتصفح',
                    child: InkWell(
                      onTap: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go('/');
                        }
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF22222E) : const Color(0xFFE8E8F0),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark ? const Color(0xFF38384A) : const Color(0xFFD4D4E0),
                          ),
                        ),
                        child: const Icon(
                          Icons.public_rounded,
                          size: 19,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 14),

                  Expanded(
                    child: Text(
                      currentItem.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                  ),

                  const SizedBox(width: 12),

                  if (playlist != null && playlist.items.length > 1)
                    Tooltip(
                      message: _showPlaylist ? 'طي قائمة الفيديوهات' : 'فتح قائمة الفيديوهات',
                      child: InkWell(
                        onTap: () => setState(() => _showPlaylist = !_showPlaylist),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                          decoration: BoxDecoration(
                            color: _showPlaylist
                                ? AppColors.primary.withOpacity(0.18)
                                : (isDark ? const Color(0xFF22222E) : const Color(0xFFEEEEF4)),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _showPlaylist
                                  ? AppColors.primary
                                  : (isDark ? const Color(0xFF353545) : const Color(0xFFD8D8E2)),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _showPlaylist ? Icons.view_sidebar_rounded : Icons.view_sidebar_outlined,
                                size: 18,
                                color: _showPlaylist ? AppColors.primary : (isDark ? Colors.white : Colors.black87),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _showPlaylist ? 'طي القائمة' : 'فتح القائمة',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _showPlaylist ? AppColors.primary : (isDark ? Colors.white : Colors.black87),
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

            // Main Cinema Player & Collapsible Playlist Content
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 16:9 Cinema Player Box
                          AspectRatio(
                            aspectRatio: 16 / 9,
                            child: _buildVideoPlayerSurface(context, watchState, watchNotifier, isDark, playlist, currentItem),
                          ),

                          const SizedBox(height: 16),

                          // Action Controls Bar
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF16161D) : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark ? const Color(0xFF262633) : const Color(0xFFE8E8F0),
                              ),
                            ),
                            child: Row(
                              children: [
                                if (watchState.hasNext)
                                  ElevatedButton.icon(
                                    onPressed: () => watchNotifier.playNext(),
                                    icon: const Icon(Icons.skip_next_rounded, size: 20),
                                    label: Text(
                                      watchState.nextItem?.episodeNumber != null
                                          ? 'الحلقة التالية (${watchState.nextItem!.episodeNumber})'
                                          : 'الفيديو التالي',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    ),
                                  ),

                                if (watchState.hasPrevious) ...[
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    onPressed: () => watchNotifier.playPrevious(),
                                    icon: const Icon(Icons.skip_previous_rounded, size: 18),
                                    label: const Text('السابقة', style: TextStyle(fontSize: 12)),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    ),
                                  ),
                                ],

                                const Spacer(),

                                IconButton(
                                  icon: Icon(
                                    watchState.isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                                    color: isDark ? Colors.white70 : Colors.black87,
                                    size: 22,
                                  ),
                                  tooltip: watchState.isFullscreen ? 'تصغير الشاشة' : 'ملء الشاشة',
                                  onPressed: _toggleFullscreen,
                                ),
                                const SizedBox(width: 8),

                                ElevatedButton.icon(
                                  onPressed: () {
                                    VideoDownloadDialog.showById(context, currentItem.id);
                                  },
                                  icon: const Icon(Icons.download_rounded, size: 18),
                                  label: const Text('تنزيل الفيديو', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isDark ? const Color(0xFF2B2B36) : const Color(0xFFEAEAEE),
                                    foregroundColor: isDark ? Colors.white : Colors.black87,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 18),

                          // Video Title & Channel Info
                          Text(
                            currentItem.title,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: AppColors.primary.withOpacity(0.15),
                                child: Text(
                                  currentItem.author.isNotEmpty ? currentItem.author[0].toUpperCase() : 'Y',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 14),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      currentItem.author,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    if (currentItem.duration != null)
                                      Text(
                                        'المدة: ${Formatters.formatDuration(currentItem.duration)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Collapsible Side Playlist Drawer
                  if (_showPlaylist && playlist != null && playlist.items.isNotEmpty)
                    Container(
                      width: 360,
                      margin: const EdgeInsets.only(top: 20, bottom: 20, left: 16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF13131A) : Colors.white,
                        borderRadius: BorderRadius.circular(AppTheme.borderRadius),
                        border: Border.all(
                          color: isDark ? const Color(0xFF242430) : const Color(0xFFE4E4EC),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: isDark ? const Color(0xFF242430) : const Color(0xFFE4E4EC),
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.playlist_play_rounded, color: AppColors.primary, size: 20),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        playlist.title ?? 'قائمة الحلقات',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        'الحلقة ${playlist.currentIndex + 1} من ${playlist.items.length}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close_rounded, size: 18),
                                  tooltip: 'إخفاء القائمة',
                                  onPressed: () => setState(() => _showPlaylist = false),
                                ),
                              ],
                            ),
                          ),

                          Expanded(
                            child: ListView.separated(
                              controller: _playlistScrollController,
                              itemCount: playlist.items.length + (watchState.isLoadingMore ? 1 : 0),
                              separatorBuilder: (_, __) => Divider(
                                height: 1,
                                color: isDark ? const Color(0xFF1E1E28) : const Color(0xFFF0F0F4),
                              ),
                              itemBuilder: (context, index) {
                                if (index == playlist.items.length) {
                                  return const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 14),
                                    child: Center(
                                      child: SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                final item = playlist.items[index];
                                final isSelected = index == playlist.currentIndex;
                                return _buildPlaylistItem(item, index, isSelected, isDark, watchNotifier, isMobile: false);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (watchState.isFullscreen) _setFullscreen(false);
        },
      },
      child: Focus(
        autofocus: true,
        child: PopScope(
          canPop: !watchState.isFullscreen,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && watchState.isFullscreen) {
              _setFullscreen(false);
            }
          },
          child: screenContent,
        ),
      ),
    );
  }
}
