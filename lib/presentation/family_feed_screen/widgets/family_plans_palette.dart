import 'package:flutter/material.dart';

/// Nov 7 2026: the Family Plans look from the approved mockup (terracotta
/// on warm cream), with a dark-mode version of each color. Used by the
/// Plans tab, its sheets, and the Home tab strip.
class PlansPalette {
  const PlansPalette(this.dark);
  final bool dark;

  /// Buttons, selected tab, selected options.
  Color get accent => dark ? const Color(0xFFD0623F) : const Color(0xFFB94A2A);

  /// Text and icons that sit on a [tint] background.
  Color get deep => dark ? const Color(0xFFF2B8A0) : const Color(0xFF8A3A1F);

  /// Soft terracotta wash (date block, selected poll option).
  Color get tint => dark ? const Color(0xFF3A2620) : const Color(0xFFF9E4DA);

  /// Background of the tab strip.
  Color get track => dark ? const Color(0xFF2A241D) : const Color(0xFFF1E3D3);

  /// The selected tab (white pill in light mode).
  Color get tabSelected =>
      dark ? const Color(0xFF3D342B) : const Color(0xFFFFFFFF);

  /// Page background for the Plans tab.
  Color get cream => dark ? const Color(0xFF1F1A15) : const Color(0xFFFBF6EE);

  Color get card => dark ? const Color(0xFF2A241D) : const Color(0xFFFFFFFF);
  Color get border => dark ? const Color(0xFF3D342B) : const Color(0xFFE4D8C8);
  Color get ink => dark ? const Color(0xFFF5EDD8) : const Color(0xFF3B2F2A);
  Color get muted => dark ? const Color(0xFFC4B49C) : const Color(0xFF6B5A50);

  /// Gray note chips ("Private · Hidden from Nana") and faded past plans.
  Color get chip => dark ? const Color(0xFF332C24) : const Color(0xFFEFE8DE);
  Color get chipText => dark ? const Color(0xFFC4B49C) : const Color(0xFF5F554E);

  /// Small person-circles, picked by name so each person keeps one color.
  static const List<Color> _people = [
    Color(0xFFB94A2A),
    Color(0xFF2F6F73),
    Color(0xFF5B4B8A),
    Color(0xFF8A5A12),
  ];
  static Color personColor(String name) {
    if (name.isEmpty) return _people[0];
    var sum = 0;
    for (final c in name.codeUnits) {
      sum += c;
    }
    return _people[sum % _people.length];
  }
}
