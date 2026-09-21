import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

/// Tells whether a YouTube Short is *letterboxed*: a 16:9 video pasted into
/// the 9:16 canvas with black bands above and below.
///
/// The scenes page shows a short full-frame (BoxFit.contain), so such a
/// short looks like a small landscape strip between two black slabs and
/// is not worth showing. The judgement is made off the short's portrait
/// thumbnail rather than the stream itself: it is one small fetch, it is
/// a frame of the actual video, and the bands are pure black on it.
class ReelLetterbox {
  ReelLetterbox({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  /// The band fraction at or above which a short counts as letterboxed.
  ///
  /// A 16:9 picture on a 9:16 canvas leaves 1 - (9/16)² ≈ 0.68 of it black;
  /// a 4:3 one ≈ 0.58; 0.28 keeps those well in and leaves out the thin
  /// bars some vertical edits carry (a title strip, a 5% margin).
  static const double threshold = 0.28;

  final http.Client _client;
  final bool _ownsClient;

  /// True when the short's portrait thumbnail is letterboxed, false when
  /// the picture fills the canvas, null when no portrait thumbnail could be
  /// fetched or decoded within [timeout] (the caller treats null as "not
  /// letterboxed" so a hiccup never empties the feed).
  ///
  /// The whole check — every candidate thumbnail together — is bounded by
  /// [timeout]; the fetch under way when it runs out is left to finish on
  /// its own and its answer dropped.
  Future<bool?> isLetterboxed(String videoId, {Duration timeout = const Duration(seconds: 6)}) {
    return _measure(videoId).timeout(timeout, onTimeout: () => null);
  }

  /// Closes the HTTP client this object created; one handed in stays the
  /// caller's to close.
  void close() {
    if (_ownsClient) _client.close();
  }

  /// The band fraction of the first thumbnail that answers with an image,
  /// against [threshold]; null when none does.
  Future<bool?> _measure(String videoId) async {
    for (final candidate in _candidates(videoId)) {
      final bytes = await _fetch(candidate.uri);
      if (bytes == null) continue;
      final image = _decode(bytes);
      if (image == null) continue;
      final fraction = candidate.pillarboxed ? _centralColumnBandFraction(image) : _bandFraction(image, left: 0, right: image.width);
      return fraction >= threshold;
    }
    return null;
  }

  /// The thumbnails to try, in order.
  ///
  /// `oardefault.jpg` and `oar2.jpg` are the portrait (9:16) frames YouTube
  /// renders for Shorts; they exist only for shorts, so either answers or
  /// 404s. `hqdefault.jpg` is the last resort every video has, but it is a
  /// 4:3 frame with the portrait video pillarboxed in the middle, so its
  /// bands are measured inside the central portrait column only — a full
  /// row of it is black at the top and bottom of every portrait video,
  /// letterboxed or not, as the pillarbox slabs meet.
  static List<_Candidate> _candidates(String videoId) => [
        _Candidate(Uri.https('i.ytimg.com', '/vi/$videoId/oardefault.jpg'), pillarboxed: false),
        _Candidate(Uri.https('i.ytimg.com', '/vi/$videoId/oar2.jpg'), pillarboxed: false),
        _Candidate(Uri.https('i.ytimg.com', '/vi/$videoId/hqdefault.jpg'), pillarboxed: true),
      ];

  /// The body of a 200 answer to [uri]; null on any other status or when
  /// the request itself fails (no network, a refused connection).
  Future<Uint8List?> _fetch(Uri uri) async {
    try {
      final response = await _client.get(uri);
      if (response.statusCode != 200) return null;
      return response.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  /// The band fraction of a pillarboxed 4:3 thumbnail, measured over the
  /// middle 9/16 of its width (the portrait column, with a small black
  /// margin on either side that does not tip a picture row into "black").
  static double _centralColumnBandFraction(img.Image image) {
    final columnWidth = image.width * 9 ~/ 16;
    final left = (image.width - columnWidth) ~/ 2;
    return _bandFraction(image, left: left, right: left + columnWidth);
  }
}

/// A thumbnail to try, and whether its picture sits pillarboxed inside a
/// wider frame.
class _Candidate {
  const _Candidate(this.uri, {required this.pillarboxed});

  final Uri uri;
  final bool pillarboxed;
}

/// Fraction of the canvas taken by near-black bands at the top and bottom
/// together (0..1), from a decoded portrait thumbnail; null when [bytes]
/// is not a decodable image.
double? reelBlackBandFraction(Uint8List bytes) {
  final image = _decode(bytes);
  if (image == null) return null;
  return _bandFraction(image, left: 0, right: image.width);
}

/// Luminance (of 255) below which a pixel is black. Generous enough to
/// swallow JPEG ringing along the band edges, well under any picture.
const int _blackLuminance = 20;

/// The share of a row's sampled pixels that must be black for the row to
/// count as a band row — the rest is left for compression noise and a
/// stray bright pixel.
const double _blackRowShare = 0.96;

/// At most this many pixels are sampled per row; enough to see any
/// picture, cheap on a 1080-wide thumbnail.
const int _samplesPerRow = 64;

img.Image? _decode(Uint8List bytes) {
  try {
    return img.decodeImage(bytes);
  } catch (_) {
    // A truncated or malformed file: the decoder recognised the format but
    // could not read it, which is as good as not an image.
    return null;
  }
}

/// (top + bottom) / height, where top and bottom are the contiguous runs
/// of black rows from either edge, sampling the columns [left]..[right).
///
/// A picture that is black all the way down scores 0, not 1: a black
/// poster is not letterboxing, and the caller must not reject it for it.
double _bandFraction(img.Image image, {required int left, required int right}) {
  final height = image.height;
  if (height == 0 || right <= left) return 0;

  var top = 0;
  while (top < height && _isBlackRow(image, top, left, right)) {
    top++;
  }
  if (top == height) return 0;

  var bottom = 0;
  while (_isBlackRow(image, height - 1 - bottom, left, right)) {
    bottom++;
  }
  return (top + bottom) / height;
}

bool _isBlackRow(img.Image image, int y, int left, int right) {
  final width = right - left;
  final step = width < _samplesPerRow ? 1 : width ~/ _samplesPerRow;
  var sampled = 0;
  var black = 0;
  for (var x = left; x < right; x += step) {
    sampled++;
    if (image.getPixel(x, y).luminanceNormalized * 255 < _blackLuminance) black++;
  }
  return black >= sampled * _blackRowShare;
}
