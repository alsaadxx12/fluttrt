/// Which live channels the app shows: only beIN Sports and the app's own
/// YASIR TV / Sir TV channels, matched by name. Applied once, at the source
/// of the channel list, so the channels page and the home row agree — and
/// nothing else the feeds carry is ever shown.
class ChannelWhitelist {
  ChannelWhitelist._();

  /// Lower-case, single-spaced, Arabic alef forms unified — so "beIN Sports 1
  /// HD", "bein sports mena 1" and "بي إن سبورت" all compare the same way.
  static String normalize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[\s\-_.]+'), ' ')
      .replaceAll('إ', 'ا')
      .replaceAll('أ', 'ا')
      .replaceAll('آ', 'ا')
      .trim();

  static bool allows(String channelName) {
    final n = normalize(channelName);
    if (n.isEmpty) return false;
    // beIN Sports, Latin or Arabic.
    if (n.contains('bein') || n.contains('بي ان') || n.contains('بين سبورت')) return true;
    // The app's own channels: YASIR TV, Latin or Arabic.
    if (n.contains('yasir') || n.contains('ياسر')) return true;
    return false;
  }
}
