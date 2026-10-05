import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../profile_photo_picker_screen/profile_photo_picker_screen.dart';



/// Horizontal row of avatars for everyone in the Nest, shown at the top of
/// the Home feed. Tapping a member is meant to open a private 1:1 message
/// thread with them (see priority list: private messaging via avatar row).
/// Until that thread screen exists, taps are wired to [onMemberTap] so the
/// parent screen decides what happens (currently: navigate to compose).
class NestAvatarRowWidget extends StatelessWidget {
  const NestAvatarRowWidget({
    super.key,
    required this.members,
    required this.isDarkMode,
    required this.onMemberTap,
  });

  /// Each member map is expected to have: id, name, avatarUrl, avatarLabel, role
  final List<Map<String, dynamic>> members;
  final bool isDarkMode;
  final void Function(Map<String, dynamic> member) onMemberTap;

  /// Tap on an avatar opens a medium-sized card over the page (not
  /// full-screen, so small uploads don't look pixelated) with the person's
  /// name and a Message button. Tapping outside the card closes it and
  /// leaves the page exactly as it was.
  void _showEnlarged(BuildContext context, Map<String, dynamic> member) {
    final name = member['name'] as String? ?? '';
    final avatarUrl = member['avatarUrl'] as String? ?? '';
    final cardBg = isDarkMode ? const Color(0xFF242018) : Colors.white;
    final textColor =
        isDarkMode ? const Color(0xFFF5EDD8) : const Color(0xFF2C2417);
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: cardBg,
        insetPadding: const EdgeInsets.symmetric(horizontal: 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ProfileAvatarWidget(
                avatarUrl: avatarUrl,
                displayName: name,
                size: 200,
                borderColor: const Color(0xFF5DA399),
                borderWidth: 3,
              ),
              const SizedBox(height: 16),
              Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.nunitoSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    onMemberTap(member);
                  },
                  icon: const Icon(Icons.chat_bubble_outline_rounded,
                      size: 18, color: Colors.white),
                  label: Text(
                    name.isEmpty ? 'Message' : 'Message $name',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.nunitoSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5DA399),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(100),
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

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 86,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: members.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final member = members[index];
          final name = member['name'] as String? ?? '';
          final avatarUrl = member['avatarUrl'] as String? ?? '';

          return GestureDetector(
            onTap: () => _showEnlarged(context, member),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF5DA399),
                      width: 2,
                    ),
                  ),
                  child: ProfileAvatarWidget(
                    avatarUrl: avatarUrl,
                    displayName: name,
                    size: 56,
                    borderColor: Colors.transparent,
                    borderWidth: 0,
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: 60,
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.nunitoSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode
                          ? const Color(0xFFE8DFD0)
                          : const Color(0xFF3D3527),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
