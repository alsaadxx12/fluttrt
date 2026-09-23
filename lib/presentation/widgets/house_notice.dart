import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// A word from the house, full screen: an animated figure in the middle of
/// a black page and a line or two under it.
///
/// It stays until the viewer sends it away — the button, or a tap anywhere
/// — and then it is gone for as long as the page is open. Over a page, put
/// it last in a Stack; over the whole app, bottom bar and all, use [show].
///
/// A notice with a [once] key is shown one time per launch of the app: the
/// joke on the film page is funny the first time and a chore the fifth,
/// and a viewer going in and out of films all evening was reading it on
/// every one. The named constructors all carry a key; the gate on the
/// sports player, which stands in the way on purpose, does not.
class HouseNotice extends StatefulWidget {
  const HouseNotice({
    super.key,
    required this.animation,
    required this.line,
    required this.reason,
    required this.button,
    this.onDone,
    this.tapAnywhere = true,
    this.onClose,
    this.once,
  });

  /// When a film's page opens: bring popcorn.
  const HouseNotice.snacks({Key? key, VoidCallback? onDone})
      : this(
          key: key,
          animation: 'assets/animations/popcorn_bucket.json',
          line: snacksLine,
          reason: snacksReason,
          button: snacksButton,
          onDone: onDone,
          once: 'snacks',
        );

  /// When the app opens: a night of it, on one condition.
  const HouseNotice.welcome({Key? key, VoidCallback? onDone})
      : this(
          key: key,
          animation: 'assets/animations/enjoying_film.json',
          line: welcomeLine,
          reason: welcomeReason,
          button: welcomeButton,
          onDone: onDone,
          once: 'welcome',
        );

  /// On the subscription page: what brought you here?
  const HouseNotice.subscription({Key? key, VoidCallback? onDone})
      : this(
          key: key,
          animation: 'assets/animations/funny_emoji.json',
          line: subscriptionLine,
          reason: subscriptionReason,
          button: subscriptionButton,
          onDone: onDone,
          once: 'subscription',
        );

  static const String snacksLine = 'لا تنسه جيب شامية - جبس - وياه ببسي دايت';
  static const String snacksReason = 'مو منشان شي، من شان صحتك يا غالي';
  static const String snacksButton = 'تمام، جبتهم 🍿';

  static const String welcomeLine = 'اليوم أسهرك للصبح، شورطك؟';
  static const String welcomeReason = 'اغلق التطبيق أحسنلك 😴';
  static const String welcomeButton = 'لا، خليني أسهر 🎬';

  static const String subscriptionLine = 'انته وينك وين طوبه؟';
  static const String subscriptionReason = 'شجابك عليه؟';
  static const String subscriptionButton = 'جاي أشترك 💳';

  /// The Lottie asset shown in the middle.
  final String animation;

  /// The big line, the smaller one under it, and the button's label.
  final String line;
  final String reason;
  final String button;

  /// Called once the notice has been dismissed, for whoever wants to know.
  final VoidCallback? onDone;

  /// Whether a tap anywhere dismisses it, or only the button does — a
  /// notice that stands in the way of something wants only the button.
  final bool tapAnywhere;

  /// When given, a small close mark in the top corner calls this instead
  /// of dismissing: the way back for someone who does not want the button.
  final VoidCallback? onClose;

  /// When given, the notice is shown once per launch under this name and
  /// is simply absent every time after.
  final String? once;

  /// The notices already shown since the app started.
  ///
  /// In memory, on purpose: the next launch is a new evening and gets the
  /// jokes again.
  static final Set<String> _shown = <String>{};

  /// True when a notice named [key] has already been shown this launch.
  static bool shownThisLaunch(String key) => _shown.contains(key);

  /// Forgets what was shown — for a test, where every case is a fresh
  /// launch.
  @visibleForTesting
  static void forgetShown() => _shown.clear();

