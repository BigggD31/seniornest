import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Aug 21 2026: shared collapsible year/month grouping, built once and fed
// into Home, Legacy, and Favs rather than three separate builds -- per
// D Von's tracker item. Two pieces: DateGroup/groupByYearMonth below turn
// any list of dated items into an ordered structure of year -> month ->
// items; CollapsibleGroupHeader is the one shared header widget (used for
// both year and month rows, just styled slightly differently) each
// screen's own sliver-building code renders alongside its own item cards.
//
// Deliberately NOT a single all-in-one widget that owns a whole
// SliverList itself -- each screen's items render very differently
// (MessageCardWidget, legacy story cards, favs items), and each screen
// already has its own animation/entrance timing tied to a flat item
// index. Keeping the grouping as data + a shared header widget, with
// each screen flattening (groups + collapse state) into its own sliver
// list, avoids forcing three different card types through one rigid
// shared list widget.

class DateMonthGroup<T> {
  DateMonthGroup({required this.month, required this.items});
  final int month; // 1-12
  final List<T> items;
}

class DateYearGroup<T> {
  DateYearGroup({required this.year, required this.months});
  final int year;
  final List<DateMonthGroup<T>> months;
}

const List<String> kMonthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Groups [items] into year -> month buckets using [dateOf] to extract
/// each item's date. Both years and months are ordered newest-first,
/// matching every one of these three screens' existing sort order. Items
/// [dateOf] can't resolve a date for (returns null) are simply excluded
/// from the grouped result -- callers render those separately,
/// ungrouped, rather than inventing a fake "Unknown" bucket.
List<DateYearGroup<T>> groupByYearMonth<T>(
  List<T> items,
  DateTime? Function(T item) dateOf,
) {
  final Map<int, Map<int, List<T>>> buckets = {};
  for (final item in items) {
    final date = dateOf(item);
    if (date == null) continue;
    buckets.putIfAbsent(date.year, () => {});
    buckets[date.year]!.putIfAbsent(date.month, () => []);
    buckets[date.year]![date.month]!.add(item);
  }
  final years = buckets.keys.toList()..sort((a, b) => b.compareTo(a));
  return years.map((year) {
    final monthsMap = buckets[year]!;
    final months = monthsMap.keys.toList()..sort((a, b) => b.compareTo(a));
    return DateYearGroup<T>(
      year: year,
      months: months
          .map((m) => DateMonthGroup<T>(month: m, items: monthsMap[m]!))
          .toList(),
    );
  }).toList();
}

/// One shared header row for both year and month groups -- a year header
/// (bold, larger) and a month header (lighter, indented) both use this,
/// just with different [isYear]/styling. Tap anywhere on the row toggles
/// collapse; the chevron rotates to match, matching the same collapse
/// affordance already used elsewhere in the app (e.g. Setup's
/// expandable sections).
class CollapsibleGroupHeader extends StatelessWidget {
  const CollapsibleGroupHeader({
    super.key,
    required this.label,
    required this.itemCount,
    required this.isCollapsed,
    required this.onToggle,
    required this.isDarkMode,
    this.isYear = true,
  });

  final String label;
  final int itemCount;
  final bool isCollapsed;
  final VoidCallback onToggle;
  final bool isDarkMode;
  final bool isYear;

  @override
  Widget build(BuildContext context) {
    final textPrimary =
        isDarkMode ? const Color(0xFFF5EDD8) : const Color(0xFF2C2417);
    final textSecondary =
        isDarkMode ? const Color(0xFFB8A888) : const Color(0xFF6B5E4E);
    return GestureDetector(
      onTap: onToggle,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.only(
          left: isYear ? 0 : 16,
          top: isYear ? 20 : 10,
          bottom: 8,
        ),
        child: Row(
          children: [
            AnimatedRotation(
              turns: isCollapsed ? -0.25 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: isYear ? 22 : 18,
                color: textSecondary,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.nunitoSans(
                fontSize: isYear ? 18 : 14,
                fontWeight: isYear ? FontWeight.w800 : FontWeight.w700,
                color: isYear ? textPrimary : textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '($itemCount)',
              style: GoogleFonts.nunitoSans(
                fontSize: isYear ? 14 : 12,
                fontWeight: FontWeight.w600,
                color: textSecondary.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
