import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

// Web-only import
import 'share_service_web.dart'
    if (dart.library.io) 'share_service_stub.dart'
    as web_helper;

class ShareService {
  static const String _appUrl = 'https://apps.apple.com/us/app/seniornest-family-connection/id6763690515';

  /// Share invite code — native sheet on mobile, web modal on web.
  static void shareInviteCode(
    BuildContext context, {
    String inviteCode = 'NEST000000',
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
      // Oct 6 2026: on iPad the share sheet is a popover and silently does
      // nothing unless it is told where to anchor. Anchor it to the tapped
      // widget, or the middle of the screen if that is not available.
      Rect? origin;
      try {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null &&
            box.hasSize &&
            box.size.width > 0 &&
            box.size.width < MediaQuery.of(context).size.width * 0.6) {
          origin = box.localToGlobal(Offset.zero) & box.size;
        }
      } catch (_) {}
      if (origin == null) {
        final size = MediaQuery.of(context).size;
        origin = Rect.fromCenter(
          center: Offset(size.width / 2, size.height / 2),
          width: 10,
          height: 10,
        );
      }
      () async {
        try {
          await Share.share(
            shareText,
            subject: 'Join our SeniorNest Family!',
            sharePositionOrigin: origin,
          );
        } catch (_) {
          // If the share sheet can't open for any reason, copy instead so the
          // person is never left with a button that does nothing.
          await Clipboard.setData(ClipboardData(text: shareText));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Invite copied to your clipboard.')),
            );
          }
        }
      }();
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
