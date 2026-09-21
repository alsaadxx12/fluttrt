import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/features/cinemana/presentation/screens/cinemana_detail_screen.dart';
import 'package:youtube_downloader/features/reels/data/reel_stream_proxy.dart';
import 'package:youtube_downloader/features/reels/data/reel_stream_resolver.dart';
import 'package:youtube_downloader/features/reels/data/reel_text.dart';
import 'package:youtube_downloader/features/reels/data/reels_service.dart';
import 'package:youtube_downloader/features/reels/presentation/providers/reel_likes_provider.dart';
import 'package:youtube_downloader/features/reels/presentation/providers/reel_stream_resolver_provider.dart';
import 'package:youtube_downloader/features/reels/presentation/providers/reel_video_provider.dart';
import 'package:youtube_downloader/features/reels/presentation/providers/reels_feed_provider.dart';
import 'package:youtube_downloader/features/reels/presentation/providers/reels_mute.dart';
import 'package:youtube_downloader/features/reels/presentation/screens/reels_search_screen.dart';
import 'package:youtube_downloader/features/reels/presentation/widgets/reel_widgets.dart';
import 'package:youtube_downloader/features/trailers/data/trailer_stream_resolver.dart';

/// Soft shadows behind the white overlay text so it reads on any frame.
const List<Shadow> _kTextShadows = [
  Shadow(color: Color(0x99000000), blurRadius: 6, offset: Offset(0, 1)),
  Shadow(color: Color(0x66000000), blurRadius: 14),
];

/// How long opening a stream in media_kit may take before the page gives
/// up on it and falls back.
const Duration _kOpenTimeout = Duration(seconds: 20);

/// How far a double tap on a side of the frame moves the clip.
const Duration kReelSeekStep = Duration(seconds: 10);

/// How often, at most, the picture follows the finger along the seek bar.
const Duration _kScrubSeekEvery = Duration(milliseconds: 200);

/// The red pill under the title that opens the reel's own film, series or
/// anime in the app.
const String kReelWatchFilmLabel = 'مشاهدة الفيلم';
const String kReelWatchSeriesLabel = 'مشاهدة المسلسل';
const String kReelWatchAnimeLabel = 'مشاهدة الأنمي';

/// What the page says while a reel cannot be played, and while YouTube is
/// refusing the stream requests for a moment.
const String kReelFailedLabel = 'تعذّر تشغيل المقطع';
const String kReelBusyLabel = 'يوتيوب مشغول، لحظة…';
const String kReelRetryLabel = 'إعادة المحاولة';

/// What the page past the last reel says: while the next one is being
/// fetched, and once there is nothing more to fetch.
const String kReelsMoreComingLabel = 'جارٍ جلب مشاهد جديدة…';
const String kReelsEndLabel = 'هذه كل المشاهد حالياً';
const String kReelsRefreshLabel = 'تحديث';

/// How long a reel that could not be reached waits before resolving itself
/// again, when the resolver did not say when to come back.
const Duration _kRetryAfter = Duration(seconds: 8);

/// «مشاهد»: the TikTok page. Black, one film trailer per page, swiped
/// vertically; the feed by default, or a fixed list (search results) when
/// [initialItems] is given.
///
/// Only the current page plays; the ones just before and after it are
/// resolved and opened so a swipe starts at once, and everything further
/// away is torn down. The player pauses while another route sits on top
/// and while the app is in the background.
class ReelsScreen extends ConsumerStatefulWidget {
  const ReelsScreen({super.key, this.initialItems, this.initialIndex = 0, this.embedded = true});

  final List<Reel>? initialItems;
  final int initialIndex;

  /// True when the page is a tab of the shell (the bottom bar under it, no
  /// back chevron); false when it was pushed full-screen over the app, as
  /// the search page does, and the chevron pops it.
  final bool embedded;

