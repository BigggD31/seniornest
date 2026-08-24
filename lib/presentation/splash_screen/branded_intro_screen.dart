import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Aug 20 2026: D Von's ask -- a short sequence of full-bleed marketing
// photos (his own wording already baked into each image, nothing else
// drawn on top) shown before the real splash/pitch screen. Each one
// advances on tap, or automatically after ~2.5s if nobody touches it.
// Built as one reusable widget rather than one-off screens per image,
// since D Von's plan is "build one, then just give you a different photo
// for the next one" -- IntroSequenceScreen below takes a plain list of
// asset paths, so adding a second (or third) slide later is a one-line
// change, not new screens.

class BrandedIntroSlide extends StatefulWidget {
  const BrandedIntroSlide({
    super.key,
    required this.imagePath,
    required this.onAdvance,
    this.autoAdvanceDelay = const Duration(milliseconds: 2500),
  });

  final String imagePath;
  final VoidCallback onAdvance;
  final Duration autoAdvanceDelay;

  @override
  State<BrandedIntroSlide> createState() => _BrandedIntroSlideState();
}

class _BrandedIntroSlideState extends State<BrandedIntroSlide> {
  bool _advanced = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.autoAdvanceDelay, _advance);
  }

  // Guards against both the timer AND a tap firing in the same frame
  // (e.g. a tap landing right as the timer elapses) -- onAdvance should
  // only ever run once per slide.
  void _advance() {
    if (_advanced || !mounted) return;
    _advanced = true;
    widget.onAdvance();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _advance,
      behavior: HitTestBehavior.opaque,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(
          child: Image.asset(
            widget.imagePath,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}

class IntroSequenceScreen extends StatefulWidget {
  const IntroSequenceScreen({
    super.key,
    required this.imagePaths,
    required this.builder,
  });

  // One entry per slide, in order. Empty list skips straight to the real
  // screen -- safe default if this is ever reused somewhere without
  // slides configured yet.
  final List<String> imagePaths;

  // Builds the real screen (SplashScreen today) shown once every slide
  // has been advanced past.
  final WidgetBuilder builder;

  @override
  State<IntroSequenceScreen> createState() => _IntroSequenceScreenState();
}

class _IntroSequenceScreenState extends State<IntroSequenceScreen> {
  int _index = 0;
  bool _markedSeen = false;

  void _advance() {
    if (!mounted) return;
    setState(() => _index++);
    if (_index >= widget.imagePaths.length) {
      _markSeenOnce();
    }
  }

  // Aug 21 2026: writes a permanent, device-scoped "this device has seen
  // the intro" flag exactly once, the moment the sequence genuinely
  // completes (last slide advanced past). Deliberately a brand new key,
  // never has_onboarded -- that one turned out to be account-scoped
  // (cleared on sign-out, account switch, and account deletion
  // elsewhere in the app), which was the actual reason the intro kept
  // reappearing for D Von even on a device he'd used many times before.
  // This key is never included in any of that clearing logic anywhere,
  // by design -- it means "this physical device," not "this account."
  Future<void> _markSeenOnce() async {
    if (_markedSeen) return;
    _markedSeen = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_intro_sequence', true);
  }

  @override
  Widget build(BuildContext context) {
    if (_index >= widget.imagePaths.length) {
      return widget.builder(context);
    }
    return BrandedIntroSlide(
      // Keying by index forces a fresh State (and a fresh 2.5s timer)
      // for each slide -- without this, Flutter could reuse the same
      // State object across slides since they're the same widget type,
      // and the old timer/tap-guard would carry over incorrectly.
      key: ValueKey(_index),
      imagePath: widget.imagePaths[_index],
      onAdvance: _advance,
    );
  }
}
