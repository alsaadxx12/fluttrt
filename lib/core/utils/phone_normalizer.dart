class PhoneNormalizer {
  PhoneNormalizer._();

  /// Converts Arabic-Indic and Eastern Arabic digits to standard ASCII Latin digits.
  static String convertArabicDigits(String input) {
    const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
    const easternArabic = '۰۱۲۳۴۵۶۷۸۹';
    var result = input;
    for (int i = 0; i < 10; i++) {
      result = result.replaceAll(arabicIndic[i], '$i');
      result = result.replaceAll(easternArabic[i], '$i');
    }
    return result;
  }

  /// Normalizes a phone number into standard international E.164 format.
  /// Handles Iraqi local formats (07xxxxxxxxx -> +9647xxxxxxxxx) and global numbers.
  static String normalize(String rawPhone) {
    if (rawPhone.isEmpty) return '';

    // Convert any Arabic numerals
    String digits = convertArabicDigits(rawPhone.trim());

    // Remove any formatting characters (spaces, dashes, parentheses)
    digits = digits.replaceAll(RegExp(r'[\s\-\(\)\.]'), '');

    // Handle 00 prefix -> +
    if (digits.startsWith('00')) {
      digits = '+${digits.substring(2)}';
    }

    // If starts with +, ensure digits follow
    if (digits.startsWith('+')) {
      final sub = digits.substring(1).replaceAll(RegExp(r'\D'), '');
      return '+$sub';
    }

    // Iraqi local format: 07xxxxxxxxx (11 digits starting with 07)
    if (digits.startsWith('07') && digits.length == 11) {
      return '+964${digits.substring(1)}';
    }

    // Iraqi local format missing leading zero: 7xxxxxxxxx (10 digits starting with 7)
    if (digits.startsWith('7') && digits.length == 10) {
      return '+964$digits';
    }

    // Iraqi with country code but no plus: 9647xxxxxxxxx
    if (digits.startsWith('9647')) {
      return '+$digits';
    }

    // If general digits without +, prepend + if looks international, or keep clean digits
    final onlyDigits = digits.replaceAll(RegExp(r'\D'), '');
    return onlyDigits.isNotEmpty ? '+$onlyDigits' : '';
  }

  /// Validates whether the normalized phone number looks valid.
  static bool isValid(String normalizedPhone) {
    if (normalizedPhone.isEmpty) return false;
    final regex = RegExp(r'^\+[1-9]\d{7,14}$');
    return regex.hasMatch(normalizedPhone);
  }

  /// Deterministically maps a normalized phone to a synthetic internal email
  /// for Supabase Email/Password authentication without OTP or SMS.
  /// User never sees this email.
  static String toAuthEmail(String normalizedPhone) {
    final clean = normalizedPhone.replaceAll('+', '').trim();
    return '$clean@auth.cineball.app';
  }
}