  @override
  ConsumerState<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends ConsumerState<ReelsScreen> with WidgetsBindingObserver {
  late final PageController _pageController;
  late final ValueNotifier<int> _current;

  /// Whether playback is allowed at all: the route is on top and the app is
  /// in the foreground.
  final ValueNotifier<bool> _active = ValueNotifier<bool>(true);
  bool _routeActive = true;
  bool _foreground = true;
  int _prewarmedFor = -1;

  /// How long the list was when the prewarm ran: reels landing under the
  /// same index bring new neighbours to resolve ahead.
  int _prewarmedOf = -1;

  /// True once a swipe has carried the finger onto the last reel — or onto
  /// the page past it — which is what puts that page there and keeps it
  /// even after the feed has run out, so the end of the list is always
  /// reachable rather than only while [ReelsFeedState.hasMore] happens to
  /// be true. Set from the page changes alone: a list that shrinks under
  /// the finger — a reel dropped — never sets it, so the page falls back
  /// onto the new last reel instead of onto the end page.
  bool _atEnd = false;

  /// How many reels the last build drew, so a list that shrank under the
  /// finger — a reel dropped, or the feed thrown away by «تحديث» — clears
  /// [_atEnd] again: the end page it was holding there belongs past the
  /// last reel, and the fall-back is the new last reel, not the end of the
  /// feed. Without this the flag, once set, would keep the trailing page
  /// under an index that no longer has a reel behind it.
  int _drawnCount = 0;

  bool get _usesFeed => widget.initialItems == null;

  @override
  void initState() {
    super.initState();
    _current = ValueNotifier<int>(widget.initialIndex);
    _pageController = PageController(initialPage: widget.initialIndex);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // TickerMode is off while another route sits over this one.
    _routeActive = TickerMode.of(context);
    _syncActive();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state != AppLifecycleState.paused &&
        state != AppLifecycleState.hidden &&
        state != AppLifecycleState.detached;
    _syncActive();
  }

  void _syncActive() {
    _active.value = _routeActive && _foreground;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _current.dispose();
    _active.dispose();
    super.dispose();
  }

  /// Resolves the streams of the next two reels ahead of the swipe. Run
  /// again when the list has grown, since the reels that just landed are
  /// the ones about to be swiped to.
  void _prewarm(int index, List<Reel> items) {
    if (_prewarmedFor == index && _prewarmedOf == items.length) return;
    _prewarmedFor = index;
    _prewarmedOf = items.length;
    final ids = [for (var k = index + 1; k <= index + 2 && k < items.length; k++) items[k].id];
    if (ids.isNotEmpty) ref.read(reelStreamResolverProvider).prewarm(ids);
  }

  void _onPageChanged(int index, List<Reel> items) {
    _current.value = index;
    _prewarm(index, items);
    if (!_usesFeed) return;
    // Reaching the last reel — or the page past it — is what puts that page
    // there; swiping back up the list takes it away again.
    final atEnd = index >= items.length - 1;
    if (atEnd != _atEnd) setState(() => _atEnd = atEnd);
    ref.read(reelsFeedProvider.notifier).ensureAhead(index);
  }

  /// A page that could not be reached asks to move on; only honoured while
  /// it is still the one showing, and never onto the page past the reels.
  void _skipForward(int from, int count) {
    if (!mounted || _current.value != from || from + 1 >= count) return;
    _pageController.animateToPage(
      from + 1,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  /// A reel whose short YouTube has written off leaves the feed at once, so
  /// the next one slides into its place — the page index does not move, so
  /// what is now under it starts playing by itself. A fixed list (the
  /// search results) has nothing to drop from: it moves on instead.
  void _onDead(Reel reel, int index, int count) {
    if (_usesFeed) {
      ref.read(reelsFeedProvider.notifier).drop(reel.id);
    } else {
      _skipForward(index, count);
    }
  }

  /// «تحديث» — on the end page and on the empty feed alike: the feed starts
  /// over and so does the page. Walking back to the top first is what makes
  /// the button do something visible: the refresh empties the list, the
  /// controller keeps the offset it had while the reels are gone, and the
  /// fresh first page would otherwise arrive under a finger still standing
  /// on the trailing page, which is exactly what it was tapped to leave.
  void _refreshFeed() {
    _current.value = 0;
    if (_pageController.hasClients) _pageController.jumpToPage(0);
    if (_atEnd) setState(() => _atEnd = false);
    // The fresh list is a different one: let the first build of it resolve
    // the streams ahead of the finger again.
    _prewarmedFor = -1;
    _prewarmedOf = -1;
    ref.read(reelsFeedProvider.notifier).refresh();
  }

  /// On the root navigator, so the page covers the bottom bar.
  void _openSearch() {
    Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute<void>(builder: (_) => const ReelsSearchScreen()),
    );
  }

  Future<void> _share(Reel reel) async {
    final url = reel.shareUrl;
    var shared = false;
    try {
      final box = context.findRenderObject() as RenderBox?;
      final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
      final result = await Share.share(url, subject: reel.title, sharePositionOrigin: origin);
      shared = result.status != ShareResultStatus.unavailable;
    } catch (_) {
      shared = false;
    }
    if (shared || !mounted) return;
    // No share sheet on this platform: the link goes to the clipboard.
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('تم نسخ الرابط', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
          backgroundColor: Colors.white,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final List<Reel> items;
    final bool loading;
    final bool failed;
    final bool hasMore;
    if (_usesFeed) {
      final feed = ref.watch(reelsFeedProvider);
      items = feed.items;
      loading = feed.isLoading;
      failed = feed.failed;
      hasMore = feed.hasMore;
    } else {
      items = widget.initialItems!;
      loading = false;
      failed = false;
      hasMore = false;
    }
    if (items.isNotEmpty && _prewarmedFor < 0) {
      _prewarm(_current.value.clamp(0, items.length - 1), items);
    }
    // A list that shrank — a reel dropped out of the feed — takes the end
    // page with it, so the finger standing on the last reel falls back onto
    // the new last reel rather than onto the page past the reels. Swiping
    // down there puts it back ([_onPageChanged]).
    if (items.length < _drawnCount) _atEnd = false;
    _drawnCount = items.length;
    // The feed carries one page past its reels: while there is more to come
    // it is the page that fetches it, and once the swipe has reached the end
    // of the list it stays there whatever the feed answers, so a feed that
    // runs out mid-list still says so — with its «تحديث» — under the finger
    // that walks down to it, instead of dead-ending on the last reel. A
    // fixed list ends where it ends.
    final hasTail = _usesFeed && (loading || hasMore || _atEnd);

    // Light status icons over the black page. The navigation bar colour is
    // left alone: the white pages underneath do not set it back.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (items.isEmpty)
              _EmptyFeed(
                loading: loading,
                failed: failed,
                onRetry: _refreshFeed,
              )
            else
              PageView.builder(
                controller: _pageController,
                scrollDirection: Axis.vertical,
                physics: const PageScrollPhysics(),
                allowImplicitScrolling: true,
                onPageChanged: (i) => _onPageChanged(i, items),
                itemCount: items.length + (hasTail ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i >= items.length) {
                    return ReelsFeedTailPage(
                      loading: loading,
                      hasMore: hasMore,
                      onRefresh: _refreshFeed,
                    );
                  }
                  final reel = items[i];
                  return _ReelPage(
                    key: ValueKey(reel.id),
                    reel: reel,
                    index: i,
                    current: _current,
                    active: _active,
                    onFailed: () => _skipForward(i, items.length),
                    onDead: () => _onDead(reel, i, items.length),
                    onShare: () => _share(reel),
                  );
                },
              ),
            _TopBar(
              onBack: widget.embedded ? null : () => Navigator.of(context).pop(),
              onSearch: _openSearch,
            ),
          ],
        ),
      ),
    );
  }
}

