// Writes the iOS app icon set from the app's own icon.
//
//     dart run tool/ios_icons.dart
//
// Reads assets/images/cineball_icon.png and writes every size the
// AppIcon.appiconset's Contents.json names, so the Xcode project carries the
// same mark as the Android one. Apple wants the 1024 px icon without an alpha
// channel, so the alpha is dropped onto black - the app's own background -
// for every size.
import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  const source = 'assets/images/cineball_icon.png';
  const setDir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';

  final original = img.decodePng(File(source).readAsBytesSync());
  if (original == null) {
    stderr.writeln('could not read $source');
    exit(1);
  }
  // Flattened onto black: no alpha anywhere, as Apple asks for the 1024.
  final flat = img.Image(width: original.width, height: original.height, numChannels: 3);
  img.fill(flat, color: img.ColorRgb8(0, 0, 0));
  img.compositeImage(flat, original);

  final contents = jsonDecode(File('$setDir/Contents.json').readAsStringSync()) as Map<String, dynamic>;
  final images = (contents['images'] as List).cast<Map<String, dynamic>>();
  final written = <String>{};
  for (final entry in images) {
    final size = double.parse((entry['size'] as String).split('x').first);
    final scale = int.parse((entry['scale'] as String).replaceAll('x', ''));
    final px = (size * scale).round();
    final name = entry['filename'] as String;
    if (!written.add(name)) continue;
    final resized = img.copyResize(flat, width: px, height: px, interpolation: img.Interpolation.cubic);
    File('$setDir/$name').writeAsBytesSync(img.encodePng(resized));
    stdout.writeln('$name  ${px}px');
  }
  stdout.writeln('${written.length} icons written from ${original.width}px source');
}
