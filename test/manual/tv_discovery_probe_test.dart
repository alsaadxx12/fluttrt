import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/casting/services/dlna_cast_service.dart';

/// Live probe (network): what the DLNA search finds from this machine.
void main() {
  test('televisions on this network', () async {
    final found = await DlnaCastService().discoverDevices();
    for (final d in found) {
      // ignore: avoid_print
      print('found: ${d.name} | ${d.subtitle} | ${d.brand}');
    }
    // ignore: avoid_print
    print('${found.length} renderer(s)');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