/// «مشاهد», the speaker and search — over the video, in the safe area —
/// with a back chevron only when the page was pushed ([onBack] given).
class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack, required this.onSearch});

  final VoidCallback? onBack;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 52,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const IgnorePointer(
                child: Text(
                  'مشاهد',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    shadows: _kTextShadows,
                  ),
                ),
              ),
              if (onBack != null)
                PositionedDirectional(
                  start: 4,
                  child: IconButton(
                    tooltip: 'رجوع',
                    onPressed: onBack,
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 22,
                      shadows: _kTextShadows,
                    ),
                  ),
                ),
              PositionedDirectional(
                end: 4,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _MuteButton(),
                    IconButton(
                      tooltip: 'بحث',
                      onPressed: onSearch,
                      icon: const Icon(
                        Icons.search_rounded,
                        color: Colors.white,
                        size: 26,
                        shadows: _kTextShadows,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The speaker beside the search icon: a tap silences every page for the
/// session, the next one brings the sound back. Redraws from [reelsMuted]
/// alone, which every open player follows.
class _MuteButton extends StatelessWidget {
  const _MuteButton();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: reelsMuted,
      builder: (_, muted, __) => IconButton(
        tooltip: muted ? 'تشغيل الصوت' : 'كتم الصوت',
        onPressed: () => reelsMuted.value = !muted,
        icon: Icon(
          muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
          color: Colors.white,
          size: 22,
          shadows: _kTextShadows,
        ),
      ),
    );
  }
}

/// What the feed shows before it has anything: a spinner, or the reason
/// and a retry.
class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed({required this.loading, required this.failed, required this.onRetry});

  final bool loading;
  final bool failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4),
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(failed ? Icons.cloud_off_rounded : Icons.video_library_outlined, color: Colors.white54, size: 44),
          const SizedBox(height: 12),
          Text(
            failed ? 'تعذّر تحميل المشاهد' : 'لا توجد مقاطع الآن',
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: const Text('إعادة المحاولة', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// The page past the last reel, so the feed never dead-ends under the
/// finger: while the next page is on its way — or while landing here has
/// just asked for it — a spinner and «جارٍ جلب مشاهد جديدة…»; once there is
/// nothing more to fetch, «هذه كل المشاهد حالياً» and a «تحديث» that starts
/// the feed over.
class ReelsFeedTailPage extends StatelessWidget {
  const ReelsFeedTailPage({
    super.key,
    required this.loading,
    required this.hasMore,
    required this.onRefresh,
  });

  final bool loading;
  final bool hasMore;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final fetching = loading || hasMore;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (fetching) ...[
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4),
              ),
              const SizedBox(height: 14),
              const Text(
                kReelsMoreComingLabel,
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ] else ...[
              const Icon(Icons.done_all_rounded, color: Colors.white54, size: 44),
              const SizedBox(height: 12),
              const Text(
                kReelsEndLabel,
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: onRefresh,
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: const Text(kReelsRefreshLabel, style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One reel: the player with its poster under it, the gestures and the
/// TikTok overlay.
///
/// The picture comes through media_kit — the best video-only stream (up to
/// 1440p) with its audio-only stream alongside for a clip YouTube serves
/// whole, the muxed stream for a longer one (see
/// [kReelAdaptiveMaxDuration]) — and is drawn whole: the feed is native
/// vertical 1080p clips, so the picture fits the page on black, never
/// cropped. Where media_kit cannot run (no native library on this build, an
/// open that threw, an audio track that never attached) the page falls back
/// to video_player on the best muxed stream, which carries its own sound.
///
/// What a clip that does not play means is told apart rather than guessed
/// (see [ReelResolveResult]): a clip YouTube has written off is gone for
/// good and the page says so through [_ReelPage.onDead], which takes it out
/// of the feed at once; YouTube refusing the requests for a moment holds
/// the poster with a spinner and resolves again when the refusal lifts;
/// anything else — the network — shows the poster with a retry and moves on
/// while it is the page showing, but nothing is written off for it. Nor is
/// a stream that opened and then broke ([_playbackBroke]): a picture that
/// stops is no word from YouTube about the clip.
///
/// Gestures: a tap pauses and resumes; a double tap on the middle third
/// likes (the heart burst), on the left third — where the clip starts, the
/// line filling from the left whatever the page's direction — it goes back
/// [kReelSeekStep], on the right third forward; the seek bar at the foot
/// ([ReelSeekBar]) scrubs under the finger, paused meanwhile, and a tap on
/// it seeks to that point.
class _ReelPage extends ConsumerStatefulWidget {
  const _ReelPage({
    super.key,
    required this.reel,
    required this.index,
    required this.current,
    required this.active,
    required this.onFailed,
    required this.onDead,
    required this.onShare,
  });

  final Reel reel;
  final int index;
  final ValueListenable<int> current;
  final ValueListenable<bool> active;

  /// The clip could not be reached: move on, but keep it.
  final VoidCallback onFailed;

  /// The clip itself is gone: take it out of the feed.
  final VoidCallback onDead;
  final VoidCallback onShare;

  @override
  ConsumerState<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends ConsumerState<_ReelPage> {
  /// media_kit: the player and its view, once the streams are open.
  Player? _player;
  VideoController? _video;
  final List<StreamSubscription<Object?>> _subs = [];

  /// The fallback: video_player on the muxed stream.
  VideoPlayerController? _legacy;

  bool _ready = false;
  bool _failed = false;
  bool _firstFrame = false;
  bool _resolving = false;
  bool _userPaused = false;

  /// True while YouTube is refusing the stream requests: the page stays on
  /// its poster, says so, and resolves again once the refusal lifts.
  bool _waiting = false;

  /// The last play / pause asked of the player, so it is not asked again.
  bool? _requestedPlaying;

  /// How much of the clip has played, 0..1, for the line at the foot.
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);

  /// How much of the clip is buffered, 0..1, for the line's fainter share.
  final ValueNotifier<double> _buffered = ValueNotifier<double>(0);

  /// The clip's length and where playback stands, for the seek bar's chip
  /// and the side seeks.
  final ValueNotifier<Duration> _duration = ValueNotifier<Duration>(Duration.zero);
  Duration _position = Duration.zero;

  /// The fraction under the finger while the seek bar is touched; null the
  /// rest of the time.
  final ValueNotifier<double?> _scrub = ValueNotifier<double?>(null);

  /// True while the seek bar is touched: the clip holds still meanwhile.
  bool _scrubbing = false;

  /// A finger move the picture has not followed yet, and the throttle that
  /// paces the following (see [_kScrubSeekEvery]).
  bool _scrubPending = false;
  Timer? _scrubSeekTimer;

  /// The open picture's quality as YouTube labels it — its shorter side, so
  /// 1080 for a vertical 1080×1920 clip as for a landscape 1920×1080 one
  /// (see [reelQualityOf]) — for the quality chip. Read off the picture the
  /// player has actually decoded, not [ReelStreams.height], which is the
  /// long side of a vertical clip; null until the player reports it.
  int? _quality;

  /// Bumped by every prepare / teardown so a stale async step is dropped.
  int _generation = 0;
  Timer? _skipTimer;

  /// Waiting to resolve again: YouTube's refusal to run out, or the short
  /// backoff after the network let the page down.
  Timer? _retryTimer;

  /// How often the page has resolved itself again after a clip it could not
  /// reach; past [_maxAutoRetries] it waits for «إعادة المحاولة» rather than
  /// keep asking a network that is plainly down.
  int _retries = 0;
  static const int _maxAutoRetries = 3;

  /// Running while a player error waits to see whether playback goes on.
  Timer? _errorTimer;

  IconData? _flashIcon;
  Timer? _flashTimer;
  Offset? _heartAt;
  int _heartTick = 0;
  Timer? _heartTimer;
  _SeekMark? _seekMark;
  int _seekTick = 0;
  Timer? _seekTimer;
  Offset _lastTap = Offset.zero;

  bool get _isCurrent => widget.current.value == widget.index;
  bool get _isNear => (widget.current.value - widget.index).abs() <= 1;
  bool get _hasPlayer => _player != null || _legacy != null;

  @override
  void initState() {
    super.initState();
    widget.current.addListener(_onCurrentChanged);
    widget.active.addListener(_applyPlayback);
    reelsMuted.addListener(_applyVolume);
    _sync();
  }

  @override
  void dispose() {
    widget.current.removeListener(_onCurrentChanged);
    widget.active.removeListener(_applyPlayback);
    reelsMuted.removeListener(_applyVolume);
    _flashTimer?.cancel();
    _heartTimer?.cancel();
    _seekTimer?.cancel();
    _skipTimer?.cancel();
    _retryTimer?.cancel();
    _teardown();
    _progress.dispose();
    _buffered.dispose();
    _duration.dispose();
    _scrub.dispose();
    super.dispose();
  }

  void _onCurrentChanged() {
    if (!mounted) return;
    if (!_isCurrent) {
      // Leaving: next time it shows it starts from the top, like TikTok.
      _userPaused = false;
      _skipTimer?.cancel();
      _dropScrub();
      if (_ready) {
        _player?.seek(Duration.zero);
        _legacy?.seekTo(Duration.zero);
      }
    } else if (_failed) {
      _armSkip();
    }
    setState(_sync);
  }

  /// Prepares the player while this page is next to the current one, tears
  /// it down once it is further away, and starts or stops playback.
  void _sync() {
    if (_isNear) {
      if (!_hasPlayer && !_resolving && !_failed) _prepare();
    } else if (_hasPlayer || _resolving) {
      _teardown();
    }
    _applyPlayback();
  }

  void _applyPlayback() {
    if (!_ready) return;
    final shouldPlay = _isCurrent && widget.active.value && !_userPaused && !_scrubbing;
    final p = _player;
    if (p != null) {
      if (_requestedPlaying == shouldPlay) return;
      _requestedPlaying = shouldPlay;
      if (shouldPlay) {
        p.play();
      } else {
        p.pause();
      }
      return;
    }
    final c = _legacy;
    if (c == null) return;
    if (shouldPlay && !c.value.isPlaying) {
      c.play();
    } else if (!shouldPlay && c.value.isPlaying) {
      c.pause();
    }
  }

  /// Full volume — or none while [reelsMuted] — on whichever player is
  /// open. A clip never starts silent on its own: the flag is off until the
  /// user turns it on.
  void _applyVolume() {
    final muted = reelsMuted.value;
    _player?.setVolume(muted ? 0 : 100);
    _legacy?.setVolume(muted ? 0 : 1);
  }

  Future<void> _prepare() async {
    final gen = ++_generation;
    _resolving = true;
    _retryTimer?.cancel();
    final resolver = ref.read(reelStreamResolverProvider);
    ReelResolveResult result;
    try {
      result = await resolver.resolveDetailed(widget.reel.id);
    } catch (_) {
      result = const ReelResolveResult(ReelResolveReason.network);
    }
    if (!mounted || gen != _generation) return;
    final streams = result.streams;
    if (streams == null) {
      switch (result.reason) {
        // YouTube has written the clip off: so does the feed.
        case ReelResolveReason.unavailable:
          _dead();
        // Nothing was learnt about the clip: hold the poster and ask again.
        case ReelResolveReason.throttled:
          _waitAndRetry(resolver.throttledUntil);
        case ReelResolveReason.network:
        case ReelResolveReason.ok:
          _fail();
      }
      return;
    }
    if (await _openMediaKit(streams, gen)) return;
    if (!mounted || gen != _generation) return;
    // media_kit is not available here: the muxed stream through video_player.
    await _openLegacy(gen);
  }

  /// Opens [streams] in a media_kit player. False when media_kit could not
  /// be used at all (no native library, an open that threw or hung, an
  /// audio stream that never attached): the caller then falls back to
  /// video_player on the muxed stream, so the sound is never silently
  /// missing. True when the page is now on media_kit — or was torn down
  /// meanwhile, in which case there is nothing left to do.
  Future<bool> _openMediaKit(ReelStreams streams, int gen) async {
    Player? created;
    final VideoController video;
    try {
      created = Player(configuration: const PlayerConfiguration(bufferSize: 16 * 1024 * 1024));
      video = VideoController(
        created,
        configuration: const VideoControllerConfiguration(enableHardwareAcceleration: true),
      );
    } catch (_) {
      if (created != null) _disposeQuietly(created);
      return false;
    }
    final player = created;
    try {
      // Adaptive streams go through the loopback relay: YouTube refuses
      // mpv's open-ended range requests for them (a muxed stream it serves
      // as is).
      final proxy = ReelStreamProxy.instance;
      final videoUrl = streams.muxed ? streams.video : await proxy.register(streams.video);
      final audioUrl = streams.audio == null ? null : await proxy.register(streams.audio!);
      if (!mounted || gen != _generation) {
        _disposeQuietly(player);
        return true;
      }
      await player.open(Media(videoUrl.toString()), play: false).timeout(_kOpenTimeout);
      if (audioUrl != null) {
        // media_kit does not throw when mpv refuses the command (say, while
        // it is still switching to the file), so the track list is checked;
        // one more try, then the page gives up on media_kit for this reel.
        var attached = false;
        for (var attempt = 0; attempt < 2 && !attached; attempt++) {
          await player.setAudioTrack(AudioTrack.uri(audioUrl.toString())).timeout(_kOpenTimeout);
          attached = await _externalAudioAttached(player);
        }
        if (!attached) throw StateError('the audio stream did not attach');
      }
      // A file loop (mpv's loop-file), not a playlist loop: at the end of a
      // playlist loop mpv reloads the file and drops the external audio
      // track added above, while a file loop seeks back and keeps it.
      await player.setPlaylistMode(PlaylistMode.single);
      // Heard from the first frame: full volume unless the user has muted
      // the page.
      await player.setVolume(reelsMuted.value ? 0 : 100);
    } catch (_) {
      _disposeQuietly(player);
      return false;
    }
    if (!mounted || gen != _generation) {
      _disposeQuietly(player);
      return true;
    }
    _listen(player, gen);
    setState(() {
      _player = player;
      _video = video;
      _quality = _pictureQuality(player.state.width, player.state.height);
      _ready = true;
      _resolving = false;
    });
    _applyVolume();
    _applyPlayback();
    return true;
  }

  /// True once mpv lists an audio track. The video-only file has none of its
  /// own, so any audio track is the external one; the list arrives a moment
  /// after the command, hence the short wait.
  static Future<bool> _externalAudioAttached(Player player) async {
    bool has(Tracks t) => t.audio.any((a) => a.id != 'auto' && a.id != 'no');
    if (has(player.state.tracks)) return true;
    try {
      await player.stream.tracks.firstWhere(has).timeout(const Duration(seconds: 4));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Follows [player]: the poster comes off at the first position past zero
  /// (a frame is on screen by then; the controller's own first-frame signal
  /// fires on Android as soon as the picture size is known, before anything
  /// is drawn), the progress and buffered lines follow the position and the
  /// buffer, the quality chip follows the decoded picture's size, and an
  /// error that playback does not recover from fails the page.
  void _listen(Player player, int gen) {
    bool live() => mounted && gen == _generation;
    void pictureChanged(int? _) {
      if (!live()) return;
      final quality = _pictureQuality(player.state.width, player.state.height);
      if (quality != _quality) setState(() => _quality = quality);
    }

    _subs.add(player.stream.width.listen(pictureChanged));
    _subs.add(player.stream.height.listen(pictureChanged));
    _subs.add(player.stream.duration.listen((d) {
      if (live()) _duration.value = d;
    }));
    _subs.add(player.stream.position.listen((pos) {
      if (!live()) return;
      _position = pos;
      if (pos > Duration.zero && !_firstFrame) setState(() => _firstFrame = true);
      _progress.value = _fraction(pos, _duration.value);
    }));
    _subs.add(player.stream.buffer.listen((b) {
      if (live()) _buffered.value = _fraction(b, _duration.value);
    }));
    _subs.add(player.stream.error.listen((_) {
      if (live()) _onPlayerError(player, live);
    }));
  }

  /// [pos] as a share of [total], 0..1; zero while the length is unknown.
  static double _fraction(Duration pos, Duration total) {
    final ms = total.inMilliseconds;
    return ms > 0 ? (pos.inMilliseconds / ms).clamp(0.0, 1.0) : 0;
  }

  /// The quality of a [width]×[height] picture as YouTube labels it (see
  /// [reelQualityOf]); null until both sides are known.
  static int? _pictureQuality(int? width, int? height) {
    if (width == null || height == null || width <= 0 || height <= 0) return null;
    return reelQualityOf(width, height);
  }

  /// mpv logs errors it then recovers from (a decoder falling back to
  /// software, a request it retries), so an error counts only when playback
  /// has not moved on 1.2 s later — and then the stream at hand is broken,
  /// which is [_playbackBroke]'s business, not the feed's.
  void _onPlayerError(Player player, bool Function() live) {
    if (_failed || _errorTimer != null) return;
    final at = player.state.position;
    _errorTimer = Timer(const Duration(milliseconds: 1200), () {
      _errorTimer = null;
      if (!live() || _failed) return;
      if (player.state.position > at + const Duration(milliseconds: 250)) return;
      _playbackBroke();
    });
  }

  /// The previous path: the best muxed stream (720p at most) in
  /// video_player.
  Future<void> _openLegacy(int gen) async {
    Uri? url;
    try {
      url = await TrailerStreamResolver.instance.resolve(widget.reel.id);
    } catch (_) {
      url = null;
    }
    if (!mounted || gen != _generation) return;
    if (url == null) {
      _fail();
      return;
    }
    final c = VideoPlayerController.networkUrl(url);
    try {
      await c.initialize();
      await c.setLooping(true);
      // Heard from the first frame: full volume unless the user has muted
      // the page.
      await c.setVolume(reelsMuted.value ? 0 : 1);
    } catch (_) {
      await c.dispose();
      if (mounted && gen == _generation) _fail();
      return;
    }
    if (!mounted || gen != _generation) {
      await c.dispose();
      return;
    }
    c.addListener(_onLegacyTick);
    final picture = c.value.size;
    setState(() {
      _legacy = c;
      _quality = _pictureQuality(picture.width.round(), picture.height.round());
      _ready = true;
      _resolving = false;
    });
    _applyVolume();
    _applyPlayback();
  }

  void _onLegacyTick() {
    final c = _legacy;
    if (c == null || !mounted) return;
    final v = c.value;
    if (!_firstFrame && v.isInitialized && v.position > Duration.zero) {
      setState(() => _firstFrame = true);
    }
    _position = v.position;
    _duration.value = v.duration;
    _progress.value = _fraction(v.position, v.duration);
    _buffered.value = _fraction(_bufferedEnd(v.buffered, v.position), v.duration);
    // The same rule as media_kit's: a stream that opened and then errs
    // without playing on is broken, so it is opened again.
    if (v.hasError && !_failed) _onLegacyError(c);
  }

  /// A video_player error under the 1.2 s rule: the stream counts as broken
  /// only when playback has not moved on by then.
  void _onLegacyError(VideoPlayerController controller) {
    if (_errorTimer != null) return;
    final at = controller.value.position;
    _errorTimer = Timer(const Duration(milliseconds: 1200), () {
      _errorTimer = null;
      if (!mounted || _failed || !identical(_legacy, controller)) return;
      if (controller.value.position > at + const Duration(milliseconds: 250)) return;
      _playbackBroke();
    });
  }

  /// How far ahead of [position] the buffer reaches: the far end of the
  /// furthest-reaching [ranges] entry that starts at or before it; zero when
  /// none does.
  static Duration _bufferedEnd(List<DurationRange> ranges, Duration position) {
    var end = Duration.zero;
    for (final r in ranges) {
      if (r.start <= position && r.end > end) end = r.end;
    }
    return end;
  }

  /// Marks the page failed and, while it is the one showing, moves on:
  /// after 1.2 s, or at once when [now]. The reel keeps its place in the
  /// feed — nothing here says the clip is gone — and resolves itself again
  /// after a short wait, so a page left on it comes back on its own.
  void _fail({bool now = false}) {
    if (!mounted) return;
    setState(() {
      _failed = true;
      _waiting = false;
      _resolving = false;
    });
    if (_retries < _maxAutoRetries) {
      // A little longer each time, so a page left open on a network that is
      // down does not keep asking.
      _armRetry(_kRetryAfter * (1 << _retries));
      _retries++;
    }
    if (!_isCurrent) return;
    if (now) {
      widget.onFailed();
    } else {
      _armSkip();
    }
  }

  /// The stream that was open broke while it was playing: the picture
  /// stopped and did not come back (see [_onPlayerError]).
  ///
  /// Nothing YouTube said stands behind that — the phone may have gone into
  /// a tunnel, or the URLs the page was handed may have stopped being
  /// honoured mid-clip — so the reel keeps its place in the feed; only a
  /// clip YouTube itself has written off is dropped. The broken player goes,
  /// the stale URLs are forgotten so resolving again asks YouTube afresh,
  /// and the page then retries under the same backoff as a clip it could not
  /// reach — carrying [_retries] across the teardown, so a stream that keeps
  /// breaking is not retried for ever.
  void _playbackBroke() {
    if (!mounted) return;
    ref.read(reelStreamResolverProvider).forget(widget.reel.id);
    final retries = _retries;
    setState(() {
      _teardown();
      _retries = retries;
    });
    _fail();
  }

  /// The clip itself is gone (see [ReelResolveReason.unavailable]): the reel
  /// leaves the feed at once and is never shown again.
  void _dead() {
    if (!mounted) return;
    setState(() {
      _failed = true;
      _waiting = false;
      _resolving = false;
    });
    widget.onDead();
  }

  /// YouTube is refusing the requests: the poster stays with its spinner and
  /// the page resolves again a second past [until] — or after the plain
  /// backoff when the resolver named no time. [_resolving] stays on, so
  /// [_sync] does not start a second attempt meanwhile.
  void _waitAndRetry(DateTime? until) {
    if (!mounted) return;
    setState(() {
      _waiting = true;
      _failed = false;
    });
    final left = until == null ? _kRetryAfter : until.difference(DateTime.now()) + const Duration(seconds: 1);
    _armRetry(left.isNegative ? const Duration(seconds: 1) : left);
  }

  /// Clears the failure [after] a wait and resolves again — or, when the
  /// page has drifted away from the one showing meanwhile, leaves it clear
  /// for [_sync] to pick up when it comes back.
  void _armRetry(Duration after) {
    _retryTimer?.cancel();
    _retryTimer = Timer(after, () {
      if (!mounted || _hasPlayer) return;
      setState(() {
        _waiting = false;
        _failed = false;
        _resolving = false;
      });
      if (_isNear) _prepare();
    });
  }

  /// The retry under «تعذّر تشغيل المقطع»: resolve again now.
  void _retryNow() {
    _skipTimer?.cancel();
    _retryTimer?.cancel();
    _retryTimer = null;
    _retries = 0;
    setState(() {
      _failed = false;
      _waiting = false;
      _resolving = false;
    });
    _prepare();
  }

  void _armSkip() {
    _skipTimer?.cancel();
    _skipTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted && _isCurrent) widget.onFailed();
    });
  }

  /// Drops the player (if any) and forgets any resolution under way. Does
  /// not rebuild: callers that are not disposing wrap it in setState.
  void _teardown() {
    ++_generation;
    _errorTimer?.cancel();
    _errorTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _waiting = false;
    _retries = 0;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    final p = _player;
    final c = _legacy;
    _player = null;
    _video = null;
    _legacy = null;
    _ready = false;
    _firstFrame = false;
    _resolving = false;
    _userPaused = false;
    _requestedPlaying = null;
    _quality = null;
    _position = Duration.zero;
    _duration.value = Duration.zero;
    _progress.value = 0;
    _buffered.value = 0;
    _dropScrub();
    if (p != null) _disposeQuietly(p);
    if (c != null) {
      c.removeListener(_onLegacyTick);
      c.dispose();
    }
  }

  /// Disposes a media_kit player without waiting on it: one whose native
  /// side never came up may never answer.
  static void _disposeQuietly(Player player) {
    unawaited(player.dispose().catchError((_) {}));
  }

  void _flash(IconData icon) {
    _flashTimer?.cancel();
    setState(() => _flashIcon = icon);
    _flashTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _flashIcon = null);
    });
  }

  void _onTap() {
    if (!_ready) return;
    _userPaused = !_userPaused;
    _applyPlayback();
    _flash(_userPaused ? Icons.pause_rounded : Icons.play_arrow_rounded);
  }

  /// A double tap: on the left third of the frame ten seconds back, on the
  /// right third ten seconds forward (once the clip plays), in the middle
  /// — or before it plays — the like.
  void _onDoubleTap() {
    if (_ready) {
      final zone = reelSeekZone(_lastTap.dx, context.size?.width ?? 0);
      if (zone != 0) return _seekBy(zone < 0 ? -kReelSeekStep : kReelSeekStep, _lastTap);
    }
    HapticFeedback.lightImpact();
    ref.read(reelLikesProvider.notifier).like(widget.reel.id);
    _heartTimer?.cancel();
    setState(() {
      _heartAt = _lastTap;
      _heartTick++;
    });
    _heartTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _heartAt = null);
    });
  }

  /// Moves the clip to [to], held within its length, on whichever player
  /// is open; the line follows at once rather than on the next tick.
  void _seekTo(Duration to) {
    final total = _duration.value;
    final target = reelClampSeek(to, total);
    _position = target;
    _progress.value = _fraction(target, total);
    _player?.seek(target);
    _legacy?.seekTo(target);
  }

  /// [delta] from where playback stands, with the flash at [at].
  void _seekBy(Duration delta, Offset at) {
    HapticFeedback.selectionClick();
    _seekTo(_position + delta);
    _seekTimer?.cancel();
    setState(() {
      _seekMark = _SeekMark(forward: delta > Duration.zero, at: at);
      _seekTick++;
    });
    _seekTimer = Timer(const Duration(milliseconds: 550), () {
      if (mounted) setState(() => _seekMark = null);
    });
  }

  /// A finger lands on the seek bar at [fraction] of the clip: the thumb
  /// shows there and the clip holds still until it lifts.
  void _onSeekTouchDown(double fraction) {
    if (!_ready) return;
    _scrub.value = fraction;
    if (_scrubbing) return;
    _scrubbing = true;
    _applyPlayback();
  }

  /// The finger moves: the thumb follows at once, the picture at most every
  /// [_kScrubSeekEvery].
  void _onSeekTouchMove(double fraction) {
    if (!_ready) return;
    _scrub.value = fraction;
    _scrubPending = true;
    if (_scrubSeekTimer == null) _followScrub();
  }

  void _followScrub() {
    _scrubSeekTimer = null;
    if (!_scrubPending || !mounted) return;
    _scrubPending = false;
    final f = _scrub.value;
    if (f == null || !_ready) return;
    _seekTo(_duration.value * f);
    _scrubSeekTimer = Timer(_kScrubSeekEvery, _followScrub);
  }

  /// The finger lifts (or tapped) at [fraction]: the clip jumps there and
  /// plays on, whether or not it had been paused.
  void _onSeekTouchUp(double fraction) {
    _dropScrub();
    if (!_ready) return;
    _seekTo(_duration.value * fraction);
    _userPaused = false;
    _applyPlayback();
  }

  /// The touch went elsewhere: the clip goes on from where it stood.
  void _onSeekTouchCancel() {
    _dropScrub();
    _applyPlayback();
  }

  /// Forgets a touch on the seek bar, without touching playback.
  void _dropScrub() {
    _scrubSeekTimer?.cancel();
    _scrubSeekTimer = null;
    _scrubPending = false;
    _scrubbing = false;
    _scrub.value = null;
  }

  /// «مشاهدة الفيلم»: the reel holds still and the title's own page opens
  /// over the whole app (the root navigator, so the bottom bar stays under
  /// it).
  void _openCatalogItem() {
    final item = widget.reel.catalogItem;
    if (item == null) return;
    _userPaused = true;
    _applyPlayback();
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(builder: (_) => CinemanaDetailScreen(item: item)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = _ready;
    final video = _video;
    final legacy = _legacy;
    final size = MediaQuery.sizeOf(context);
    final reel = widget.reel;
    // Zero under the bottom bar (the shell's Scaffold already keeps the body
    // above it); the system inset when the page was pushed full-screen.
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final seekMark = _seekMark;

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (ready && video != null)
            _MediaKitFrame(controller: video)
          else if (ready && legacy != null)
            _LegacyFrame(controller: legacy),
          // The vertical poster over the player until its first frame has
          // played, drawn whole like the clip so nothing jumps when the
          // frame arrives: the media_kit view paints its black fill before
          // it has any frame, so under the player the poster would go dark
          // early.
          if (!_firstFrame) ReelPoster(reel: reel, width: size.width, fit: BoxFit.contain),

          // Gestures over the whole frame; the buttons above take theirs first.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _onTap,
              onDoubleTapDown: (d) => _lastTap = d.localPosition,
              onDoubleTap: _onDoubleTap,
            ),
          ),

          // A soft darkening at the foot so the text reads on bright frames.
          const IgnorePointer(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                height: 220,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0x8A000000)],
                    ),
                  ),
                ),
              ),
            ),
          ),

          if (_flashIcon != null)
            IgnorePointer(
              child: Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.45),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_flashIcon, color: Colors.white, size: 44),
                ),
              ),
            ),

          if (_heartAt != null)
            IgnorePointer(
              child: _HeartBurst(key: ValueKey(_heartTick), at: _heartAt!),
            ),

          if (seekMark != null)
            IgnorePointer(
              child: _SeekFlash(key: ValueKey(_seekTick), mark: seekMark),
            ),

          // Could not be reached: the poster stays, with the reason and a
          // retry — the reel is not written off for it.
          if (_failed)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    kReelFailedLabel,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      shadows: _kTextShadows,
                    ),
                  ),
                  TextButton(
                    onPressed: _retryNow,
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: const Text(kReelRetryLabel, style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),

          // YouTube is refusing the stream requests for a moment: the poster
          // holds, and the page resolves again by itself.
          if (_waiting)
            const IgnorePointer(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
                    ),
                    SizedBox(height: 12),
                    Text(
                      kReelBusyLabel,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        shadows: _kTextShadows,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Bottom-start: the kind, the quality, the film and its «مشاهدة»
          // button — clear of the seek bar's touch strip under them, and
          // out of the way (untouchable too) while the bar is touched, when
          // its time chip rises above the strip. Only the button takes
          // touches; the text lets them through to the frame.
          ValueListenableBuilder<double?>(
            valueListenable: _scrub,
            builder: (_, touched, child) => IgnorePointer(
              ignoring: touched != null,
              child: AnimatedOpacity(
                opacity: touched == null ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                child: child,
              ),
            ),
            child: Align(
              alignment: AlignmentDirectional.bottomStart,
              child: Padding(
                padding: EdgeInsetsDirectional.only(start: 14, end: 80, bottom: kReelSeekBarHeight + 4 + bottomInset),
                child: _ReelInfo(
                  reel: reel,
                  quality: _quality,
                  onOpen: reel.catalogItem == null ? null : _openCatalogItem,
                ),
              ),
            ),
          ),

          // End-side: like, share.
          PositionedDirectional(
            end: 10,
            bottom: 96 + bottomInset,
            child: _SideActions(reel: reel, onShare: widget.onShare),
          ),

          // Loading: a thin line at the very bottom; playing: the seek bar
          // above the bottom edge, which a touch scrubs.
          if (!ready && !_failed && !_waiting)
            const IgnorePointer(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: Colors.white24,
                  valueColor: AlwaysStoppedAnimation(AppColors.primary),
                ),
              ),
            ),
          if (ready)
            Positioned(
              left: 0,
              right: 0,
              bottom: bottomInset,
              child: ReelSeekBar(
                played: _progress,
                buffered: _buffered,
                duration: _duration,
                touched: _scrub,
                onTouchDown: _onSeekTouchDown,
                onTouchMove: _onSeekTouchMove,
                onTouchUp: _onSeekTouchUp,
                onTouchCancel: _onSeekTouchCancel,
              ),
            ),
        ],
      ),
    );
  }
}

