import 'package:flutter/material.dart';


/// Global notifier — setup_screen writes here; MyApp rebuilds immediately.
final ValueNotifier<double> appTextScaleNotifier = ValueNotifier<double>(1.0);

/// Global dark-mode notifier — setup_screen writes here; MyApp switches ThemeMode.
final ValueNotifier<bool> appDarkModeNotifier = ValueNotifier<bool>(false);

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
