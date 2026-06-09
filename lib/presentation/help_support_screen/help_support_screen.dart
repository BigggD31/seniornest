import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

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

    final faqs = [
      {
        'q': 'How do I invite a family member?',
        'a':
            'Go to Setup → Your Nest section and tap "Share Invite Code". Send the code to your family member.',
      },
      {
        'q': 'How do I change my display name?',
        'a': 'Go to Setup → tap your name at the top of the screen to edit it.',
      },
      {
        'q': 'Can I use SeniorNest on multiple devices?',
        'a':
            'Yes! Sign in with the same account on any device and your nest will sync automatically.',
      },
      {
        'q': 'How do I turn off notifications?',
        'a':
            'Go to Setup → Notifications section and toggle off the notifications you don\'t want.',
      },
      {
        'q': 'How do I delete my account?',
        'a':
            'Go to Setup → Account section → Sign Out. To fully delete your account, contact us at the email below.',
      },
      {
        'q': 'Is my data private?',
        'a':
            'Yes. SeniorNest collects only what\'s needed to run the app. We never share or sell your data. See our Privacy Policy for full details.',
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
          'Help & Support',
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
          // Contact card
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
                        color: teal.withAlpha(25),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.mail_outline_rounded,
                        color: teal,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Contact Us',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'We\'re here to help! Reach out anytime and we\'ll get back to you within 24 hours.',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 14,
                    color: textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.email_rounded, color: gold, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'support@seniornest.app',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: gold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // FAQ header
          Text(
            'Frequently Asked Questions',
            style: GoogleFonts.nunitoSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          // FAQ items
          ...faqs.map(
            (faq) => Container(
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('💬', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          faq['q']!,
                          style: GoogleFonts.nunitoSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 24),
                    child: Text(
                      faq['a']!,
                      style: GoogleFonts.nunitoSans(
                        fontSize: 13,
                        color: textSecondary,
                        height: 1.5,
                      ),
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
