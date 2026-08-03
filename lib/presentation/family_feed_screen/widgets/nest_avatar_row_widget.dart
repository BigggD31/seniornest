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
            onTap: () => onMemberTap(member),
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
