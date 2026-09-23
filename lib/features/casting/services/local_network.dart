import 'dart:io';

import 'package:flutter/foundation.dart';

/// Which network the phone is on, as far as casting is concerned.
enum LocalNetworkStatus {
  /// On a wifi with a private address: a television can be reached.
  wifi,

  /// Only a carrier interface is up. Nothing on the home network is
  /// reachable from here, however many bars the phone shows.
  cellularOnly,

  /// No usable interface at all.
  offline,
}

/// A quick look at the phone's interfaces before anyone goes looking for a
/// television.
///
/// «It does not find my TV» is, more often than not, a phone on mobile data
/// with the wifi off, or a wifi that never came up. Saying so before the
/// search — in a sentence, with the fix in it — beats a spinner that never
/// stops.
class LocalNetwork {
  LocalNetwork._();

  static Future<LocalNetworkStatus> status() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      return judge({
        for (final i in interfaces) i.name: [for (final a in i.addresses) a.address],
      });
    } catch (e) {
      debugPrint('[cast] interfaces: $e');
      return LocalNetworkStatus.offline;
    }
  }

  /// The judgement, from interface names and addresses, for a test.
  @visibleForTesting
  static LocalNetworkStatus judge(Map<String, List<String>> interfaces) {
    var anyUp = false;
    for (final entry in interfaces.entries) {
      final name = entry.key.toLowerCase();
      for (final address in entry.value) {
        if (address.isEmpty || address.startsWith('169.254')) continue;
        anyUp = true;
        final wifiName = name.startsWith('wlan') ||
            name.startsWith('wl') ||
            name.startsWith('wi') ||
            name.startsWith('en') ||
            name.startsWith('eth') ||
            name.startsWith('ap');
        final cellularName = name.startsWith('rmnet') ||
            name.startsWith('ccmni') ||
            name.startsWith('pdp') ||
            name.startsWith('wwan') ||
            name.startsWith('usb');
        if (wifiName && !cellularName) return LocalNetworkStatus.wifi;
        // An unnamed interface with a home-router address is wifi in all
        // but name.
        if (!cellularName && _homeRange(address)) return LocalNetworkStatus.wifi;
      }
    }
    return anyUp ? LocalNetworkStatus.cellularOnly : LocalNetworkStatus.offline;
  }

  static bool _homeRange(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    if (a == null || b == null) return false;
    if (a == 192 && b == 168) return true;
    return a == 172 && b >= 16 && b <= 31;
  }

  /// What to tell the viewer, or null when there is nothing wrong.
  static String? advice(LocalNetworkStatus status) => switch (status) {
        LocalNetworkStatus.wifi => null,
        LocalNetworkStatus.cellularOnly =>
          'الهاتف على بيانات الجوال — اتصل بنفس شبكة الواي فاي التي عليها التلفاز',
        LocalNetworkStatus.offline => 'لا توجد شبكة — شغّل الواي فاي واتصل بشبكة التلفاز',
      };

  /// When the wifi is up and nothing answers for a while, this is the usual
  /// reason.
  static const String isolationAdvice =
      'الواي فاي متصل لكن لا يظهر أي تلفاز. غالبًا الراوتر يعزل الأجهزة عن بعضها '
      '(AP Isolation / Client Isolation) — أوقف هذا الخيار في إعدادات الراوتر، '
      'أو تأكد أن الهاتف والتلفاز على نفس الشبكة لا شبكة الضيوف';
}