/// The media_kit frame: the clip drawn whole — a native vertical clip fits
/// the page, anything else sits on black — with no controls of its own; the
/// page handles the taps and the pausing.
class _MediaKitFrame extends StatelessWidget {
  const _MediaKitFrame({required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Video(
        controller: controller,
        fit: BoxFit.contain,
        fill: Colors.black,
        controls: NoVideoControls,
        pauseUponEnteringBackgroundMode: false,
        resumeUponEnteringForegroundMode: false,
      ),
    );
  }
}

/// The fallback frame (video_player): the clip drawn whole the same way,
/// on black, never cropped.
class _LegacyFrame extends StatelessWidget {
  const _LegacyFrame({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final v = controller.value.size;
    final w = v.width <= 0 ? 9.0 : v.width;
    final h = v.height <= 0 ? 16.0 : v.height;
    return IgnorePointer(
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(width: w, height: h, child: VideoPlayer(controller)),
      ),
    );
  }
}

/// The big heart of a double tap: grows and fades out where the tap landed.
class _HeartBurst extends StatelessWidget {
  const _HeartBurst({super.key, required this.at});

  final Offset at;

  @override
  Widget build(BuildContext context) {
    const size = 110.0;
    return Stack(
      children: [
        Positioned(
          left: at.dx - size / 2,
          top: at.dy - size / 2,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (_, t, child) {
              final scale = t < 0.35 ? 0.5 + (t / 0.35) * 0.8 : 1.3 - (t - 0.35) / 0.65 * 0.2;
              final opacity = t < 0.6 ? 1.0 : (1 - (t - 0.6) / 0.4).clamp(0.0, 1.0);
              return Opacity(
                opacity: opacity,
                child: Transform.scale(scale: scale, child: child),
              );
            },
            child: const Icon(
              Icons.favorite_rounded,
              size: size,
              color: AppColors.primary,
              shadows: [Shadow(color: Color(0x66000000), blurRadius: 16)],
            ),
          ),
        ),
      ],
    );
  }
}

