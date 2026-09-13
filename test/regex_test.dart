import 'package:flutter_test/flutter_test.dart';

void main() {
  test('yt-dlp regex parsing', () {
    final regex = RegExp(
      r'\[download\]\s+([\d\.]+)%\s+of\s+(?:~\s*)?([\d\.]+)\s*([a-zA-Z]+)(?:\s+at\s+([^E]+?))?(?:\s+ETA\s+([^\s]+))?$',
    );

    const line1 = '[download]  16.1% of   12.41MiB at    9.10MiB/s ETA 00:01';
    final m1 = regex.firstMatch(line1);
    expect(m1, isNotNull);
    expect(m1!.group(1), '16.1');
    expect(m1.group(2), '12.41');
    expect(m1.group(3), 'MiB');
    expect(m1.group(4)?.trim(), '9.10MiB/s');
    expect(m1.group(5), '00:01');

    const line2 = '[download]  78.3% of   12.41MiB at  Unknown B/s ETA Unknown';
    final m2 = regex.firstMatch(line2);
    expect(m2, isNotNull);
    expect(m2!.group(1), '78.3');
    expect(m2.group(4)?.trim(), 'Unknown B/s');
    expect(m2.group(5), 'Unknown');

    const line3 = '[download] 100.0% of   12.41MiB at    9.77MiB/s ETA 00:00';
    final m3 = regex.firstMatch(line3);
    expect(m3, isNotNull);
    expect(m3!.group(1), '100.0');
    expect(m3.group(4)?.trim(), '9.77MiB/s');
    expect(m3.group(5), '00:00');
  });
}
