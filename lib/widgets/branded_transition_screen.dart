import 'package:flutter/material.dart';

/// Shared branded loading/transition screen: the same golden-green
/// gradient as splash_screen.dart, with the SeniorNest icon centered, no
/// wordmark. Used anywhere the app has a few seconds of async work with
/// nothing else to show -- app resume/cold start while the initial route
/// resolves, and the gap after "Create Account" while the auth provider
/// verifies -- instead of a black screen, a stale previous screen, or
/// nothing at all.
class BrandedTransitionScreen extends StatefulWidget {
  const BrandedTransitionScreen({super.key});

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

  @override
  void dispose() {
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
