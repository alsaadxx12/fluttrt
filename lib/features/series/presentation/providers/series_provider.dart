import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:youtube_downloader/features/downloads/data/models/download_task_model.dart';
import 'package:youtube_downloader/features/downloads/domain/download_service.dart';
import 'package:youtube_downloader/features/downloads/presentation/providers/downloads_provider.dart';
import '../../domain/series_models.dart';
import '../../domain/series_aggregator_service.dart';

final seriesAggregatorServiceProvider = Provider<SeriesAggregatorService>((ref) {
  final service = SeriesAggregatorService();
  ref.onDispose(() => service.dispose());
  return service;
});

class SeriesState {
  final bool isSeriesMode;
  final bool isLoading;
  final bool isSeasonLoading;
  final String query;
  final SeriesModel? seriesModel;
  final int selectedSeason;
  final Set<int> selectedEpisodeNumbers;
  final Set<int> fetchedSeasons;
  final String? errorMessage;

  const SeriesState({
    this.isSeriesMode = false,
    this.isLoading = false,
    this.isSeasonLoading = false,
    this.query = '',
    this.seriesModel,
    this.selectedSeason = 1,
    this.selectedEpisodeNumbers = const {},
    this.fetchedSeasons = const {},
    this.errorMessage,
  });

  bool get hasResults => seriesModel != null && seriesModel!.isNotEmpty;

  List<EpisodeItem> get currentSeasonEpisodes {
    if (seriesModel == null) return [];
    return seriesModel!.getEpisodesForSeason(selectedSeason);
  }

  SeriesState copyWith({
    bool? isSeriesMode,
    bool? isLoading,
    bool? isSeasonLoading,
    String? query,
    SeriesModel? seriesModel,
    int? selectedSeason,
    Set<int>? selectedEpisodeNumbers,
    Set<int>? fetchedSeasons,
    String? errorMessage,
  }) {
    return SeriesState(
      isSeriesMode: isSeriesMode ?? this.isSeriesMode,
      isLoading: isLoading ?? this.isLoading,
      isSeasonLoading: isSeasonLoading ?? this.isSeasonLoading,
      query: query ?? this.query,
      seriesModel: seriesModel ?? this.seriesModel,
      selectedSeason: selectedSeason ?? this.selectedSeason,
      selectedEpisodeNumbers: selectedEpisodeNumbers ?? this.selectedEpisodeNumbers,
      fetchedSeasons: fetchedSeasons ?? this.fetchedSeasons,
      errorMessage: errorMessage,
    );
  }
}

class SeriesNotifier extends StateNotifier<SeriesState> {
  final SeriesAggregatorService _aggregatorService;

  SeriesNotifier(this._aggregatorService) : super(const SeriesState());

  void toggleSeriesMode() {
    state = state.copyWith(isSeriesMode: !state.isSeriesMode);
  }

  void setSeriesMode(bool enabled) {
    state = state.copyWith(isSeriesMode: enabled);
  }

  void reset() {
    state = const SeriesState();
  }

  Future<void> selectSeason(int season) async {
    state = state.copyWith(selectedSeason: season);

    final model = state.seriesModel;
    if (model == null) return;

    final existingEpisodes = model.getEpisodesForSeason(season);
    final alreadyFetched = state.fetchedSeasons.contains(season);

    // If season hasn't been deep-fetched yet or has few episodes, fetch on demand
    if (!alreadyFetched && existingEpisodes.length < 20) {
      state = state.copyWith(isSeasonLoading: true);
      try {
        final newEpisodes = await _aggregatorService.fetchSeasonEpisodes(
          seriesName: model.seriesName,
          seasonNumber: season,
        );

        if (newEpisodes.isNotEmpty) {
          final otherEpisodes = model.episodes.where((e) => e.seasonNumber != season).toList();
          final mergedEpisodes = [...otherEpisodes, ...newEpisodes];

          final updatedModel = SeriesModel(
            seriesName: model.seriesName,
            episodes: mergedEpisodes,
            availableSeasons: model.availableSeasons,
            totalSourcesFound: model.totalSourcesFound + newEpisodes.length,
          );

          state = state.copyWith(
            seriesModel: updatedModel,
            isSeasonLoading: false,
            fetchedSeasons: {...state.fetchedSeasons, season},
            selectedEpisodeNumbers: newEpisodes.map((e) => e.episodeNumber).toSet(),
          );
          return;
        }
      } catch (_) {}

      state = state.copyWith(
        isSeasonLoading: false,
        fetchedSeasons: {...state.fetchedSeasons, season},
      );
    }
  }

