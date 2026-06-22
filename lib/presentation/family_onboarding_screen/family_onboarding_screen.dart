import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../routes/app_routes.dart';
import '../../services/share_service.dart';
import '../profile_photo_picker_screen/profile_photo_picker_screen.dart';

class FamilyOnboardingScreen extends StatefulWidget {
  const FamilyOnboardingScreen({super.key});

  @override
  State<FamilyOnboardingScreen> createState() => _FamilyOnboardingScreenState();
}

class _FamilyOnboardingScreenState extends State<FamilyOnboardingScreen>
    with TickerProviderStateMixin {
  int _currentStep = 0;
  bool _isLoading = false;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _inviteCodeController = TextEditingController();
  final TextEditingController _nestNameController = TextEditingController();
  String? _selectedRelationship;
  bool _notifyOnCheckIn = true;
  bool _notifyOnMessages = true;
  String _savedName = '';
  String _inviteCode = 'NEST-7842';
  bool _joinedViaInvite = false;
  Map<String, dynamic>? _profilePhotoData;
  DateTime? _birthday;
  DateTime? _anniversary;

  late AnimationController _entranceController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  static const List<String> _relationships = [
    'Son',
    'Daughter',
    'Grandson',
    'Granddaughter',
    'Spouse',
    'Sibling',
    'Caregiver',
    'Friend',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOut),
    );
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: Curves.easeOutCubic,
          ),
        );
    _entranceController.forward();
    _loadInviteCode();

    // Pre-fill invite code if passed as argument, or handle startAtStep
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map) {
        if (args['invite_code'] != null) {
          _inviteCodeController.text = args['invite_code'] as String;
        }
        if (args['startAtStep'] == 1) {
          // Restore name and relationship passed back from subscribe screen
          if (args['name'] != null) {
            _nameController.text = args['name'] as String;
          }
          if (args['relationship'] != null) {
            _selectedRelationship = args['relationship'] as String;
          }
          if (args['nestName'] != null) {
            _nestNameController.text = args['nestName'] as String;
          }
          setState(() => _currentStep = 1);
          _entranceController
            ..reset()
            ..forward();
        }
      }
    });
  }

  Future<void> _loadInviteCode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('invite_code');
    final joinedViaInvite = prefs.getBool('joined_via_invite') ?? false;
    final profileJson = prefs.getString(kProfilePhotoKey);
    // Restore birthday/anniversary saved before the subscribe-screen detour
    final birthdayStr = prefs.getString('birthday');
    final anniversaryStr = prefs.getString('anniversary');
    if (mounted) {
      setState(() {
        if (saved != null && saved.isNotEmpty) _inviteCode = saved;
        _joinedViaInvite = joinedViaInvite;
        if (profileJson != null) {
          try {
            _profilePhotoData = jsonDecode(profileJson) as Map<String, dynamic>;
          } catch (_) {}
        }
        if (birthdayStr != null && _birthday == null) {
          try {
            _birthday = DateTime.parse(birthdayStr);
          } catch (_) {}
        }
        if (anniversaryStr != null && _anniversary == null) {
          try {
            _anniversary = DateTime.parse(anniversaryStr);
          } catch (_) {}
        }
      });
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _nameController.dispose();
    _inviteCodeController.dispose();
    _nestNameController.dispose();
    super.dispose();
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.nunitoSans(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFFC0392B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _nextStep() async {
    if (_currentStep == 0) {
      if (_nameController.text.trim().isEmpty) {
        _showError('Please enter your name');
        return;
      }
      if (_selectedRelationship == null) {
        _showError('Please select your relationship');
        return;
      }
      // Save name immediately so it persists through the subscribe detour
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('display_name', _nameController.text.trim());
      setState(() => _savedName = _nameController.text.trim());
      // Save birthday/anniversary now so they survive the pushReplacementNamed detour
      if (_birthday != null) {
        await prefs.setString('birthday', _birthday!.toIso8601String());
      }
      if (_anniversary != null) {
        await prefs.setString('anniversary', _anniversary!.toIso8601String());
      }
      if (!mounted) return;
      // Read joined_via_invite directly from prefs to avoid async timing issues
      final joinedViaInvite = prefs.getBool('joined_via_invite') ?? false;
      // After step 0, skip subscribe screen for invite joiners
      if (joinedViaInvite) {
        setState(() {
          _joinedViaInvite = true;
        });
      }
      await _entranceController.forward();
      _entranceController.reset();
      setState(() => _currentStep = 1);
      _entranceController
        ..reset()
        ..forward();
      return;
    }

    if (_currentStep == 1) {
      // Save preferences then show finish screen
      await _savePreferences();
      setState(() => _currentStep = 2);
      _entranceController
        ..reset()
        ..forward();
      return;
    }

    if (_currentStep == 2) {
      // Final step — navigate to family feed
      await _finishOnboarding();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
      _entranceController
        ..reset()
        ..forward();
    }
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_role', 'family');
    // Use controller text if present; fall back to _savedName (set before subscribe detour);
    // final fallback reads the value already persisted to SharedPreferences before the detour
    final nameFromPrefs = prefs.getString('display_name') ?? '';
    final name = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : _savedName.isNotEmpty
        ? _savedName
        : nameFromPrefs;
    await prefs.setString('display_name', name);
    await prefs.setString('relationship', _selectedRelationship ?? 'Family');
    await prefs.setBool('notify_check_in', _notifyOnCheckIn);
    await prefs.setBool('notify_messages', _notifyOnMessages);
    await prefs.setBool('onboarding_complete', true);
    await prefs.setBool('first_load', true);
    await prefs.setString('nest_name', _nestNameController.text.trim());
    await prefs.setBool('has_onboarded', true);
    if (_birthday != null) {
      await prefs.setString('birthday', _birthday!.toIso8601String());
    }
    if (_anniversary != null) {
      await prefs.setString('anniversary', _anniversary!.toIso8601String());
    }
    // Generate and save invite code for family nest owner
    final existingCode = prefs.getString('invite_code');
    if (existingCode == null ||
        existingCode.isEmpty ||
        !RegExp(r'^NEST-\d{6}$').hasMatch(existingCode)) {
      final digits = (100000 + Random().nextInt(900000)).toString();
      final code = 'NEST-$digits';
      await prefs.setString('invite_code', code);
      setState(() => _inviteCode = code);
    } else {
      setState(() => _inviteCode = existingCode);
    }
  }

  Future<void> _finishOnboarding() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
    await prefs.setBool('has_onboarded', true);
    await prefs.setString('user_role', 'family');

    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      final name = prefs.getString('display_name') ?? '';
      final joinedViaInvite = prefs.getBool('joined_via_invite') ?? false;
      final inviteCode = prefs.getString('invite_code') ?? '';

      if (userId != null) {
        await supabase.from('user_profiles').update({
          'display_name': name,
          'full_name': name,
          'role': 'family',
          'relation_type': (_selectedRelationship ?? 'Other').toLowerCase(),
        }).eq('id', userId);

        final profileCheck = await supabase
            .from('user_profiles')
            .select('id')
            .eq('id', userId)
            .maybeSingle();

        if (profileCheck != null) {
          final existingNestId = prefs.getString('nest_id') ?? '';
          bool nestIdIsValid = false;
          if (existingNestId.isNotEmpty) {
            try {
              final membershipCheck = await supabase
                  .from('nest_members')
                  .select('nest_id')
                  .eq('nest_id', existingNestId)
                  .eq('user_id', userId)
                  .maybeSingle();
              nestIdIsValid = membershipCheck != null;
            } catch (_) {
              nestIdIsValid = false;
            }
          }
          if (!nestIdIsValid) {
            await prefs.remove('nest_id');
            if (joinedViaInvite && inviteCode.isNotEmpty) {
              // Member joining existing nest via invite code
              try {
                final nestResponse = await supabase
                    .from('nests')
                    .select('id')
                    .eq('invite_code', inviteCode)
                    .maybeSingle();

                if (nestResponse != null) {
                  final nestId = nestResponse['id'] as String;
                  await prefs.setString('nest_id', nestId);
                  await supabase.from('nest_members').upsert({
                    'nest_id': nestId,
                    'user_id': userId,
                  });
                  debugPrint('Member joined nest: \$nestId');
                } else {
                  debugPrint('Nest not found for invite code: \$inviteCode');
                }
              } catch (e) {
                debugPrint('Member join error: \$e');
              }
            } else {
              // Owner creating new nest
              final nestName = prefs.getString('nest_name') ?? 'Our Nest';
              final nestResponse = await supabase.from('nests').insert({
                'name': nestName,
                'created_by': userId,
              }).select().single();
              final nestId = nestResponse['id'] as String;
              await prefs.setString('nest_id', nestId);
              await supabase.from('nest_members').upsert({
                'nest_id': nestId,
                'user_id': userId,
              });
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Family onboarding Supabase error: \$e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
      Navigator.pushReplacementNamed(
        context,
        AppRoutes.saveMessagesPromptScreen,
      );
    }
  }

  void _shareInviteCode() {
    ShareService.shareInviteCode(context, inviteCode: _inviteCode);
  }

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.of(context).platformBrightness;
    final isDark = brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final isTablet = size.width >= 600;

    final bgColor = isDark ? const Color(0xFF1C1812) : const Color(0xFFFDFDFD);
    final gradientEnd = isDark
        ? const Color(0xFF2A2218)
        : const Color(0xFFF5F0E8);

    return Scaffold(
      backgroundColor: bgColor,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [bgColor, gradientEnd],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(isTablet, isDark),
              _buildProgressBar(isDark),
              Expanded(
                child: AnimatedBuilder(
                  animation: _entranceController,
                  builder: (context, child) => SlideTransition(
                    position: _slideAnim,
                    child: Opacity(opacity: _fadeAnim.value, child: child),
                  ),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 60 : 28,
                      vertical: 24,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: isTablet ? 500 : 420,
                      ),
                      child: _buildCurrentStep(isTablet, isDark),
                    ),
                  ),
                ),
              ),
              _buildBottomActions(isTablet, isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isTablet, bool isDark) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? 60 : 28,
        vertical: 16,
      ),
      child: Row(
        children: [
          if (_currentStep == 0)
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF5DA399).withAlpha(31),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.arrow_back_rounded,
                  color: Color(0xFF5DA399),
                  size: 22,
                ),
              ),
            )
          else if (_currentStep > 0 && _currentStep < 2)
            GestureDetector(
              onTap: _prevStep,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF2A2218)
                      : const Color(0xFFF5F0E8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.arrow_back_rounded,
                  color: isDark
                      ? const Color(0xFFF5EDD8)
                      : const Color(0xFF2C2417),
                  size: 20,
                ),
              ),
            )
          else
            GestureDetector(
              onTap: _prevStep,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF2A2218)
                      : const Color(0xFFF5F0E8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.arrow_back_rounded,
                  color: isDark
                      ? const Color(0xFFF5EDD8)
                      : const Color(0xFF2C2417),
                  size: 20,
                ),
              ),
            ),
          const Spacer(),
          const SizedBox(width: 44),
        ],
      ),
    );
  }

  Widget _buildProgressBar(bool isDark) {
    final totalSteps = 3;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Row(
            children: List.generate(totalSteps, (i) {
              final isActive = i <= _currentStep;
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: i < totalSteps - 1 ? 6 : 0),
                  height: 4,
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0xFF5DA399)
                        : (isDark
                              ? const Color(0xFF3A3228)
                              : const Color(0xFFE8E0D0)),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'One-time setup only—takes just a minute!',
          textAlign: TextAlign.center,
          style: GoogleFonts.nunitoSans(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: isDark ? const Color(0xFF8A7A68) : const Color(0xFFB0A898),
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildCurrentStep(bool isTablet, bool isDark) {
    switch (_currentStep) {
      case 0:
        return _buildStep0(isTablet, isDark);
      case 1:
        return _buildStep1(isTablet, isDark);
      case 2:
        return _buildFinishStep(isTablet, isDark);
      default:
        return _buildStep0(isTablet, isDark);
    }
  }

  Widget _buildStep0(bool isTablet, bool isDark) {
    final textPrimary = isDark
        ? const Color(0xFFF5EDD8)
        : const Color(0xFF2C2417);
    final textSecondary = isDark
        ? const Color(0xFFB8A888)
        : const Color(0xFF6B5E4E);
    final cardBg = isDark ? const Color(0xFF2A2218) : const Color(0xFFF5F0E8);
    final borderColor = isDark
        ? const Color(0xFF3A3228)
        : const Color(0xFFE8E0D0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              gradient: const RadialGradient(
                colors: [Color(0xFFD4AA00), Color(0xFF5DA399)],
                center: Alignment.topLeft,
                radius: 1.5,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFD4AA00).withAlpha(50),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(
              Icons.family_restroom_rounded,
              color: Colors.white,
              size: 44,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'You\'re joining the\nnest! 🏡',
          style: GoogleFonts.nunitoSans(
            fontSize: isTablet ? 30 : 26,
            fontWeight: FontWeight.w800,
            color: textPrimary,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Your loved one will be so happy to see you here. Let\'s get you set up in just a few steps.',
          style: GoogleFonts.nunitoSans(
            fontSize: isTablet ? 17 : 15,
            color: textSecondary,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 20),
        _buildWarmFeatureRow(
          Icons.send_rounded,
          const Color(0xFF5DA399),
          'Send photos, voice messages, and warm notes',
          isDark,
        ),
        const SizedBox(height: 10),
        _buildWarmFeatureRow(
          Icons.auto_stories_rounded,
          const Color(0xFFD4AA00),
          'Read and heart your loved one\'s Legacy stories',
          isDark,
        ),
        const SizedBox(height: 10),
        _buildWarmFeatureRow(
          Icons.notifications_active_rounded,
          const Color(0xFFE05C5C),
          'Get notified when they send their daily check-in',
          isDark,
        ),
        const SizedBox(height: 32),
        Text(
          'Your name',
          style: GoogleFonts.nunitoSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        // Name field + profile photo picker side by side
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                style: GoogleFonts.nunitoSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Your first name',
                  hintStyle: GoogleFonts.nunitoSans(
                    fontSize: 20,
                    color: borderColor,
                  ),
                  enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: Color(0xFFE8E0D0),
                      width: 1.5,
                    ),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF5DA399), width: 2),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            _buildProfilePhotoCircle(isDark),
          ],
        ),
        const SizedBox(height: 16),
        _buildDateField(
          label: 'Birthday (optional)',
          icon: Icons.cake_rounded,
          iconColor: const Color(0xFFE05C5C),
          value: _birthday,
          isBirthday: true,
          isDark: isDark,
        ),
        const SizedBox(height: 12),
        _buildDateField(
          label: 'Anniversary (optional)',
          icon: Icons.favorite_rounded,
          iconColor: const Color(0xFFD4AA00),
          value: _anniversary,
          isBirthday: false,
          isDark: isDark,
        ),
        const SizedBox(height: 28),
        Text(
          'Your relationship to the senior',
          style: GoogleFonts.nunitoSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _relationships.map((rel) {
            final isSelected = _selectedRelationship == rel;
            return GestureDetector(
              onTap: () => setState(() => _selectedRelationship = rel),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF5DA399).withAlpha(20)
                      : cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF5DA399) : borderColor,
                    width: isSelected ? 2 : 1.5,
                  ),
                ),
                child: Text(
                  rel,
                  style: GoogleFonts.nunitoSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? const Color(0xFF5DA399) : textPrimary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 32),
        // ── Nest name field (optional) ──────────────────────────
        if (!_joinedViaInvite)
          Text(
            'Name your family nest (optional)',
            style: GoogleFonts.nunitoSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textSecondary,
            ),
          ),
        if (!_joinedViaInvite) const SizedBox(height: 8),
        if (!_joinedViaInvite)
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor, width: 1.5),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: _nestNameController,
              textCapitalization: TextCapitalization.words,
              style: GoogleFonts.nunitoSans(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'e.g. Poppy & Nana\'s Nest',
                hintStyle: GoogleFonts.nunitoSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? const Color(0xFF5A5040)
                      : const Color(0xFFD0C8B8),
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildProfilePhotoCircle(bool isDark) {
    final hasPhoto = _profilePhotoData != null;
    return GestureDetector(
      onTap: _openProfilePhotoPicker,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: hasPhoto
                    ? const Color(0xFF5DA399)
                    : const Color(0xFFE8E0D0),
                width: 2,
              ),
              color: isDark ? const Color(0xFF2A2218) : const Color(0xFFF5F0E8),
            ),
            child: hasPhoto
                ? ClipOval(
                    child: ProfileAvatarWidget(
                      profileData: _profilePhotoData,
                      displayName: _nameController.text,
                      size: 64,
                      borderWidth: 0,
                    ),
                  )
                : const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_a_photo_rounded,
                        color: Color(0xFFB0A898),
                        size: 22,
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 4),
          Text(
            hasPhoto ? 'Change' : 'Add Photo',
            style: GoogleFonts.nunitoSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF5DA399),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openProfilePhotoPicker() async {
    final result = await Navigator.pushNamed(
      context,
      AppRoutes.profilePhotoPickerScreen,
    );
    if (result != null && result is Map<String, dynamic>) {
      setState(() => _profilePhotoData = result);
    }
  }

  Widget _buildWarmFeatureRow(
    IconData icon,
    Color color,
    String text,
    bool isDark,
  ) {
    final textSecondary = isDark
        ? const Color(0xFFB8A888)
        : const Color(0xFF6B5E4E);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withAlpha(26),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Text(
              text,
              style: GoogleFonts.nunitoSans(
                fontSize: 13,
                color: textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep1(bool isTablet, bool isDark) {
    final textPrimary = isDark
        ? const Color(0xFFF5EDD8)
        : const Color(0xFF2C2417);
    final textSecondary = isDark
        ? const Color(0xFFB8A888)
        : const Color(0xFF6B5E4E);
    final cardBg = isDark ? const Color(0xFF2A2218) : const Color(0xFFF5F0E8);
    final borderColor = isDark
        ? const Color(0xFF3A3228)
        : const Color(0xFFE8E0D0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0xFFD4AA00).withAlpha(26),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(
            Icons.notifications_rounded,
            color: Color(0xFFD4AA00),
            size: 32,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Stay in the loop',
          style: GoogleFonts.nunitoSans(
            fontSize: isTablet ? 30 : 26,
            fontWeight: FontWeight.w800,
            color: textPrimary,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Choose when you\'d like to be notified about your loved one.',
          style: GoogleFonts.nunitoSans(
            fontSize: isTablet ? 17 : 15,
            color: textSecondary,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 32),
        _buildNotifCard(
          icon: Icons.favorite_rounded,
          iconColor: const Color(0xFF5DA399),
          title: '"I\'m Good Today" Check-ins',
          subtitle:
              'Get notified when your loved one sends their daily check-in',
          value: _notifyOnCheckIn,
          onChanged: (v) => setState(() => _notifyOnCheckIn = v),
          isDark: isDark,
        ),
        const SizedBox(height: 12),
        _buildNotifCard(
          icon: Icons.chat_bubble_rounded,
          iconColor: const Color(0xFFD4AA00),
          title: 'New Messages',
          subtitle:
              'Get notified when your loved one replies or hearts a message',
          value: _notifyOnMessages,
          onChanged: (v) => setState(() => _notifyOnMessages = v),
          isDark: isDark,
        ),
        const SizedBox(height: 28),
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
              const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF5DA399),
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'You\'re joining as ${_nameController.text.trim()} (${_selectedRelationship ?? ''})',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFinishStep(bool isTablet, bool isDark) {
    final textPrimary = isDark
        ? const Color(0xFFF5EDD8)
        : const Color(0xFF2C2417);
    final textSecondary = isDark
        ? const Color(0xFFB8A888)
        : const Color(0xFF6B5E4E);
    final cardBg = isDark ? const Color(0xFF2A2218) : const Color(0xFFF5F0E8);
    final borderColor = isDark
        ? const Color(0xFF3A3228)
        : const Color(0xFFE8E0D0);
    final mutedText = isDark
        ? const Color(0xFF7A6A58)
        : const Color(0xFFA8A090);

    final name = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : (_savedName.isNotEmpty ? _savedName : 'you');

    final nestName = _nestNameController.text.trim().isNotEmpty
        ? _nestNameController.text.trim()
        : '$name\'s Nest';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 16),
        // Checkmark circle
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFF5DA399).withAlpha(26),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_rounded,
            color: Color(0xFF5DA399),
            size: 40,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          _joinedViaInvite
              ? 'Welcome to the\nfamily nest!'
              : 'You\'re all set as $name!\nYou\'re the Nest Owner.',
          style: GoogleFonts.nunitoSans(
            fontSize: isTablet ? 30 : 26,
            fontWeight: FontWeight.w800,
            color: textPrimary,
            height: 1.2,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          _joinedViaInvite
              ? 'You\'re all set! You can now connect with your family nest.'
              : 'Your family nest is ready. Share your invite code with loved ones so they can join.',
          style: GoogleFonts.nunitoSans(
            fontSize: isTablet ? 17 : 15,
            color: textSecondary,
            height: 1.6,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 36),
        // Invite code card — only for Nest Owner
        if (!_joinedViaInvite)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor, width: 1.5),
            ),
            child: Column(
              children: [
                Text(
                  'Your Invite Code',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _inviteCode,
                  style: GoogleFonts.nunitoSans(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF5DA399),
                    letterSpacing: 6,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Share this with your family members',
                  style: GoogleFonts.nunitoSans(fontSize: 13, color: mutedText),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _shareInviteCode,
                    icon: const Icon(
                      Icons.share_rounded,
                      size: 20,
                      color: Colors.white,
                    ),
                    label: Text(
                      'Share Invite Code',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5DA399),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 28),
        _buildSummaryRow(Icons.person_rounded, 'Name', name, isDark),
        const SizedBox(height: 8),
        _buildSummaryRow(Icons.home_rounded, 'Nest', nestName, isDark),
        const SizedBox(height: 8),
        _buildSummaryRow(
          Icons.favorite_rounded,
          'Relationship',
          _selectedRelationship ?? 'Family',
          isDark,
        ),
        const SizedBox(height: 8),
        _buildSummaryRow(
          Icons.notifications_active_rounded,
          'Notifications',
          _notifyOnCheckIn ? 'On' : 'Off',
          isDark,
        ),
        const SizedBox(height: 16),
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
              const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF5DA399),
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'You\'re joining as $name (${_selectedRelationship ?? 'Family'})',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFFF5EDD8)
                        : const Color(0xFF2C2417),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
      ],
    );
  }

  Widget _buildSummaryRow(
    IconData icon,
    String label,
    String value,
    bool isDark,
  ) {
    final textSecondary = isDark
        ? const Color(0xFFB8A888)
        : const Color(0xFF6B5E4E);
    final textPrimary = isDark
        ? const Color(0xFFF5EDD8)
        : const Color(0xFF2C2417);
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF5DA399)),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: GoogleFonts.nunitoSans(fontSize: 14, color: textSecondary),
        ),
        Text(
          value,
          style: GoogleFonts.nunitoSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildNotifCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool isDark,
  }) {
    final textPrimary = isDark
        ? const Color(0xFFF5EDD8)
        : const Color(0xFF2C2417);
    final textSecondary = isDark
        ? const Color(0xFFB8A888)
        : const Color(0xFF6B5E4E);
    final cardBg = isDark ? const Color(0xFF2A2218) : const Color(0xFFF5F0E8);
    final borderColor = isDark
        ? const Color(0xFF3A3228)
        : const Color(0xFFE8E0D0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconColor.withAlpha(26),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.nunitoSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.nunitoSans(
                    fontSize: 12,
                    color: textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: const Color(0xFF5DA399),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActions(bool isTablet, bool isDark) {
    final isLastStep = _currentStep == 2;
    final bottomBg = isDark ? const Color(0xFF1C1812) : const Color(0xFFFDFDFD);
    final borderColor = isDark
        ? const Color(0xFF3A3228)
        : const Color(0xFFE8E0D0);

    return Container(
      padding: EdgeInsets.fromLTRB(
        isTablet ? 60 : 28,
        16,
        isTablet ? 60 : 28,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      decoration: BoxDecoration(
        color: bottomBg,
        border: Border(top: BorderSide(color: borderColor, width: 1)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: _isLoading ? null : _nextStep,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF5DA399),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Text(
                  isLastStep ? 'Enter My Nest 🏡' : 'Continue',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }

  Future<void> _pickDate({
    required bool isBirthday,
    required bool isDark,
  }) async {
    final now = DateTime.now();
    final initial = isBirthday
        ? (_birthday ?? DateTime(now.year - 40, 1, 1))
        : (_anniversary ?? DateTime(now.year - 10, 1, 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: isBirthday ? 'Select Birthday' : 'Select Anniversary',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(
            primary: const Color(0xFF5DA399),
            onPrimary: Colors.white,
            surface: isDark ? const Color(0xFF242018) : const Color(0xFFFDFDFD),
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

  Widget _buildDateField({
    required String label,
    required IconData icon,
    required Color iconColor,
    required DateTime? value,
    required bool isBirthday,
    required bool isDark,
  }) {
    final textPrimary = isDark
        ? const Color(0xFFF5EDD8)
        : const Color(0xFF2C2417);
    final textSecondary = isDark
        ? const Color(0xFFB8A888)
        : const Color(0xFF6B5E4E);
    final cardBg = isDark ? const Color(0xFF2A2218) : const Color(0xFFF5F0E8);
    final borderColor = isDark
        ? const Color(0xFF3A3228)
        : const Color(0xFFE8E0D0);

    final display = value != null
        ? '${_monthName(value.month)} ${value.day}, ${value.year}'
        : null;

    return GestureDetector(
      onTap: () => _pickDate(isBirthday: isBirthday, isDark: isDark),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                display ?? label,
                style: GoogleFonts.nunitoSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: display != null ? textPrimary : textSecondary,
                ),
              ),
            ),
            Icon(Icons.calendar_today_rounded, color: textSecondary, size: 16),
          ],
        ),
      ),
    );
  }
}
