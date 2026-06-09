import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../services/share_service.dart';

/// Elegant share preview card + native share sheet trigger.
/// Matches the cream/gold/blush quiet-luxury aesthetic.
class SharePreviewWidget {
  static const String _caption =
      'A special moment from our SeniorNest ❤️ Check out our nest: https://seniornest6932.builtwithrocket.new';

  /// Show the warm preview card bottom sheet, then trigger native share.
  static void show(
    BuildContext context, {
    required String title,
    required String body,
    String? imageUrl,
    bool isDarkMode = false,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SharePreviewSheet(
        title: title,
        body: body,
        imageUrl: imageUrl,
        isDarkMode: isDarkMode,
      ),
    );
  }
}

class _SharePreviewSheet extends StatelessWidget {
  const _SharePreviewSheet({
    required this.title,
    required this.body,
    this.imageUrl,
    required this.isDarkMode,
  });

  final String title;
  final String body;
  final String? imageUrl;
  final bool isDarkMode;

  static const String _caption =
      'A special moment from our SeniorNest ❤️ Check out our nest: https://seniornest6932.builtwithrocket.new';

  Color get _sheetBg =>
      isDarkMode ? const Color(0xFF242018) : const Color(0xFFFDFDFD);
  Color get _textPrimary =>
      isDarkMode ? const Color(0xFFF5EDD8) : const Color(0xFF2C2417);
  Color get _textSecondary =>
      isDarkMode ? const Color(0xFFB8A888) : const Color(0xFF6B5E4E);
  Color get _cardBg =>
      isDarkMode ? const Color(0xFF2E2820) : const Color(0xFFFAF7F2);
  Color get _cardBorder =>
      isDarkMode ? const Color(0xFF3D3428) : const Color(0xFFE8E0D0);

  void _triggerShare(BuildContext context) {
    Navigator.pop(context);
    Future.delayed(const Duration(milliseconds: 300), () {
      if (kIsWeb) {
        ShareService.shareStory(
          context,
          title: title,
          body: body,
          isDarkMode: isDarkMode,
        );
      } else {
        Share.share(_caption, subject: title);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _cardBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Sheet title
              Text(
                'Share this moment',
                style: GoogleFonts.nunitoSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'A beautiful preview will be shared with your caption.',
                style: GoogleFonts.nunitoSans(
                  fontSize: 13,
                  color: _textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              // ── Preview Card ──────────────────────────────────
              _ShareCard(
                title: title,
                body: body,
                imageUrl: imageUrl,
                isDarkMode: isDarkMode,
              ),
              const SizedBox(height: 16),
              // Caption preview
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFD4AA00).withAlpha(15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFD4AA00).withAlpha(60),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.auto_awesome_rounded,
                          size: 14,
                          color: Color(0xFFD4AA00),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Pre-filled caption',
                          style: GoogleFonts.nunitoSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFD4AA00),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _caption,
                      style: GoogleFonts.nunitoSans(
                        fontSize: 13,
                        color: _textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Share button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => _triggerShare(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5DA399),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.ios_share_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Share Now',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Cancel
              Center(
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      'Not now',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 14,
                        color: _textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The warm preview card shown inside the share sheet.
class _ShareCard extends StatelessWidget {
  const _ShareCard({
    required this.title,
    required this.body,
    this.imageUrl,
    required this.isDarkMode,
  });

  final String title;
  final String body;
  final String? imageUrl;
  final bool isDarkMode;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFAF7F2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFD4AA00).withAlpha(80),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD4AA00).withAlpha(20),
            blurRadius: 16,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image (if present)
          if (hasImage)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18),
              ),
              child: Image.network(
                imageUrl!,
                height: 140,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title + heart accent
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: GoogleFonts.nunitoSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF2C2417),
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.favorite_rounded,
                      color: Color(0xFFE8A0A0),
                      size: 18,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  body,
                  style: GoogleFonts.nunitoSans(
                    fontSize: 13,
                    color: const Color(0xFF6B5E4E),
                    height: 1.5,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 14),
                // Divider
                Container(height: 1, color: const Color(0xFFE8E0D0)),
                const SizedBox(height: 12),
                // Footer: SeniorNest logo mark
                Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: const Color(0xFF5DA399).withAlpha(30),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Text('🏡', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'SeniorNest',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF5DA399),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4AA00).withAlpha(20),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '❤️ Shared with love',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFD4AA00),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
