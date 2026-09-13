import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/series/domain/series_aggregator_service.dart';

void main() {
  group('SeriesAggregatorService Integration Test', () {
    test('Aggregates real series into sequential episodes with alternatives', () async {
      final service = SeriesAggregatorService();
      try {
        final series = await service.aggregateSeries('مسلسل عمر');
        
        expect(series.seriesName, isNotEmpty);
        expect(series.isNotEmpty, isTrue);
        expect(series.totalEpisodes, greaterThanOrEqualTo(10));
        expect(series.totalSourcesFound, greaterThan(0));

        // Check sequence
        final firstEpisode = series.episodes.first;
        expect(firstEpisode.episodeNumber, equals(1));
        expect(firstEpisode.primaryVideo.title, isNotEmpty);
        expect(firstEpisode.primaryVideo.author, isNotEmpty);

        // Check switching primary video if alternatives exist
        if (firstEpisode.alternativeVideos.isNotEmpty) {
          final alt = firstEpisode.alternativeVideos.first;
          final switched = firstEpisode.switchPrimary(alt);
          expect(switched.primaryVideo.id.value, equals(alt.id.value));
          expect(switched.alternativeVideos.any((v) => v.id.value == firstEpisode.primaryVideo.id.value), isTrue);
        }
      } finally {
        service.dispose();
      }
    }, timeout: const Timeout(Duration(seconds: 40)));
  });
}
