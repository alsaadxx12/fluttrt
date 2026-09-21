import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:window_manager/window_manager.dart';
import '../widgets/windows_youtube_player.dart';
import '../widgets/mobile_youtube_player.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_palette.dart';
import '../../../../core/constants/app_theme.dart';
import '../../../../core/network/image_cache.dart';
import '../../../../core/utils/formatters.dart';
import '../../../home/presentation/widgets/video_download_dialog.dart';
import '../../domain/watch_models.dart';
import '../providers/channel_info_provider.dart';
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

  /// True while this page sits in a shell branch other than the one showing.
  ///
  /// The main shell keeps every visited branch built (an IndexedStack), so a
  /// watch page pushed over the home or the YouTube page stays alive,
  /// offstage, after the user goes to settings or about. The page is cheap
  /// to keep; its player is not - the video would carry on playing, audibly,
  /// behind the other page. A page behind a route pushed over the shell (a
  /// catalogue, the matches) is still in the showing branch and plays on as
  /// before.
  bool _inInactiveBranch(BuildContext context) {
    final shell = StatefulNavigationShell.maybeOf(context);
    if (shell == null) return false;
    final activeKey = shell.route.branches[shell.currentIndex].navigatorKey;
    return Navigator.of(context).widget.key != activeKey;
  }

  /// [squareCorners] drops the rounded frame: the phone layout runs the
  /// player edge to edge like YouTube's. Fullscreen is square regardless.
  Widget _buildVideoPlayerSurface(
    BuildContext context,
    WatchState watchState,
    WatchNotifier watchNotifier,
    bool isDark,
    WatchPlaylistContext? playlist,
    PlayableItem currentItem, {
    bool squareCorners = false,
  }) {
    // TickerMode is off in an inactive branch (and behind a pushed route);
    // reading it here also rebuilds this page when its branch is shown or
    // hidden. Only the inactive branch drops the player, see above.
    if (!TickerMode.of(context) && _inInactiveBranch(context)) {
      return const ColoredBox(color: Colors.black);
    }
    if (Platform.isAndroid || Platform.isIOS) {
      return _buildMobilePlayerSurface(context, watchState, watchNotifier, isDark, playlist, currentItem,
          squareCorners: squareCorners);
    }
    return _buildDesktopPlayerSurface(context, watchState, watchNotifier, isDark, playlist, currentItem,
        squareCorners: squareCorners);
  }

  Widget _buildMobilePlayerSurface(
    BuildContext context,
    WatchState watchState,
    WatchNotifier watchNotifier,
    bool isDark,
    WatchPlaylistContext? playlist,
    PlayableItem currentItem, {
    bool squareCorners = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: (watchState.isFullscreen || squareCorners)
            ? BorderRadius.zero
            : BorderRadius.circular(AppTheme.borderRadius),
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
    PlayableItem currentItem, {
    bool squareCorners = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: (watchState.isFullscreen || squareCorners)
            ? BorderRadius.zero
            : BorderRadius.circular(AppTheme.borderRadius),
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
                    : (isDark ? const Color(0xFF242432) : Colors.white),
                shape: BoxShape.circle,
                border: (!isDark && !isSelected) ? Border.all(color: AppPalette.of(context).border) : null,
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

  // ---------------------------------------------------------------------------
  // Phone layout: the YouTube watch page
  // ---------------------------------------------------------------------------

  /// UI-only memory of the like / save / subscribe taps. Nothing is sent
  /// anywhere; the sets only keep a tap visible while this page lives.
  final Set<String> _likedVideos = {};
  final Set<String> _savedVideos = {};
  final Set<String> _subscribedChannels = {};

  Widget _buildMobileLayout(
    BuildContext context,
    WatchState watchState,
    WatchNotifier watchNotifier,
    bool isDark,
    WatchPlaylistContext? playlist,
    PlayableItem currentItem,
  ) {
    final items = playlist?.items ?? const <PlayableItem>[];
    final currentIndex = playlist?.currentIndex ?? -1;
    final currentInList = currentIndex >= 0 && currentIndex < items.length;
    final suggestedCount = currentInList ? items.length - 1 : items.length;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The strip above the player is black, as on YouTube, so the status
      // bar icons go white while this page shows. The navigation bar keeps
      // the page's own ground: .light alone would paint it black.
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: isDark ? const Color(0xFF0A0A0E) : Colors.white,
        systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0A0A0E) : Colors.white,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. The player, pinned edge to edge. It sits outside the scroll
            // view, so scrolling never lays it out or rebuilds it.
            ColoredBox(
              color: Colors.black,
              child: SafeArea(
                bottom: false,
                child: Stack(
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: _buildVideoPlayerSurface(
                        context,
                        watchState,
                        watchNotifier,
                        isDark,
                        playlist,
                        currentItem,
                        squareCorners: true,
                      ),
                    ),
                    PositionedDirectional(
                      top: 8,
                      start: 8,
                      child: _PlayerBackButton(
                        // The watch page is pushed over the page that opened
                        // it, so going back pops to that page as it was.
                        onTap: () => context.canPop() ? context.pop() : context.go('/'),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 2. Title, meta, channel, actions, description and suggestions:
            // one continuous scroll with no separate sections.
            Expanded(
              child: CustomScrollView(
                controller: _mobileScrollController,
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                slivers: [
                  SliverToBoxAdapter(
                    child: _buildMobileHeader(context, watchState, watchNotifier, isDark, items, currentItem),
                  ),
                  SliverList.builder(
                    itemCount: suggestedCount,
                    itemBuilder: (context, i) {
                      // The playing video is never listed under itself.
                      final originalIndex = (currentInList && i >= currentIndex) ? i + 1 : i;
                      final item = items[originalIndex];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _SuggestedVideoTile(
                          key: ValueKey(item.id),
                          item: item,
                          isDark: isDark,
                          onTap: () => _playSuggested(watchNotifier, originalIndex),
                          onMore: () => _showSuggestedOptions(item, isDark),
                        ),
                      );
                    },
                  ),
                  if (watchState.isLoadingMore)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                          ),
                        ),
                      ),
                    ),
                  SliverToBoxAdapter(child: SizedBox(height: bottomInset + 24)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Title, meta line, channel row, action chips and the description card.
  Widget _buildMobileHeader(
    BuildContext context,
    WatchState watchState,
    WatchNotifier watchNotifier,
    bool isDark,
    List<PlayableItem> items,
    PlayableItem item,
  ) {
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final mutedColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final titleDirection = _bidiOf(item.title);
    final meta = _metaLineOf(item);
    final description = item.description ?? '';
    final channelKey = item.channelId ?? item.author;
    // A series keeps its episode chips; a plain playlist has no episodes.
    final isEpisodeList = items.any((i) => i.episodeNumber != null);

    final chips = <Widget>[
      if (isEpisodeList && watchState.hasNext)
        _ActionChip(
          icon: Icons.skip_next_rounded,
          label: 'الحلقة التالية',
          isDark: isDark,
          onTap: () => _playAdjacentEpisode(watchNotifier.playNext),
        ),
      if (isEpisodeList && watchState.hasPrevious)
        _ActionChip(
          icon: Icons.skip_previous_rounded,
          label: 'الحلقة السابقة',
          isDark: isDark,
          onTap: () => _playAdjacentEpisode(watchNotifier.playPrevious),
        ),
      _ToggleChip(
        key: ValueKey('like_${item.id}'),
        id: item.id,
        store: _likedVideos,
        icon: Icons.thumb_up_outlined,
        activeIcon: Icons.thumb_up,
        label: 'إعجاب',
        isDark: isDark,
      ),
      _ActionChip(
        icon: Icons.share_outlined,
        label: 'مشاركة',
        isDark: isDark,
        onTap: () => _shareVideo(item.id),
      ),
      _ActionChip(
        icon: Icons.download_rounded,
        label: 'تنزيل',
        isDark: isDark,
        onTap: () => VideoDownloadDialog.showById(context, item.id),
      ),
      _ToggleChip(
        key: ValueKey('save_${item.id}'),
        id: item.id,
        store: _savedVideos,
        icon: Icons.bookmark_border_rounded,
        activeIcon: Icons.bookmark_rounded,
        label: 'حفظ',
        isDark: isDark,
      ),
      _ActionChip(
        icon: Icons.fullscreen_rounded,
        label: 'ملء الشاشة',
        isDark: isDark,
        onTap: _toggleFullscreen,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.start,
                textDirection: titleDirection,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.3, color: textColor),
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.start,
                  textDirection: titleDirection,
                  style: TextStyle(fontSize: 12.5, color: mutedColor),
                ),
              ],
              const SizedBox(height: 12),
              _ChannelRow(
                item: item,
                isDark: isDark,
                subscribeButton: _SubscribeButton(
                  key: ValueKey('subscribe_$channelKey'),
                  channelKey: channelKey,
                  subscribed: _subscribedChannels,
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // The chips scroll to the screen edge, not to the 12 px gutter.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              for (var i = 0; i < chips.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                chips[i],
              ],
            ],
          ),
        ),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _DescriptionCard(
              key: ValueKey('description_${item.id}'),
              description: description,
              meta: meta,
              isDark: isDark,
            ),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  /// Plays [index] and, like YouTube, brings the list back to its top so the
  /// new video's title sits right under the player.
  void _playSuggested(WatchNotifier watchNotifier, int index) {
    watchNotifier.playIndex(index);
    _scrollToTop();
  }

  /// The episode chips: the notifier's own [WatchNotifier.playNext] or
  /// [WatchNotifier.playPrevious], then back to the top like a suggestion.
  void _playAdjacentEpisode(Future<void> Function() play) {
    play();
    _scrollToTop();
  }

  void _scrollToTop() {
    if (_mobileScrollController.hasClients) {
      _mobileScrollController.jumpTo(0);
    }
  }

  /// Hands the video's link to the system share sheet on a phone, as
  /// YouTube's 'مشاركة' does. Elsewhere share_plus would only open a mail
  /// draft, so the link is copied instead; a phone whose sheet fails falls
  /// back to the same copy.
  Future<void> _shareVideo(String id) async {
    final url = 'https://youtu.be/$id';
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        // The origin anchors the iPad popover; a phone ignores it.
        final box = context.findRenderObject() as RenderBox?;
        final origin = (box != null && box.hasSize) ? box.localToGlobal(Offset.zero) & box.size : null;
        await Share.share(url, sharePositionOrigin: origin);
        return;
      } catch (_) {
        // Fall through to the clipboard.
      }
    }
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم نسخ الرابط'),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// The ⋮ sheet of a suggested video: download or share it.
  void _showSuggestedOptions(PlayableItem item, bool isDark) {
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final mutedColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final labelStyle = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor);
    final pageContext = context;

    showModalBottomSheet<void>(
      context: pageContext,
      backgroundColor: isDark ? const Color(0xFF16161D) : Colors.white,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.start,
                textDirection: _bidiOf(item.title),
                style: TextStyle(fontSize: 13, color: mutedColor),
              ),
            ),
            ListTile(
              leading: Icon(Icons.download_rounded, color: textColor),
              title: Text('تنزيل', style: labelStyle),
              onTap: () {
                Navigator.of(sheetContext).pop();
                VideoDownloadDialog.showById(pageContext, item.id);
              },
            ),
            ListTile(
              leading: Icon(Icons.share_outlined, color: textColor),
              title: Text('مشاركة', style: labelStyle),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _shareVideo(item.id);
              },
            ),
            const SizedBox(height: 8),
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
        backgroundColor: isDark ? const Color(0xFF0F0F13) : Colors.white,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.play_disabled_rounded, size: 54, color: AppColors.darkTextSecondary),
              const SizedBox(height: 14),
              const Text('لم يتم تحديد فيديو للمشاهدة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                // The watch page is pushed over the page that opened it, so
                // going back pops to that page as it was.
                onPressed: () => context.canPop() ? context.pop() : context.go('/'),
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
      // Mobile Layout: the YouTube watch page. The player is pinned edge to
      // edge at the top; title, meta line, channel row, action chips,
      // description and the suggestions scroll beneath it as one list.
      screenContent = _buildMobileLayout(context, watchState, watchNotifier, isDark, playlist, currentItem);
    } else {
      // Desktop / Tablet Layout: Player on Left, Side Playlist Drawer on Right
      screenContent = Scaffold(
        backgroundColor: isDark ? const Color(0xFF0A0A0E) : Colors.white,
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
                          color: isDark ? const Color(0xFF22222E) : Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark ? const Color(0xFF38384A) : AppPalette.of(context).border,
                          ),
                        ),
                        child: Icon(
                          Icons.public_rounded,
                          size: 19,
                          color: isDark ? Colors.white : Colors.black87,
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
                                : (isDark ? const Color(0xFF22222E) : Colors.white),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _showPlaylist
                                  ? AppColors.primary
                                  : (isDark ? const Color(0xFF353545) : AppPalette.of(context).border),
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
                                    backgroundColor: isDark ? const Color(0xFF2B2B36) : Colors.white,
                                    foregroundColor: isDark ? Colors.white : Colors.black87,
                                    elevation: 0,
                                    side: isDark ? null : BorderSide(color: AppPalette.of(context).border),
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

// -----------------------------------------------------------------------------
// Phone layout helpers and widgets
// -----------------------------------------------------------------------------

/// The paragraph direction of [text] from its first strong character, the
/// way Android lays a title out: one that begins with Latin (or Greek,
/// Cyrillic, CJK) reads left to right and sits on the left even under the
/// Arabic UI; anything else - Arabic, Hebrew, or no letters at all - follows
/// the page and reads right to left.
TextDirection _bidiOf(String text) {
  for (final rune in text.runes) {
    if (_isRtlRune(rune)) return TextDirection.rtl;
    if (_isLtrRune(rune)) return TextDirection.ltr;
  }
  return TextDirection.rtl;
}

bool _isRtlRune(int r) =>
    (r >= 0x0590 && r <= 0x08FF) || (r >= 0xFB1D && r <= 0xFDFF) || (r >= 0xFE70 && r <= 0xFEFF);

bool _isLtrRune(int r) =>
    (r >= 0x41 && r <= 0x5A) ||
    (r >= 0x61 && r <= 0x7A) ||
    (r >= 0x00C0 && r <= 0x024F) ||
    (r >= 0x0370 && r <= 0x03FF) ||
    (r >= 0x0400 && r <= 0x052F) ||
    (r >= 0x3040 && r <= 0x30FF) ||
    (r >= 0x4E00 && r <= 0x9FFF) ||
    (r >= 0xAC00 && r <= 0xD7AF);

/// 'views • time ago', dropping whichever part is unknown.
String _metaLineOf(PlayableItem item) {
  return [Formatters.formatViews(item.viewCount), Formatters.timeAgo(item.uploadDate)]
      .where((s) => s.isNotEmpty)
      .join(' • ');
}

/// The small chevron over the player's top-start corner that leaves the page.
class _PlayerBackButton extends StatelessWidget {
  final VoidCallback onTap;

  const _PlayerBackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'رجوع',
      child: Material(
        color: Colors.black54,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: const SizedBox(
            width: 32,
            height: 32,
            child: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 24),
          ),
        ),
      ),
    );
  }
}

