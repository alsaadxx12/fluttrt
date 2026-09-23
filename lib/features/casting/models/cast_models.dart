import 'package:flutter/foundation.dart';

/// How a device is reached.
enum CastTransport {
  /// A browser showing the CineBall receiver page, paired by code or QR.
  web,

  /// A Chromecast, Google TV or Android TV found by the Cast SDK.
  googleCast,

  /// A smart television found over UPnP. Samsung and LG sets speak this
  /// and not Google Cast, so a Chromecast search never sees one.
  dlna,
}

/// Something that can play what the phone sends it.
@immutable
class CastDevice {
  const CastDevice({
    required this.id,
    required this.name,
    required this.transport,
    this.subtitle = '',
    this.brand = '',
  });

  /// For a browser this is the cast session's uuid; for a Chromecast, the
  /// route id the Cast SDK gave it.
  final String id;

  /// What the viewer sees: «Living Room TV», «Chrome — Windows».
  final String name;

  /// The line under it: what kind of device it is.
  final String subtitle;

  /// Who made it, as the device says — `manufacturer` and `modelName` from
  /// its UPnP description, run together. Empty when it did not say.
  final String brand;

  final CastTransport transport;

  @override
  bool operator ==(Object other) => other is CastDevice && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// The makers whose sets turn up in a living room, for the badge beside
/// the name.
enum CastBrand {
  samsung('SAMSUNG', 0xFF1428A0),
  lg('LG', 0xFFA50034),
  tcl('TCL', 0xFFE30613),
  sony('SONY', 0xFF222222),
  hisense('HISENSE', 0xFF00A0E9),
  haier('HAIER', 0xFF0066B3),
  xiaomi('MI', 0xFFFF6900),
  philips('PHILIPS', 0xFF0B5ED7),
  panasonic('PANA', 0xFF0057A8),
  toshiba('TOSHIBA', 0xFFE50000),
  sharp('SHARP', 0xFFCC0000),
  roku('ROKU', 0xFF662D91),
  google('CAST', 0xFF4285F4),
  unknown('', 0xFF333333);

  const CastBrand(this.mark, this.color);

  /// The word on the badge.
  final String mark;

  /// The badge's colour, as a Flutter colour value.
  final int color;

  /// Reads the maker out of what the device said about itself, and failing
  /// that out of its name — «[TV] Samsung 7 Series» says enough.
  static CastBrand of(CastDevice device) {
    final text = '${device.brand} ${device.name} ${device.subtitle}'.toLowerCase();
    if (text.contains('samsung')) return samsung;
    if (text.contains('lg ') || text.startsWith('lg') || text.contains('[lg]') || text.contains('webos')) return lg;
    if (text.contains('tcl')) return tcl;
    if (text.contains('sony') || text.contains('bravia')) return sony;
    if (text.contains('hisense') || text.contains('vidaa')) return hisense;
    if (text.contains('haier')) return haier;
    if (text.contains('xiaomi') || text.contains('mi tv') || text.contains('mi box') || text.contains('redmi'))
      return xiaomi;
    if (text.contains('philips')) return philips;
    if (text.contains('panasonic')) return panasonic;
    if (text.contains('toshiba')) return toshiba;
    if (text.contains('sharp')) return sharp;
    if (text.contains('roku')) return roku;
    if (text.contains('chromecast') || text.contains('google')) return google;
    return unknown;
  }
}

/// One of the streams the catalogue offers for a title: the address and
/// how tall its picture is.
@immutable
class CastStreamOption {
  const CastStreamOption({required this.url, required this.height});
  final String url;
  final int height;
}

/// What the phone asks a device to play.
///
/// The stream url is carried in the message and nowhere else: it is never
/// written to the database, never put in a pairing code, and never shown.
@immutable
class CastMedia {
  const CastMedia({
    required this.mediaId,
    required this.title,
    required this.streamUrl,
    this.posterUrl = '',
    this.description = '',
    this.contentType,
    this.subtitleUrl,
    this.subtitleLabel,
    this.position = Duration.zero,
    this.duration,
    this.isLive = false,
    this.quality,
    this.height = 0,
    this.fallbacks = const [],
    this.headers,
  });

  final String mediaId;
  final String title;
  final String description;
  final String posterUrl;

  /// The playable url, resolved by the app the moment casting starts.
  final String streamUrl;

  /// 'application/x-mpegURL' for HLS, 'video/mp4' otherwise. Null lets the
  /// receiver decide from the url.
  final String? contentType;

  /// What the phone sends upstream when it fetches the stream for the set:
  /// a CDN that wants the site named as Origin gets it here.
  final Map<String, String>? headers;

