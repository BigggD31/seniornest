import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_state.dart';

// The bar's top corners are rounded (against the sheet above it) but its
// bottom corners are square. iOS's own keyboard has ROUNDED top corners --
// so wherever the bar sits flush against the keyboard, that shape mismatch
// left a small gap at both bottom corners where whatever was behind the bar
// showed through. Confirmed by D Von on Setup, Legacy, AND Share (Aug 18
// 2026) via zoomed screenshots -- this is not one screen's bug, it's the
// bar's own shape not fully covering the keyboard's shape everywhere it's
// used. Fix: extend the bar's solid color straight down past where the
// keyboard's rounded corners curve inward, so there's fill color behind
// that curve regardless of the keyboard's exact shape, instead of trying to
// make the bar's corners match the keyboard's corners exactly. This extra
// strip sits behind the keyboard for its full width except at the two
// rounded corners, where it's what actually shows through.
// D Von confirmed the Share corner gap persisted even after fixing the
// Stack clipping (build 189) -- both that fix and this bleed amount were
// genuinely in place, so 24px itself just wasn't covering how far the
// real keyboard's corner actually curves in. Less noticeable in light
// mode where the bar and background colors are closer together; in dark
// mode the contrast between the near-black background and the dark gray
// bar made the same gap much more obvious. Bumped generously -- this is
// always hidden behind the real keyboard regardless of screen, so an
// oversized value is harmless everywhere it's used.
const double kDoneBarBleed = 60;

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
class KeyboardDoneBar extends StatefulWidget {
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
  State<KeyboardDoneBar> createState() => _KeyboardDoneBarState();
}

class _KeyboardDoneBarState extends State<KeyboardDoneBar> {
  double _targetInset = 0;
  bool _pointerDown = false;

  @override
  void initState() {
    super.initState();
    // Tracks whether a touch is CURRENTLY active anywhere on screen, using
    // Flutter's global pointer router rather than a GestureDetector -- this
    // way it works regardless of where in `child` the touch happens,
    // without needing to restructure that content at all. See
    // _handleInset below for why this distinction matters.
    GestureBinding.instance.pointerRouter.addGlobalRoute(_handlePointerEvent);
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter
        .removeGlobalRoute(_handlePointerEvent);
    super.dispose();
  }

  void _handlePointerEvent(PointerEvent event) {
    if (event is PointerDownEvent) {
      _pointerDown = true;
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _pointerDown = false;
    }
  }

  // Aug 19 2026, build 191: builds 186/187 tried to solve two DIFFERENT
  // problems with one blunt rule ("never accept a decrease unless it hits
  // exactly 0"), and that rule broke a case it was never meant to touch.
  //
  // Problem 1 (real, needed fixing): iOS lets you interactively drag the
  // real keyboard down with a touch on content sitting above it, and
  // MediaQuery.viewInsets.bottom reports that drag's live, shrinking
  // height frame by frame -- so an ordinary scroll gesture could
  // accidentally register as this native drag-to-dismiss, and the bar
  // would ride down with it.
  //
  // Problem 2 (accidentally introduced by the fix for problem 1): a
  // NORMAL keyboard-close animation -- tapping Done, no touch involved at
  // all -- ALSO produces a smoothly decreasing sequence of values before
  // landing on 0. The old rule ignored every one of those too, freezing
  // the bar in its old position for the ~250ms the real keyboard takes to
  // animate away, then snapping it only at the very last instant --
  // exactly the floating, disconnected bar D Von's screenshots showed.
  //
  // Researched the standard fix rather than patching this blind (D Von's
  // explicit ask): Flutter's own docs and a real flutter/flutter GitHub
  // issue (#19279, "soft keyboard animation unsynchronized with Flutter
  // resize animation") both point to the same pattern -- bind position
  // directly to the live inset via AnimatedPositioned/AnimatedContainer
  // and let Flutter's own implicit animation smooth the transition,
  // rather than hand-rolling accept/reject logic on the raw numbers.
  //
  // Combined fix: only freeze during an ACTIVE touch (tracked above via
  // the global pointer router) -- that's the actual signal that
  // distinguishes "you're dragging" from "the keyboard is just
  // animating closed on its own," which a raw sequence of numbers alone
  // can never tell apart. Every other transition (open, close via Done,
  // close via losing focus some other way) updates the target immediately
  // and lets AnimatedPositioned below animate it smoothly, instead of
  // freezing and jumping.
  void _handleInset(double liveInset) {
    if (liveInset == _targetInset) return;
    final bool isGrowingOrFullyClosed =
        liveInset >= _targetInset || liveInset == 0;
    if (_pointerDown && !isGrowingOrFullyClosed) return;
    setState(() => _targetInset = liveInset);
  }

