import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart' hide Video;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../domain/watch_models.dart';
import '../../../downloads/domain/download_service.dart';
import '../../../downloads/presentation/providers/downloads_provider.dart';

class WatchState {
  final PlayableItem? currentItem;
  final WatchPlaylistContext? playlistContext;
  final bool isLoading;
  final String? errorMessage;
  final List<StreamQualityOption> availableQualities;
  final StreamQualityOption? selectedQuality;
  final bool isPlaying;
  final bool isBuffering;
  final Duration position;
  final Duration duration;
  final Duration buffer;
  final int? autoPlayCountdown;
  final bool isFullscreen;
  final bool isLoadingMore;

  const WatchState({
    this.currentItem,
    this.playlistContext,
    this.isLoading = false,
    this.errorMessage,
    this.availableQualities = const [],
    this.selectedQuality,
    this.isPlaying = false,
    this.isBuffering = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffer = Duration.zero,
    this.autoPlayCountdown,
    this.isFullscreen = false,
    this.isLoadingMore = false,
  });

  bool get hasNext => playlistContext?.hasNext ?? false;
  bool get hasPrevious => playlistContext?.hasPrevious ?? false;
  PlayableItem? get nextItem => playlistContext?.nextItem;
  PlayableItem? get previousItem => playlistContext?.previousItem;

  WatchState copyWith({
    PlayableItem? currentItem,
    WatchPlaylistContext? playlistContext,
    bool? isLoading,
    String? errorMessage,
    List<StreamQualityOption>? availableQualities,
    StreamQualityOption? selectedQuality,
    bool? isPlaying,
    bool? isBuffering,
    Duration? position,
    Duration? duration,
    Duration? buffer,
    int? autoPlayCountdown,
    bool? isFullscreen,
    bool clearCountdown = false,
    bool? isLoadingMore,
  }) {
    return WatchState(
      currentItem: currentItem ?? this.currentItem,
      playlistContext: playlistContext ?? this.playlistContext,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      availableQualities: availableQualities ?? this.availableQualities,
      selectedQuality: selectedQuality ?? this.selectedQuality,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      buffer: buffer ?? this.buffer,
      autoPlayCountdown: clearCountdown ? null : (autoPlayCountdown ?? this.autoPlayCountdown),
      isFullscreen: isFullscreen ?? this.isFullscreen,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

class WatchNotifier extends StateNotifier<WatchState> {
  final DownloadService? _downloadService;
  final YoutubeExplode _yt = YoutubeExplode();
  final Map<String, StreamManifest> _manifestCache = {};

  Player? player;
  VideoController? controller;

  final List<StreamSubscription> _subscriptions = [];
  Timer? _countdownTimer;

  WatchNotifier({DownloadService? downloadService})
      : _downloadService = downloadService,
        super(const WatchState()) {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      _initDesktopPlayer();
    }
  }

  void _initDesktopPlayer() {
    final p = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 32 * 1024 * 1024,
      ),
    );
    player = p;
    controller = VideoController(p);

    _subscriptions.add(p.stream.playing.listen((playing) {
      if (mounted) state = state.copyWith(isPlaying: playing);
    }));

    _subscriptions.add(p.stream.buffering.listen((buffering) {
      if (mounted) state = state.copyWith(isBuffering: buffering);
    }));

    _subscriptions.add(p.stream.position.listen((pos) {
      if (mounted) state = state.copyWith(position: pos);
    }));

    _subscriptions.add(p.stream.duration.listen((dur) {
      if (mounted) state = state.copyWith(duration: dur);
    }));

    _subscriptions.add(p.stream.buffer.listen((buf) {
      if (mounted) state = state.copyWith(buffer: buf);
    }));

    _subscriptions.add(p.stream.completed.listen((completed) {
      if (completed && state.hasNext && mounted) {
        _startAutoPlayCountdown();
      }
    }));
  }

  /// Loads and starts playing an item with playlist context
  Future<void> loadAndPlay(PlayableItem item, {WatchPlaylistContext? playlistContext}) async {
    _cancelCountdown();

    state = state.copyWith(
      currentItem: item,
      playlistContext: playlistContext,
      isLoading: true,
      errorMessage: null,
      availableQualities: [],
      selectedQuality: null,
      position: Duration.zero,
      duration: item.duration ?? Duration.zero,
      buffer: Duration.zero,
      clearCountdown: true,
    );

    if (Platform.isAndroid || Platform.isIOS || Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      player?.stop();
      state = state.copyWith(isLoading: false);

      if (playlistContext != null && playlistContext.hasNext) {
        final nextItem = playlistContext.nextItem;
        if (nextItem != null && !_manifestCache.containsKey(nextItem.id)) {
          _yt.videos.streamsClient.getManifest(nextItem.id).then((m) {
            _manifestCache[nextItem.id] = m;
          }).catchError((_) {});
        }
      }
      return;
    }
  }

