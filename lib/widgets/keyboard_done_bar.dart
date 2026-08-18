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

  // Set true when [child] already reserves its own bottom padding equal to
  // the keyboard height (a common modal pattern: `padding: EdgeInsets.only(
  // bottom: 24 + MediaQuery.of(context).viewInsets.bottom)`). In that case
  // [child]'s own bottom edge already sits exactly where the bar should go
  // -- adding this widget's own `bottom: bottomInset` offset on TOP of that
  // double-counts the keyboard height, pushing the bar up far too high
  // (roughly a full keyboard-height above where it should sit). D Von
  // caught this on Setup's Rename Nest, Legacy's Write Your Story, and
  // Share's compose panel (Aug 16 2026, build 175) -- the bar was floating
  // disconnected from the modal's own content in every one of them, all
  // for this same reason. Default false preserves the correct behavior
  // for content that does NOT pre-pad for the keyboard.
  final bool alreadyPaddedForKeyboard;

  const KeyboardDoneBar({
    super.key,
    required this.child,
    this.alreadyPaddedForKeyboard = false,
  });

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final bool keyboardVisible = bottomInset > 0;
    final double barBottomOffset =
        alreadyPaddedForKeyboard ? 0 : bottomInset;

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
                bottom: barBottomOffset,
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
  // just hidden underneath something.
  final double? rawBottomInset;

  // Some screens (Share) already have their OWN body correctly shrunk to
  // align with the keyboard via resizeToAvoidBottomInset: true -- proven
  // by an existing, working dismiss button on that exact screen sitting
  // flush at bottom: 0 with no extra offset at all. Passing rawBottomInset
  // for POSITIONING in that case double-counts the keyboard height (the
  // frame is already shrunk to end right at the keyboard's top, then this
  // widget's own offset pushes it up a full keyboard-height further) --
  // exactly what D Von saw floating disconnected above Share's tabs,
  // Aug 16 2026. When true, sits flush at bottom: 0 like that dismiss
  // button; rawBottomInset is still used to decide whether to show at all.
  final bool positionAtZero;

  const KeyboardDoneBarOverlay({
    super.key,
    this.rawBottomInset,
    this.positionAtZero = false,
  });

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
          bottom: positionAtZero ? 0 : bottomInset,
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
    // D Von's third design pass, Aug 17 2026: the plain-text version from
    // the second pass read as "too faint" and, worse, was found to be
    // genuinely invisible on plain white modals (Setup's Rename Nest) --
    // near-white on near-white gave zero contrast, unlike Share's warmer
    // cream background which happened to show just enough of it. This
    // version fixes both: a background that stays visible regardless of
    // what's behind it (light warm tint, not matched to any one screen),
    // bold gold "Done" text (the established app gold, #D4AA00 --
    // distinct from the gray text around it, per D Von's request), and a
    // small contained teal checkmark badge instead of a bare icon that
    // was easy to miss entirely.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onDone,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            color: Color(0xFFFAF6EC),
            // Rounded top corners to visually match the rounding on
            // iOS's own gray keyboard directly below this bar, per
            // D Von's direct request (Aug 17 2026) -- 13px matches the
            // system keyboard's own corner radius.
            borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
            border: Border(
              top: BorderSide(color: Color(0xFFE8E0D0), width: 1),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                'Done',
                style: GoogleFonts.nunitoSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFD4AA00),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: Color(0xFF4A8A80),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
