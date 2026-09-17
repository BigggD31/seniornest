import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sep 17 2026: D Von's request -- wraps the check-in/meds status cards
/// (whichever ones the caller passes in as [child]) under a single
/// collapsible "Daily Updates" header. Collapsible, not dismissible --
/// nothing ever disappears for good, it just tucks away until the
/// person wants to see it again.
///
/// Collapse state persists per calendar day only: collapsing saves
/// today's local date string, and on every load this widget compares
/// that saved date against today. A mismatch (yesterday's date, or no
/// saved state at all) means it opens back up automatically -- reset in
/// lockstep with the same local-device midnight boundary the check-in
/// cards themselves already use for "today" vs. "yesterday", per D
/// Von's ask that this follow the same daily reset the check-ins do.
/// Manually reopening it the same day it was collapsed clears the saved
/// state entirely, so it won't silently re-collapse on the next screen
/// load that same day.
class DailyUpdatesSectionWidget extends StatefulWidget {
  final bool isDarkMode;
  final Widget child;

  const DailyUpdatesSectionWidget({
    super.key,
    required this.isDarkMode,
    required this.child,
  });

  @override
  State<DailyUpdatesSectionWidget> createState() =>
      _DailyUpdatesSectionWidgetState();
}

class _DailyUpdatesSectionWidgetState
    extends State<DailyUpdatesSectionWidget> {
  static const _prefsKey = 'daily_updates_collapsed_date';
  bool _isCollapsed = false;
  bool _loaded = false;

  String get _todayKey {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedDate = prefs.getString(_prefsKey);
      if (mounted) {
        setState(() {
          _isCollapsed = savedDate == _todayKey;
          _loaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _toggle() async {
    final newCollapsed = !_isCollapsed;
    setState(() => _isCollapsed = newCollapsed);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (newCollapsed) {
        await prefs.setString(_prefsKey, _todayKey);
      } else {
        await prefs.remove(_prefsKey);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final textColor =
        widget.isDarkMode ? Colors.white70 : const Color(0xFF544C42);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: _toggle,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Daily Updates',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: _isCollapsed ? -0.25 : 0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  child: Icon(Icons.expand_more, size: 18, color: textColor),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: widget.child,
          secondChild: const SizedBox(width: double.infinity),
          crossFadeState:
              _isCollapsed ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 300),
          sizeCurve: Curves.easeOut,
        ),
      ],
    );
  }
}
