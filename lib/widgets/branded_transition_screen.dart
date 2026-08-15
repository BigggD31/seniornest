import 'package:flutter/material.dart';

/// Shared branded loading/transition screen: the same golden-green
/// gradient as splash_screen.dart, with the SeniorNest icon centered, no
/// wordmark. Used anywhere the app has a few seconds of async work with
/// nothing else to show -- app resume/cold start while the initial route
/// resolves, and the gap after "Create Account" while the auth provider
/// verifies -- instead of a black screen, a stale previous screen, or
/// nothing at all.
class BrandedTransitionScreen extends StatelessWidget {
  const BrandedTransitionScreen({super.key});

  // Minimum time this screen should stay visible before being replaced by
  // real content, even if the underlying work finishes faster -- long
  // enough to read as intentional rather than a flash, short enough not
  // to feel slow given this shows on every app open, not just once.
  // Callers (main.dart's cold-start gate, save_messages_prompt_screen.dart's
  // post-signup gate) are responsible for actually enforcing this by timing
  // their own async work against it; this constant just keeps both call
  // sites in agreement on the one shared value instead of duplicating it.
  static const Duration minDisplayDuration = Duration(milliseconds: 1500);

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
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_gradientTop, _gradientMiddle, _gradientBottom],
          ),
        ),
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
    );
  }
}
