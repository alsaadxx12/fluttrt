import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/features/reels/data/reel_stream_resolver.dart';

/// The resolver every reel page opens its streams through.
///
/// The app reads the one session-wide resolver — its cache, its verdicts on
/// the innertube clients and its throttle are shared by every page, which is
/// the point of the singleton. It is behind a provider so that what a reel
/// resolves to can be stood in for: a test overrides this and drives the
/// page through each [ReelResolveReason] — a clip YouTube has written off, a
/// refusal to answer for now, a request that never arrived — without a
/// network.
final reelStreamResolverProvider = Provider<ReelStreamResolver>((ref) => ReelStreamResolver.instance);
