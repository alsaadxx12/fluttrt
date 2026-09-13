enum AppLanguage {
  arabic('ar', 'العربية'),
  english('en', 'English');

  final String code;
  final String displayName;
  const AppLanguage(this.code, this.displayName);

  static AppLanguage fromCode(String code) {
    return AppLanguage.values.firstWhere(
      (l) => l.code == code,
      orElse: () => AppLanguage.arabic,
    );
  }
}

class AppStrings {
  final AppLanguage language;
  AppStrings(this.language);

  bool get isArabic => language == AppLanguage.arabic;

  // App General
  String get appName => 'CINEBALL';
  String get appSubtitle => isArabic ? 'سينما ومباريات ومحتوى ترفيهي متكامل' : 'Cinema, live sports & entertainment';

  // Navigation
  String get navHome => isArabic ? 'الرئيسية' : 'Home';
  String get navDownloads => isArabic ? 'التنزيلات' : 'Downloads';
  String get navSettings => isArabic ? 'الإعدادات' : 'Settings';
  String get navAbout => isArabic ? 'حول البرنامج' : 'About';

  // Home Screen
  String get homeTitle => isArabic ? 'تحميل فيديو' : 'Download Video';
  String get urlPlaceholder => isArabic ? 'الصق رابط الفيديو هنا...' : 'Paste video link here...';
  String get pasteTooltip => isArabic ? 'لصق من الحافظة (Ctrl+V)' : 'Paste from clipboard (Ctrl+V)';
  String get clearTooltip => isArabic ? 'مسح الرابط' : 'Clear input';
  String get analyzeButton => isArabic ? 'تحليل الرابط' : 'Analyze Link';
  String get analyzing => isArabic ? 'جاري تحليل الرابط...' : 'Analyzing link...';

  // Video Preview
  String get videoTitle => isArabic ? 'عنوان الفيديو' : 'Video Title';
  String get channel => isArabic ? 'القناة' : 'Channel';
  String get duration => isArabic ? 'المدة' : 'Duration';
  String get quality => isArabic ? 'الجودة' : 'Quality';
  String get estimatedSize => isArabic ? 'الحجم التقريبي' : 'Approx Size';

  // Format & Quality Selection
  String get selectType => isArabic ? 'نوع التنزيل' : 'Download Type';
  String get video => isArabic ? 'فيديو (Video)' : 'Video';
  String get audio => isArabic ? 'صوت فقط (Audio)' : 'Audio';
  String get selectQuality => isArabic ? 'اختر الجودة' : 'Select Quality';
  String get selectAudioFormat => isArabic ? 'صيغة الصوت' : 'Audio Format';
  String get startDownload => isArabic ? 'بدء التنزيل' : 'Start Download';

  // Download Progress Card
  String get activeDownloads => isArabic ? 'التنزيلات النشطة' : 'Active Downloads';
  String get speed => isArabic ? 'السرعة' : 'Speed';
  String get remaining => isArabic ? 'متبقي' : 'Remaining';
  String get seconds => isArabic ? 'ثوانٍ' : 'seconds';
  String get minutes => isArabic ? 'دقائق' : 'minutes';
  String get pause => isArabic ? 'إيقاف مؤقت' : 'Pause';
  String get resume => isArabic ? 'استئناف' : 'Resume';
  String get cancel => isArabic ? 'إلغاء التنزيل' : 'Cancel';
  String get downloadCompleted => isArabic ? 'اكتمل التنزيل بنجاح' : 'Download Completed';
  String get openFile => isArabic ? 'فتح الملف' : 'Open File';
  String get openFolder => isArabic ? 'فتح المجلد' : 'Open Folder';
  String get downloadFailed => isArabic ? 'فشل التنزيل' : 'Download Failed';
  String get downloadPaused => isArabic ? 'التنزيل متوقف مؤقتاً' : 'Download Paused';