  void prefetchEpisodes(WatchPlaylistContext? playlistContext) {
    if (playlistContext == null) return;
    for (int i = playlistContext.currentIndex + 1;
        i < playlistContext.items.length && i <= playlistContext.currentIndex + 3;
        i++) {
      final item = playlistContext.items[i];
      if (!_manifestCache.containsKey(item.id)) {
        _yt.videos.streamsClient.getManifest(item.id).then((m) {
          _manifestCache[item.id] = m;
        }).catchError((_) {});
      }
    }
  }



  /// Advances and plays the next episode in the playlist
  Future<void> playNext() async {
    _cancelCountdown();
    final ctx = state.playlistContext;
    if (ctx == null || !ctx.hasNext) return;

    final nextIndex = ctx.currentIndex + 1;
    final nextItem = ctx.items[nextIndex];
    final updatedCtx = ctx.copyWith(currentIndex: nextIndex);

    await loadAndPlay(nextItem, playlistContext: updatedCtx);
  }

  /// Plays previous episode
  Future<void> playPrevious() async {
    _cancelCountdown();
    final ctx = state.playlistContext;
    if (ctx == null || !ctx.hasPrevious) return;

    final prevIndex = ctx.currentIndex - 1;
    final prevItem = ctx.items[prevIndex];
    final updatedCtx = ctx.copyWith(currentIndex: prevIndex);

    await loadAndPlay(prevItem, playlistContext: updatedCtx);
  }

  /// Plays a specific episode clicked from the side playlist
  Future<void> playIndex(int index) async {
    _cancelCountdown();
    final ctx = state.playlistContext;
    if (ctx == null || index < 0 || index >= ctx.items.length) return;

    final item = ctx.items[index];
    final updatedCtx = ctx.copyWith(currentIndex: index);

    await loadAndPlay(item, playlistContext: updatedCtx);
  }

  void _startAutoPlayCountdown() {
    _cancelCountdown();
    state = state.copyWith(autoPlayCountdown: 5);

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final current = state.autoPlayCountdown ?? 0;
      if (current <= 1) {
        _cancelCountdown();
        playNext();
      } else {
        state = state.copyWith(autoPlayCountdown: current - 1);
      }
    });
  }

  void cancelAutoPlay() {
    _cancelCountdown();
    state = state.copyWith(clearCountdown: true);
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  void togglePlayPause() {
    player?.playOrPause();
  }

  void seek(Duration pos) {
    player?.seek(pos);
  }

  void setFullscreen(bool value) {
    if (state.isFullscreen == value) return;
    state = state.copyWith(isFullscreen: value);
  }

  void toggleFullscreen() {
    setFullscreen(!state.isFullscreen);
  }

  /// Loads more videos when scrolling to the bottom of the playlist drawer
  Future<void> loadMorePlaylistItems() async {
    final ctx = state.playlistContext;
    if (ctx == null || state.isLoadingMore) return;
    state = state.copyWith(isLoadingMore: true);

    try {
      List<Video> moreVideos = [];
      final downloadService = _downloadService;
      if (downloadService != null) {
        moreVideos = await downloadService.loadMoreVideos();
      }

      if (moreVideos.isEmpty && ctx.items.isNotEmpty) {
        // Fallback search to append more relevant videos
        final seedItem = state.currentItem ?? ctx.items.first;
        final query = seedItem.author.isNotEmpty ? seedItem.author : seedItem.title;
        final results = await _yt.search.search(query);
        final existingIds = ctx.items.map((i) => i.id).toSet();
        moreVideos = results.where((v) => !existingIds.contains(v.id.value)).take(15).toList();
      }

      if (moreVideos.isNotEmpty) {
        final existingIds = ctx.items.map((i) => i.id).toSet();
        final newItems = moreVideos
            .where((v) => !existingIds.contains(v.id.value))
            .map((v) => PlayableItem.fromVideo(v))
            .toList();

        if (newItems.isNotEmpty) {
          final updatedItems = [...ctx.items, ...newItems];
          final updatedCtx = ctx.copyWith(items: updatedItems);
          state = state.copyWith(
            playlistContext: updatedCtx,
            isLoadingMore: false,
          );
          return;
        }
      }
      state = state.copyWith(isLoadingMore: false);
    } catch (_) {
      state = state.copyWith(isLoadingMore: false);
    }
  }

  @override
  void dispose() {
    _cancelCountdown();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    player?.dispose();
    _yt.close();
    super.dispose();
  }
}

final watchProvider = StateNotifierProvider<WatchNotifier, WatchState>((ref) {
  final downloadService = ref.watch(downloadServiceProvider);
  return WatchNotifier(downloadService: downloadService);
});
