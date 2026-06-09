import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum BadgeVariant { success, warning, error, info, neutral }

class StatusBadgeWidget extends StatelessWidget {
  const StatusBadgeWidget({
    super.key,
    required this.label,
    this.variant = BadgeVariant.neutral,
    this.icon,
  });

  final String label;
  final BadgeVariant variant;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = _resolveColors();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.$2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.$1.withAlpha(77), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: colors.$1),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: GoogleFonts.nunitoSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.$1,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  (Color, Color) _resolveColors() {
    switch (variant) {
      case BadgeVariant.success:
        return (const Color(0xFF5DA399), const Color(0xff5da39918));
      case BadgeVariant.warning:
        return (const Color(0xFFD4AA00), const Color(0xffd4aa0018));
      case BadgeVariant.error:
        return (const Color(0xFFC0392B), const Color(0xffc0392b18));
      case BadgeVariant.info:
        return (const Color(0xFF4A7FA5), const Color(0xff4a7fa518));
      case BadgeVariant.neutral:
        return (const Color(0xFFA8A090), const Color(0xffa8a09018));
    }
  }
}