/// A side double tap, for its flash: which way, and where the tap landed.
class _SeekMark {
  const _SeekMark({required this.forward, required this.at});

  final bool forward;
  final Offset at;
}

/// The flash of a side double tap: the ten-second icon over «10 ثوانٍ» in a
/// translucent disc where the tap landed, fading as it goes.
class _SeekFlash extends StatelessWidget {
  const _SeekFlash({super.key, required this.mark});

  final _SeekMark mark;

  @override
  Widget build(BuildContext context) {
    const size = 76.0;
    return Stack(
      children: [
        Positioned(
          left: mark.at.dx - size / 2,
          top: mark.at.dy - size / 2,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 550),
            curve: Curves.easeOut,
            builder: (_, t, child) => Opacity(
              opacity: t < 0.55 ? 1.0 : (1 - (t - 0.55) / 0.45).clamp(0.0, 1.0),
              child: child,
            ),
            child: Container(
              width: size,
              height: size,
              decoration: const BoxDecoration(color: Color(0x73000000), shape: BoxShape.circle),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    mark.forward ? Icons.forward_10_rounded : Icons.replay_10_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                  const Text(
                    '10 ثوانٍ',
                    style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700, height: 1.2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The kind pill with the quality chip beside it (once the stream is open
/// and the picture's [quality] known — «1080p»), the film's title (with
/// its year), and — for a reel of the catalogue, when [onOpen] is given —
/// the «مشاهدة الفيلم» pill under it. Nothing else: no channel, no sound
/// line. The text takes no touches; the pill does.
class _ReelInfo extends StatelessWidget {
  const _ReelInfo({required this.reel, required this.quality, required this.onOpen});

  final Reel reel;
  final int? quality;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final open = onOpen;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IgnorePointer(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _KindPill(),
                  if (reelQualityLabel(quality) != null) ...[
                    const SizedBox(width: 6),
                    ReelQualityChip(quality: quality),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                reel.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textDirection: reelTextDirection(reel.title),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                  shadows: _kTextShadows,
                ),
              ),
            ],
          ),
        ),
        if (open != null) ...[
          const SizedBox(height: 10),
          _WatchButton(lane: reel.lane, onTap: open),
        ],
      ],
    );
  }
}

/// «مشاهدة الفيلم» — «مشاهدة المسلسل» for a series, «مشاهدة الأنمي» for an
/// anime: the red pill under the title — the play arrow and the label,
/// 34 px tall — that opens the title's own page in the app.
class _WatchButton extends StatelessWidget {
  const _WatchButton({required this.lane, required this.onTap});