/// Round channel picture, name, subscriber count and the subscribe pill.
///
/// The picture and count come from [channelInfoProvider]; until they arrive
/// (or when the lookup fails) the row shows the author's initial on a light
/// red disc and no count, which is all the playlist item itself knows.
class _ChannelRow extends ConsumerWidget {
  final PlayableItem item;
  final bool isDark;
  final Widget subscribeButton;

  const _ChannelRow({required this.item, required this.isDark, required this.subscribeButton});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channelId = item.channelId;
    final info = channelId == null ? null : ref.watch(channelInfoProvider(channelId)).valueOrNull;
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final mutedColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final name = item.author.isNotEmpty ? item.author : (info?.title ?? '');
    final subscribers = (info != null && info.subscribersCount > 0)
        ? '${Formatters.compactCount(info.subscribersCount)} مشترك'
        : null;
    final logoUrl = info?.logoUrl ?? '';
    final dpr = MediaQuery.devicePixelRatioOf(context);

    final initial = ColoredBox(
      color: AppColors.primary.withOpacity(0.12),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : 'Y',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primary),
        ),
      ),
    );

    return Row(
      children: [
        SizedBox(
          width: 36,
          height: 36,
          child: ClipOval(
            child: logoUrl.isEmpty
                ? initial
                : CachedNetworkImage(
                    imageUrl: logoUrl,
                    fit: BoxFit.cover,
                    cacheManager: appImageCache,
                    memCacheWidth: (36 * dpr).round(),
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                    placeholderFadeInDuration: Duration.zero,
                    useOldImageOnUrlChange: true,
                    placeholder: (_, __) => initial,
                    errorWidget: (_, __, ___) => initial,
                  ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor),
              ),
              if (subscribers != null)
                Text(
                  subscribers,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: mutedColor),
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        subscribeButton,
      ],
    );
  }
}

