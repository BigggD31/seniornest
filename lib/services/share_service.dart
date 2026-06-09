import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

// Web-only import
import 'share_service_web.dart'
    if (dart.library.io) 'share_service_stub.dart'
    as web_helper;

class ShareService {
  static const String _appUrl = 'https://seniornest6932.builtwithrocket.new';

  /// Share invite code — native sheet on mobile, web modal on web.
  static void shareInviteCode(
    BuildContext context, {
    String inviteCode = 'NEST-000000',
    bool isDarkMode = false,
  }) {
    final shareText =
        'Join my SeniorNest! 🏡\n\nInvite code: $inviteCode\n\nDownload SeniorNest and enter this code to connect with our family.\n\n$_appUrl';

    if (kIsWeb) {
      _showWebModal(
        context,
        shareText: shareText,
        inviteCode: inviteCode,
        isDarkMode: isDarkMode,
        subject: 'Join our SeniorNest Family!',
      );
    } else {
      Share.share(shareText, subject: 'Join our SeniorNest Family!');
    }
  }

  /// Share a legacy story — native sheet on mobile, web modal on web.
  static void shareStory(
    BuildContext context, {
    required String title,
    required String body,
    bool isDarkMode = false,
  }) {
    final shareText = '$title\n\n$body\n\nShared from SeniorNest ❤️\n$_appUrl';

    if (kIsWeb) {
      _showWebModal(
        context,
        shareText: shareText,
        inviteCode: null,
        isDarkMode: isDarkMode,
        subject: title,
      );
    } else {
      Share.share(shareText, subject: title);
    }
  }

  static void _showWebModal(
    BuildContext context, {
    required String shareText,
    required String? inviteCode,
    required bool isDarkMode,
    required String subject,
  }) {
    final bg = isDarkMode ? const Color(0xFF242018) : const Color(0xFFFAF3EC);
    final textPrimary = isDarkMode
        ? const Color(0xFFF5EDD8)
        : const Color(0xFF2C2417);
    final textSecondary = isDarkMode
        ? const Color(0xFFB8A888)
        : const Color(0xFF6B5E4E);
    final codeBg = isDarkMode
        ? const Color(0xFF1E2E2C)
        : const Color(0xFFEDF7F6);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.share_rounded, color: Color(0xFF5DA399), size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                inviteCode != null ? 'Share Invite Code' : 'Share Story',
                style: GoogleFonts.nunitoSans(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (inviteCode != null) ...[
              Text(
                'Invite Code',
                style: GoogleFonts.nunitoSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: codeBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF5DA399).withAlpha(80),
                  ),
                ),
                child: Text(
                  inviteCode,
                  style: GoogleFonts.nunitoSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF5DA399),
                    letterSpacing: 6,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              shareText,
              style: GoogleFonts.nunitoSans(
                fontSize: 13,
                color: textSecondary,
                height: 1.5,
              ),
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          // Share via Email
          TextButton.icon(
            onPressed: () {
              final encodedSubject = Uri.encodeComponent(subject);
              final encodedBody = Uri.encodeComponent(shareText);
              final mailtoUrl =
                  'mailto:?subject=$encodedSubject&body=$encodedBody';
              Navigator.pop(ctx);
              web_helper.openUrl(mailtoUrl);
            },
            icon: const Icon(
              Icons.mail_outline_rounded,
              color: Color(0xFF5DA399),
              size: 18,
            ),
            label: Text(
              'Share via Email',
              style: GoogleFonts.nunitoSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF5DA399),
              ),
            ),
          ),
          // Copy button
          ElevatedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: shareText));
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Copied!',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                    backgroundColor: const Color(0xFF5DA399),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    margin: const EdgeInsets.all(16),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            icon: const Icon(Icons.copy_rounded, size: 18, color: Colors.white),
            label: Text(
              inviteCode != null ? 'Copy Invite Code' : 'Copy Text',
              style: GoogleFonts.nunitoSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5DA399),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
