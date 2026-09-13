import 'package:intl/intl.dart';
import '../localization/app_localizations.dart';

class Formatters {
  Formatters._();

  /// Formats speed in bytes per second to human readable string (e.g. 5.8 MB/s, 420 KB/s)
  static String formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond <= 0) return '0 KB/s';
    if (bytesPerSecond >= 1024 * 1024) {
      final mb = bytesPerSecond / (1024 * 1024);
      return '${mb.toStringAsFixed(1)} MB/s';
    } else {
      final kb = bytesPerSecond / 1024;
      return '${kb.toStringAsFixed(0)} KB/s';
    }
  }

  /// Formats duration (e.g. 03:45 or 01:23:45)
  static String formatDuration(Duration? duration) {
    if (duration == null) return '--:--';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    final mStr = minutes.toString().padLeft(2, '0');
    final sStr = seconds.toString().padLeft(2, '0');

    if (hours > 0) {
      return '$hours:$mStr:$sStr';
    }
    return '$mStr:$sStr';
  }

  /// Formats remaining time (ETA)
  static String formatRemainingTime(Duration remaining, AppLanguage language) {
    final isArabic = language == AppLanguage.arabic;
    final totalSeconds = remaining.inSeconds;

    if (totalSeconds <= 0) {
      return isArabic ? 'أقل من ثانية' : '< 1 sec';
    }

    if (totalSeconds < 60) {
      return isArabic ? 'متبقي $totalSeconds ثوانٍ' : '$totalSeconds seconds remaining';
    }

    final minutes = remaining.inMinutes;
    final sec = totalSeconds % 60;
    if (isArabic) {
      return 'متبقي $minutes دقيقة${sec > 0 ? ' و $sec ث' : ''}';
    } else {
      return '$minutes min${sec > 0 ? ' $sec sec' : ''} remaining';
    }
  }

  /// Formats DateTime into a readable local string
  static String formatDate(DateTime dateTime) {
    return DateFormat('yyyy-MM-dd HH:mm').format(dateTime);
  }
}
