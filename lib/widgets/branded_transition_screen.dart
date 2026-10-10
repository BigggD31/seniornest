import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Shared branded loading/transition screen: the same golden-green
/// gradient as splash_screen.dart, with the SeniorNest icon centered, no
/// wordmark. Used anywhere the app has a few seconds of async work with
/// nothing else to show -- app resume/cold start while the initial route
/// resolves, and the gap after "Create Account" while the auth provider
/// verifies -- instead of a black screen, a stale previous screen, or
/// nothing at all.
class BrandedTransitionScreen extends StatefulWidget {
  const BrandedTransitionScreen({super.key, this.showMessages = false});

  /// Oct 10 2026: when true, warm family phrases fade in under the dots
  /// (sign-in / account creation only). The phrase shown is derived from one
  /// shared start time, so the sign-in screen and the Home hold overlay show
  /// the same phrase and carry on seamlessly from one to the other.
  final bool showMessages;

  static DateTime? _messageEpoch;
  static bool get messagesActive => _messageEpoch != null;
  static void startMessages() => _messageEpoch = DateTime.now();
  static void stopMessages() => _messageEpoch = null;

  static const List<String> messages = [
    'Stay close to the people who matter most.',
    'One private place for your entire family.',
    'Make Nana feel loved every single day.',
    'Every story, saved for generations to come.',
  ];
  // First phrase waits a beat so a fast load never flashes text.
  static const Duration messageDelay = Duration(milliseconds: 1000);
  static const Duration messageInterval = Duration(milliseconds: 3000);

  // Minimum time this screen should stay visible before being replaced by
  // real content, even if the underlying work finishes faster -- long
  // enough to read as intentional rather than a flash, short enough not
  // to feel slow given this shows on every app open, not just once.
  // Callers (main.dart's cold-start gate, save_messages_prompt_screen.dart's
  // post-signup gate) are responsible for actually enforcing this by timing
  // their own async work against it; this constant just keeps both call
  // sites in agreement on the one shared value instead of duplicating it.
  // Sep 26 2026: briefly raised to 2500ms to make a warm, already-signed-in
  // relaunch hold this screen longer, then reverted back to 1500ms the same
  // day -- that change added a new floor-delay in main.dart's
  // _resolveInitialRoute() that reintroduced the Home skeleton-flash
  // regression on sign-in that build 264 had already fixed. Back to the
  // build-264-clean value; do not re-add a floor delay in main.dart without
  // re-verifying against that regression first.
  static const Duration minDisplayDuration = Duration(milliseconds: 1500);

  @override
  State<BrandedTransitionScreen> createState() =>
      _BrandedTransitionScreenState();
}

class _BrandedTransitionScreenState extends State<BrandedTransitionScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dots = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  Timer? _messageTimer;
  int _messageIndex = -1; // -1 = nothing shown yet

  int _currentIndex() {
    final epoch = BrandedTransitionScreen._messageEpoch;
    if (!widget.showMessages || epoch == null) return -1;
    final ms = DateTime.now().difference(epoch).inMilliseconds -
        BrandedTransitionScreen.messageDelay.inMilliseconds;
    if (ms < 0) return -1;
    return (ms ~/ BrandedTransitionScreen.messageInterval.inMilliseconds) %
        BrandedTransitionScreen.messages.length;
  }

  @override
  void initState() {
    super.initState();
    if (widget.showMessages) {
      _messageIndex = _currentIndex();
      _messageTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        final i = _currentIndex();
        if (i != _messageIndex && mounted) setState(() => _messageIndex = i);
      });
    }
  }

  @override
  void dispose() {
    _messageTimer?.cancel();
    _dots.dispose();
    super.dispose();
  }

  static const String _iconAsset = 'assets/images/nest_icon_transparent.png';

  // Same golden-green gradient as splash_screen.dart (candidate B, chosen
  // Aug 2026) -- D Von wants every logo-only transition moment (cold
  // start/resume, post-account-creation) using the same palette as the
  // splash/sign-in screen, not the earlier brown "mockup C" gradient.
  // Deliberately NOT applied to the actual onboarding flow screens
  // (role choice, senior/family onboarding, etc.) -- those keep their own
  // original near-white gradient, unrelated to this decision.
  static const Color _gradientTop = Color(0xFFE9F1EE);
  static const Color _gradientMiddle = Color(0xFFF3E7C4);
  static const Color _gradientBottom = Color(0xFFF8E9E1);

  @override
  Widget build(BuildContext context) {
    // Sized as a share of screen width (~31%, matching the approved
    // mockup's proportions: 336px icon on a 1080px-wide reference canvas),
    // capped so it doesn't balloon on tablets/large screens.
    final screenWidth = MediaQuery.of(context).size.width;
    final iconWidth = (screenWidth * 0.31).clamp(100.0, 180.0);

    return Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_gradientTop, _gradientMiddle, _gradientBottom],
          ),
        ),
        // Oct 9 2026 (build 287): per Flutter's animation guidance -- the
        // static gradient + logo live in their own RepaintBoundary (drawn
        // once, kept), and the dots are three FadeTransitions (paint-only,
        // no per-frame rebuild) inside another RepaintBoundary, so the
        // looping animation can never force the page underneath (Home
        // loading, Setup) to repaint every frame.
        child: Stack(
          children: [
            RepaintBoundary(
              child: Center(
                child: SizedBox(
                  width: iconWidth,
                  child: Image.asset(
                    _iconAsset,
                    fit: BoxFit.contain,
                    semanticLabel: 'SeniorNest',
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(
                        Icons.favorite_rounded,
                        color: Color(0xFFD4AA00),
                        size: 90,
                      );
                    },
                  ),
                ),
              ),
            ),
            Align(
              alignment: const Alignment(0, 0.32),
              child: RepaintBoundary(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 3; i++)
                      FadeTransition(
                        opacity: _dots.drive(_Pulse(i * 0.18)),
                        child: const _Dot(),
                      ),
                  ],
                ),
              ),
            ),
            if (widget.showMessages)
              Align(
                alignment: const Alignment(0, 0.52),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 36),
                  child: RepaintBoundary(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 600),
                      child: _messageIndex < 0
                          ? const SizedBox.shrink(key: ValueKey('none'))
                          : Text(
                              BrandedTransitionScreen.messages[_messageIndex],
                              key: ValueKey(_messageIndex),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.nunitoSans(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                                color: const Color(0xFF6B5B3E),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      margin: const EdgeInsets.symmetric(horizontal: 5),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFFD4AA00),
      ),
    );
  }
}

/// Soft up-and-down pulse (0.25 -> 1.0 -> 0.25) offset per dot.
class _Pulse extends Animatable<double> {
  _Pulse(this.offset);
  final double offset;

  @override
  double transform(double t) {
    final x = (t - offset) % 1.0;
    final wave = x < 0.5 ? x * 2 : (1 - x) * 2;
    return 0.25 + 0.75 * wave;
  }
}
