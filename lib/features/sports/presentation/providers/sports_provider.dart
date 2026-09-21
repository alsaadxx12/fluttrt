import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/core/network/http_cache.dart';
import '../../data/models/sports_models.dart';
import '../../data/services/sports_service.dart';
import '../../data/channel_whitelist.dart';
import '../../../shahid/data/shahid_models.dart';
import '../../../shahid/presentation/shahid_providers.dart';
import '../../data/services/stream_warmup.dart';

/// Keeps resolved streams warm across screens, so re-entering a match does
/// not repeat the whole resolution chain.
final streamWarmupProvider = Provider<StreamWarmup>((ref) => StreamWarmup(ref.watch(sportsServiceProvider)));

final sportsServiceProvider = Provider<SportsService>((ref) {
  return SportsService();
});

final sportsDayProvider = StateProvider<String>((ref) => 'today');
final sportsTabProvider = StateProvider<int>((ref) => 0); // 0: Matches, 1: Live, 2: News
final sportsSearchQueryProvider = StateProvider<String>((ref) => '');
final sportsLeagueFilterProvider = StateProvider<int?>((ref) => null);

class SportsState {
  final List<LeagueGroup> groups;
  final List<SportMatchItem> liveMatches;
  final bool isLoading;
  final String? error;

  const SportsState({
    this.groups = const [],
    this.liveMatches = const [],
    this.isLoading = false,
    this.error,
  });

  SportsState copyWith({
    List<LeagueGroup>? groups,
    List<SportMatchItem>? liveMatches,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return SportsState(
      groups: groups ?? this.groups,
      liveMatches: liveMatches ?? this.liveMatches,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}



class SportsNotifier extends StateNotifier<SportsState> {
  final SportsService _service;
  final String _day;

  SportsNotifier(this._service, this._day) : super(const SportsState(isLoading: true)) {
    loadData();
  }

  Future<void> loadData() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final results = await Future.wait([
        _service.fetchMatches(day: _day),
        _service.fetchLiveMatches(day: _day),
      ]);

      final groups = results[0] as List<LeagueGroup>;
      final liveMatches = results[1] as List<SportMatchItem>;

      state = state.copyWith(
        groups: groups,
        liveMatches: liveMatches,
        isLoading: false,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'تعذر جلب بيانات المباريات',
      );
    }
  }

  Future<void> refresh() async {
    HttpCache.instance.markStale();
    try {
      final results = await Future.wait([
        _service.fetchMatches(day: _day),
        _service.fetchLiveMatches(day: _day),
      ]);
      state = state.copyWith(
        groups: results[0] as List<LeagueGroup>,
        liveMatches: results[1] as List<SportMatchItem>,
        clearError: true,
      );
    } catch (_) {}
  }
}

final sportsNotifierProvider =
    StateNotifierProvider.family<SportsNotifier, SportsState, String>((ref, day) {
  final service = ref.watch(sportsServiceProvider);
  return SportsNotifier(service, day);
});

final sportsNewsProvider = FutureProvider<List<SportNewsItem>>((ref) async {
  final service = ref.watch(sportsServiceProvider);
  return service.fetchNews();
});

final matchDetailsProvider =
    FutureProvider.family<MatchDetailedInfo?, ({int matchId, String? sourceId, String? homeName, String? awayName})>(
        (ref, arg) async {
  final service = ref.watch(sportsServiceProvider);
  return service.fetchMatchDetails(
    arg.matchId,
    sourceId: arg.sourceId,
    homeName: arg.homeName,
    awayName: arg.awayName,
  );
});

/// Live sports channels from Yacine API (Category 13)
/// Channels page source: the official streams that answer, plus MBC Shahid's
/// free channels (each one already verified to have an open HLS stream).
/// Where both have the same channel the Shahid entry wins (proper logo).
final sportsChannelsProvider = FutureProvider<List<SportsChannel>>((ref) async {
  final results = await Future.wait([
    ref.watch(sportsServiceProvider).fetchSportsChannels(),
    ref.watch(shahidServiceProvider).fetchLiveChannels(),
  ]);
  final own = results[0] as List<SportsChannel>;
  final shahid = (results[1] as List<ShahidItem>).map(sportsChannelFromShahid).toList();

  bool sameChannel(SportsChannel a, SportsChannel b) {
    final x = normalizeChannelName(a.channelName);
    final y = normalizeChannelName(b.channelName);
    return x.isNotEmpty && y.isNotEmpty && (x == y || x.contains(y) || y.contains(x));
  }

  final sportsChannels = own.where((o) => o.categoryName == 'قنوات رياضية' || o.categoryName == 'رياضة عربية').toList();
  final otherOwn = own.where((o) => o.categoryName != 'قنوات رياضية' && o.categoryName != 'رياضة عربية' && !shahid.any((s) => sameChannel(o, s))).toList();

  final all = [
    ...sportsChannels,
    ...shahid,
    ...otherOwn,
  ];
  // Only beIN Sports and the app's own YASIR TV / Sir TV channels are shown,
  // on the channels page and the home row alike; everything else the feeds
  // carry is dropped here, at the single source.
  return all.where((c) => ChannelWhitelist.allows(c.channelName)).toList();
});

/// Category shown on the channels page for a Shahid channel.
String _shahidCategory(List<String> genres) {
  if (genres.any((g) => g.contains('أخبار') || g.contains('الأحداث'))) return 'أخبار';
  if (genres.any((g) => g.contains('أطفال') || g.contains('رسوم'))) return 'أطفال وتسلية';
  if (genres.any((g) => g.contains('غنائي') || g.contains('موسيق'))) return 'موسيقى';
  if (genres.any((g) => g.contains('وثائقي'))) return 'وثائقي';
  if (genres.any((g) => g.contains('ديني'))) return 'ديني';
  if (genres.any((g) => g.contains('رياضة'))) return 'رياضة عربية';
  return 'منوعات ودراما';
}

SportsChannel sportsChannelFromShahid(ShahidItem c) => SportsChannel(
      channelId: c.id,
      categoryId: 90,
      channelName: c.title,
      channelImage: c.tileUrl(480) ?? c.logoUrl(400) ?? '',
      channelUrl: c.streamUrl ?? '',
      channelType: 'SHAHID',
      categoryName: _shahidCategory(c.genres),
    );

