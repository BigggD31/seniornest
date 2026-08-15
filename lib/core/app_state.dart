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
