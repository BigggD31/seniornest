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

  // Aug 18 2026, build 181 revert: this widget was briefly converted to a
  // StatefulWidget with a 220ms "settle delay" before showing the bar, to
  // work around a theorized iOS accessory-view timing bug. D Von tested
  // build 181 across three separate screens (Legacy Write Your Story,
  // Setup Rename Nest, Share compose) and the bar did not appear AT ALL on
  // any of them -- not delayed, genuinely absent. That conversion was the
  // only functional change to this shared widget between build 180 (bar
  // confirmed working, pending only a visual redesign) and 181 (bar gone
  // everywhere) -- send_screen.dart itself had zero changes in that same
  // window. Reverting to immediate Stateless rendering, matching the last
  // point this was known to actually render, to isolate whether this
  // mechanism was the cause. Do not reintroduce a delay here without
  // confirming on-device first.
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

  // Aug 18 2026, build 181 revert: reverted back to immediate Stateless
  // rendering along with KeyboardDoneBar above -- see that class's comment
  // for the full explanation. The settle-delay conversion was the only
  // functional change to this shared widget between build 180 (bar
  // confirmed working) and 181 (bar absent on every tested screen).
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
    // D Von's fourth design pass, Aug 18 2026: two real bugs found in the
    // third pass, not just taste. (1) The darkened background (#CDC9C1)
    // read as flat gray, not the warm gold-family tone D Von asked for --
    // scaling all three RGB channels down by the same percentage shrinks
    // the R-vs-B spread that actually reads as "warm" to the eye, so a
    // uniformly-darkened neutral tends toward gray even though the math
    // says "same color, just darker." Fixed by choosing a tan with a much
    // wider R/G/B spread instead of just scaling the old value down.
    // (2) The bar showed up "fragmented, with parts with no fill color"
    // -- a known Flutter rendering conflict: a Border that only specifies
    // one side (top) combined with a rounded BoxDecoration produces
    // exactly this kind of broken-looking corner artifact. Removed the
    // border entirely, replaced with a soft shadow for separation, which
    // doesn't have this conflict. Also bumped Done/checkmark size and
    // weight per direct request -- both were still reading as too small.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onDone,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
        child: Container(
          // TEMP DIAGNOSTIC (build 183) -- deliberately hot pink and taller
          // than the real design so it is impossible to mistake for "just
          // styled oddly." D Von reported this bar is completely absent on
          // Legacy's Write Your Story and Setup's Rename Nest despite a
          // prior fix (commit d5ccfbf, already in build 182) that should
          // have made it appear. This marker answers one question only:
          // does ANYTHING from this widget paint on those two screens at
          // all? Revert to the real #D9C9A5 design once that's confirmed
          // either way -- do not ship this color.
          height: 70,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFFF00AA),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(20),
                blurRadius: 4,
                offset: const Offset(0, -1),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                'BAR TEST 183',
                style: GoogleFonts.nunitoSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: Color(0xFF4A8A80),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
