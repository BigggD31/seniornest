import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Key used to persist the profile photo choice across the app.
/// Value is a JSON string: {"type": "emoji"|"photo", "value": "<emoji char>"|"<base64 bytes>"}
const String kProfilePhotoKey = 'profile_photo_data';

class ProfilePhotoPickerScreen extends StatefulWidget {
  const ProfilePhotoPickerScreen({super.key});

  @override
  State<ProfilePhotoPickerScreen> createState() =>
      _ProfilePhotoPickerScreenState();
}

class _ProfilePhotoPickerScreenState extends State<ProfilePhotoPickerScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  bool _isPickingPhoto = false;

  // Emoji options
  static const List<String> _emojis = [
    '😊',
    '🥰',
    '😄',
    '😎',
    '🤗',
    '😇',
    '👴',
    '👵',
    '🧓',
    '👨',
    '👩',
    '🧑',
    '🌸',
    '🌻',
    '🌺',
    '🌹',
    '🍀',
    '🌿',
    '🐶',
    '🐱',
    '🐦',
    '🦋',
    '🐝',
    '🌈',
    '⭐',
    '🌙',
    '☀️',
    '❤️',
    '💛',
    '💚',
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _pickFromPhotoLibrary() async {
    if (_isPickingPhoto) return;
    setState(() => _isPickingPhoto = true);
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 400,
        maxHeight: 400,
        imageQuality: 80,
      );
      if (image != null && mounted) {
        final bytes = await image.readAsBytes();
        final base64Str = base64Encode(bytes);
        await _saveAndReturn({'type': 'photo', 'value': base64Str});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not access photo library. Please try again.',
              style: GoogleFonts.nunitoSans(color: Colors.white),
            ),
            backgroundColor: const Color(0xFFC0392B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPickingPhoto = false);
    }
  }

  Future<void> _pickEmoji(String emoji) async {
    await _saveAndReturn({'type': 'emoji', 'value': emoji});
  }

  Future<void> _saveAndReturn(Map<String, String> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kProfilePhotoKey, jsonEncode(data));

    // Save to Supabase so photo survives sign-out and restores on sign-in
    try {
      final supabaseClient = Supabase.instance.client;
      final userId = supabaseClient.auth.currentUser?.id;
      if (userId != null) {
        await supabaseClient
            .from('user_profiles')
            .update({'avatar_url': jsonEncode(data)})
            .eq('id', userId);
        print('PROFILE_PHOTO: saved to Supabase for user $userId');
      }
    } catch (e) {
      print('PROFILE_PHOTO: Supabase save error = $e');
    }

    if (mounted) Navigator.pop(context, data);
  }

  void _skip() {
    Navigator.pop(context, null);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = MediaQuery.of(context).platformBrightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1C1812) : const Color(0xFFFDFDFD);
    final surface = isDark ? const Color(0xFF2A2218) : const Color(0xFFF5F0E8);
    final border = isDark ? const Color(0xFF3A3228) : const Color(0xFFE8E0D0);
    final textPrimary = isDark
        ? const Color(0xFFF5EDD8)
        : const Color(0xFF2C2417);
    final textSecondary = isDark
        ? const Color(0xFFB8A888)
        : const Color(0xFF6B5E4E);

    return Scaffold(
      backgroundColor: bg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _skip,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFF5DA399).withAlpha(31),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Color(0xFF5DA399),
                          size: 22,
                        ),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _skip,
                      child: Text(
                        'Do it later',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF5DA399),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        'Add a profile photo',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: textPrimary,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your photo will appear in the top corner of the app so your family knows it\'s you.',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 15,
                          color: textSecondary,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Photo Library option
                      GestureDetector(
                        onTap: _isPickingPhoto ? null : _pickFromPhotoLibrary,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: border, width: 1.5),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF5DA399).withAlpha(26),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: _isPickingPhoto
                                    ? const Padding(
                                        padding: EdgeInsets.all(14),
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Color(0xFF5DA399),
                                        ),
                                      )
                                    : const Icon(
                                        Icons.photo_library_rounded,
                                        color: Color(0xFF5DA399),
                                        size: 28,
                                      ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Choose from Photo Library',
                                      style: GoogleFonts.nunitoSans(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Pick a photo from your device',
                                      style: GoogleFonts.nunitoSans(
                                        fontSize: 13,
                                        color: textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: textSecondary,
                                size: 22,
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 28),

                      // Emoji section
                      Text(
                        'Choose from Emoji',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tap an emoji to use it as your profile picture',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 13,
                          color: textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 6,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              childAspectRatio: 1,
                            ),
                        itemCount: _emojis.length,
                        itemBuilder: (context, index) {
                          final emoji = _emojis[index];
                          return GestureDetector(
                            onTap: () => _pickEmoji(emoji),
                            child: Container(
                              decoration: BoxDecoration(
                                color: surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: border, width: 1.5),
                              ),
                              child: Center(
                                child: Text(
                                  emoji,
                                  style: const TextStyle(fontSize: 26),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 32),
                    ],
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

/// Helper widget that renders a profile avatar from stored SharedPreferences data.
/// Shows emoji, photo bytes, or initials fallback.
class ProfileAvatarWidget extends StatelessWidget {
  const ProfileAvatarWidget({
    super.key,
    required this.profileData,
    required this.displayName,
    this.size = 40.0,
    this.borderColor = const Color(0xFF5DA399),
    this.borderWidth = 2.0,
  });

  final Map<String, dynamic>? profileData;
  final String displayName;
  final double size;
  final Color borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    final type = profileData?['type'] as String?;
    final value = profileData?['value'] as String?;

    Widget inner;

    if (type == 'emoji' && value != null && value.isNotEmpty) {
      inner = Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(shape: BoxShape.circle),
        child: Center(
          child: Text(value, style: TextStyle(fontSize: size * 0.5)),
        ),
      );
    } else if (type == 'photo' && value != null && value.isNotEmpty) {
      Uint8List? bytes;
      try {
        bytes = base64Decode(value);
      } catch (_) {}
      inner = bytes != null
          ? ClipOval(
              child: Image.memory(
                bytes,
                width: size,
                height: size,
                fit: BoxFit.cover,
              ),
            )
          : _buildInitials();
    } else {
      inner = _buildInitials();
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      child: ClipOval(child: inner),
    );
  }

  Widget _buildInitials() {
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: const Color(0xFF5DA399).withAlpha(40),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: size * 0.38,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF5DA399),
          ),
        ),
      ),
    );
  }
}
