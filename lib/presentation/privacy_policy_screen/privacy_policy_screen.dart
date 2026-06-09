import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1A1612) : const Color(0xFFF8F4ED);
    final cardBg = isDark ? const Color(0xFF242018) : const Color(0xFFFAF7F2);
    final cardBorder = isDark
        ? const Color(0xFF3D3428)
        : const Color(0xFFE8E0D0);
    final textPrimary = isDark
        ? const Color(0xFFF5EDD8)
        : const Color(0xFF2C2417);
    final textSecondary = isDark
        ? const Color(0xFFB8A888)
        : const Color(0xFF6B5E4E);
    const gold = Color(0xFFD4AA5E);
    const teal = Color(0xFF5DA399);

    final sections = [
      {
        'icon': '🔒',
        'title': 'Data We Collect',
        'body':
            'SeniorNest collects no personal data beyond account info (name, email, and role). This is used solely to identify you within your family nest.',
      },
      {
        'icon': '🎯',
        'title': 'How We Use It',
        'body':
            'Your account information is used only to provide app functionality — connecting you with your family nest, sending check-ins, and personalizing your experience.',
      },
      {
        'icon': '🚫',
        'title': 'No Sharing, No Ads',
        'body':
            'We do not share, sell, or rent your personal data to any third parties. SeniorNest is completely ad-free. Your family\'s privacy is our priority.',
      },
      {
        'icon': '🗑️',
        'title': 'Delete Anytime',
        'body':
            'You can delete your account and all associated data at any time via Settings → Account → Sign Out, then contacting us at support@seniornest.app to request full deletion.',
      },
      {
        'icon': '🔐',
        'title': 'Security',
        'body':
            'Your data is stored securely using industry-standard encryption. We use Supabase infrastructure with row-level security to ensure only you and your nest members can access your data.',
      },
      {
        'icon': '📬',
        'title': 'Contact',
        'body':
            'Questions about this policy? Email us at support@seniornest.app and we\'ll respond within 24 hours.',
      },
    ];

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: textPrimary,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Privacy Policy',
          style: GoogleFonts.nunitoSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: textPrimary,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        children: [
          // Header banner
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cardBorder, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: gold.withAlpha(25),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.privacy_tip_outlined,
                        color: gold,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'SeniorNest Privacy Policy',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Last updated: 2025 · Effective immediately',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 12,
                    color: textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: teal.withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: teal.withAlpha(50), width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.verified_outlined,
                        color: teal,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'We respect your privacy. Simple, honest, no surprises.',
                          style: GoogleFonts.nunitoSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: teal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Policy sections
          ...sections.map(
            (section) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cardBorder, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        section['icon']!,
                        style: const TextStyle(fontSize: 18),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        section['title']!,
                        style: GoogleFonts.nunitoSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    section['body']!,
                    style: GoogleFonts.nunitoSans(
                      fontSize: 13,
                      color: textSecondary,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
