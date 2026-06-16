import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../routes/app_routes.dart';
import '../splash_screen/widgets/nest_logo_widget.dart';
import '../../core/app_state.dart';
import '../../services/share_service.dart';
import '../profile_photo_picker_screen/profile_photo_picker_screen.dart';

class SeniorOnboardingScreen extends StatefulWidget {
  const SeniorOnboardingScreen({super.key});

  @override
  State<SeniorOnboardingScreen> createState() => _SeniorOnboardingScreenState();
}

class _SeniorOnboardingScreenState extends State<SeniorOnboardingScreen>
    with TickerProviderStateMixin {
  int _currentStep = 0;
  bool _isLoading = false;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _nestNameController = TextEditingController();
  String _selectedFontSize = 'Large';
  bool _medsReminders = true;
  bool _dailyCheckIn = true;
  String _savedName = '';
  String _inviteCode = '';
  bool _joinedViaInvite = false;
  Map<String, dynamic>? _profilePhotoData;
  DateTime? _birthday;
  DateTime? _anniversary;

  late AnimationController _entranceController;
  late AnimationController _stepController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  static const List<String> _fontSizes = ['Normal', 'Large', 'Extra Large'];

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
    _stepController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
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

    // Load persisted name so it's available after returning from subscribe screen
    _loadSavedName();

    // Handle returning from subscribe screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null && args['startAtStep'] == 1) {
        setState(() => _currentStep = 1);
        _entranceController
          ..reset()
          ..forward();
      }
    });
  }

  Future<void> _loadSavedName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('display_name') ?? '';
    final savedNestName = prefs.getString('nest_name') ?? '';
    final joinedViaInvite = prefs.getBool('joined_via_invite') ?? false;
    final profileJson = prefs.getString(kProfilePhotoKey);
    // Restore birthday/anniversary saved before the subscribe-screen detour
    final birthdayStr = prefs.getString('birthday');
    final anniversaryStr = prefs.getString('anniversary');
    final savedCode = prefs.getString('invite_code') ?? '';
    if (mounted) {
      setState(() {
        if (name.isNotEmpty) _savedName = name;
        // Restore nest name into controller so _finishOnboarding saves it correctly
        if (savedNestName.isNotEmpty && _nestNameController.text.isEmpty) {
          _nestNameController.text = savedNestName;
        }
        _joinedViaInvite = joinedViaInvite;
        if (savedCode.isNotEmpty) _inviteCode = savedCode;
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
    _stepController.dispose();
    _nameController.dispose();
    _nestNameController.dispose();
    super.dispose();
  }

  Future<void> _nextStep() async {
    if (_currentStep == 0 && _nameController.text.trim().isEmpty) {
      _showError('Please enter your name to continue');
      return;
    }
    // After step 0, navigate to subscribe screen
    if (_currentStep == 0) {
      // Save name and nest name to SharedPreferences immediately so they persist
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('display_name', _nameController.text.trim());
      await prefs.setString('nest_name', _nestNameController.text.trim());
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
      if (joinedViaInvite) {
        setState(() {
          _joinedViaInvite = true;
        });
      }
      await _stepController.forward();
      _stepController.reset();
      setState(() => _currentStep = 1);
      _entranceController
        ..reset()
        ..forward();
      return;
    }
    if (_currentStep < 3) {
      await _stepController.forward();
      _stepController.reset();
      // Generate invite code when entering step 3 so it shows immediately
      if (_currentStep == 2) {
        final prefs = await SharedPreferences.getInstance();
        final existingCode = prefs.getString('invite_code') ?? '';
        if (existingCode.isEmpty ||
            !RegExp(r'^NEST-\d{6}$').hasMatch(existingCode)) {
          final digits = (100000 + Random().nextInt(900000)).toString();
          final code = 'NEST-$digits';
          await prefs.setString('invite_code', code);
          if (mounted) setState(() => _inviteCode = code);
        } else {
          if (mounted) setState(() => _inviteCode = existingCode);
        }
      }
      setState(() => _currentStep++);
      _entranceController
        ..reset()
        ..forward();
    } else {
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

  Future<void> _finishOnboarding() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();

    // Use controller text if present; fall back to _savedName
    final name = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : _savedName;
    final nestName = _nestNameController.text.trim();

    // Save to SharedPreferences
    await prefs.setString('user_role', 'senior');
    await prefs.setString('display_name', name);
    await prefs.setString('nest_name', nestName);
    await prefs.setString('text_size', _selectedFontSize);
    await prefs.setBool('meds_reminders', _medsReminders);
    await prefs.setBool('daily_check_in', _dailyCheckIn);
    await prefs.setBool('onboarding_complete', true);
    await prefs.setBool('first_load', true);
    await prefs.setBool('has_onboarded', true);
    if (_birthday != null) {
      await prefs.setString('birthday', _birthday!.toIso8601String());
    }
    if (_anniversary != null) {
      await prefs.setString('anniversary', _anniversary!.toIso8601String());
    }

    // Generate invite code
    final existingCode = prefs.getString('invite_code') ?? '';
    String inviteCode = existingCode;
    if (existingCode.isEmpty || !RegExp(r'^NEST-\d{6}$').hasMatch(existingCode)) {
      final digits = (100000 + Random().nextInt(900000)).toString();
      inviteCode = 'NEST-$digits';
      await prefs.setString('invite_code', inviteCode);
      if (mounted) setState(() => _inviteCode = inviteCode);
    } else {
      if (mounted) setState(() => _inviteCode = existingCode);
    }

    // Save to Supabase
    try {
      final supabase = Supabase.instance.client;
      // Wait for auth session to be ready
      String? userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        print('NEST_DEBUG: userId null on first check, waiting for session...');
        await Future.delayed(const Duration(seconds: 2));
        userId = supabase.auth.currentUser?.id;
        print('NEST_DEBUG: userId after wait = $userId');
      }
      print('NEST_DEBUG: userId = $userId');

      if (userId != null) {
        print('NEST_DEBUG: upserting profile...');
        final profileData = <String, dynamic>{
          'id': userId,
          'role': 'senior',
          'birthday': _birthday?.toIso8601String(),
          'anniversary': _anniversary?.toIso8601String(),
        };
        if (name.isNotEmpty) {
          profileData['display_name'] = name;
          profileData['full_name'] = name;
        }
        await supabase.from('user_profiles').upsert(profileData);
        print('NEST_DEBUG: profile upsert done');

        // Check if nest already exists for this user
        final existingNestId = prefs.getString('nest_id') ?? '';
        String nestId = existingNestId;

        if (nestId.isEmpty) {
          // Create new nest with invite code
          final nestResponse = await supabase.from('nests').insert({
            'name': nestName,
            'created_by': userId,
            'invite_code': inviteCode,
          }).select().single();

          nestId = nestResponse['id'] as String;
          await prefs.setString('nest_id', nestId);

          // Add user as nest member
          await supabase.from('nest_members').upsert({
            'nest_id': nestId,
            'user_id': userId,
          });
        }
      }
    } catch (e) {
      debugPrint('SENIORNEST ERROR: $e');
      print('SENIORNEST ERROR: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('DEBUG: $e'),
            duration: Duration(seconds: 10),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
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
    final size = MediaQuery.of(context).size;
    final isTablet = size.width >= 600;

    return Scaffold(
      backgroundColor: const Color(0xFFFDFDFD),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFDFDFD), Color(0xFFF5F0E8)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(isTablet),
              _buildProgressBar(),
              Expanded(
                child: AnimatedBuilder(
                  animation: _entranceController,
                  builder: (context, _) => SlideTransition(
                    position: _slideAnim,
                    child: Opacity(
                      opacity: _fadeAnim.value,
                      child: SingleChildScrollView(
                        padding: EdgeInsets.symmetric(
                          horizontal: isTablet ? 60 : 28,
                          vertical: 24,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: isTablet ? 500 : 420,
                          ),
                          child: _buildCurrentStep(isTablet),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _buildBottomActions(isTablet),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isTablet) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? 60 : 28,
        vertical: 16,
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            GestureDetector(
              onTap: _prevStep,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F0E8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.arrow_back_rounded,
                  color: Color(0xFF2C2417),
                  size: 20,
                ),
              ),
            )
          else
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
            ),
          const Spacer(),
          const SizedBox(width: 44),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Row(
            children: List.generate(4, (i) {
              final isActive = i <= _currentStep;
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: i < 3 ? 6 : 0),
                  height: 4,
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0xFF5DA399)
                        : const Color(0xFFE8E0D0),
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
            color: const Color(0xFFB0A898),
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildCurrentStep(bool isTablet) {
    switch (_currentStep) {
      case 0:
        return _buildStep0(isTablet);
      case 1:
        return _buildStep1(isTablet);
      case 2:
        return _buildStep2(isTablet);
      case 3:
        return _buildStep3(isTablet);
      default:
        return _buildStep0(isTablet);
    }
  }

  Widget _buildStep0(bool isTablet) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 2),
        // Large logo at top
        Center(child: NestLogoWidget(size: isTablet ? 211.0 : 208.0)),
        const SizedBox(height: 10),
        Text(
          'Welcome! 🏡',
          style: GoogleFonts.nunitoSans(
            fontSize: isTablet ? 30 : 26,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF2C2417),
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your family is so glad you\'re here. Let\'s set up your cozy corner — it only takes a minute.',
          style: GoogleFonts.nunitoSans(
            fontSize: isTablet ? 17 : 15,
            color: const Color(0xFF6B5E4E),
            height: 1.6,
          ),
        ),
        const SizedBox(height: 14),
        // Warm feature highlights
        _buildWarmFeatureRow(
          Icons.chat_bubble_rounded,
          const Color(0xFF5DA399),
          'Receive warm messages from your family every day',
        ),
        const SizedBox(height: 8),
        _buildWarmFeatureRow(
          Icons.auto_stories_rounded,
          const Color(0xFFD4AA00),
          'Write and preserve your life stories for generations',
        ),
        const SizedBox(height: 8),
        _buildWarmFeatureRow(
          Icons.favorite_rounded,
          const Color(0xFFE05C5C),
          'Send a quick "I\'m Good Today" heart to your loved ones',
        ),
        const SizedBox(height: 20),
        Text(
          'What should we call you?',
          style: GoogleFonts.nunitoSans(
            fontSize: isTablet ? 24 : 22,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF2C2417),
            height: 1.3,
          ),
        ),
        const SizedBox(height: 10),
        // Name field + profile photo picker side by side
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                style: GoogleFonts.nunitoSans(
                  fontSize: isTablet ? 28 : 26,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF2C2417),
                ),
                decoration: InputDecoration(
                  hintText: 'Your first name',
                  hintStyle: GoogleFonts.nunitoSans(
                    fontSize: isTablet ? 28 : 26,
                    color: const Color(0xFFE8E0D0),
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
            _buildProfilePhotoCircle(),
          ],
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
        const SizedBox(height: 24),
        if (!_joinedViaInvite)
          Text(
            'Name your family nest (optional)',
            style: GoogleFonts.nunitoSans(
              fontSize: isTablet ? 20 : 18,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF2C2417),
              height: 1.3,
            ),
          ),
        if (!_joinedViaInvite) const SizedBox(height: 10),
        if (!_joinedViaInvite)
          TextField(
            controller: _nestNameController,
            textCapitalization: TextCapitalization.words,
            style: GoogleFonts.nunitoSans(
              fontSize: isTablet ? 22 : 20,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF2C2417),
            ),
            decoration: InputDecoration(
              hintText: 'e.g. "The Johnson Family Nest"',
              hintStyle: GoogleFonts.nunitoSans(
                fontSize: isTablet ? 22 : 20,
                color: const Color(0xFFE8E0D0),
              ),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFE8E0D0), width: 1.5),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF5DA399), width: 2),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildWarmFeatureRow(IconData icon, Color color, String text) {
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
                color: const Color(0xFF6B5E4E),
                height: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep1(bool isTablet) {
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
            Icons.text_fields_rounded,
            color: Color(0xFFD4AA00),
            size: 32,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'How big would you\nlike the text?',
          style: GoogleFonts.nunitoSans(
            fontSize: isTablet ? 30 : 26,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF2C2417),
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Choose what feels most comfortable for your eyes.',
          style: GoogleFonts.nunitoSans(
            fontSize: isTablet ? 17 : 15,
            color: const Color(0xFF6B5E4E),
            height: 1.6,
          ),
        ),
        const SizedBox(height: 32),
        ..._fontSizes.map((size) {
          final isSelected = _selectedFontSize == size;
          final fontSize = size == 'Normal'
              ? 15.0
              : size == 'Large'
              ? 18.0
              : 22.0;
          return GestureDetector(
            onTap: () {
              setState(() => _selectedFontSize = size);
              appTextScaleNotifier.value = textSizeToScale(size);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF5DA399).withAlpha(20)
                    : const Color(0xFFF5F0E8),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF5DA399)
                      : const Color(0xFFE8E0D0),
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
                          : const Color(0xFF2C2417),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      size,
                      style: GoogleFonts.nunitoSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? const Color(0xFF5DA399)
                            : const Color(0xFF2C2417),
                      ),
                    ),
                  ),
                  if (isSelected)
                    const Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xFF5DA399),
                      size: 22,
                    ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildStep2(bool isTablet) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0xFF5DA399).withAlpha(26),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(
            Icons.notifications_active_rounded,
            color: Color(0xFF5DA399),
            size: 32,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Helpful reminders\nfor your day',
          style: GoogleFonts.nunitoSans(
            fontSize: isTablet ? 30 : 26,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF2C2417),
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'We can send gentle reminders to help you stay on track.',
          style: GoogleFonts.nunitoSans(
            fontSize: isTablet ? 17 : 15,
            color: const Color(0xFF6B5E4E),
            height: 1.6,
          ),
        ),
        const SizedBox(height: 32),
        _buildToggleCard(
          icon: Icons.medication_rounded,
          iconColor: const Color(0xFF5DA399),
          title: 'Medication Reminders',
          subtitle: 'Daily gentle nudge to take your medications',
          value: _medsReminders,
          onChanged: (v) => setState(() => _medsReminders = v),
        ),
        const SizedBox(height: 12),
        _buildToggleCard(
          icon: Icons.favorite_rounded,
          iconColor: const Color(0xFFD4AA00),
          title: '"I\'m Good Today" Check-in',
          subtitle: 'Let your family know you\'re doing well each day',
          value: _dailyCheckIn,
          onChanged: (v) => setState(() => _dailyCheckIn = v),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F0E8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: Color(0xFF6B5E4E),
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'You can always change these in Setup later.',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 13,
                    color: const Color(0xFF6B5E4E),
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

  Widget _buildToggleCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F0E8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8E0D0), width: 1.5),
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
                    color: const Color(0xFF2C2417),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.nunitoSans(
                    fontSize: 12,
                    color: const Color(0xFF6B5E4E),
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

  Widget _buildStep3(bool isTablet) {
    // Read from controller first; fall back to SharedPreferences-loaded _savedName
    final name = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : (_savedName.isNotEmpty ? _savedName : 'your friend');
    final nestName = _nestNameController.text.trim().isEmpty
        ? '$name\'s Nest'
        : _nestNameController.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 16),
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
            color: const Color(0xFF2C2417),
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
            color: const Color(0xFF6B5E4E),
            height: 1.6,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 36),
        if (!_joinedViaInvite)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F0E8),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE8E0D0), width: 1.5),
            ),
            child: Column(
              children: [
                Text(
                  'Your Invite Code',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF6B5E4E),
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
                  style: GoogleFonts.nunitoSans(
                    fontSize: 13,
                    color: const Color(0xFFA8A090),
                  ),
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
        const SizedBox(height: 20),
        _buildSummaryRow(Icons.person_rounded, 'Name', name),
        const SizedBox(height: 8),
        _buildSummaryRow(Icons.home_rounded, 'Nest', nestName),
        const SizedBox(height: 8),
        _buildSummaryRow(
          Icons.text_fields_rounded,
          'Text Size',
          _selectedFontSize,
        ),
        const SizedBox(height: 8),
        _buildSummaryRow(
          Icons.medication_rounded,
          'Meds Reminders',
          _medsReminders ? 'On' : 'Off',
        ),
        const SizedBox(height: 28),
      ],
    );
  }

  Widget _buildSummaryRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF5DA399)),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: GoogleFonts.nunitoSans(
            fontSize: 14,
            color: const Color(0xFF6B5E4E),
          ),
        ),
        Text(
          value,
          style: GoogleFonts.nunitoSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF2C2417),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomActions(bool isTablet) {
    final isLastStep = _currentStep == 3;
    return Container(
      padding: EdgeInsets.fromLTRB(
        isTablet ? 60 : 28,
        16,
        isTablet ? 60 : 28,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFFDFDFD),
        border: Border(top: BorderSide(color: Color(0xFFE8E0D0), width: 1)),
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
                  isLastStep
                      ? 'Enter My Nest 🏡'
                      : (_currentStep == 0 ? 'Continue' : 'Continue'),
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

  Widget _buildProfilePhotoCircle() {
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
              color: const Color(0xFFF5F0E8),
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
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
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
                  color: hasValue
                      ? const Color(0xFF2C2417)
                      : const Color(0xFFB0A898),
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
