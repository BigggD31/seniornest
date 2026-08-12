import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Pinned status card showing whether the senior has logged their
/// medications today, visible to everyone in the nest -- same pattern as
/// DailyCheckinCardWidget, backed by the daily_medications table.
class DailyMedsCardWidget extends StatelessWidget {
  const DailyMedsCardWidget({
    super.key,
    required this.isDarkMode,
    required this.isSenior,
    required this.seniorName,
    required this.takenToday,
    this.takenTime,
  });

  final bool isDarkMode;
  final bool isSenior;
  final String seniorName;
  final bool takenToday;
  final DateTime? takenTime;

  String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return 'today';
  }

  @override
  Widget build(BuildContext context) {
    final headline = takenToday
        ? (isSenior
              ? 'You took your medications today ✓'
              : '$seniorName took their medications today')
        : (isSenior
              ? 'Medications not logged yet today'
              : '$seniorName hasn\'t logged medications yet today');

    final subtext = takenToday
        ? (isSenior
              ? 'Your family knows you\'re on track.'
              : takenTime != null
                  ? 'Logged ${_relativeTime(takenTime!)}.'
                  : 'All set for today.')
        : (isSenior
              ? 'Tap the button below once you\'ve taken them.'
              : 'No news is usually good news — check back later.');

    // Distinct accent from the check-in card's teal, so the two pinned
    // cards read as separate at a glance rather than blending together.
    final Color accentColor = const Color(0xFF8A6FB0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF242018) : const Color(0xFFFAF7F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accentColor.withAlpha(80),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accentColor.withAlpha(31),
            ),
            child: Icon(
              takenToday ? Icons.medication_rounded : Icons.medication_outlined,
              color: accentColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: GoogleFonts.nunitoSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDarkMode
                        ? const Color(0xFFF5EDD8)
                        : const Color(0xFF2C2417),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtext,
                  style: GoogleFonts.nunitoSans(
                    fontSize: 13,
                    color: isDarkMode
                        ? const Color(0xFFB8A888)
                        : const Color(0xFF6B5E4E),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
