import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cast_models.dart';
import 'cast_service.dart';

/// Casting to a browser — a computer, a Google TV, any screen that can open
/// `cineball.netlify.app/cast`.
///
/// The browser opens a session and shows a six-digit code; the phone claims
/// that code and the two then talk over a Supabase Realtime channel named
/// after the session. Commands go one way as broadcasts, the receiver's
/// state comes back the same way — neither is written to the database, so a
/// pause does not wait on a round trip to Postgres and no stream url is ever
/// stored.
class WebCastService implements CastService {
  WebCastService({SupabaseClient? client}) : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  RealtimeChannel? _channel;
  CastDevice? _device;
  Timer? _heartbeat;

  final StreamController<CastPlaybackEvent> _events =
      StreamController<CastPlaybackEvent>.broadcast();

  @override
  CastTransport get transport => CastTransport.web;

  @override
  Stream<CastPlaybackEvent> get events => _events.stream;

  /// A browser cannot be found on the network — that is the point of the
  /// pairing code — so there is nothing to discover. The sheet offers
  /// «ربط كمبيوتر» instead.
  @override
  Future<List<CastDevice>> discoverDevices() async => const [];

  /// Claims [code] and returns the screen behind it.
  ///
  /// The lookup runs in the database ([claim_cast_session]): the phone has
  /// no way to read a session by code, only by the id it does not yet know.
  Future<CastDevice> pair(String code, {String? phoneName}) async {
    final digits = code.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 6) {
      throw const CastException('الرمز يجب أن يكون ستة أرقام');
    }
    try {
      final row = await _db.rpc<Map<String, dynamic>>(
        'claim_cast_session',
        params: {'code': digits, 'claimed_device_name': phoneName},
      );
      return CastDevice(
        id: '${row['id']}',
        name: '${row['device_name'] ?? 'الكمبيوتر'}',
        subtitle: 'CineBall Web',
        transport: CastTransport.web,
      );
    } on PostgrestException catch (e) {
      // The function raises no_data_found when the code is wrong, already
      // claimed, or past its ten minutes.
      if (e.code == 'P0002' || (e.message).contains('not found')) {
        throw const CastException('الرمز غير صحيح أو انتهت صلاحيته');
      }
      throw CastException('تعذّر الربط: ${e.message}');
    } catch (_) {
      throw const CastException('تعذّر الاتصال بالخادم');
    }
  }

  @override
  Future<void> connect(CastDevice device) async {
    await disconnect();
    _device = device;

    final channel = _db.channel(
      'cast:${device.id}',
      opts: const RealtimeChannelConfig(self: false),
    );

    channel.onBroadcast(event: 'state', callback: _onState);
    channel.subscribe();
    _channel = channel;

    // Keeps the session from expiring while it is in use; the receiver does
    // the same from its end.
    _heartbeat = Timer.periodic(const Duration(minutes: 1), (_) => _touch());
    await _touch();
  }

  void _onState(Map<String, dynamic> payload) {
    if (_events.isClosed) return;
    final type = '${payload['type'] ?? 'STATE'}';

    if (type == 'ERROR') {
      _events.add(CastPlaybackEvent(error: '${payload['message'] ?? 'تعذّر التشغيل'}'));
      return;
    }

    double? asDouble(Object? v) => v is num ? v.toDouble() : null;
    final position = asDouble(payload['position']);
    final duration = asDouble(payload['duration']);

    _events.add(CastPlaybackEvent(
      position: position == null ? null : Duration(milliseconds: (position * 1000).round()),
      duration: duration == null ? null : Duration(milliseconds: (duration * 1000).round()),
      isPlaying: payload['paused'] is bool ? !(payload['paused'] as bool) : null,
      isMuted: payload['muted'] is bool ? payload['muted'] as bool : null,
      volume: asDouble(payload['volume']),
      ended: type == 'MEDIA_ENDED' || payload['ended'] == true,
    ));
  }

  Future<void> _touch() async {
    final id = _device?.id;
    if (id == null) return;
    try {
      await _db.rpc<void>('touch_cast_session', params: {'session_id': id});
    } catch (e) {
      debugPrint('[cast] heartbeat failed: $e');
    }
  }

  Future<void> _send(Map<String, dynamic> command) async {
    final channel = _channel;
    if (channel == null) throw const CastException('لا يوجد جهاز متصل');
    await channel.sendBroadcastMessage(event: 'command', payload: command);
  }

  @override
  Future<void> loadMedia(CastMedia media) => _send(media.toCommand());

  /// The device is already playing something else: it swaps without the
  /// viewer pairing again.
  Future<void> changeMedia(CastMedia media) => _send(media.toCommand(change: true));

  @override
  Future<void> play() => _send({'type': 'PLAY'});

  @override
  Future<void> pause() => _send({'type': 'PAUSE'});

  @override
  Future<void> seek(Duration position) => _send({
        'type': 'SEEK',
        'position': position.inSeconds,
      });

  @override
  Future<void> setVolume(double volume) => _send({
        'type': 'VOLUME',
        'value': volume.clamp(0.0, 1.0),
      });

  @override
  Future<void> setMuted(bool muted) => _send({'type': muted ? 'MUTE' : 'UNMUTE'});

  @override
  Future<void> stop() async {
    try {
      await _send({'type': 'STOP'});
    } on CastException {
      // Nothing listening any more; disconnecting is still the right move.
    }
  }

  @override
  Future<void> disconnect() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    final channel = _channel;
    _channel = null;
    final id = _device?.id;
    _device = null;
    if (channel != null) {
      try {
        await _db.removeChannel(channel);
      } catch (_) {}
    }
    if (id != null) {
      try {
        await _db.from('cast_sessions').update({'status': 'disconnected'}).eq('id', id);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    _events.close();
    final channel = _channel;
    if (channel != null) _db.removeChannel(channel);
  }
}
