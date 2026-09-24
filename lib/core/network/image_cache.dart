import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// The one disk cache for every poster, logo and thumbnail.
///
/// The default manager keeps only 200 files, while the home page alone
/// references ~400 images, so every launch re-downloaded most of them. This
/// store is large enough that a home visit plus a catalogue never evicts the
/// home, and entries live long enough that a picture seen once is simply
/// there next time. Pass it as `cacheManager:` to every CachedNetworkImage /
/// CachedNetworkImageProvider so all of them share one store.
///
/// The store is the second of its name: the first kept pictures that a
/// dropped connection had cut short, and a JPEG cut short decodes as a
/// grey tile - for good, since the file was kept. Every download is now
/// checked against the length the server promised, and anything short is
/// thrown away rather than kept; the old store, with whatever it holds,
/// is left behind.
final CacheManager appImageCache = CacheManager(
  Config(
    'cineball_images_v2',
    stalePeriod: const Duration(days: 60),
    maxNrOfCacheObjects: 3000,
    fileService: _CheckedFileService(),
  ),
);

/// Fetches like the default service, and refuses a picture that arrives
/// shorter than the server said it would be.
class _CheckedFileService extends HttpFileService {
  @override
  Future<FileServiceResponse> get(String url, {Map<String, String>? headers}) async {
    final response = await super.get(url, headers: headers);
    return _CheckedResponse(response);
  }
}

class _CheckedResponse implements FileServiceResponse {
  _CheckedResponse(this._inner);

  final FileServiceResponse _inner;

  @override
  Stream<List<int>> get content async* {
    var received = 0;
    await for (final chunk in _inner.content) {
      received += chunk.length;
      yield chunk;
    }
    final promised = _inner.contentLength;
    if (promised != null && promised > 0 && received < promised) {
      // Not kept: the cache manager drops a download whose stream fails.
      throw HttpException('picture cut short: $received of $promised bytes');
    }
  }

  @override
  int? get contentLength => _inner.contentLength;

  @override
  String? get eTag => _inner.eTag;

  @override
  String get fileExtension => _inner.fileExtension;

  @override
  int get statusCode => _inner.statusCode;

  @override
  DateTime get validTill => _inner.validTill;
}
