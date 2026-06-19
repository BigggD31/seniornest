import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_state.dart';
import '../../services/auth_service.dart';
import '../../services/share_service.dart';
import '../../widgets/app_navigation.dart';
import '../profile_photo_picker_screen/profile_photo_picker_screen.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen>
    with TickerProviderStateMixin {
  int _currentNavIndex = 5;
  bool _isSenior = false;
  bool _isDarkMode = false;
  bool _isLoading = true;
  bool _isNestOwner = false;
  String _displayName = '';
  String _nestName = '';
  String _relationship = '';
  bool _medsReminders = true;
  bool _dailyCheckIn = true;
  bool _notifyMessages = true;
  bool _notifyCheckIn = true;
  String _textSize = 'Large';
  bool _isGuest = false;
  String _inviteCode = '';
  Map<String, dynamic>? _profileData;
  DateTime? _birthday;
  DateTime? _anniversary;

  // Family members list — populated when real members join via Supabase
  List<Map<String, dynamic>> _familyMembers = [];

  late AnimationController _entranceController;
  late List<Animation<double>> _itemAnimations;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _itemAnimations = [];
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.delayed(const Duration(milliseconds: 300));
    final role = prefs.getString('user_role') ?? 'senior';
    final isSenior = role == 'senior';
    final joinedViaInvite = prefs.getBool('joined_via_invite') ?? false;
    final isNestOwner = !joinedViaInvite;
    final defaultSize = isSenior ? 'Large' : 'Normal';

    String savedName = prefs.getString('display_name') ?? '';
    if (savedName.isEmpty) {
      try {
        final user = Supabase.instance.client.auth.currentUser;
        final metaName =
            user?.userMetadata?['display_name'] as String? ??
            user?.userMetadata?['full_name'] as String? ??
            user?.userMetadata?['name'] as String? ??
            '';
        if (metaName.isNotEmpty) {
          savedName = metaName;
          await prefs.setString('display_name', savedName);
        }
      } catch (_) {}
    }

    final hasRealPost = prefs.getBool('has_real_post') ?? false;
    final inviteCodeShared = prefs.getBool('invite_code_shared') ?? false;
    final isGuest = prefs.getBool('is_guest') ?? false;

    final removedIds = prefs.getStringList('removed_member_ids') ?? [];

    final profileJson = prefs.getString(kProfilePhotoKey);
    Map<String, dynamic>? profileData;
    if (profileJson != null) {
      try {
        profileData = jsonDecode(profileJson) as Map<String, dynamic>;
      } catch (_) {}
    }

    DateTime? birthday;
    DateTime? anniversary;
    final birthdayStr = prefs.getString('birthday');
    final anniversaryStr = prefs.getString('anniversary');
    if (birthdayStr != null) {
      try {
        birthday = DateTime.parse(birthdayStr);
      } catch (_) {}
    }
    if (anniversaryStr != null) {
      try {
        anniversary = DateTime.parse(anniversaryStr);
      } catch (_) {}
    }

    setState(() {
      _isSenior = isSenior;
      _isNestOwner = isNestOwner;
      _displayName = savedName;
      _nestName = prefs.getString('nest_name') ?? "Eleanor's Nest";
      _relationship = prefs.getString('relationship') ?? '';
      _isDarkMode = prefs.getBool('dark_mode') ?? false;
      _medsReminders = prefs.getBool('meds_reminders') ?? true;
      _dailyCheckIn = prefs.getBool('daily_check_in') ?? true;
      _notifyMessages = prefs.getBool('notify_messages') ?? true;
      _notifyCheckIn = prefs.getBool('notify_check_in') ?? true;
      _textSize = prefs.getString('text_size') ?? defaultSize;
      _isGuest = prefs.getBool('is_guest') ?? false;
      _isLoading = false;
      _profileData = profileData;
      _birthday = birthday;
      _anniversary = anniversary;
      _inviteCode = prefs.getString('invite_code') ?? '';
      if (removedIds.isNotEmpty) {
        _familyMembers = _familyMembers
            .where((m) => !removedIds.contains(m['id'] as String))
            .toList();
      }
    });
    _setupAnimations();
    _entranceController.forward();
  }

  void _setupAnimations() {
    _itemAnimations.clear();
    for (int i = 0; i < 12; i++) {
      final start = (i * 0.07).clamp(0.0, 0.7);
      final end = (start + 0.4).clamp(0.0, 1.0);
      _itemAnimations.add(
        Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: Interval(start, end, curve: Curves.easeOutCubic),
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  Color get _bg =>
      _isDarkMode ? const Color(0xFF1A1612) : const Color(0xFFFDFDFD);
  Color get _surface =>
      _isDarkMode ? const Color(0xFF242018) : const Color(0xFFF5F0E8);
  Color get _cardBg =>
      _isDarkMode ? const Color(0xFF242018) : const Color(0xFFFAF7F2);
  Color get _cardBorder =>
      _isDarkMode ? const Color(0xFF3D3428) : const Color(0xFFE8E0D0);
  Color get _textPrimary =>
      _isDarkMode ? const Color(0xFFF5EDD8) : const Color(0xFF2C2417);
  Color get _textSecondary =>
      _isDarkMode ? const Color(0xFFB8A888) : const Color(0xFF6B5E4E);

  Future<void> _toggleDarkMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', value);
    appDarkModeNotifier.value = value;
    setState(() => _isDarkMode = value);
  }

  Future<void> _togglePref(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    setState(() {
      switch (key) {
        case 'meds_reminders':
          _medsReminders = value;
          break;
        case 'daily_check_in':
          _dailyCheckIn = value;
          break;
        case 'notify_messages':
          _notifyMessages = value;
          break;
        case 'notify_check_in':
          _notifyCheckIn = value;
          break;
      }
    });
  }

  void _onNavTap(int index) {
    if (index == _currentNavIndex) return;
    setState(() => _currentNavIndex = index);
    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(context, '/family-feed-screen');
        break;
      case 1:
        Navigator.pushReplacementNamed(context, '/send-screen');
        break;
      case 2:
        Navigator.pushReplacementNamed(context, '/legacy-screen');
        break;
      case 3:
        Navigator.pushReplacementNamed(context, '/safety-screen');
        break;
      case 4:
        Navigator.pushReplacementNamed(context, '/favs-screen');
        break;
    }
  }

  void _shareInviteCode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('invite_code_shared', true);
    ShareService.shareInviteCode(context, inviteCode: _inviteCode);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTablet = size.width >= 600;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: _isLoading
            ? _buildLoadingState()
            : CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _buildTopBar(isTablet)),
                  SliverToBoxAdapter(child: _buildProfileCard(isTablet)),
                  SliverToBoxAdapter(
                    child: _buildBirthdayAnniversaryCard(isTablet),
                  ),
                  if (_isGuest)
                    SliverToBoxAdapter(
                      child: _buildGuestAccountBanner(isTablet),
                    ),
                  if (_isNestOwner)
                    SliverToBoxAdapter(child: _buildInviteCodeCard(isTablet)),
                  SliverToBoxAdapter(child: _buildNestSection(isTablet)),
                  SliverToBoxAdapter(child: _buildPreferencesSection(isTablet)),
                  SliverToBoxAdapter(
                    child: _buildNotificationsSection(isTablet),
                  ),
                  SliverToBoxAdapter(child: _buildAppearanceSection(isTablet)),
                  SliverToBoxAdapter(child: _buildAccountSection(isTablet)),
                  const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
                ],
              ),
      ),
      bottomNavigationBar: AppNavigation(
        currentIndex: _currentNavIndex,
        onTap: _onNavTap,
      ),
    );
  }

  Widget _buildTopBar(bool isTablet) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? 28 : 20,
        vertical: 14,
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Setup',
                style: GoogleFonts.nunitoSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _textPrimary,
                ),
              ),
              Text(
                'Customize your SeniorNest',
                style: GoogleFonts.nunitoSans(
                  fontSize: 13,
                  color: _textSecondary,
                ),
              ),
            ],
          ),
          const Spacer(),
          ProfileAvatarWidget(
            profileData: _profileData,
            displayName: _displayName,
            size: 40,
            borderColor: const Color(0xFF5DA399),
            borderWidth: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard(bool isTablet) {
    final anim = _itemAnimations.isNotEmpty
        ? _itemAnimations[0]
        : const AlwaysStoppedAnimation(1.0);
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
          offset: Offset(0, 20 * (1 - anim.value)),
          child: child,
        ),
      ),
      child: GestureDetector(
        onTap: () => _showEditProfileSheet(),
        child: Container(
          margin: EdgeInsets.symmetric(
            horizontal: isTablet ? 28 : 20,
            vertical: 8,
          ),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF5DA399), Color(0xFF7DBDB5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(40),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    _displayName.isNotEmpty
                        ? _displayName[0].toUpperCase()
                        : '?',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _displayName,
                      style: GoogleFonts.nunitoSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    // Clearly labeled role line
                    if (_isSenior)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(40),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_displayName.isNotEmpty ? _displayName : 'You'} — ${_isNestOwner ? 'Nest Owner 🏠' : 'Member'}',
                          style: GoogleFonts.nunitoSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      )
                    else
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(40),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_displayName.isNotEmpty ? _displayName : 'You'} — ${_isNestOwner ? 'Nest Owner 🏠' : 'Member'}',
                          style: GoogleFonts.nunitoSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.edit_rounded, color: Colors.white, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBirthdayAnniversaryCard(bool isTablet) {
    final anim = _itemAnimations.isNotEmpty
        ? _itemAnimations[1]
        : const AlwaysStoppedAnimation(1.0);

    String monthName(int month) {
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return months[month - 1];
    }

    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
          offset: Offset(0, 20 * (1 - anim.value)),
          child: child,
        ),
      ),
      child: Container(
        margin: EdgeInsets.fromLTRB(
          isTablet ? 28 : 20,
          12,
          isTablet ? 28 : 20,
          0,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _cardBorder, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Birthday row
            GestureDetector(
              onTap: () => _pickDateOnMain(isBirthday: true),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    const Icon(
                      Icons.cake_rounded,
                      color: Color(0xFFE05C5C),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _birthday != null
                            ? '${monthName(_birthday!.month)} ${_birthday!.day}'
                            : 'Birthday (optional)',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 15,
                          fontWeight: _birthday != null
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: _birthday != null
                              ? _textPrimary
                              : const Color(0xFFB0A898),
                        ),
                      ),
                    ),
                    if (_birthday != null)
                      GestureDetector(
                        onTap: () async {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.remove('birthday');
                          setState(() => _birthday = null);
                        },
                        child: const Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: Color(0xFFB0A898),
                        ),
                      )
                    else
                      const Icon(
                        Icons.calendar_today_rounded,
                        size: 16,
                        color: Color(0xFFB0A898),
                      ),
                  ],
                ),
              ),
            ),
            const Divider(color: Color(0xFFE8E0D0), height: 1),
            // Anniversary row
            GestureDetector(
              onTap: () => _pickDateOnMain(isBirthday: false),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    const Icon(
                      Icons.favorite_rounded,
                      color: Color(0xFFD4AA00),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _anniversary != null
                            ? '${monthName(_anniversary!.month)} ${_anniversary!.day}'
                            : 'Anniversary (optional)',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 15,
                          fontWeight: _anniversary != null
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: _anniversary != null
                              ? _textPrimary
                              : const Color(0xFFB0A898),
                        ),
                      ),
                    ),
                    if (_anniversary != null)
                      GestureDetector(
                        onTap: () async {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.remove('anniversary');
                          setState(() => _anniversary = null);
                        },
                        child: const Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: Color(0xFFB0A898),
                        ),
                      )
                    else
                      const Icon(
                        Icons.calendar_today_rounded,
                        size: 16,
                        color: Color(0xFFB0A898),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDateOnMain({required bool isBirthday}) async {
    final now = DateTime.now();
    final initial = isBirthday
        ? (_birthday ?? DateTime(now.year - 60, 1, 1))
        : (_anniversary ?? DateTime(now.year - 10, 1, 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: isBirthday ? 'Select Birthday' : 'Select Anniversary',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF5DA399),
            onPrimary: Colors.white,
            surface: Color(0xFFFDFDFD),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      final prefs = await SharedPreferences.getInstance();
      if (isBirthday) {
        await prefs.setString('birthday', picked.toIso8601String());
        setState(() => _birthday = picked);
      } else {
        await prefs.setString('anniversary', picked.toIso8601String());
        setState(() => _anniversary = picked);
      }
    }
  }

  Widget _buildGuestAccountBanner(bool isTablet) {
    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(context, '/save-messages-prompt-screen');
      },
      child: Container(
        margin: EdgeInsets.fromLTRB(
          isTablet ? 28 : 20,
          16,
          isTablet ? 28 : 20,
          0,
        ),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF5DA399).withAlpha(20),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF5DA399).withAlpha(100),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF5DA399).withAlpha(40),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_add_rounded,
                color: Color(0xFF5DA399),
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Create Account to Save Your Messages',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Tap to sign up and keep your messages & stories safe',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 12,
                      color: _textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: Color(0xFF5DA399),
              size: 14,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInviteCodeCard(bool isTablet) {
    final anim = _itemAnimations.length > 1
        ? _itemAnimations[1]
        : const AlwaysStoppedAnimation(1.0);
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) => Opacity(opacity: anim.value, child: child),
      child: Container(
        margin: EdgeInsets.fromLTRB(
          isTablet ? 28 : 20,
          16,
          isTablet ? 28 : 20,
          0,
        ),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFD4AA00).withAlpha(15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFD4AA00).withAlpha(80),
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.vpn_key_rounded,
                  color: Color(0xFFD4AA00),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Your Invite Code',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
                const Spacer(),
                // Only Nest Owner (senior) sees this — functional share button
                GestureDetector(
                  onTap: _shareInviteCode,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF5DA399),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.ios_share_rounded,
                          color: Colors.white,
                          size: 15,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Share',
                          style: GoogleFonts.nunitoSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Tappable code with copy feedback
            GestureDetector(
              onTap: () {
                final code = _inviteCode;
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Invite code copied! 📋',
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
              },
              child: SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _inviteCode,
                        style: GoogleFonts.nunitoSans(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFFD4AA00),
                          letterSpacing: 6,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.copy_rounded,
                        color: Color(0xFFD4AA00),
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Tap code to copy • Only you can share this as Nest Owner',
                style: GoogleFonts.nunitoSans(
                  fontSize: 12,
                  color: _textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNestSection(bool isTablet) {
    final anim = _itemAnimations.length > 2
        ? _itemAnimations[2]
        : const AlwaysStoppedAnimation(1.0);
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) => Opacity(opacity: anim.value, child: child),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          isTablet ? 28 : 20,
          24,
          isTablet ? 28 : 20,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('🏡', 'Your Nest'),
            const SizedBox(height: 12),
            if (_isNestOwner)
              _buildSettingRow(
                icon: Icons.home_rounded,
                label: 'Nest Name',
                value: _nestName,
                onTap: () => _showEditNestSheet(),
              ),
            _buildSettingRow(
              icon: Icons.people_rounded,
              label: 'Family Members',
              value: '${_familyMembers.length} members',
              onTap: () => _showFamilyMembersSheet(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreferencesSection(bool isTablet) {
    final anim = _itemAnimations.length > 4
        ? _itemAnimations[4]
        : const AlwaysStoppedAnimation(1.0);
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) => Opacity(opacity: anim.value, child: child),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          isTablet ? 28 : 20,
          24,
          isTablet ? 28 : 20,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('⚙️', 'Preferences'),
            const SizedBox(height: 12),
            if (_isSenior) ...[
              _buildToggleRow(
                icon: Icons.medication_rounded,
                label: 'Medication Reminders',
                value: _medsReminders,
                onChanged: (v) => _togglePref('meds_reminders', v),
              ),
              _buildToggleRow(
                icon: Icons.favorite_rounded,
                label: 'Daily Check-In',
                value: _dailyCheckIn,
                onChanged: (v) => _togglePref('daily_check_in', v),
              ),
            ],
            _buildSettingRow(
              icon: Icons.text_fields_rounded,
              label: 'Text Size',
              value: _textSize,
              onTap: () => _showTextSizeSheet(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationsSection(bool isTablet) {
    final anim = _itemAnimations.length > 6
        ? _itemAnimations[6]
        : const AlwaysStoppedAnimation(1.0);
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) => Opacity(opacity: anim.value, child: child),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          isTablet ? 28 : 20,
          24,
          isTablet ? 28 : 20,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('🔔', 'Notifications'),
            const SizedBox(height: 12),
            _buildToggleRow(
              icon: Icons.chat_bubble_rounded,
              label: 'New Messages',
              value: _notifyMessages,
              onChanged: (v) => _togglePref('notify_messages', v),
            ),
            _buildToggleRow(
              icon: Icons.favorite_rounded,
              label: '"I\'m Good Today" Check-ins',
              value: _notifyCheckIn,
              onChanged: (v) => _togglePref('notify_check_in', v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppearanceSection(bool isTablet) {
    final anim = _itemAnimations.length > 8
        ? _itemAnimations[8]
        : const AlwaysStoppedAnimation(1.0);
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) => Opacity(opacity: anim.value, child: child),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          isTablet ? 28 : 20,
          24,
          isTablet ? 28 : 20,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('🎨', 'Appearance'),
            const SizedBox(height: 12),
            _buildToggleRow(
              icon: Icons.dark_mode_rounded,
              label: 'Dark Mode',
              value: _isDarkMode,
              onChanged: _toggleDarkMode,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountSection(bool isTablet) {
    final anim = _itemAnimations.length > 10
        ? _itemAnimations[10]
        : const AlwaysStoppedAnimation(1.0);
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) => Opacity(opacity: anim.value, child: child),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          isTablet ? 28 : 20,
          24,
          isTablet ? 28 : 20,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('👤', 'Account'),
            const SizedBox(height: 12),
            _buildSettingRow(
              icon: Icons.help_outline_rounded,
              label: 'Help & Support',
              value: '',
              onTap: () => Navigator.pushNamed(context, '/help-support-screen'),
            ),
            _buildSettingRow(
              icon: Icons.privacy_tip_outlined,
              label: 'Privacy Policy',
              value: '',
              onTap: () =>
                  Navigator.pushNamed(context, '/privacy-policy-screen'),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => _showSignOutDialog(),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFC0392B).withAlpha(10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFC0392B).withAlpha(40),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.logout_rounded,
                      color: Color(0xFFC0392B),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Sign Out',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFC0392B),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => _showDeleteAccountDialog(),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B0000).withAlpha(10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF8B0000).withAlpha(40),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.delete_forever_rounded,
                      color: Color(0xFF8B0000),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Delete Account',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF8B0000),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String emoji, String title) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.nunitoSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildSettingRow({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _cardBorder, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF5DA399), size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.nunitoSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _textPrimary,
                ),
              ),
            ),
            if (value.isNotEmpty) ...[
              Text(
                value,
                style: GoogleFonts.nunitoSans(
                  fontSize: 13,
                  color: _textSecondary,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Icon(Icons.chevron_right_rounded, color: _textSecondary, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleRow({
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cardBorder, width: 1.5),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF5DA399), size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.nunitoSans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _textPrimary,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: const Color(0xFF5DA399),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: 6,
      itemBuilder: (context, index) => Container(
        height: index == 0 ? 100 : 60,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  void _showEditProfileSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EditProfileSheet(
        displayName: _displayName,
        birthday: _birthday,
        anniversary: _anniversary,
        isDarkMode: _isDarkMode,
        onSave: (name, birthday, anniversary) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('display_name', name);
          if (birthday != null) {
            await prefs.setString('birthday', birthday.toIso8601String());
          } else {
            await prefs.remove('birthday');
          }
          if (anniversary != null) {
            await prefs.setString('anniversary', anniversary.toIso8601String());
          } else {
            await prefs.remove('anniversary');
          }
          setState(() {
            _displayName = name;
            _birthday = birthday;
            _anniversary = anniversary;
          });
        },
      ),
    );
  }

  void _showEditNestSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EditNestSheet(
        nestName: _nestName,
        isDarkMode: _isDarkMode,
        onSave: (name) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('nest_name', name);
          setState(() => _nestName = name);
        },
      ),
    );
  }

  void _showFamilyMembersSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _FamilyMembersSheet(
        members: List<Map<String, dynamic>>.from(_familyMembers),
        isNestOwner: _isNestOwner,
        isDarkMode: _isDarkMode,
        onRemoveMember: (memberId) => _confirmRemoveMember(memberId),
      ),
    );
  }

  void _confirmRemoveMember(String memberId) {
    final member = _familyMembers.firstWhere(
      (m) => m['id'] == memberId,
      orElse: () => {},
    );
    if (member.isEmpty) return;

    // Close the members sheet first
    Navigator.pop(context);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Remove ${member['name']}?',
          style: GoogleFonts.nunitoSans(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
        content: Text(
          '${member['name']} will be removed from the nest and will no longer have access.',
          style: GoogleFonts.nunitoSans(
            fontSize: 15,
            color: _textSecondary,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.nunitoSans(
                fontSize: 15,
                color: _textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              // Persist removal
              final prefs = await SharedPreferences.getInstance();
              final removedIds =
                  prefs.getStringList('removed_member_ids') ?? [];
              if (!removedIds.contains(memberId)) {
                removedIds.add(memberId);
                await prefs.setStringList('removed_member_ids', removedIds);
              }
              setState(() {
                _familyMembers.removeWhere((m) => m['id'] == memberId);
              });
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '${member['name']} has been removed from the nest.',
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
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            },
            child: Text(
              'Remove',
              style: GoogleFonts.nunitoSans(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFC0392B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showTextSizeSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8E0D0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Text Size',
                style: GoogleFonts.nunitoSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
              if (_isSenior) ...[
                const SizedBox(height: 6),
                Text(
                  'Seniors default to Large for comfortable reading',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 12,
                    color: _textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              ...['Normal', 'Large', 'Extra Large'].map((size) {
                final isSelected = _textSize == size;
                final fontSize = size == 'Normal'
                    ? 15.0
                    : size == 'Large'
                    ? 18.0
                    : 22.0;
                return GestureDetector(
                  onTap: () async {
                    // Apply immediately and persist
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('text_size', size);
                    // Update global notifier so the whole app rescales at once
                    appTextScaleNotifier.value = textSizeToScale(size);
                    setState(() => _textSize = size);
                    setSheetState(() {});
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF5DA399).withAlpha(20)
                          : _surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF5DA399)
                            : _cardBorder,
                        width: isSelected ? 2 : 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          'Aa',
                          style: GoogleFonts.nunitoSans(
                            fontSize: fontSize,
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? const Color(0xFF5DA399)
                                : _textPrimary,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          size,
                          style: GoogleFonts.nunitoSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? const Color(0xFF5DA399)
                                : _textPrimary,
                          ),
                        ),
                        if (_isSenior && size == 'Large' && !isSelected) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD4AA00).withAlpha(30),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Recommended',
                              style: GoogleFonts.nunitoSans(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFFD4AA00),
                              ),
                            ),
                          ),
                        ],
                        if (isSelected) ...[
                          const Spacer(),
                          const Icon(
                            Icons.check_circle_rounded,
                            color: Color(0xFF5DA399),
                            size: 22,
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete Account?',
          style: GoogleFonts.nunitoSans(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
        content: Text(
          'This will permanently delete your account and all your data. This cannot be undone.',
          style: GoogleFonts.nunitoSans(
            fontSize: 15,
            color: _textSecondary,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.nunitoSans(
                fontSize: 15,
                color: _textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await Supabase.instance.client.rpc('delete_user');
              } catch (_) {}
              try {
                await Supabase.instance.client.auth.signOut();
              } catch (_) {}
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (mounted) {
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/splash-screen',
                  (route) => false,
                );
              }
            },
            child: Text(
              'Delete Account',
              style: GoogleFonts.nunitoSans(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF8B0000),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSignOutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Sign Out?',
          style: GoogleFonts.nunitoSans(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
        content: Text(
          'You\'ll need to sign back in to access your family nest.',
          style: GoogleFonts.nunitoSans(
            fontSize: 15,
            color: _textSecondary,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.nunitoSans(
                fontSize: 15,
                color: _textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              // Sign out from Supabase (and Google if applicable)
              await AuthService.signOut();
              // Keep has_onboarded and other permanent flags so user goes
              // straight to Sign In next time, not back through onboarding.
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('just_signed_out', true);
              if (mounted) {
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/splash-screen',
                  (route) => false,
                );
              }
            },
            child: Text(
              'Sign Out',
              style: GoogleFonts.nunitoSans(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFC0392B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({
    required this.displayName,
    required this.isDarkMode,
    required this.onSave,
    this.birthday,
    this.anniversary,
  });
  final String displayName;
  final bool isDarkMode;
  final DateTime? birthday;
  final DateTime? anniversary;
  final Future<void> Function(String, DateTime?, DateTime?) onSave;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late TextEditingController _nameController;
  bool _isSaving = false;
  DateTime? _birthday;
  DateTime? _anniversary;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.displayName);
    _birthday = widget.birthday;
    _anniversary = widget.anniversary;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Color get _bg =>
      widget.isDarkMode ? const Color(0xFF242018) : const Color(0xFFFDFDFD);
  Color get _textPrimary =>
      widget.isDarkMode ? const Color(0xFFF5EDD8) : const Color(0xFF2C2417);
  Color get _textSecondary =>
      widget.isDarkMode ? const Color(0xFFB8A888) : const Color(0xFF6B5E4E);

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: 24 + bottomPadding,
      ),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE8E0D0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Edit Profile',
            style: GoogleFonts.nunitoSans(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            style: GoogleFonts.nunitoSans(fontSize: 18, color: _textPrimary),
            decoration: InputDecoration(
              labelText: 'Your name',
              labelStyle: GoogleFonts.nunitoSans(
                fontSize: 13,
                color: _textSecondary,
              ),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFE8E0D0), width: 1.5),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF5DA399), width: 2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildDateField(
            label: 'Birthday (optional)',
            icon: Icons.cake_rounded,
            iconColor: const Color(0xFFE05C5C),
            value: _birthday,
            onTap: () => _pickDate(isBirthday: true),
          ),
          const SizedBox(height: 12),
          _buildDateField(
            label: 'Anniversary (optional)',
            icon: Icons.favorite_rounded,
            iconColor: const Color(0xFFD4AA00),
            value: _anniversary,
            onTap: () => _pickDate(isBirthday: false),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isSaving
                  ? null
                  : () async {
                      if (_nameController.text.trim().isEmpty) return;
                      setState(() => _isSaving = true);
                      await widget.onSave(
                        _nameController.text.trim(),
                        _birthday,
                        _anniversary,
                      );
                      if (mounted) Navigator.pop(context);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5DA399),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'Save Changes',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateField({
    required String label,
    required IconData icon,
    required Color iconColor,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    final hasValue = value != null;
    final displayText = hasValue
        ? '${_monthName(value.month)} ${value.day}'
        : label;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0xFFE8E0D0), width: 1.5),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                displayText,
                style: GoogleFonts.nunitoSans(
                  fontSize: 16,
                  fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400,
                  color: hasValue ? _textPrimary : const Color(0xFFB0A898),
                ),
              ),
            ),
            if (hasValue)
              GestureDetector(
                onTap: () => setState(() {
                  if (label.contains('Birthday')) {
                    _birthday = null;
                  } else {
                    _anniversary = null;
                  }
                }),
                child: const Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: Color(0xFFB0A898),
                ),
              )
            else
              const Icon(
                Icons.calendar_today_rounded,
                size: 16,
                color: Color(0xFFB0A898),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate({required bool isBirthday}) async {
    final now = DateTime.now();
    final initial = isBirthday
        ? (_birthday ?? DateTime(now.year - 60, 1, 1))
        : (_anniversary ?? DateTime(now.year - 10, 1, 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: isBirthday ? 'Select Birthday' : 'Select Anniversary',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF5DA399),
            onPrimary: Colors.white,
            surface: Color(0xFFFDFDFD),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isBirthday) {
          _birthday = picked;
        } else {
          _anniversary = picked;
        }
      });
    }
  }

  String _monthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }
}

class _EditNestSheet extends StatefulWidget {
  const _EditNestSheet({
    required this.nestName,
    required this.isDarkMode,
    required this.onSave,
  });
  final String nestName;
  final bool isDarkMode;
  final Future<void> Function(String) onSave;

  @override
  State<_EditNestSheet> createState() => _EditNestSheetState();
}

class _EditNestSheetState extends State<_EditNestSheet> {
  late TextEditingController _nestController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nestController = TextEditingController(text: widget.nestName);
  }

  @override
  void dispose() {
    _nestController.dispose();
    super.dispose();
  }

  Color get _bg =>
      widget.isDarkMode ? const Color(0xFF242018) : const Color(0xFFFDFDFD);
  Color get _textPrimary =>
      widget.isDarkMode ? const Color(0xFFF5EDD8) : const Color(0xFF2C2417);
  Color get _textSecondary =>
      widget.isDarkMode ? const Color(0xFFB8A888) : const Color(0xFF6B5E4E);

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: 24 + bottomPadding,
      ),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE8E0D0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Rename Your Nest',
            style: GoogleFonts.nunitoSans(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nestController,
            textCapitalization: TextCapitalization.words,
            style: GoogleFonts.nunitoSans(fontSize: 18, color: _textPrimary),
            decoration: InputDecoration(
              labelText: 'Nest name',
              labelStyle: GoogleFonts.nunitoSans(
                fontSize: 13,
                color: _textSecondary,
              ),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFE8E0D0), width: 1.5),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF5DA399), width: 2),
              ),
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isSaving
                  ? null
                  : () async {
                      if (_nestController.text.trim().isEmpty) return;
                      setState(() => _isSaving = true);
                      await widget.onSave(_nestController.text.trim());
                      if (mounted) Navigator.pop(context);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5DA399),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'Save Name',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Family Members Sheet ────────────────────────────────────────

class _FamilyMembersSheet extends StatefulWidget {
  const _FamilyMembersSheet({
    required this.members,
    required this.isNestOwner,
    required this.isDarkMode,
    required this.onRemoveMember,
  });

  final List<Map<String, dynamic>> members;
  final bool isNestOwner;
  final bool isDarkMode;
  final void Function(String memberId) onRemoveMember;

  @override
  State<_FamilyMembersSheet> createState() => _FamilyMembersSheetState();
}

class _FamilyMembersSheetState extends State<_FamilyMembersSheet> {
  Color get _bg =>
      widget.isDarkMode ? const Color(0xFF242018) : const Color(0xFFFDFDFD);
  Color get _cardBg =>
      widget.isDarkMode ? const Color(0xFF2E2820) : const Color(0xFFFAF7F2);
  Color get _cardBorder =>
      widget.isDarkMode ? const Color(0xFF3D3428) : const Color(0xFFE8E0D0);
  Color get _textPrimary =>
      widget.isDarkMode ? const Color(0xFFF5EDD8) : const Color(0xFF2C2417);
  Color get _textSecondary =>
      widget.isDarkMode ? const Color(0xFFB8A888) : const Color(0xFF6B5E4E);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE8E0D0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Title
          Row(
            children: [
              Text(
                'Family Members',
                style: GoogleFonts.nunitoSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF5DA399).withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${widget.members.length} members',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF5DA399),
                  ),
                ),
              ),
            ],
          ),
          if (widget.isNestOwner) ...[
            const SizedBox(height: 6),
            Text(
              'Tap a member to manage their access',
              style: GoogleFonts.nunitoSans(
                fontSize: 12,
                color: _textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 16),
          // Members list
          if (widget.members.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No family members have joined yet.',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 14,
                    color: _textSecondary,
                  ),
                ),
              ),
            )
          else
            ...widget.members.map((member) {
              return GestureDetector(
                onTap: widget.isNestOwner
                    ? () => _showMemberOptions(context, member)
                    : null,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: _cardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _cardBorder, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      // Avatar
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFF5DA399).withAlpha(40),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            member['initials'] as String,
                            style: GoogleFonts.nunitoSans(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF5DA399),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      // Name & relationship
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              member['name'] as String,
                              style: GoogleFonts.nunitoSans(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: _textPrimary,
                              ),
                            ),
                            Text(
                              member['relationship'] as String,
                              style: GoogleFonts.nunitoSans(
                                fontSize: 12,
                                color: _textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Only Nest Owner sees the manage chevron
                      if (widget.isNestOwner)
                        Icon(
                          Icons.more_vert_rounded,
                          color: _textSecondary,
                          size: 20,
                        ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  void _showMemberOptions(BuildContext context, Map<String, dynamic> member) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE8E0D0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            // Member info header
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF5DA399).withAlpha(40),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      member['initials'] as String,
                      style: GoogleFonts.nunitoSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF5DA399),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member['name'] as String,
                      style: GoogleFonts.nunitoSans(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                      ),
                    ),
                    Text(
                      member['relationship'] as String,
                      style: GoogleFonts.nunitoSans(
                        fontSize: 13,
                        color: _textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(color: Color(0xFFE8E0D0), height: 1),
            const SizedBox(height: 16),
            // Remove from Nest option
            GestureDetector(
              onTap: () {
                Navigator.pop(ctx); // close options sheet
                widget.onRemoveMember(member['id'] as String);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFC0392B).withAlpha(10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFC0392B).withAlpha(40),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.person_remove_rounded,
                      color: Color(0xFFC0392B),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Remove from Nest',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFC0392B),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Cancel
            GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: _cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _cardBorder, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
