import 'dart:async';
import 'dart:io';

import 'package:video_player/video_player.dart';

/// Playback on a desktop goes through media_kit, which behaves differently
/// from Android's ExoPlayer in one way that matters.
///
/// media_kit only learns a video's size once something is rendering it, and
/// the video_player bridge will not report a stream as initialized until it
/// knows that size. A screen that awaits initialize() before putting the
/// player on screen therefore waits forever: nothing renders, so no size
/// arrives, so initialize() never returns. On a desktop the view has to be
/// mounted first.
bool get isDesktopVideo => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// Opens [controller] while [redraw] rebuilds the view every [every].
///
/// The VideoPlayer widget only picks up its texture when it is rebuilt after
/// the backend has created it, and the stream will not finish opening until
/// that texture is being drawn. Redrawing on a short timer covers that gap
/// without reaching into video_player's internals.
Future<void> openWhileRedrawing(
  VideoPlayerController controller,
  void Function() redraw, {
  Duration every = const Duration(milliseconds: 100),
}) async {
  final ticker = Timer.periodic(every, (_) => redraw());
  try {
    await controller.initialize();
  } finally {
    ticker.cancel();
  }
}

/// Disposes a controller that may already have been disposed elsewhere. On a
/// desktop the controller is on screen while it opens, so a newer stream can
/// close it before its own open finishes.
Future<void> disposeQuietly(VideoPlayerController controller) async {
  try {
    await controller.dispose();
  } catch (_) {}
}

/// Desktop cards are viewed on a large screen from close up, so they load the
/// full-resolution poster rather than the medium thumbnail even when their
/// logical width is small.
bool get preferFullArtwork => Platform.isWindows || Platform.isLinux || Platform.isMacOS;
