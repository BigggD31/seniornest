import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 1.05: small note shown on the review screen (above Retake / Send) when a
/// recording was stopped automatically because it reached its time limit,
/// so nobody wonders why it stopped. Used by the Share page (60 seconds) and
/// Legacy (15 minutes video, 30 minutes voice).
class LimitReachedNote extends StatelessWidget {
  const LimitReachedNote({
    super.key,
    required this.message,
    this.isDarkMode = false,
  });

  final String message;
  final bool isDarkMode;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDarkMode
              ? const Color(0xFF2E2820)
              : const Color(0xFFF1EEFA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF9B8FD4).withAlpha(110),
            width: 1.2,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(
                Icons.timer_outlined,
                size: 18,
                color: Color(0xFF9B8FD4),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.nunitoSans(
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: isDarkMode
                      ? const Color(0xFFD9CFF5)
                      : const Color(0xFF5B4E9A),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
