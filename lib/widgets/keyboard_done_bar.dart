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
  // D Von kept seeing NO bar at all, consistently, specifically on
  // single-line fields like Setup's Rename Nest -- not intermittently,
  // every time. Researched this (Aug 18 2026): confirmed, current,
  // still-open Apple bugs (reported as recently as June 2026 on Apple's
  // own developer forums) where a custom keyboard accessory view can
  // fail to attach the very first time a field gets focus in a newly
  // presented sheet -- "if I background the app and return, the toolbar
  // appears as expected." Single-line and multi-line text fields use
  // different underlying native iOS input types, which plausibly
  // explains why this hit Rename Nest far more reliably than Share's
  // multi-line message field. This is a real, still-open platform bug,
  // not something fixable by matching code alone -- this delay gives
  // iOS's own keyboard-appearance animation a moment to settle before
  // the bar tries to attach, which is the documented mitigation.
  bool _readyToShow = false;
  bool _wasKeyboardVisible = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final keyboardVisible = bottomInset > 0;
    if (keyboardVisible && !_wasKeyboardVisible) {
      _readyToShow = false;
      Future.delayed(const Duration(milliseconds: 220), () {
        if (mounted) setState(() => _readyToShow = true);
      });
    } else if (!keyboardVisible) {
      _readyToShow = false;
    }
    _wasKeyboardVisible = keyboardVisible;
  }

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final bool keyboardVisible = bottomInset > 0;
    final double barBottomOffset =
        widget.alreadyPaddedForKeyboard ? 0 : bottomInset;

    return Stack(
      children: [
        widget.child,
        if (keyboardVisible && _readyToShow)
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
  State<KeyboardDoneBarOverlay> createState() => _KeyboardDoneBarOverlayState();
}

class _KeyboardDoneBarOverlayState extends State<KeyboardDoneBarOverlay> {
  // Same settle-delay mitigation as KeyboardDoneBar -- see that class's
  // comment for the full explanation (confirmed, still-open Apple bugs
  // around keyboard accessory view attachment timing, Aug 18 2026).
  bool _readyToShow = false;
  bool _wasKeyboardVisible = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bottomInset =
        widget.rawBottomInset ?? MediaQuery.of(context).viewInsets.bottom;
    final keyboardVisible = bottomInset > 0;
    if (keyboardVisible && !_wasKeyboardVisible) {
      _readyToShow = false;
      Future.delayed(const Duration(milliseconds: 220), () {
        if (mounted) setState(() => _readyToShow = true);
      });
    } else if (!keyboardVisible) {
      _readyToShow = false;
    }
    _wasKeyboardVisible = keyboardVisible;
  }

  @override
  Widget build(BuildContext context) {
    final double bottomInset =
        widget.rawBottomInset ?? MediaQuery.of(context).viewInsets.bottom;
    if (bottomInset <= 0 || !_readyToShow) return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: appSuppressKeyboardDoneBarNotifier,
      builder: (context, suppressed, _) {
        if (suppressed) return const SizedBox.shrink();
        return Positioned(
          left: 0,
          right: 0,
          bottom: widget.positionAtZero ? 0 : bottomInset,
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
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFD9C9A5),
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
                'Done',
                style: GoogleFonts.nunitoSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFD4AA00),
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
