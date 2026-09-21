import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';
import 'package:youtube_downloader/features/reels/data/reels_service.dart';
import 'package:youtube_downloader/features/reels/presentation/providers/reels_service_provider.dart';

/// The reels feed as the page sees it.
class ReelsFeedState {
  const ReelsFeedState({
    this.items = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.failed = false,
    this.page,
  });

  final List<Reel> items;
  final bool isLoading;
  final bool hasMore;

  /// The last request failed and nothing is showing: offer a retry.
  final bool failed;

  /// The last page fetched, handed back to the service for the next one.
  final ReelsPage? page;

  ReelsFeedState copyWith({
    List<Reel>? items,
    bool? isLoading,
    bool? hasMore,
    bool? failed,
    ReelsPage? page,
  }) =>
      ReelsFeedState(
        items: items ?? this.items,
        isLoading: isLoading ?? this.isLoading,
        hasMore: hasMore ?? this.hasMore,
        failed: failed ?? this.failed,
        page: page ?? this.page,
      );
}

/// Loads the film-shorts feed page by page.
///
/// Building a page costs a few YouTube searches and stream probes, so the
/// tab must never open onto a spinner: the last first page is kept on the
/// device and shown the moment the provider is first read, while the fresh
/// first page loads behind it and is appended (without repeats). The splash
/// reads this provider, so on a normal launch the fresh page is already in
/// hand by the time the tab is opened. [loadMore] is safe to call from
/// every page change because only one request runs at a time.
///
/// A reel whose short turns out not to play is dropped for good ([drop]):
/// out of the list, out of the kept first page, and onto a list of ids that
/// outlives the launch, so neither this feed nor a later search offers it
/// again. Only a clip YouTube itself has written off is dropped — never one
/// that merely could not be reached.
class ReelsFeedNotifier extends StateNotifier<ReelsFeedState> {
  ReelsFeedNotifier(this._service) : super(const ReelsFeedState()) {
    _start();
  }

  final ReelsService _service;
  Future<void>? _inflight;

  /// Where the last first page is kept between launches. Bumped when the
  /// feed's source changed to the catalogue's own titles, so a page kept by
  /// the old feed is not shown.
  static const String cacheKey = 'scenes_feed_v2';

  /// Where the shorts written off as unplayable are kept between launches.
  static const String deadKey = 'scenes_dead_v1';

  /// How many of them are kept: the newest, once there are more.
  static const int deadCap = 400;

  /// How many empty (but not failed) pages are skipped over in one go before
  /// giving the UI a chance.
  static const int _maxEmptyHops = 3;

  /// How few reels may be left ahead of the one showing before the next
  /// page is started (see [ensureAhead]).
  static const int lookAhead = 5;

  /// The written-off ids, oldest first (see [drop]).
  final List<String> _dead = [];

  /// The last reel the page said it was showing, so a page that lands short
  /// of a full one ahead of it can start another at once.
  int _lastSeenIndex = 0;

  Future<void> _start() async {
    await _readDead();
    final cached = await _readCache();
    if (!mounted) return;
    if (cached.isNotEmpty && state.items.isEmpty) {
      state = state.copyWith(items: cached);
    }
    await loadMore();
  }

  /// Starts the next page unless one is already running. [followUp] marks
  /// the one page a landing may start by itself, which never starts another:
  /// a feed that keeps coming back thin must not spin.
  Future<void> loadMore({bool followUp = false}) {
    final running = _inflight;
    if (running != null) return running;
    if (!state.hasMore) return Future.value();
    final f = _load();
    _inflight = f;
    return f.whenComplete(() {
      if (identical(_inflight, f)) _inflight = null;
      if (!followUp && mounted && _shortOfAPage) unawaited(loadMore(followUp: true));
    });
  }

  /// True when fewer than a page of reels are left past the one showing and
  /// there is more to fetch.
  bool get _shortOfAPage =>
      state.hasMore && !state.failed && state.items.length - _lastSeenIndex < kReelsPageSize;

  /// The page is showing the reel at [index]: the next page is started
  /// while fewer than [lookAhead] reels are left past it, so the swipe
  /// never runs into the end of the list.
  void ensureAhead(int index) {
    if (index > _lastSeenIndex) _lastSeenIndex = index;
    if (state.hasMore && state.items.length - index <= lookAhead) unawaited(loadMore());
  }

  Future<void> _load() async {
    final firstPage = state.page == null;
    state = state.copyWith(isLoading: true, failed: false);
    var after = state.page;
    var hops = 0;
    while (true) {
      final page = await _service.fetchFeed(after: after);
      if (!mounted) return;
      after = page;
      final items = _alive(page.items);
      final gotSomething = items.isNotEmpty;
      if (gotSomething || page.failed || !page.hasMore || ++hops >= _maxEmptyHops) {
        final seen = state.items.map((r) => r.id).toSet();
        final fresh = items.where((r) => seen.add(r.id)).toList();
        state = state.copyWith(
          items: fresh.isNotEmpty ? [...state.items, ...fresh] : state.items,
          isLoading: false,
          hasMore: page.hasMore,
          failed: page.failed && state.items.isEmpty,
          page: page,
        );
        if (firstPage && gotSomething) _writeCache(items);
        return;
      }
    }
  }