  @override
  Widget build(BuildContext context) {
    final double liveInset = MediaQuery.of(context).viewInsets.bottom;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _handleInset(liveInset);
    });

    final double barBottomOffset =
        widget.alreadyPaddedForKeyboard ? 0 : _targetInset;

    return Stack(
      children: [
        widget.child,
        ValueListenableBuilder<bool>(
          valueListenable: appSuppressKeyboardDoneBarNotifier,
          builder: (context, suppressed, _) {
            if (suppressed) return const SizedBox.shrink();
            // Always present in the tree now (rather than conditionally
            // included via `if (keyboardVisible)`) so AnimatedPositioned
            // has something to animate FROM when the keyboard closes --
            // conditionally removing it the instant the target hit 0 was
            // exactly what caused the old jump-to-frozen-position issue.
            // Sits off-screen at -200 when there's no keyboard to show
            // above.
            return AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              left: 0,
              right: 0,
              bottom: _targetInset > 0
                  ? (barBottomOffset - kDoneBarBleed)
                  : -200,
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
class KeyboardDoneBarOverlay extends StatefulWidget {
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
  State<KeyboardDoneBarOverlay> createState() =>
      _KeyboardDoneBarOverlayState();
}

class _KeyboardDoneBarOverlayState extends State<KeyboardDoneBarOverlay> {
  double _targetInset = 0;
  bool _pointerDown = false;

  @override
  void initState() {
    super.initState();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_handlePointerEvent);
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter
        .removeGlobalRoute(_handlePointerEvent);
    super.dispose();
  }

  void _handlePointerEvent(PointerEvent event) {
    if (event is PointerDownEvent) {
      _pointerDown = true;
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _pointerDown = false;
    }
  }

  // Aug 19 2026, build 191: same fix as KeyboardDoneBar's _handleInset --
  // see that class's comment for the full explanation and research
  // sources. Applied here too since Share's compose field has the same
  // live keyboard-height tracking and showed the same disconnected-bar
  // symptom on Done.
  void _handleInset(double liveInset) {
    if (liveInset == _targetInset) return;
    final bool isGrowingOrFullyClosed =
        liveInset >= _targetInset || liveInset == 0;
    if (_pointerDown && !isGrowingOrFullyClosed) return;
    setState(() => _targetInset = liveInset);
  }

  @override
  Widget build(BuildContext context) {
    final double liveInset =
        widget.rawBottomInset ?? MediaQuery.of(context).viewInsets.bottom;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _handleInset(liveInset);
    });

    return ValueListenableBuilder<bool>(
      valueListenable: appSuppressKeyboardDoneBarNotifier,
      builder: (context, suppressed, _) {
        if (suppressed) return const SizedBox.shrink();
        // Always present now, same reasoning as KeyboardDoneBar above --
        // sits off-screen at -200 when there's no keyboard to show above.
        return AnimatedPositioned(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          left: 0,
          right: 0,
          bottom: _targetInset > 0
              ? (widget.positionAtZero ? 0 : (_targetInset - kDoneBarBleed))
              : -200,
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
    //
    // Aug 18 2026, build 187: this was hardcoded to #D0D3D9 (the real
    // light-mode keyboard gray, measured from D Von's screenshot) with no
    // awareness of dark mode -- so in dark mode the bar rendered that same
    // light color sitting directly above the REAL dark keyboard (measured
    // at #373532 from D Von's dark-mode screenshot), clashing badly. Now
    // reads appDarkModeNotifier (the same app-wide dark mode flag every
    // other themed screen uses) and swaps to the measured dark value.
    return ValueListenableBuilder<bool>(
      valueListenable: appDarkModeNotifier,
      builder: (context, isDarkMode, _) {
        final Color barColor =
            isDarkMode ? const Color(0xFF373532) : const Color(0xFFD0D3D9);
        return Container(
          // Solid fill strip, same color as the visible bar, extending the
          // full kDoneBarBleed amount further down (see that constant's
          // comment). This sits behind the keyboard for its entire width
          // except at the two rounded bottom corners of the visible bar
          // above -- that's the gap this is closing. Rounded on top to
          // match the inner bar's own top radius (D Von caught this:
          // without matching radius here, this outer rectangle's square
          // top edge is what's actually visible against the sheet above,
          // since it's the same color as the rounded bar inside it -- the
          // eye can't tell the two shapes apart, so the rounded corner was
          // invisible even though the inner bar still had it). Flat on the
          // bottom on purpose -- that's the edge meant to bleed into the
          // keyboard.
          padding: const EdgeInsets.only(bottom: kDoneBarBleed),
          decoration: BoxDecoration(
            color: barColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onDone,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(13)),
              child: Container(
                // Aug 18 2026, fifth design pass: D Von asked to match the
                // bar's color to the real iOS keyboard gray so the bar
                // blends in and doesn't read as a separate element at all
                // -- only "Done" and the checkmark stay visible, both bold
                // teal. No shadow here either: a shadow line would itself
                // be a visible seam against a keyboard-matched background,
                // working against the point of blending in.
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: barColor,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(13)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'Done',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF4A8A80),
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
          ),
        );
      },
    );
  }
}
