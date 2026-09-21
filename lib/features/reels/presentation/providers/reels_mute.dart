import 'package:flutter/foundation.dart';

/// Whether the scenes page plays without sound.
///
/// One flag for every page, for the session: it starts unmuted (a clip is
/// never opened silent), the speaker in the top bar flips it, every open
/// player follows it, and it is not kept across launches.
final ValueNotifier<bool> reelsMuted = ValueNotifier<bool>(false);
