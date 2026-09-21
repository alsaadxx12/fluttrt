import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// The one disk cache for every poster, logo and thumbnail.
///
/// The default manager keeps only 200 files, while the home page alone
/// references ~400 images, so every launch re-downloaded most of them. This
/// store is large enough that a home visit plus a catalogue never evicts the
/// home, and entries live long enough that a picture seen once is simply
/// there next time. Pass it as `cacheManager:` to every CachedNetworkImage /
/// CachedNetworkImageProvider so all of them share one store.
final CacheManager appImageCache = CacheManager(
  Config(
    'cineball_images',
    stalePeriod: const Duration(days: 60),
    maxNrOfCacheObjects: 3000,
  ),
);
