import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class DailyCheckinCardWidget extends StatelessWidget {
  const DailyCheckinCardWidget({
    super.key,
    required this.isDarkMode,
    required this.isSenior,
    required this.seniorName,
    required this.checkedIn,
    this.checkinTime,
  });

  final bool isDarkMode;
  final bool isSenior;
  final String seniorName;
  final bool checkedIn;
  final DateTime? checkinTime;

  String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return 'today';
  }

  @override
  Widget build(BuildContext context) {
    final headline = checkedIn
        ? (isSenior
              ? 'You checked in today ✓'
              : '$seniorName checked in today')
        : (isSenior
              ? 'You haven\'t checked in yet today'
              : '$seniorName hasn\'t checked in yet today');

    final subtext = checkedIn
        ? (isSenior
              ? 'Your family knows you\'re doing great.'
              : checkinTime != null
                  ? 'Checked in ${_relativeTime(checkinTime!)}.'
                  : 'Everything\'s good.')
        : (isSenior
              ? 'Tap the heart button below when you\'re ready.'
              : 'No news is usually good news — check back later.');

    final Color accentColor = const Color(0xFF5DA399);

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
              checkedIn ? Icons.favorite_rounded : Icons.favorite_border_rounded,
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