  void toggleEpisodeSelection(int episodeNumber) {
    final updated = Set<int>.from(state.selectedEpisodeNumbers);
    if (updated.contains(episodeNumber)) {
      updated.remove(episodeNumber);
    } else {
      updated.add(episodeNumber);
    }
    state = state.copyWith(selectedEpisodeNumbers: updated);
  }

  void selectAllEpisodes() {
    final currentEps = currentSeasonEpisodes;
    final allNumbers = currentEps.map((e) => e.episodeNumber).toSet();
    state = state.copyWith(selectedEpisodeNumbers: allNumbers);
  }

  void deselectAllEpisodes() {
    state = state.copyWith(selectedEpisodeNumbers: {});
  }

  List<EpisodeItem> get currentSeasonEpisodes => state.currentSeasonEpisodes;

  /// Changes the uploader/channel source for a specific episode
  void switchEpisodeSource(int episodeNumber, Video newPrimary) {
    final model = state.seriesModel;
    if (model == null) return;

    final updatedEpisodes = model.episodes.map((ep) {
      if (ep.episodeNumber == episodeNumber && ep.seasonNumber == state.selectedSeason) {
        return ep.switchPrimary(newPrimary);
      }
      return ep;
    }).toList();

    state = state.copyWith(
      seriesModel: SeriesModel(
        seriesName: model.seriesName,
        episodes: updatedEpisodes,
        availableSeasons: model.availableSeasons,
        totalSourcesFound: model.totalSourcesFound,
      ),
    );
  }

  /// Searches and aggregates the series across all YouTube uploaders
  Future<void> searchSeries(String seriesName) async {
    final clean = seriesName.trim();
    if (clean.isEmpty) return;

    // Immediately clear previous seriesModel to prevent stale banner display
    state = SeriesState(
      isSeriesMode: true,
      isLoading: true,
      query: clean,
      errorMessage: null,
      selectedEpisodeNumbers: const {},
      seriesModel: null,
      fetchedSeasons: const {},
    );

    try {
      final model = await _aggregatorService.aggregateSeries(clean);
      final initialSeason = model.availableSeasons.isNotEmpty ? model.availableSeasons.first : 1;

      state = state.copyWith(
        isLoading: false,
        seriesModel: model,
        selectedSeason: initialSeason,
        fetchedSeasons: {initialSeason},
        selectedEpisodeNumbers: model.getEpisodesForSeason(initialSeason).map((e) => e.episodeNumber).toSet(),
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'تعذر تجميع حلقات المسلسل، يرجى المحاولة مرة أخرى',
      );
    }
  }

  /// Starts downloading a list of episodes sequentially with unified quality
  Future<int> startBatchDownload({
    required List<EpisodeItem> episodes,
    required String qualityLabel,
    required String format,
    required DownloadsNotifier downloadsNotifier,
  }) async {
    int queuedCount = 0;
    for (final ep in episodes) {
      final v = ep.primaryVideo;

      final analysis = VideoAnalysisResult(
        id: v.id.value,
        url: v.url,
        title: '${state.seriesModel?.seriesName ?? "مسلسل"} - ${ep.cleanTitle} [${v.author}]',
        author: v.author,
        duration: v.duration,
        thumbnailUrl: v.thumbnails.highResUrl.isNotEmpty
            ? v.thumbnails.highResUrl
            : 'https://i.ytimg.com/vi/${v.id.value}/hqdefault.jpg',
        videoQualities: [
          VideoQualityOption(
            label: qualityLabel,
            tag: 0,
            approximateSizeBytes: 0,
            container: format,
            isMuxed: true,
          ),
        ],
        audioQualities: [],
        bestSizeBytes: 0,
      );

      await downloadsNotifier.startDownload(
        video: analysis,
        type: format.toLowerCase().contains('mp3') ? DownloadType.audio : DownloadType.video,
        qualityLabel: qualityLabel,
        format: format,
      );
      queuedCount++;
    }
    return queuedCount;
  }
}

final seriesProvider = StateNotifierProvider<SeriesNotifier, SeriesState>((ref) {
  final aggregator = ref.watch(seriesAggregatorServiceProvider);
  return SeriesNotifier(aggregator);
});
