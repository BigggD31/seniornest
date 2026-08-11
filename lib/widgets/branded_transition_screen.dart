import 'package:flutter/material.dart';

/// Shared branded loading/transition screen, approved design (mockup C):
/// a warm mid-tone gradient (not light, not dark) with the SeniorNest
/// icon centered, no wordmark. Used anywhere the app has a few seconds
/// of async work with nothing else to show -- app resume/cold start
/// while the initial route resolves, and the gap after "Create Account"
/// while the auth provider verifies -- instead of a black screen, a
/// stale previous screen, or nothing at all.
class BrandedTransitionScreen extends StatelessWidget {
  const BrandedTransitionScreen({super.key});

  static const String _iconAsset = 'assets/images/nest_icon_transparent.png';

  // Approved gradient from mockup C -- warm mid-tone, gold-leaning.
  static const Color _gradientTop = Color(0xFFC9BC9E);
  static const Color _gradientBottom = Color(0xFF8A7B5E);

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
            colors: [_gradientTop, _gradientBottom],
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
