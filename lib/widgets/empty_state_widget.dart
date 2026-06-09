import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class EmptyStateWidget extends StatelessWidget {
  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.ctaLabel,
    this.onCtaTap,
    this.customIcon,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? ctaLabel;
  final VoidCallback? onCtaTap;
  final Widget? customIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            customIcon ??
                Icon(icon, size: 72, color: theme.colorScheme.outline),
            const SizedBox(height: 20),
            Text(
              title,
              style: GoogleFonts.nunitoSans(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFD4AA00),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              style: GoogleFonts.nunitoSans(
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
            if (ctaLabel != null && onCtaTap != null) ...[
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: onCtaTap,
                icon: const Icon(Icons.add_rounded, size: 20),
                label: Text(ctaLabel!),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF5DA399),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(200, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: GoogleFonts.nunitoSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