  // Downloads History Screen
  String get tabAll => isArabic ? 'الكل' : 'All';
  String get tabDownloading => isArabic ? 'جاري التنزيل' : 'Downloading';
  String get tabCompleted => isArabic ? 'مكتمل' : 'Completed';
  String get tabFailed => isArabic ? 'فشل' : 'Failed';
  String get noDownloads => isArabic ? 'لا توجد تنزيلات في هذه القائمة' : 'No downloads in this list';
  String get actionOpen => isArabic ? 'فتح الملف' : 'Open';
  String get actionOpenLocation => isArabic ? 'فتح مكان الملف' : 'Open Location';
  String get actionRedownload => isArabic ? 'إعادة التنزيل' : 'Redownload';
  String get actionDelete => isArabic ? 'حذف من السجل' : 'Delete from History';
  String get clearAllHistory => isArabic ? 'مسح السجل بالكامل' : 'Clear All History';
  String get confirmDelete => isArabic ? 'هل أنت متأكد من حذف هذا العنصر؟' : 'Are you sure you want to remove this item?';

  // Settings Screen
  String get appearanceSection => isArabic ? 'المظهر' : 'Appearance';
  String get themeMode => isArabic ? 'الوضع' : 'Theme Mode';
  String get themeLight => isArabic ? 'فاتح (Light)' : 'Light';
  String get themeDark => isArabic ? 'داكن (Dark)' : 'Dark';
  String get themeSystem => isArabic ? 'تلقائي حسب النظام' : 'System Default';

  String get languageSection => isArabic ? 'اللغة' : 'Language';
  String get selectLanguage => isArabic ? 'لغة الواجهة' : 'Interface Language';

  String get downloadSection => isArabic ? 'إعدادات التنزيل' : 'Download Settings';
  String get defaultFolder => isArabic ? 'مجلد التنزيل الافتراضي' : 'Default Download Folder';
  String get changeFolder => isArabic ? 'تغيير المجلد' : 'Browse Folder';
  String get maxConcurrentDownloads => isArabic ? 'عدد التنزيلات المتزامنة' : 'Concurrent Downloads';
  String get defaultVideoQuality => isArabic ? 'جودة الفيديو الافتراضية' : 'Default Video Quality';
  String get defaultAudioFormat => isArabic ? 'صيغة الصوت الافتراضية' : 'Default Audio Format';
  String get askBeforeOverwrite => isArabic ? 'تأكيد قبل استبدال الملفات المكررة' : 'Prompt before overwriting existing files';

  // Errors & Feedback Messages
  String get errorInvalidUrl => isArabic ? 'الرابط المدخل غير صالح أو ليس رابط YouTube صحيح' : 'Invalid URL or unsupported YouTube link';
  String get errorVideoUnavailable => isArabic ? 'تعذر الوصول للفيديو، قد يكون خاصاً أو محذوفاً' : 'Video is unavailable, private, or deleted';
  String get errorNetwork => isArabic ? 'حدث خطأ في الاتصال بالإنترنت، يرجى المحاولة ثانية' : 'Network error occurred. Please check connection';
  String get errorGeneric => isArabic ? 'حدث خطأ غير متوقع أثناء معالجة الطلب' : 'An unexpected error occurred';
  String get successAddedToQueue => isArabic ? 'تمت إضافة الفيديو إلى قائمة التنزيل' : 'Video added to download queue';
  String get fileNotFound => isArabic ? 'الملف غير موجود في المسار المحدد' : 'File not found at specified path';

  // About Screen
  /// The real installed version is passed in; never hard-code it here, or
  /// the about page keeps showing an old number after every update.
  String versionLabel(String version) => isArabic ? 'الإصدار $version' : 'Version $version';
  String get checkingUpdate => isArabic ? 'جارٍ التحقق من التحديثات…' : 'Checking for updates…';
  String get upToDate => isArabic ? 'أنت على أحدث إصدار' : 'You are on the latest version';
  String get updateAvailableLabel => isArabic ? 'يتوفر تحديث جديد' : 'An update is available';
  String get checkForUpdates => isArabic ? 'التحقق من التحديثات' : 'Check for updates';
  String get updateNow => isArabic ? 'تحديث الآن' : 'Update now';
  String get legalNotice => isArabic 
    ? 'ملاحظة قانونية: هذا البرنامج مخصص لتنزيل الفيديوهات والمحتوى المرخص بموجب المشاع الإبداعي (Creative Commons) أو المحتوى الذي تمتلك تصريحاً صريحاً بتحميله.'
    : 'Legal Notice: This application is intended for downloading Creative Commons or explicitly authorized YouTube content.';
}
