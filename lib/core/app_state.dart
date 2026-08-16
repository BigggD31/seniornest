import 'package:flutter/material.dart';


/// Global notifier — setup_screen writes here; MyApp rebuilds immediately.
final ValueNotifier<double> appTextScaleNotifier = ValueNotifier<double>(1.0);

/// Global dark-mode notifier — setup_screen writes here; MyApp switches ThemeMode.
final ValueNotifier<bool> appDarkModeNotifier = ValueNotifier<bool>(false);

/// Global nest-name notifier — resolved once in main.dart's
/// _resolveInitialRoute(), before any screen ever builds, same pattern as
/// appDarkModeNotifier above. Once someone has named their nest, that name
/// should appear everywhere instantly with nothing ever shown below it --
/// no "My Nest"/"Your Nest" placeholder flash, regardless of connection
/// speed. An earlier fix seeded each screen's own local nest-name field
/// from cache before starting its network re-check, which helped, but
/// still had a small unavoidable async gap (reading SharedPreferences
/// itself). This closes that gap completely: any screen that needs the
/// nest name reads this notifier's already-resolved value directly and
/// synchronously, the same way dark mode already works. Screens that
/// fetch a live, possibly-renamed value from Supabase should update this
/// notifier too, so every other screen picks up the change immediately.
final ValueNotifier<String> appNestNameNotifier = ValueNotifier<String>('');

/// Global returning-user notifier -- resolved once in main.dart's
/// _resolveInitialRoute(), before any screen ever builds, same pattern as
/// the two notifiers above. True when this device just signed out (the
/// only scenario where splash_screen needs to show a lean "Welcome back"
/// sign-in view instead of the full first-time pitch). Reading the
/// underlying just_signed_out flag asynchronously inside splash_screen
/// itself would flash the full pitch briefly before switching layouts --
/// exactly the class of bug fixed everywhere else tonight -- so it's
/// resolved here instead and read synchronously at field declaration.
final ValueNotifier<bool> appIsReturningUserNotifier = ValueNotifier<bool>(false);

/// Global nest-ownership notifier -- resolved once in main.dart's
/// _resolveInitialRoute(), before any screen ever builds, same pattern as
/// the notifiers above. Two screens (setup_screen and family_feed_screen)
/// each independently declared their own "bool _isNestOwner = false;" and
/// corrected it asynchronously after mount -- the exact flash-of-wrong-
/// content pattern documented Aug 14 2026 (Popy's role badge showing
/// "Member" for a frame before flipping to "Nest Owner"). One shared,
/// synchronously-readable source of truth fixes the flash on both screens
/// at once instead of patching each screen's timing independently, and
/// keeps them from ever disagreeing with each other.
final ValueNotifier<bool> appIsNestOwnerNotifier = ValueNotifier<bool>(false);

/// Global today's-check-in-status notifier -- resolved once in main.dart's
/// _resolveInitialRoute() from the existing date-scoped
/// cached_checkin_checked_in/cached_checkin_date prefs (see
/// family_feed_screen's _loadData for the original per-screen version of
/// this same scoping logic). Fixes the "I'm Good" button flashing on
/// screen for a frame before hiding, documented Aug 14 2026 -- same root
/// cause as appIsNestOwnerNotifier above: family_feed_screen declared
/// "bool _seniorCheckedInToday = false;" and only corrected it after an
/// async cache read that couldn't finish before the first frame painted.
final ValueNotifier<bool> appSeniorCheckedInTodayNotifier = ValueNotifier<bool>(false);

/// Suppresses the ambient KeyboardDoneBar/KeyboardDoneBarOverlay while a
/// single-line field with its own native "Done" key has focus. The bar
/// exists specifically for multi-line fields, where Return can't also mean
/// "close the keyboard" -- but because the bar is ambient (MediaQuery's
/// keyboard inset isn't scoped per-field), it was showing up even on
/// single-line fields that already have their own native done button,
/// producing two checkmark-style controls on screen at once. D Von
/// reported this on Setup's Rename Nest sheet (Aug 15 2026 build 171
/// follow-up). Single-line fields call suppressKeyboardBarWhileFocused()
/// on their FocusNode once, in initState, to opt into hiding the bar
/// while they're focused; nothing else needs to change at any call site.
final ValueNotifier<bool> appSuppressKeyboardDoneBarNotifier = ValueNotifier<bool>(false);

/// Attach to a single-line field's FocusNode (one that already has its own
/// native TextInputAction.done key) so the ambient KeyboardDoneBar hides
/// itself while that field is focused, instead of showing alongside the
/// native done key. Call once, in initState, right after creating the
/// FocusNode -- no other changes needed at the call site.
void suppressKeyboardBarWhileFocused(FocusNode node) {
  node.addListener(() {
    appSuppressKeyboardDoneBarNotifier.value = node.hasFocus;
  });
}

// ── Flash-of-wrong-content fix, rollout to remaining fields ──────────────
// Same pattern as appIsNestOwnerNotifier/appSeniorCheckedInTodayNotifier
// above, proven clean on-device (build 171). Each of these was previously
// declared independently, per-screen, as "bool _x = false;" -- a hardcoded
// guess corrected only after an async cache/network read finished, causing
// at least one wrong-content frame on every screen build. Resolved once in
// main.dart's _resolveInitialRoute() before any screen builds; screens read
// the notifier's value at field declaration instead of guessing, and write
// the real value back once their own live check resolves.

/// isSenior was independently duplicated across 5 screens (family_feed,
/// legacy, safety, send, setup), all deriving it from the same
/// prefs.getString('user_role') key -- one shared notifier fixes the flash
/// in all 5 at once instead of five separate patches.
final ValueNotifier<bool> appIsSeniorNotifier = ValueNotifier<bool>(false);

final ValueNotifier<bool> appIsGuestNotifier = ValueNotifier<bool>(false);
final ValueNotifier<bool> appHasRealPostNotifier = ValueNotifier<bool>(false);
final ValueNotifier<bool> appHasSentStoriesNotifier = ValueNotifier<bool>(false);
final ValueNotifier<bool> appIsVipMemberNotifier = ValueNotifier<bool>(false);

/// Date-scoped like appSeniorCheckedInTodayNotifier -- only meaningful for
/// today, resolved from the same cached_checkin_* prefs family.
final ValueNotifier<bool> appSeniorMedsTakenTodayNotifier = ValueNotifier<bool>(false);

/// Found while investigating D Von's screenshot (build 172, Aug 15): the
/// floating "I'm Good" button's own visibility flag (_isGoodTodaySent) had
/// the exact same hardcoded-false-default pattern as everything else in
/// this section, but got missed in the original rollout since it's driven
/// by a separate local-only prefs key (good_today_*) rather than the
/// cached_checkin_* family the other notifiers share. Date-scoped like the
/// others; resolved from the same key family_feed_screen.dart itself
/// writes to (see _todayKey() there for the exact date-string format this
/// must match).
final ValueNotifier<bool> appIsGoodTodaySentNotifier = ValueNotifier<bool>(false);

/// Maps the stored string to a TextScaler multiplier.
double textSizeToScale(String size) {
  switch (size) {
    case 'Large':
      return 1.2;
    case 'Extra Large':
      return 1.45;
    default:
      return 1.0; // Normal
  }
}