  /// Throws the loaded feed away and starts again from a fresh seed.
  Future<void> refresh() async {
    final running = _inflight;
    if (running != null) await running;
    if (!mounted) return;
    _lastSeenIndex = 0;
    state = const ReelsFeedState();
    await loadMore();
  }

  /// Takes the reel [id] out of the feed for good: YouTube has no playable
  /// clip behind it, so it leaves the list at once, the kept first page and
  /// the service's memory of it, and it is written down so no later launch
  /// offers it again.
  Future<void> drop(String id) async {
    if (id.isEmpty) return;
    _service.markDead(id);
    _dead
      ..remove(id)
      ..add(id);
    if (_dead.length > deadCap) _dead.removeRange(0, _dead.length - deadCap);
    if (mounted && state.items.any((r) => r.id == id)) {
      state = state.copyWith(items: [
        for (final r in state.items)
          if (r.id != id) r,
      ]);
    }
    await _writeDead();
    await _dropFromCache(id);
  }

  /// [items] without the reels written off (see [drop]).
  List<Reel> _alive(List<Reel> items) {
    if (_dead.isEmpty) return items;
    final dead = _dead.toSet();
    return [
      for (final r in items)
        if (!dead.contains(r.id)) r,
    ];
  }

  /// The written-off ids from the device, handed to the service as well, so
  /// its searches skip them from the first page on.
  Future<void> _readDead() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final kept = prefs.getStringList(deadKey) ?? const [];
      _dead
        ..clear()
        ..addAll(kept.where((id) => id.isNotEmpty));
      for (final id in _dead) {
        _service.markDead(id);
      }
    } catch (_) {
      // No store to read: the feed simply starts without a written-off list.
    }
  }

  Future<void> _writeDead() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(deadKey, _dead);
    } catch (_) {}
  }

  Future<List<Reel>> _readCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(cacheKey);
      if (raw == null || raw.isEmpty) return const [];
      final kept =
          (jsonDecode(raw) as List).whereType<Map>().map((m) => reelFromJson(Map<String, dynamic>.from(m))).toList();
      return _alive(kept);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeCache(List<Reel> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(cacheKey, jsonEncode(items.map(reelToJson).toList()));
    } catch (_) {}
  }

  /// Takes [id] out of the first page kept on the device, so the next
  /// launch does not open on the reel that was just dropped.
  Future<void> _dropFromCache(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(cacheKey);
      if (raw == null || raw.isEmpty) return;
      final kept = (jsonDecode(raw) as List).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
      final left = kept.where((m) => m['id'] != id).toList();
      if (left.length == kept.length) return;
      await prefs.setString(cacheKey, jsonEncode(left));
    } catch (_) {}
  }
}

/// A reel as it is kept on the device between launches — its catalogue
/// entry with it, so the «مشاهدة» link survives the trip, and the lane it
/// was drawn from, which tells an anime from a plain series.
Map<String, dynamic> reelToJson(Reel r) => {
      'id': r.id,
      'title': r.title,
      'author': r.author,
      'channelId': r.channelId,
      'description': r.description,
      'durationMs': r.duration?.inMilliseconds,
      'viewCount': r.viewCount,
      'likeCount': r.likeCount,
      'uploadDate': r.uploadDate?.toIso8601String(),
      'kind': r.kind,
      'lane': r.lane.name,
      'thumbnail': r.thumbnail,
      'catalogItem': r.catalogItem?.toJson(),
    };

Reel reelFromJson(Map<String, dynamic> m) {
  final item = m['catalogItem'];
  return Reel(
    id: m['id'] as String,
    title: (m['title'] as String?) ?? '',
    author: (m['author'] as String?) ?? '',
    channelId: m['channelId'] as String?,
    description: (m['description'] as String?) ?? '',
    duration: m['durationMs'] == null ? null : Duration(milliseconds: (m['durationMs'] as num).toInt()),
    viewCount: (m['viewCount'] as num?)?.toInt(),
    likeCount: (m['likeCount'] as num?)?.toInt(),
    uploadDate: m['uploadDate'] == null ? null : DateTime.tryParse(m['uploadDate'] as String),
    kind: (m['kind'] as String?) ?? Reel.kindTrailer,
    // Kept before the lanes were written down: the catalogue entry tells a
    // series from a film (see [Reel.lane]).
    lane: reelLaneNamed(m['lane'] as String?),
    thumbnail: m['thumbnail'] as String?,
    catalogItem: item is Map ? CinemanaItem.fromJson(Map<String, dynamic>.from(item)) : null,
  );
}

final reelsFeedProvider = StateNotifierProvider<ReelsFeedNotifier, ReelsFeedState>(
  (ref) => ReelsFeedNotifier(ref.watch(reelsServiceProvider)),
);