/// 'اشتراك' in brand red that flips to an outlined 'مشترك'. UI only: the
/// choice lives in the page's [subscribed] set, keyed by channel.
class _SubscribeButton extends StatefulWidget {
  final String channelKey;
  final Set<String> subscribed;
  final bool isDark;

  const _SubscribeButton({
    super.key,
    required this.channelKey,
    required this.subscribed,
    required this.isDark,
  });

  @override
  State<_SubscribeButton> createState() => _SubscribeButtonState();
}

class _SubscribeButtonState extends State<_SubscribeButton> {
  late bool _on = widget.subscribed.contains(widget.channelKey);

  void _toggle() {
    setState(() {
      _on = !_on;
      if (_on) {
        widget.subscribed.add(widget.channelKey);
      } else {
        widget.subscribed.remove(widget.channelKey);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w700);
    final textColor = widget.isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final hairline = widget.isDark ? AppColors.darkBorder : const Color(0xFFE8ECF2);

    if (_on) {
      return SizedBox(
        height: 34,
        child: OutlinedButton.icon(
          onPressed: _toggle,
          style: OutlinedButton.styleFrom(
            foregroundColor: textColor,
            side: BorderSide(color: hairline),
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            minimumSize: const Size(0, 34),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: textStyle,
          ),
          icon: const Icon(Icons.notifications_none_rounded, size: 16),
          label: const Text('مشترك'),
        ),
      );
    }
    return SizedBox(
      height: 34,
      child: FilledButton(
        onPressed: _toggle,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          minimumSize: const Size(0, 34),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: textStyle,
        ),
        child: const Text('اشتراك'),
      ),
    );
  }
}

/// A 34 px grey pill with an icon and a label, YouTube's action chip.
class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDark;
  final bool active;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isDark,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final fill = isDark ? const Color(0xFF272733) : const Color(0xFFF2F2F2);
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(17),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 34,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: active ? AppColors.primary : textColor),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An [_ActionChip] that toggles (like, save). UI only: the choice lives in
/// the page's [store] set, keyed by video, so only the chip itself repaints.
class _ToggleChip extends StatefulWidget {
  final String id;
  final Set<String> store;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isDark;

