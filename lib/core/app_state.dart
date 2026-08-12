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