  final ReelLane lane;
  final VoidCallback onTap;

  /// The label of [lane].
  static String labelOf(ReelLane lane) => switch (lane) {
        ReelLane.film => kReelWatchFilmLabel,
        ReelLane.series => kReelWatchSeriesLabel,
        ReelLane.anime => kReelWatchAnimeLabel,
      };

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(17);
    return Material(
      color: AppColors.primary,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: SizedBox(
          height: 34,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 10, end: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 4),
                Text(
                  labelOf(lane),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What the clip is: «إعلان رسمي» on red — every reel is a release trailer.
class _KindPill extends StatelessWidget {
  const _KindPill();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          'إعلان رسمي',
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

/// The column of buttons on the end side: the like and the share.
class _SideActions extends StatelessWidget {
  const _SideActions({required this.reel, required this.onShare});

  final Reel reel;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LikeButton(reel: reel),
        const SizedBox(height: 18),
        _ActionButton(
          icon: Transform.flip(
            flipX: true,
            child: const Icon(
              Icons.reply_rounded,
              color: Colors.white,
              size: 32,
              textDirection: TextDirection.ltr,
              shadows: _kTextShadows,
            ),
          ),
          label: 'مشاركة',
          onTap: onShare,
        ),
      ],
    );
  }
}

/// An icon with its count or label under it. The column sizes to its
/// content (icon + 2 px + a 12 px line) rather than a fixed height, so the
/// 34 px heart never overflows the box.
class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, required this.onTap});

  final Widget icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.2,
                shadows: _kTextShadows,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The heart and its count. Watches only this reel's like flag and, once
/// loaded, the like count from the watch page, so a tap redraws this
/// widget alone.
class _LikeButton extends ConsumerWidget {
  const _LikeButton({required this.reel});

  final Reel reel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = reel.id;
    final liked = ref.watch(reelLikesProvider.select((s) => s.contains(id)));
    final base = reel.likeCount ??
        ref.watch(reelVideoProvider(id).select((v) => v.valueOrNull?.engagement.likeCount));
    final label = base == null ? '…' : formatReelCount(base + (liked ? 1 : 0));
    return _ActionButton(
      icon: Icon(
        Icons.favorite_rounded,
        color: liked ? AppColors.primary : Colors.white,
        size: 34,
        shadows: _kTextShadows,
      ),
      label: label,
      onTap: () {
        HapticFeedback.selectionClick();
        ref.read(reelLikesProvider.notifier).toggle(id);
      },
    );
  }
}
