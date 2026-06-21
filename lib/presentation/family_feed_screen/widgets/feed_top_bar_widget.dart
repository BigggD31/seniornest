import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../profile_photo_picker_screen/profile_photo_picker_screen.dart';

class FeedTopBarWidget extends StatefulWidget {
  const FeedTopBarWidget({
    super.key,
    required this.nestName,
    required this.isDarkMode,
    required this.onNestTap,
    required this.onNotificationTap,
    required this.onProfileTap,
  });

  final String nestName;
  final bool isDarkMode;
  final VoidCallback onNestTap;
  final VoidCallback onNotificationTap;
  final VoidCallback onProfileTap;

  @override
  State<FeedTopBarWidget> createState() => _FeedTopBarWidgetState();
}

class _FeedTopBarWidgetState extends State<FeedTopBarWidget> {
  Map<String, dynamic>? _profileData;
  String _displayName = '';

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    final profileJson = prefs.getString(kProfilePhotoKey);
    final name = prefs.getString('display_name') ?? '';
    if (mounted) {
      setState(() {
        _displayName = name;
        if (profileJson != null) {
          try {
            _profileData = jsonDecode(profileJson) as Map<String, dynamic>;
          } catch (_) {}
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDarkMode
        ? const Color(0xFF1A1612)
        : const Color(0xFFFDFDFD);
    final textColor = widget.isDarkMode
        ? const Color(0xFFF5EDD8)
        : const Color(0xFF2C2417);
    final mutedColor = widget.isDarkMode
        ? const Color(0xFF6B5E4E)
        : const Color(0xFFA8A090);

    final displayName = widget.nestName.isNotEmpty
        ? widget.nestName
        : 'My Nest';

    return Container(
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          // Nest name dropdown pill
          Expanded(
            child: GestureDetector(
              onTap: widget.onNestTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: widget.isDarkMode
                      ? const Color(0xFF242018)
                      : const Color(0xFFF5F0E8),
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(
                    color: widget.isDarkMode
                        ? const Color(0xFF3D3428)
                        : const Color(0xFFE8E0D0),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.home_rounded,
                      size: 18,
                      color: Color(0xFF5DA399),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        displayName,
                        style: GoogleFonts.nunitoSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: mutedColor,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Notification button
          _TopBarIconButton(
            icon: Icons.notifications_outlined,
            isDarkMode: widget.isDarkMode,
            onTap: widget.onNotificationTap,
            badgeCount: 0, // TODO: wire to real notification count once notifications feature is built
          ),
          const SizedBox(width: 8),
          // Profile avatar — shows user's chosen photo/emoji or initials
          GestureDetector(
            onTap: widget.onProfileTap,
            child: ProfileAvatarWidget(
              profileData: _profileData,
              displayName: _displayName,
              size: 40,
              borderColor: const Color(0xFF5DA399),
              borderWidth: 2,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBarIconButton extends StatelessWidget {
  const _TopBarIconButton({
    required this.icon,
    required this.isDarkMode,
    required this.onTap,
    this.badgeCount = 0,
  });

  final IconData icon;
  final bool isDarkMode;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isDarkMode
                  ? const Color(0xFF242018)
                  : const Color(0xFFF5F0E8),
              shape: BoxShape.circle,
              border: Border.all(
                color: isDarkMode
                    ? const Color(0xFF3D3428)
                    : const Color(0xFFE8E0D0),
                width: 1.5,
              ),
            ),
            child: Icon(
              icon,
              size: 20,
              color: isDarkMode
                  ? const Color(0xFFB8A888)
                  : const Color(0xFF6B5E4E),
            ),
          ),
          if (badgeCount > 0)
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(
                  color: Color(0xFFD4AA00),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$badgeCount',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
