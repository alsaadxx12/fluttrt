import 'dart:io';

class FileUtils {
  FileUtils._();

  /// Removes illegal characters on Windows and other OSes: < > : " / \ | ? * and control chars.
  /// Preserves Arabic and Unicode letters seamlessly.
  static String sanitizeFilename(String name, {String fallback = 'youtube_download'}) {
    // Replace illegal Windows file characters
    var sanitized = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');

    // Remove leading/trailing spaces and dots which Windows disallows
    sanitized = sanitized.trim().replaceAll(RegExp(r'^\.+|\.+$'), '');

    // Windows reserved filenames check (CON, PRN, AUX, NUL, COM1-9, LPT1-9)
    final reserved = RegExp(r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\..*)?$', caseSensitive: false);
    if (reserved.hasMatch(sanitized) || sanitized.isEmpty) {
      sanitized = '${fallback}_$sanitized';
    }

    // Limit length to safe Windows MAX_PATH bounds
    if (sanitized.length > 120) {
      sanitized = sanitized.substring(0, 120);
    }

    return sanitized.isEmpty ? fallback : sanitized;
  }

  /// Ensures a unique file path if a file with the same name already exists.
  /// e.g. "video.mp4" -> "video (1).mp4"
  static Future<String> getUniqueFilePath(String targetPath) async {
    var file = File(targetPath);
    if (!await file.exists()) {
      return targetPath;
    }

    final directory = file.parent.path;
    final filename = file.uri.pathSegments.last;
    final dotIndex = filename.lastIndexOf('.');
    
    final name = dotIndex != -1 ? filename.substring(0, dotIndex) : filename;
    final ext = dotIndex != -1 ? filename.substring(dotIndex) : '';

    int counter = 1;
    while (await file.exists()) {
      final newPath = '$directory${Platform.pathSeparator}$name ($counter)$ext';
      file = File(newPath);
      counter++;
    }

    return file.path;
  }

  /// Formats byte size into human readable string (e.g. 14.5 MB, 1.2 GB)
  static String formatBytes(int bytes, {int decimals = 1}) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(decimals)} ${suffixes[i]}';
  }
}
