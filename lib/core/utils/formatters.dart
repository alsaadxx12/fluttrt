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

  /// A YouTube-style Arabic view count: '850 مشاهدة', '1.2 ألف مشاهدة',
  /// '3.4 مليون مشاهدة', '1.1 مليار مشاهدة'. Null (unknown) gives ''.
  static String formatViews(int? n) {
    if (n == null || n < 0) return '';
    return '${compactCount(n)} مشاهدة';
  }

  /// A count the way YouTube abbreviates one in Arabic: '850', '1.2 ألف',
  /// '3.4 مليون', '1.1 مليار'. Shared by view and subscriber counts.
  static String compactCount(int n) {
    if (n < 1000) return '$n';
    // Each threshold sits where rounding would otherwise print '1000 ألف'
    // instead of stepping up to '1 مليون'.
    if (n < 999500) return '${_compact(n / 1000)} ألف';
    if (n < 999500000) return '${_compact(n / 1000000)} مليون';
    return '${_compact(n / 1000000000)} مليار';
  }

  /// One decimal below 10 (1.2, 9.9), none above (12, 340) - the way YouTube
  /// rounds its compact counts. A value that rounds to a whole number drops
  /// its '.0'.
  static String _compact(double v) {
    if (v >= 10) return v.round().toString();
    final s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  /// Arabic relative time in YouTube's style: 'قبل 3 أيام', 'قبل أسبوعين',
  /// 'قبل 5 أشهر', 'قبل سنة'. Null (unknown) gives ''.
  static String timeAgo(DateTime? d, {DateTime? now}) {
    if (d == null) return '';
    final diff = (now ?? DateTime.now()).difference(d);
    if (diff.inSeconds < 60) return 'الآن';

    final minutes = diff.inMinutes;
    if (minutes < 60) return 'قبل ${_arabicCount(minutes, 'دقيقة', 'دقيقتين', 'دقائق', 'دقيقة')}';

    final hours = diff.inHours;
    if (hours < 24) return 'قبل ${_arabicCount(hours, 'ساعة', 'ساعتين', 'ساعات', 'ساعة')}';

    final days = diff.inDays;
    if (days < 7) return 'قبل ${_arabicCount(days, 'يوم', 'يومين', 'أيام', 'يوماً')}';

    final weeks = days ~/ 7;
    if (days < 30) return 'قبل ${_arabicCount(weeks, 'أسبوع', 'أسبوعين', 'أسابيع', 'أسبوعاً')}';

    final months = days ~/ 30;
    if (days < 365) return 'قبل ${_arabicCount(months, 'شهر', 'شهرين', 'أشهر', 'شهراً')}';

    final years = days ~/ 365;
    return 'قبل ${_arabicCount(years, 'سنة', 'سنتين', 'سنوات', 'سنة')}';
  }

  /// Arabic number agreement: 1 → singular alone, 2 → the dual form,
  /// 3-10 → number + plural, 11+ → number + singular (accusative).
  static String _arabicCount(int n, String one, String two, String few, String many) {
    if (n <= 1) return one;
    if (n == 2) return two;
    if (n <= 10) return '$n $few';
    return '$n $many';
  }
}
