import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/features/downloads/data/models/download_task_model.dart';
import 'package:youtube_downloader/features/downloads/domain/download_service.dart';
import 'package:youtube_downloader/features/downloads/presentation/providers/downloads_provider.dart';

enum AnalyzerStatus { idle, analyzing, success, error }

class AnalyzerState {
  final AnalyzerStatus status;
  final String url;
  final VideoAnalysisResult? result;
  final String? errorMessage;
  final DownloadType selectedType;
  final VideoQualityOption? selectedVideoQuality;
  final AudioQualityOption? selectedAudioQuality;

  const AnalyzerState({
    this.status = AnalyzerStatus.idle,
    this.url = '',
    this.result,
    this.errorMessage,
    this.selectedType = DownloadType.video,
    this.selectedVideoQuality,
    this.selectedAudioQuality,
  });

  bool get isAnalyzing => status == AnalyzerStatus.analyzing;
  bool get hasResult => status == AnalyzerStatus.success && result != null;

  AnalyzerState copyWith({
    AnalyzerStatus? status,
    String? url,
    VideoAnalysisResult? result,
    String? errorMessage,
    DownloadType? selectedType,
    VideoQualityOption? selectedVideoQuality,
    AudioQualityOption? selectedAudioQuality,
  }) {
    return AnalyzerState(
      status: status ?? this.status,
      url: url ?? this.url,
      result: result ?? this.result,
      errorMessage: errorMessage ?? this.errorMessage,
      selectedType: selectedType ?? this.selectedType,
      selectedVideoQuality: selectedVideoQuality ?? this.selectedVideoQuality,
      selectedAudioQuality: selectedAudioQuality ?? this.selectedAudioQuality,
    );
  }
}

class AnalyzerNotifier extends StateNotifier<AnalyzerState> {
  final DownloadService _downloadService;

  AnalyzerNotifier(this._downloadService) : super(const AnalyzerState());

  Future<void> analyze(String inputUrl) async {
    final cleanUrl = inputUrl.trim();
    if (cleanUrl.isEmpty) return;

    state = state.copyWith(
      status: AnalyzerStatus.analyzing,
      url: cleanUrl,
      errorMessage: null,
    );

    try {
      final analysis = await _downloadService.analyzeUrl(cleanUrl).timeout(const Duration(seconds: 7));
      
      final defaultVideo = analysis.videoQualities.isNotEmpty
          ? analysis.videoQualities.first
          : null;
      final defaultAudio = analysis.audioQualities.isNotEmpty
          ? analysis.audioQualities.first
          : null;

      state = state.copyWith(
        status: AnalyzerStatus.success,
        result: analysis,
        selectedVideoQuality: defaultVideo,
        selectedAudioQuality: defaultAudio,
      );
    } catch (e) {
      String msg = 'تعذر تحليل الرابط المدخل';
      if (e is FormatException) {
        msg = 'الرابط غير صالح أو ليس من YouTube';
      } else if (e.toString().contains('unavailable') || e.toString().contains('private')) {
        msg = 'الفيديو غير متاح أو خاص أو تم حذفه';
      } else if (e.toString().contains('SocketException') || e.toString().contains('HandshakeException')) {
        msg = 'خطأ في الاتصال بالإنترنت، يرجى التحقق من الشبكة';
      }
      state = state.copyWith(
        status: AnalyzerStatus.error,
        errorMessage: msg,
      );
    }
  }

  void setType(DownloadType type) {
    state = state.copyWith(selectedType: type);
  }

  void selectVideoQuality(VideoQualityOption quality) {
    state = state.copyWith(selectedVideoQuality: quality);
  }

  void selectAudioQuality(AudioQualityOption quality) {
    state = state.copyWith(selectedAudioQuality: quality);
  }

  void reset() {
    state = const AnalyzerState();
  }
}

final analyzerProvider = StateNotifierProvider<AnalyzerNotifier, AnalyzerState>((ref) {
  final service = ref.watch(downloadServiceProvider);
  return AnalyzerNotifier(service);
});
