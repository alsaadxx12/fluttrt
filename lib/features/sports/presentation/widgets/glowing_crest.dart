import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:youtube_downloader/core/network/image_cache.dart';

/// A club crest with no frame, over a soft glow in the crest's own colour.
///
/// The colour is the crest's dominant hue (white, black and grey parts are
/// set aside), read once from a tiny decode and remembered per crest.
class GlowingCrest extends StatefulWidget {
  final String? url;
  final double size;

  const GlowingCrest({super.key, required this.url, this.size = 76});

  /// Glow for crests with no real colour (black and white).
  static const neutralGlow = Color(0xFFB8C2D6);

  /// The glow colour for a decoded crest.
  static Future<Color> crestGlowColor(ui.Image image) => _GlowingCrestState.crestGlowColor(image);

  /// The dominant colour of the picture at [url] (its strongest hue, with
  /// white, black and grey set aside), read from a tiny decode and cached.
  /// Null when the picture can't be read.
  static Future<Color?> dominantColorOf(String url) => _GlowingCrestState.dominantColorOf(url);

  @override
  State<GlowingCrest> createState() => _GlowingCrestState();
}

class _GlowingCrestState extends State<GlowingCrest> {
  static final Map<String, Color> _cache = {};
  static const _neutralGlow = GlowingCrest.neutralGlow;

  Color? _glow;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(GlowingCrest old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _glow = null;
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final url = widget.url;
    if (url == null || url.isEmpty) return;
    final color = await dominantColorOf(url);
    if (color != null && mounted && widget.url == url) setState(() => _glow = color);
  }

  static Future<Color?> dominantColorOf(String url) async {
    if (url.isEmpty) return null;
    final cached = _cache[url];
    if (cached != null) return cached;
    try {
      final color = await crestGlowColor(await _decodeSmall(url));
      _cache[url] = color;
      return color;
    } catch (_) {
      return null; // decoration only
    }
  }

  static Future<ui.Image> _decodeSmall(String url) {
    final completer = Completer<ui.Image>();
    final stream = ResizeImage(CachedNetworkImageProvider(url, cacheManager: appImageCache), width: 24)
        .resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!completer.isCompleted) completer.complete(info.image);
        stream.removeListener(listener);
      },
      onError: (e, st) {
        if (!completer.isCompleted) completer.completeError(e, st);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  /// The most-weighted of 12 hue buckets, averaged, then brightened so it
  /// glows on the dark card.
  static Future<Color> crestGlowColor(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return _neutralGlow;
    final px = data.buffer.asUint8List();
    final weight = List<double>.filled(12, 0);
    final r = List<double>.filled(12, 0), g = List<double>.filled(12, 0), b = List<double>.filled(12, 0);
    var opaque = 0.0;
    for (var i = 0; i + 3 < px.length; i += 4) {
      final a = px[i + 3] / 255;
      if (a < 0.5) continue;
      opaque += a;
      final hsl = HSLColor.fromColor(Color.fromARGB(255, px[i], px[i + 1], px[i + 2]));
      // Grey, near-white and near-black parts carry no colour.
      if (hsl.saturation < 0.25 || hsl.lightness < 0.12 || hsl.lightness > 0.92) continue;
      final k = (hsl.hue / 30).floor() % 12;
      final w = a * hsl.saturation;
      weight[k] += w;
      r[k] += px[i] * w;
      g[k] += px[i + 1] * w;
      b[k] += px[i + 2] * w;
    }
    var best = 0;
    for (var k = 1; k < 12; k++) {
      if (weight[k] > weight[best]) best = k;
    }
    // Hardly any colour at all: a black-and-white crest.
    if (opaque == 0 || weight[best] < opaque * 0.06) return _neutralGlow;
    final w = weight[best];
    final base = Color.fromARGB(255, (r[best] / w).round(), (g[best] / w).round(), (b[best] / w).round());
    final hsl = HSLColor.fromColor(base);
    return hsl
        .withSaturation((hsl.saturation * 1.15).clamp(0.0, 1.0))
        .withLightness(hsl.lightness.clamp(0.45, 0.62))
        .toColor();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final url = widget.url;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    const fallback = Icon(Icons.shield_rounded, size: 40, color: Color(0xFFFF4D5B));
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // The glow: a blurred disc in the crest's colour, behind it.
          AnimatedOpacity(
            opacity: _glow == null ? 0 : 1,
            duration: const Duration(milliseconds: 350),
            child: Container(
              width: size * 0.62,
              height: size * 0.62,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (_glow ?? Colors.transparent).withOpacity(_glow == _neutralGlow ? 0.35 : 0.55),
                    blurRadius: size * 0.42,
                    spreadRadius: size * 0.06,
                  ),
                ],
              ),
            ),
          ),
          if (url != null && url.isNotEmpty)
            CachedNetworkImage(
              imageUrl: url,
              cacheManager: appImageCache,
              width: size,
              height: size,
              fit: BoxFit.contain,
              memCacheWidth: (size * dpr).round(),
              fadeInDuration: Duration.zero,
              fadeOutDuration: Duration.zero,
              placeholderFadeInDuration: Duration.zero,
              useOldImageOnUrlChange: true,
              placeholder: (_, __) => const SizedBox.shrink(),
              errorWidget: (_, __, ___) => fallback,
            )
          else
            fallback,
        ],
      ),
    );
  }
}
