import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_state.dart';

/// Wraps [child] so that whenever the keyboard is open, a thin bar with a
/// blue checkmark "Done" button is pinned directly above the keyboard.
/// Tapping it dismisses the keyboard only — it does NOT submit/clear the
/// field, and it does not interfere with the Return key (multi-line fields
/// keep inserting line breaks normally).
///
/// This matches the standard iOS "keyboard accessory bar" pattern (seen in
/// Notes, Messages, Instagram, etc.) so every text field in the app gets an
/// identical, familiar way to close the keyboard.
///
/// Stays hidden while appSuppressKeyboardDoneBarNotifier is true -- see
/// app_state.dart's suppressKeyboardBarWhileFocused() for why: single-line
/// fields already have their own native "Done" key, and without this check
/// this bar would show up alongside it, producing two checkmark-style
/// controls on screen at once.
class KeyboardDoneBar extends StatelessWidget {
  final Widget child;

  const KeyboardDoneBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final bool keyboardVisible = bottomInset > 0;

    return Stack(
      children: [
        child,
        if (keyboardVisible)
          ValueListenableBuilder<bool>(
            valueListenable: appSuppressKeyboardDoneBarNotifier,
            builder: (context, suppressed, _) {
              if (suppressed) return const SizedBox.shrink();
              return Positioned(
                left: 0,
                right: 0,
                bottom: bottomInset,
                child: _DoneBar(
                  onDone: () => FocusScope.of(context).unfocus(),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// For screens that already have their own root [Stack] (so wrapping with
/// [KeyboardDoneBar] would create a redundant nested Stack). Drop this in
/// as one more child of that existing Stack — it positions itself and
/// hides itself automatically when the keyboard is closed, or when
/// appSuppressKeyboardDoneBarNotifier is true (see KeyboardDoneBar above).
class KeyboardDoneBarOverlay extends StatelessWidget {
  // If the Scaffold this overlay lives inside has
  // resizeToAvoidBottomInset: true, the Scaffold itself already consumes
  // the keyboard's height to shrink its body -- by the time this widget's
  // own context reads MediaQuery.of(context).viewInsets.bottom, it's
  // already been reduced to 0, so the overlay would incorrectly render
  // nothing even with the keyboard open. D Von caught this on the Share
  // screen (build 173): the bar was genuinely never showing at all, not
  // just hidden underneath something. Screens with that Scaffold setting
  // need to capture the real inset from a context ABOVE the Scaffold's
  // resize boundary (e.g. the outer build(BuildContext context) method,
  // before the Scaffold is constructed) and pass it here explicitly.
  final double? rawBottomInset;

  const KeyboardDoneBarOverlay({super.key, this.rawBottomInset});

  @override
  Widget build(BuildContext context) {
    final double bottomInset =
        rawBottomInset ?? MediaQuery.of(context).viewInsets.bottom;
    if (bottomInset <= 0) return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: appSuppressKeyboardDoneBarNotifier,
      builder: (context, suppressed, _) {
        if (suppressed) return const SizedBox.shrink();
        return Positioned(
          left: 0,
          right: 0,
          bottom: bottomInset,
          child: _DoneBar(
            onDone: () => FocusScope.of(context).unfocus(),
          ),
        );
      },
    );
  }
}

class _DoneBar extends StatelessWidget {
  final VoidCallback onDone;

  const _DoneBar({required this.onDone});

  @override
  Widget build(BuildContext context) {
    // D Von's design pass, Aug 16 2026: the previous bar was a plain iOS
    // system-gray-and-blue default, which read as generic/unbranded next
    // to the rest of the app. Same colors as everywhere else in
    // SeniorNest -- the warm cream surface + cardBorder used on every
    // card (app_theme.dart), and the established teal (#5DA399) used for
    // every other primary action in the app, not iOS's default blue.
    // Whole bar is tappable, not just the pill -- a larger, more forgiving
    // touch target given SeniorNest's older-adult audience.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onDone,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F0E8),
            border: const Border(
              top: BorderSide(color: Color(0xFFE8E0D0), width: 1),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(15),
                blurRadius: 6,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF5DA399),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Done',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