  const _ToggleChip({
    super.key,
    required this.id,
    required this.store,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isDark,
  });

  @override
  State<_ToggleChip> createState() => _ToggleChipState();
}

class _ToggleChipState extends State<_ToggleChip> {
  late bool _on = widget.store.contains(widget.id);

  void _toggle() {
    setState(() {
      _on = !_on;
      if (_on) {
        widget.store.add(widget.id);
      } else {
        widget.store.remove(widget.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return _ActionChip(
      icon: _on ? widget.activeIcon : widget.icon,
      label: widget.label,
      active: _on,
      isDark: widget.isDark,
      onTap: _toggle,
    );
  }
}

/// The grey description card: two lines and 'المزيد' until tapped, then the
/// whole text and 'أقل'. Keyed by video, so a new video starts collapsed.
class _DescriptionCard extends StatefulWidget {
  final String description;
  final String meta;
  final bool isDark;

  const _DescriptionCard({
    super.key,
    required this.description,
    required this.meta,
    required this.isDark,
  });

  @override
  State<_DescriptionCard> createState() => _DescriptionCardState();
}

class _DescriptionCardState extends State<_DescriptionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final fill = widget.isDark ? const Color(0xFF272733) : const Color(0xFFF2F2F2);
    final textColor = widget.isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.meta.isNotEmpty) ...[
                Text(
                  widget.meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor),
                ),
                const SizedBox(height: 6),
              ],
              Text(
                widget.description,
                maxLines: _expanded ? null : 2,
                overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                textAlign: TextAlign.start,
                textDirection: _bidiOf(widget.description),
                style: TextStyle(fontSize: 13, height: 1.45, color: textColor),
              ),
              const SizedBox(height: 6),
              Text(
                _expanded ? 'أقل' : 'المزيد',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: textColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One suggested video in YouTube's style: a big 16:9 thumbnail with the
/// duration inside it, then title, channel, views and age with a more
/// button. From 600 px up (a tablet held upright) the thumbnail moves to the
/// start of a row, 160 px wide, with the text beside it.
class _SuggestedVideoTile extends StatelessWidget {
  final PlayableItem item;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onMore;

  const _SuggestedVideoTile({
    super.key,
    required this.item,
    required this.isDark,
    required this.onTap,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final wide = width >= 600;
    final thumbWidth = wide ? 160.0 : width - 24;
    final fill = isDark ? const Color(0xFF272733) : const Color(0xFFF2F2F2);
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final mutedColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final title = item.episodeNumber != null ? 'الحلقة ${item.episodeNumber}: ${item.title}' : item.title;
    final direction = _bidiOf(title);
    final subline = [item.author, Formatters.formatViews(item.viewCount), Formatters.timeAgo(item.uploadDate)]
        .where((s) => s.isNotEmpty)
        .join(' • ');

    final thumbnail = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: item.thumbnailUrl,
              fit: BoxFit.cover,
              cacheManager: appImageCache,
              memCacheWidth: (thumbWidth * dpr).round(),
              fadeInDuration: Duration.zero,
              fadeOutDuration: Duration.zero,
              placeholderFadeInDuration: Duration.zero,
              useOldImageOnUrlChange: true,
              placeholder: (_, __) => ColoredBox(color: fill),
              errorWidget: (_, __, ___) => ColoredBox(
                color: fill,
                child: Icon(Icons.videocam_off_outlined, color: mutedColor, size: 22),
              ),
            ),
            if (item.duration != null)
              Positioned(
                bottom: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    Formatters.formatDuration(item.duration),
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, height: 1.2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    final details = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.start,
                textDirection: direction,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, height: 1.3, color: textColor),
              ),
              if (subline.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.start,
                  textDirection: direction,
                  style: TextStyle(fontSize: 12, color: mutedColor),
                ),
              ],
            ],
          ),
        ),
        SizedBox(
          width: 32,
          height: 32,
          child: IconButton(
            padding: EdgeInsets.zero,
            iconSize: 20,
            icon: Icon(Icons.more_vert, color: textColor),
            tooltip: 'خيارات',
            onPressed: onMore,
          ),
        ),
      ],
    );

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 160, child: thumbnail),
                  const SizedBox(width: 12),
                  Expanded(child: details),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  thumbnail,
                  const SizedBox(height: 8),
                  details,
                ],
              ),
      ),
    );
  }
}
