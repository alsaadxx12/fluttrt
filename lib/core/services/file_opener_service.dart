import 'dart:io';
import 'package:url_launcher/url_launcher.dart';

class FileOpenerService {
  FileOpenerService._();

  /// Opens the file with its default registered system application.
  static Future<bool> openFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return false;
    }

    try {
      if (Platform.isWindows) {
        // Run Windows shell start command
        await Process.run('cmd', ['/c', 'start', '', filePath], runInShell: true);
        return true;
      } else {
        final uri = Uri.file(filePath);
        if (await canLaunchUrl(uri)) {
          return await launchUrl(uri);
        }
      }
    } catch (_) {
      // Fallback
    }
    return false;
  }

  /// Opens the folder containing the file in Windows Explorer with the file selected.
  static Future<bool> openFolder(String filePath) async {
    try {
      if (Platform.isWindows) {
        final file = File(filePath);
        if (await file.exists()) {
          // Highlight the specific file in Windows Explorer
          await Process.run('explorer.exe', ['/select,', filePath]);
          return true;
        } else {
          // If file is missing, open parent directory if it exists
          final dir = file.parent;
          if (await dir.exists()) {
            await Process.run('explorer.exe', [dir.path]);
            return true;
          }
        }
      } else {
        final file = File(filePath);
        final dir = file.parent;
        final uri = Uri.file(dir.path);
        if (await canLaunchUrl(uri)) {
          return await launchUrl(uri);
        }
      }
    } catch (_) {}
    return false;
  }
}
