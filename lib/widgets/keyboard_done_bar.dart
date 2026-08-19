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
const double kDoneBarBleed = 24;

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
  double _stableInset = 0;

  // Aug 18 2026, build 187: iOS lets you interactively drag the real
  // system keyboard down with your finger from content sitting right
  // above it -- and while that drag is happening,
  // MediaQuery.viewInsets.bottom reports the keyboard's live, shrinking
  // height frame by frame. Since this bar's position and visibility used
  // to be driven directly off that live value every build, a normal
  // scroll gesture on the sheet's own content (trying to see what you'd
  // just typed) could accidentally register as this native
  // drag-to-dismiss, and the bar would visibly ride down with your
  // finger, then vanish -- reported by D Von on both Setup and Legacy.
  //
  // A first attempt (build 186) only DELAYED a partial drag position by
  // 150ms instead of preventing it -- if the drag paused even briefly
  // (exactly what happens mid-gesture, or when a screenshot gets taken to
  // show the bug), the delay elapsed and the bar committed to the paused
  // position anyway. D Von confirmed this was still happening after 186.
  //
  // This version is stricter: a decrease is NEVER accepted unless it's a
  // clean drop to exactly 0 (a real, decisive dismiss). Any other
  // decrease -- a partial, in-progress height while a drag is still
  // happening -- is ignored outright, forever, not just delayed, until
  // the inset either grows again (keyboard reopening/expanding) or hits 0
  // (a complete dismiss). Trade-off: if the keyboard's real height
  // legitimately gets smaller for a non-drag reason without fully closing
  // first, the bar sits slightly high above it until the keyboard fully
  // closes and reopens -- a minor cosmetic gap, versus the bar visibly
  // chasing your finger during an ordinary scroll.
  //
  // NOTE: this is the same category of change that broke the bar entirely
  // in build 181 (a stateful settle-delay caused it to never render at
  // all, not just late). Test this thoroughly on-device before trusting
  // it (open keyboard, type, drag-scroll to see typed text, cancel a
  // drag partway, and tap Done) given that history.
  void _handleInset(double liveInset) {
    if (liveInset == _stableInset) return;
    final bool respondImmediately =
        liveInset >= _stableInset || liveInset == 0;
    if (!respondImmediately) return;
    setState(() => _stableInset = liveInset);
  }

  @override
  Widget build(BuildContext context) {
    final double liveInset = MediaQuery.of(context).viewInsets.bottom;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _handleInset(liveInset);
    });

    final bool keyboardVisible = _stableInset > 0;
    final double barBottomOffset =
        widget.alreadyPaddedForKeyboard ? 0 : _stableInset;

    return Stack(
      children: [
        widget.child,
        if (keyboardVisible)
          ValueListenableBuilder<bool>(
            valueListenable: appSuppressKeyboardDoneBarNotifier,
            builder: (context, suppressed, _) {
              if (suppressed) return const SizedBox.shrink();
              return Positioned(
                left: 0,
                right: 0,
                bottom: barBottomOffset - kDoneBarBleed,
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
  double _stableInset = 0;

  // Aug 18 2026, build 187: same stricter fix as KeyboardDoneBar's
  // _handleInset -- see that class's comment for the full explanation.
  // Applied here too since Share's compose field has the same live
  // keyboard-height tracking and showed the same symptom.
  void _handleInset(double liveInset) {
    if (liveInset == _stableInset) return;
    final bool respondImmediately =
        liveInset >= _stableInset || liveInset == 0;
    if (!respondImmediately) return;
    setState(() => _stableInset = liveInset);
  }

  @override
  Widget build(BuildContext context) {
    final double liveInset =
        widget.rawBottomInset ?? MediaQuery.of(context).viewInsets.bottom;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _handleInset(liveInset);
    });

    if (_stableInset <= 0) return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: appSuppressKeyboardDoneBarNotifier,
      builder: (context, suppressed, _) {
        if (suppressed) return const SizedBox.shrink();
        return Positioned(
          left: 0,
          right: 0,
          bottom: widget.positionAtZero
              ? 0
              : (_stableInset - kDoneBarBleed),
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
