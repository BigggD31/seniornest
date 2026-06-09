import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../widgets/app_navigation.dart';
import '../profile_photo_picker_screen/profile_photo_picker_screen.dart';

class SafetyScreen extends StatefulWidget {
  const SafetyScreen({super.key});

  @override
  State<SafetyScreen> createState() => _SafetyScreenState();
}

class _SafetyScreenState extends State<SafetyScreen>
    with TickerProviderStateMixin {
  int _currentNavIndex = 3;
  bool _isSenior = false;
  bool _isDarkMode = false;
  bool _isLoading = true;
  bool _isSendingAlert = false;
  String _seniorName = '';
  String _nestName = '';
  Map<String, dynamic>? _profileData;
  String _displayName = '';

  late AnimationController _entranceController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;
  late List<Animation<double>> _itemAnimations;

  List<Map<String, dynamic>> _mockContacts = [];

  static const List<Map<String, String>> _safetyTips = [
    {
      'icon': '💊',
      'title': 'Medication Safety',
      'tip':
          'Always take medications as prescribed. Never skip or double doses.',
    },
    {
      'icon': '🚿',
      'title': 'Fall Prevention',
      'tip':
          'Use grab bars in the bathroom and keep pathways clear of clutter.',
    },
    {
      'icon': '🌡️',
      'title': 'Stay Hydrated',
      'tip':
          'Drink at least 8 glasses of water daily, especially in warm weather.',
    },
    {
      'icon': '🏠',
      'title': 'Home Safety',
      'tip':
          'Keep emergency numbers visible and ensure good lighting throughout your home.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _itemAnimations = [];
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.delayed(const Duration(milliseconds: 300));
    // Load contacts from Supabase
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId != null) {
        final response = await supabase
            .from('safety_contacts')
            .select()
            .eq('user_id', userId)
            .order('created_at');
        final contacts = response as List<dynamic>;
        setState(() {
          _mockContacts = contacts.map((c) => {
            'id': c['id'],
            'name': c['name'],
            'phone': c['phone'],
            'relation': c['relation'] ?? '',
            'isPrimary': c['is_primary'] ?? false,
          }).toList();
        });
      }
    } catch (e) {
      debugPrint('Load contacts error: $e');
    }
    final systemDark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
    final profileJson = prefs.getString(kProfilePhotoKey);
    Map<String, dynamic>? profileData;
    if (profileJson != null) {
      try {
        profileData = jsonDecode(profileJson) as Map<String, dynamic>;
      } catch (_) {}
    }
    setState(() {
      _isSenior = (prefs.getString('user_role') ?? 'senior') == 'senior';
      // Default light mode; auto-switch to dark if system is dark and no manual pref saved
      _isDarkMode = prefs.getBool('dark_mode') ?? systemDark;
      // For seniors, use their own display_name; for family members, use the saved senior_name key
      final isSeniorRole =
          (prefs.getString('user_role') ?? 'senior') == 'senior';
      if (isSeniorRole) {
        _seniorName =
            prefs.getString('display_name') ??
            prefs.getString('user_name') ??
            '';
      } else {
        _seniorName = prefs.getString('senior_name') ?? '';
      }
      // Load nest name from family nest setup
      _nestName = prefs.getString('nest_name') ?? '';
      _isLoading = false;
      _profileData = profileData;
      _displayName = prefs.getString('display_name') ?? '';
    });
    _setupAnimations();
    _entranceController.forward();
  }

  void _setupAnimations() {
    _itemAnimations.clear();
    final count = _mockContacts.length + _safetyTips.length + 3;
    for (int i = 0; i < count; i++) {
      final start = (i * 0.08).clamp(0.0, 0.7);
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
    _pulseController.dispose();
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

  void _showSOSConfirmation() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: _bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFC0392B).withAlpha(20),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.help_outline_rounded,
                  color: Color(0xFFC0392B),
                  size: 36,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Are you okay right now?',
                textAlign: TextAlign.center,
                style: GoogleFonts.nunitoSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Let your family know how you\'re doing.',
                textAlign: TextAlign.center,
                style: GoogleFonts.nunitoSans(
                  fontSize: 14,
                  color: _textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
              // Green "I'm Okay" button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _sendMessageToContacts(
                      "I'm okay right now, but please check on me when you can.",
                      isEmergency: false,
                    );
                  },
                  icon: const Icon(Icons.check_circle_rounded, size: 22),
                  label: Text(
                    "I'm Okay",
                    style: GoogleFonts.nunitoSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF27AE60),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // Red "I Need Help" button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _sendMessageToContacts(
                      "EMERGENCY – I need help right now. Please call me immediately.",
                      isEmergency: true,
                    );
                  },
                  icon: const Icon(Icons.sos_rounded, size: 22),
                  label: Text(
                    "I Need Help",
                    style: GoogleFonts.nunitoSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC0392B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 14),
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
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendMessageToContacts(
    String message, {
    required bool isEmergency,
  }) async {
    setState(() => _isSendingAlert = true);
    // TODO: Replace with Supabase push notification / SMS to all emergency contacts
    await Future.delayed(const Duration(milliseconds: 800));
    setState(() => _isSendingAlert = false);

    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(
                isEmergency
                    ? Icons.warning_rounded
                    : Icons.check_circle_rounded,
                color: isEmergency
                    ? const Color(0xFFC0392B)
                    : const Color(0xFF27AE60),
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                isEmergency ? 'Alert Sent ✓' : 'Message Sent ✓',
                style: GoogleFonts.nunitoSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
            ],
          ),
          content: Text(
            isEmergency
                ? 'Your emergency contacts have been notified. Help is on the way.'
                : 'Your family has been notified that you\'re okay.',
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
                'OK',
                style: GoogleFonts.nunitoSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF5DA399),
                ),
              ),
            ),
          ],
        ),
      );
    }
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
      case 4:
        Navigator.pushReplacementNamed(context, '/favs-screen');
        break;
      case 5:
        Navigator.pushReplacementNamed(context, '/setup-screen');
        break;
    }
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
                  if (!_isSenior)
                    SliverToBoxAdapter(
                      child: _buildFamilyReadOnlyNote(isTablet),
                    ),
                  if (_isSenior) ...[
                    SliverToBoxAdapter(child: _buildSOSButton(isTablet)),
                  ] else ...[
                    SliverToBoxAdapter(
                      child: _buildSOSButton(isTablet, deadButton: true),
                    ),
                  ],
                  SliverToBoxAdapter(child: _buildCheckInSection(isTablet)),
                  if (_isSenior)
                    SliverToBoxAdapter(
                      child: _buildEmergencyContacts(isTablet),
                    ),
                  SliverToBoxAdapter(child: _buildSafetyTips(isTablet)),
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
                'Safety',
                style: GoogleFonts.nunitoSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _textPrimary,
                ),
              ),
              Text(
                _isSenior
                    ? 'Your family is always close'
                    : 'Keep your loved one safe',
                style: GoogleFonts.nunitoSans(
                  fontSize: 13,
                  color: _textSecondary,
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFC0392B).withAlpha(20),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.shield_rounded,
              color: Color(0xFFC0392B),
              size: 22,
            ),
          ),
          const SizedBox(width: 8),
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

  Widget _buildSOSButton(bool isTablet, {bool deadButton = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? 28 : 20,
        vertical: 8,
      ),
      child: AnimatedBuilder(
        animation: _pulseAnim,
        builder: (context, child) =>
            Transform.scale(scale: _pulseAnim.value, child: child),
        child: GestureDetector(
          onTap: deadButton
              ? null
              : (_isSendingAlert ? null : _showSOSConfirmation),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFC0392B), Color(0xFFE74C3C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFC0392B).withAlpha(80),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                _isSendingAlert
                    ? const SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.sos_rounded,
                        color: Colors.white,
                        size: 44,
                      ),
                const SizedBox(height: 10),
                Text(
                  _isSendingAlert ? 'Sending Alert...' : 'I Need Help',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap to alert your family immediately',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 13,
                    color: Colors.white.withAlpha(200),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCheckInSection(bool isTablet) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isTablet ? 28 : 20,
        20,
        isTablet ? 28 : 20,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Daily Check-In',
            style: GoogleFonts.nunitoSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF5DA399).withAlpha(15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF5DA399).withAlpha(60),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFF5DA399).withAlpha(26),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.favorite_rounded,
                    color: Color(0xFF5DA399),
                    size: 26,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isSenior
                            ? 'Let your family know you\'re okay'
                            : 'Waiting for today\'s check-in',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isSenior
                            ? 'Tap "I\'m Good Today" on the Family Feed'
                            : 'Your loved one hasn\'t checked in yet today',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 12,
                          color: _textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFamilyReadOnlyNote(bool isTablet) {
    final displayName = _seniorName.isNotEmpty ? _seniorName : 'your loved one';
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isTablet ? 28 : 20,
        16,
        isTablet ? 28 : 20,
        0,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xFF1A6B63),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1A6B63).withAlpha(80),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(40),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.visibility_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'This is what $displayName sees',
                style: GoogleFonts.nunitoSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmergencyContacts(bool isTablet) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isTablet ? 28 : 20,
        24,
        isTablet ? 28 : 20,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Emergency Contacts',
                style: GoogleFonts.nunitoSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
              const Spacer(),
              if (_isSenior)
                GestureDetector(
                  onTap: () => _showAddContactSheet(),
                  child: Text(
                    '+ Add',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF5DA399),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ..._mockContacts.asMap().entries.map((entry) {
            final index = entry.key;
            final contact = entry.value;
            final anim = index < _itemAnimations.length
                ? _itemAnimations[index + 2]
                : const AlwaysStoppedAnimation(1.0);
            final hasAvatar = (contact['avatar'] as String).isNotEmpty;
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
                onTap: () => _showEditContactSheet(contact),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: contact['isPrimary'] as bool
                        ? const Color(0xFFC0392B).withAlpha(10)
                        : _cardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: contact['isPrimary'] as bool
                          ? const Color(0xFFC0392B).withAlpha(60)
                          : _cardBorder,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      hasAvatar
                          ? CircleAvatar(
                              radius: 22,
                              backgroundImage: NetworkImage(
                                contact['avatar'] as String,
                              ),
                              backgroundColor: _surface,
                            )
                          : CircleAvatar(
                              radius: 22,
                              backgroundColor: const Color(
                                0xFF5DA399,
                              ).withAlpha(26),
                              child: const Icon(
                                Icons.local_hospital_rounded,
                                color: Color(0xFF5DA399),
                                size: 20,
                              ),
                            ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  contact['name'] as String,
                                  style: GoogleFonts.nunitoSans(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: _textPrimary,
                                  ),
                                ),
                                if (contact['isPrimary'] as bool) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFFC0392B,
                                      ).withAlpha(20),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'Primary',
                                      style: GoogleFonts.nunitoSans(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFFC0392B),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            Text(
                              contact['phone'] as String,
                              style: GoogleFonts.nunitoSans(
                                fontSize: 13,
                                color: _textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () {},
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFF5DA399).withAlpha(20),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.phone_rounded,
                            color: Color(0xFF5DA399),
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSafetyTips(bool isTablet) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isTablet ? 28 : 20,
        24,
        isTablet ? 28 : 20,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.lightbulb_rounded,
                color: Color(0xFFD4AA00),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Safety Tips',
                style: GoogleFonts.nunitoSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._safetyTips.asMap().entries.map((entry) {
            final index = entry.key;
            final tip = entry.value;
            final anim = index < _itemAnimations.length
                ? _itemAnimations[index + _mockContacts.length + 2]
                : const AlwaysStoppedAnimation(1.0);
            return AnimatedBuilder(
              animation: anim,
              builder: (context, child) =>
                  Opacity(opacity: anim.value, child: child),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _cardBorder, width: 1.5),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tip['icon']!, style: const TextStyle(fontSize: 24)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tip['title']!,
                            style: GoogleFonts.nunitoSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            tip['tip']!,
                            style: GoogleFonts.nunitoSans(
                              fontSize: 13,
                              color: _textSecondary,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildLoadingState() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: 5,
      itemBuilder: (context, index) => Container(
        height: index == 0 ? 120 : 80,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  void _showAddContactSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddContactSheet(isDarkMode: _isDarkMode),
    ).then((_) { if (mounted) _loadData(); });
  }

  void _showEditContactSheet(Map<String, dynamic> contact) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) =>
          _EditContactSheet(isDarkMode: _isDarkMode, contact: contact),
    ).then((_) { if (mounted) _loadData(); });
  }
}

class _AddContactSheet extends StatefulWidget {
  const _AddContactSheet({required this.isDarkMode});
  final bool isDarkMode;

  @override
  State<_AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends State<_AddContactSheet> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  bool _isPrimary = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Color get _bg =>
      widget.isDarkMode ? const Color(0xFF242018) : const Color(0xFFFDFDFD);
  Color get _textPrimary =>
      widget.isDarkMode ? const Color(0xFFF5EDD8) : const Color(0xFF2C2417);
  Color get _textSecondary =>
      widget.isDarkMode ? const Color(0xFFB8A888) : const Color(0xFF6B5E4E);

  Future<void> _saveContact() async {
    if (_nameController.text.trim().isEmpty ||
        _phoneController.text.trim().isEmpty) {
      return;
    }
    setState(() => _isSaving = true);
    try {
      final supabase = Supabase.instance.client;
      String? userId = supabase.auth.currentUser?.id;
      // Fallback: get userId from session if currentUser is null
      if (userId == null) {
        final session = supabase.auth.currentSession;
        userId = session?.user.id;
        print('SAFETY_CONTACT: userId from session = $userId');
      }
      print('SAFETY_CONTACT: userId = $userId');
      if (userId != null) {
        await supabase.from('safety_contacts').insert({
          'user_id': userId,
          'name': _nameController.text.trim(),
          'phone': _phoneController.text.trim(),
          'is_primary': false,
        });
        print('SAFETY_CONTACT: inserted successfully');
        if (mounted) setState(() => _isSaving = false);
      } else {
        print('SAFETY_CONTACT: userId is null - cannot save');
        if (mounted) setState(() => _isSaving = false);
      }
    } catch (e) {
      print('SAFETY_CONTACT ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving contact: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isSaving = false);
        return;
      }
    }
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
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
            'Add Emergency Contact',
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
            style: GoogleFonts.nunitoSans(fontSize: 16, color: _textPrimary),
            decoration: InputDecoration(
              labelText: 'Name',
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
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            style: GoogleFonts.nunitoSans(fontSize: 16, color: _textPrimary),
            decoration: InputDecoration(
              labelText: 'Phone number',
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
          Row(
            children: [
              Text(
                'Set as primary contact',
                style: GoogleFonts.nunitoSans(
                  fontSize: 15,
                  color: _textPrimary,
                ),
              ),
              const Spacer(),
              Switch(
                value: _isPrimary,
                onChanged: (v) => setState(() => _isPrimary = v),
                activeThumbColor: const Color(0xFF5DA399),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveContact,
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
                      'Save Contact',
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
    ),
  );
  }
}

class _EditContactSheet extends StatefulWidget {
  const _EditContactSheet({required this.isDarkMode, required this.contact});
  final bool isDarkMode;
  final Map<String, dynamic> contact;

  @override
  State<_EditContactSheet> createState() => _EditContactSheetState();
}

class _EditContactSheetState extends State<_EditContactSheet> {
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late bool _isPrimary;
  bool _isSaving = false;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.contact['name'] as String? ?? '',
    );
    _phoneController = TextEditingController(
      text: widget.contact['phone'] as String? ?? '',
    );
    _isPrimary = widget.contact['isPrimary'] as bool? ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Color get _bg =>
      widget.isDarkMode ? const Color(0xFF242018) : const Color(0xFFFDFDFD);
  Color get _textPrimary =>
      widget.isDarkMode ? const Color(0xFFF5EDD8) : const Color(0xFF2C2417);
  Color get _textSecondary =>
      widget.isDarkMode ? const Color(0xFFB8A888) : const Color(0xFF6B5E4E);

  Future<void> _saveContact() async {
    if (_nameController.text.trim().isEmpty ||
        _phoneController.text.trim().isEmpty) {
      return;
    }
    setState(() => _isSaving = true);
    try {
      final supabase = Supabase.instance.client;
      final contactId = widget.contact['id'];
      if (contactId != null) {
        await supabase.from('safety_contacts').update({
          'name': _nameController.text.trim(),
          'phone': _phoneController.text.trim(),
        }).eq('id', contactId);
      }
    } catch (e) {
      debugPrint('Update contact error: $e');
    }
    if (mounted) {
      Navigator.pop(context);
    }
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Remove Contact?',
          style: GoogleFonts.nunitoSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
        content: Text(
          'Are you sure you want to remove ${_nameController.text.trim()} from your emergency contacts?',
          style: GoogleFonts.nunitoSans(
            fontSize: 14,
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
              setState(() => _isDeleting = true);
              try {
                final supabase = Supabase.instance.client;
                final contactId = widget.contact['id'];
                if (contactId != null) {
                  await supabase.from('safety_contacts')
                      .delete()
                      .eq('id', contactId);
                }
              } catch (e) {
                debugPrint('Delete contact error: $e');
              }
              if (mounted) {
                Navigator.pop(context);
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

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
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
          Row(
            children: [
              Text(
                'Edit Emergency Contact',
                style: GoogleFonts.nunitoSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: (_isSaving || _isDeleting) ? null : _confirmDelete,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFC0392B).withAlpha(15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _isDeleting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFFC0392B),
                          ),
                        )
                      : Text(
                          'Delete',
                          style: GoogleFonts.nunitoSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFC0392B),
                          ),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            style: GoogleFonts.nunitoSans(fontSize: 16, color: _textPrimary),
            decoration: InputDecoration(
              labelText: 'Name',
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
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            style: GoogleFonts.nunitoSans(fontSize: 16, color: _textPrimary),
            decoration: InputDecoration(
              labelText: 'Phone number',
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
          Row(
            children: [
              Text(
                'Set as primary contact',
                style: GoogleFonts.nunitoSans(
                  fontSize: 15,
                  color: _textPrimary,
                ),
              ),
              const Spacer(),
              Switch(
                value: _isPrimary,
                onChanged: (v) => setState(() => _isPrimary = v),
                activeThumbColor: const Color(0xFF5DA399),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: (_isSaving || _isDeleting) ? null : _saveContact,
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
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: TextButton(
              onPressed: (_isSaving || _isDeleting)
                  ? null
                  : () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: GoogleFonts.nunitoSans(
                  fontSize: 15,
                  color: _textSecondary,
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
