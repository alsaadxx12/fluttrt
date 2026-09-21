import 'package:flutter/foundation.dart';

/// How a device is reached.
enum CastTransport {
  /// A browser showing the CineBall receiver page, paired by code or QR.
  web,

  /// A Chromecast, Google TV or Android TV found by the Cast SDK.
  googleCast,
}

/// Something that can play what the phone sends it.
@immutable
class CastDevice {
  const CastDevice({
    required this.id,
    required this.name,
    required this.transport,
    this.subtitle = '',
  });

  /// For a browser this is the cast session's uuid; for a Chromecast, the
  /// route id the Cast SDK gave it.
  final String id;

  /// What the viewer sees: «Living Room TV», «Chrome — Windows».
  final String name;

  /// The line under it: what kind of device it is.
  final String subtitle;

  final CastTransport transport;

  @override
  bool operator ==(Object other) => other is CastDevice && other.id == id;

  @override
  int get hashCode => id.hashCode;
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

  final String? subtitleUrl;
  final String? subtitleLabel;

  /// Where the phone had got to, so the other screen picks it up there.
  final Duration position;
  final Duration? duration;

  /// A live channel: no duration to show and no seeking.
  final bool isLive;

  bool get isHls =>
      contentType == 'application/x-mpegURL' || streamUrl.toLowerCase().contains('.m3u8');

  CastMedia copyWith({Duration? position, String? streamUrl}) => CastMedia(
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
    bool clearDevice = false,
    bool clearMedia = false,
    bool clearError = false,
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
      );
}