  final String? subtitleUrl;
  final String? subtitleLabel;

  /// Where the phone had got to, so the other screen picks it up there.
  final Duration position;
  final Duration? duration;

  /// A live channel: no duration to show and no seeking.
  final bool isLive;

  /// What was chosen and why, when the quality was decided from the link:
  /// «720p · 2.1 Mbit/s». Null when the viewer chose.
  final String? quality;

  /// How tall the picture in [streamUrl] is, when known; zero otherwise.
  final int height;

  /// The other streams the catalogue offers for the same title, so a link
  /// that turns out too slow can be answered with a softer picture from
  /// the same minute.
  final List<CastStreamOption> fallbacks;

  /// The next picture down from this one, or null at the bottom.
  CastStreamOption? get softer {
    CastStreamOption? best;
    for (final option in fallbacks) {
      if (option.height <= 0 || option.height >= height) continue;
      if (best == null || option.height > best.height) best = option;
    }
    return best;
  }

  bool get isHls => contentType == 'application/x-mpegURL' || streamUrl.toLowerCase().contains('.m3u8');

  CastMedia copyWith({
    Duration? position,
    String? streamUrl,
    int? height,
    String? quality,
  }) =>
      CastMedia(
        mediaId: mediaId,
        title: title,
        streamUrl: streamUrl ?? this.streamUrl,
        posterUrl: posterUrl,
        description: description,
        contentType: contentType,
        subtitleUrl: subtitleUrl,
        subtitleLabel: subtitleLabel,
        position: position ?? this.position,
        duration: duration,
        isLive: isLive,
        quality: quality ?? this.quality,
        height: height ?? this.height,
        fallbacks: fallbacks,
        headers: headers,
      );

  /// The LOAD_MEDIA command as the receiver reads it.
  Map<String, dynamic> toCommand({bool change = false}) => {
        'type': change ? 'CHANGE_MEDIA' : 'LOAD_MEDIA',
        'mediaId': mediaId,
        'title': title,
        'description': description,
        'poster': posterUrl,
        'url': streamUrl,
        'contentType': contentType ?? (isHls ? 'application/x-mpegURL' : 'video/mp4'),
        if (subtitleUrl != null) 'subtitleUrl': subtitleUrl,
        if (subtitleLabel != null) 'subtitleLabel': subtitleLabel,
        'position': position.inSeconds,
        'duration': duration?.inSeconds,
        'isLive': isLive,
      };
}

/// Where casting stands, as the button, the sheet and the remote read it.
enum CastStatus {
  /// Nothing connected. The button is an outline.
  idle,

  /// Looking for devices.
  searching,

  /// A device was chosen and is being reached.
  connecting,

  /// Connected. Something may or may not be playing on it.
  connected,

  /// The last attempt failed; [CastState.error] says why.
  error,
}

@immutable
class CastState {
  const CastState({
    this.status = CastStatus.idle,
    this.device,
    this.media,
    this.devices = const [],
    this.position = Duration.zero,
    this.duration,
    this.isPlaying = false,
    this.isMuted = false,
    this.volume = 1,
    this.error,
    this.note,
  });

  final CastStatus status;
  final CastDevice? device;
  final CastMedia? media;
  final List<CastDevice> devices;

  /// Where the other screen actually is, as it last reported.
  final Duration position;
  final Duration? duration;
  final bool isPlaying;
  final bool isMuted;
  final double volume;
  final String? error;

  /// What the controller is doing about a problem right now — «trying
  /// again, 2 of 4» — for the sheet and the remote to show while it does.
  /// Not an error: the attempt is still on.
  final String? note;

  bool get isConnected => status == CastStatus.connected && device != null;

  /// True once something has been sent to the device: the mini controller
  /// and the remote only mean anything then.
  bool get hasMedia => isConnected && media != null;

  CastState copyWith({
    CastStatus? status,
    CastDevice? device,
    CastMedia? media,
    List<CastDevice>? devices,
    Duration? position,
    Duration? duration,
    bool? isPlaying,
    bool? isMuted,
    double? volume,
    String? error,
    String? note,
    bool clearDevice = false,
    bool clearMedia = false,
    bool clearError = false,
    bool clearNote = false,
  }) =>
      CastState(
        status: status ?? this.status,
        device: clearDevice ? null : (device ?? this.device),
        media: clearMedia ? null : (media ?? this.media),
        devices: devices ?? this.devices,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        isPlaying: isPlaying ?? this.isPlaying,
        isMuted: isMuted ?? this.isMuted,
        volume: volume ?? this.volume,
        error: clearError ? null : (error ?? this.error),
        note: clearNote ? null : (note ?? this.note),
      );
}