  /// Puts [notice] over everything, the bottom bar included, until it is
  /// dismissed. The page underneath stays where it is.
  static Future<void> show(BuildContext context, HouseNotice notice) {
    // Already had its turn this launch: nothing to put up, and nothing to
    // wait for.
    final once = notice.once;
    if (once != null && _shown.contains(once)) {
      notice.onDone?.call();
      return Future<void>.value();
    }
    final navigator = Navigator.of(context, rootNavigator: true);
    return navigator.push<void>(PageRouteBuilder<void>(
      opaque: false,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (routeContext, _, __) => HouseNotice(
        animation: notice.animation,
        line: notice.line,
        reason: notice.reason,
        button: notice.button,
        once: once,
        onDone: () {
          if (navigator.canPop()) navigator.pop();
          notice.onDone?.call();
        },
      ),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    ));
  }

  @override
  State<HouseNotice> createState() => _HouseNoticeState();
}

class _HouseNoticeState extends State<HouseNotice>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    reverseDuration: const Duration(milliseconds: 320),
  );

  /// The figure drops in from above and bounces to a stop.
  late final Animation<Offset> _drop = Tween<Offset>(
    begin: const Offset(0, -1.2),
    end: Offset.zero,
  ).animate(CurvedAnimation(
    parent: _motion,
    curve: const Interval(0, 0.8, curve: Curves.elasticOut),
    reverseCurve: Curves.easeIn,
  ));

  /// The words fade up a moment after it.
  late final Animation<double> _words = CurvedAnimation(
    parent: _motion,
    curve: const Interval(0.35, 1, curve: Curves.easeOut),
    reverseCurve: Curves.easeIn,
  );

  late final Animation<Offset> _rise = Tween<Offset>(
    begin: const Offset(0, 0.25),
    end: Offset.zero,
  ).animate(_words);

  /// Absent from the start when this notice has had its turn this launch.
  late bool _gone = widget.once != null && HouseNotice._shown.contains(widget.once);
  bool _leaving = false;

  /// True when the controller was never started, and so must not be
  /// disposed: creating it late, inside dispose, looks up a ticker
  /// provider on a widget that is already gone.
  bool _neverStarted = false;

  @override
  void initState() {
    super.initState();
    if (_gone) {
      _neverStarted = true;
      return;
    }
    final once = widget.once;
    if (once != null) HouseNotice._shown.add(once);
    _motion.forward();
    _motion.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && mounted) {
        setState(() => _gone = true);
        widget.onDone?.call();
      }
    });
  }

  void _dismiss() {
    if (_leaving) return;
    setState(() => _leaving = true);
    _motion.reverse();
  }

  @override
  void dispose() {
    if (!_neverStarted) _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return const SizedBox.shrink();
    final width = MediaQuery.sizeOf(context).width;
    final figure = (width * 0.62).clamp(200.0, 320.0);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.tapAnywhere ? _dismiss : null,
      child: FadeTransition(
        opacity: _leaving ? _words : const AlwaysStoppedAnimation(1),
        child: Material(
          color: Colors.black,
          child: SafeArea(
            child: Stack(
              children: [
                if (widget.onClose != null)
                  PositionedDirectional(
                    top: 4,
                    start: 4,
                    child: IconButton(
                      onPressed: widget.onClose,
                      tooltip: 'رجوع',
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white70, size: 28),
                    ),
                  ),
                Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SlideTransition(
                          position: _drop,
                          child: SizedBox(
                            width: figure,
                            height: figure,
                            child: Lottie.asset(
                              widget.animation,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.movie_filter_rounded,
                                color: Color(0xFFFFC857),
                                size: 140,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        FadeTransition(
                          opacity: _words,
                          child: SlideTransition(
                            position: _rise,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.line,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    height: 1.45,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  widget.reason,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFFFFC857),
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 32),
                                _DismissButton(
                                    label: widget.button, onTap: _dismiss),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DismissButton extends StatelessWidget {
  const _DismissButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      // Painted here rather than with Ink: an Ink pill draws on the
      // Material above, and from inside a scroll view and a slide it lands
      // nowhere near its text.
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: const LinearGradient(
            colors: [Color(0xFFFFC857), Color(0xFFFF9F1C)],
          ),
          boxShadow: const [
            BoxShadow(
                color: Color(0x66FF9F1C), blurRadius: 24, offset: Offset(0, 8)),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(30),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 14),
              child: Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF1A1200),
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
