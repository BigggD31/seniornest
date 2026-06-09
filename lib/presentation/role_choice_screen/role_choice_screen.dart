import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../routes/app_routes.dart';
import '../splash_screen/widgets/nest_logo_widget.dart';
import './widgets/role_button_widget.dart';

class RoleChoiceScreen extends StatefulWidget {
  const RoleChoiceScreen({super.key});

  @override
  State<RoleChoiceScreen> createState() => _RoleChoiceScreenState();
}

class _RoleChoiceScreenState extends State<RoleChoiceScreen>
    with TickerProviderStateMixin {
  // TODO: Replace with Riverpod/Bloc for production — user role state
  bool _isLoading = false;
  String? _selectedRole;

  late AnimationController _entranceController;
  late Animation<double> _logoFade;
  late Animation<Offset> _titleSlide;
  late Animation<double> _titleFade;
  late Animation<Offset> _buttonsSlide;
  late Animation<double> _buttonsFade;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    _setupAnimations();
    _entranceController.forward();
  }

  void _setupAnimations() {
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      ),
    );
    _titleSlide = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: const Interval(0.2, 0.6, curve: Curves.easeOutCubic),
          ),
        );
    _titleFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.2, 0.6, curve: Curves.easeOut),
      ),
    );
    _buttonsSlide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: const Interval(0.4, 1.0, curve: Curves.easeOutCubic),
          ),
        );
    _buttonsFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
      ),
    );
  }

  Future<void> _selectRole(String role) async {
    // TODO: Replace with Riverpod/Bloc for production — persist user role
    if (_isLoading) return;
    setState(() {
      _selectedRole = role;
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_role', role);
      await prefs.setBool('onboarding_complete', false);

      await Future.delayed(const Duration(milliseconds: 200));

      if (mounted) {
        if (role == 'senior') {
          await Navigator.pushNamed(context, AppRoutes.seniorOnboardingScreen);
        } else {
          await Navigator.pushNamed(context, AppRoutes.familyOnboardingScreen);
        }
      }
    } catch (_) {
      // no-op: navigation or prefs failure — fall through to reset
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _selectedRole = null;
        });
      }
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
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
            stops: [0.0, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.symmetric(
                horizontal: isTablet ? 60 : 28,
                vertical: 8,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isTablet ? 500 : 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(height: isTablet ? 20 : 8),
                    // Back button row
                    Align(
                      alignment: Alignment.centerLeft,
                      child: GestureDetector(
                        onTap: () {
                          Navigator.pushNamedAndRemoveUntil(
                            context,
                            AppRoutes.splashScreen,
                            (route) => false,
                          );
                        },
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
                    ),
                    // Logo
                    AnimatedBuilder(
                      animation: _logoFade,
                      builder: (context, child) =>
                          Opacity(opacity: _logoFade.value, child: child),
                      child: NestLogoWidget(size: isTablet ? 270.0 : 265.0),
                    ),
                    const SizedBox(height: 10),
                    // Subtitle
                    AnimatedBuilder(
                      animation: _entranceController,
                      builder: (context, child) => SlideTransition(
                        position: _titleSlide,
                        child: Opacity(opacity: _titleFade.value, child: child),
                      ),
                      child: Text(
                        style: GoogleFonts.nunitoSans(
                          color: const Color(0xFF6B5E4E),
                          height: 1.5,
                          fontSize: isTablet ? 18 : 16,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                        'Who are you joining as?',
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Role clarification text
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text(
                        style: GoogleFonts.nunitoSans(
                          color: const Color(0xFF9E8E7E),
                          height: 1.5,
                          fontSize: isTablet ? 15 : 13,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                        'Choose your role. The person who creates the Nest is the Nest Owner and pays the subscription.',
                      ),
                    ),
                    SizedBox(height: isTablet ? 28 : 20),
                    // Role buttons
                    AnimatedBuilder(
                      animation: _entranceController,
                      builder: (context, child) => SlideTransition(
                        position: _buttonsSlide,
                        child: Opacity(
                          opacity: _buttonsFade.value,
                          child: child,
                        ),
                      ),
                      child: isTablet
                          ? Row(
                              children: [
                                Expanded(
                                  child: RoleButtonWidget(
                                    label: "I'm the Senior",
                                    subtitle:
                                        'Stay connected with your loved ones',
                                    icon: Icons.elderly_rounded,
                                    isSelected: _selectedRole == 'senior',
                                    isLoading:
                                        _isLoading && _selectedRole == 'senior',
                                    onTap: () => _selectRole('senior'),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: RoleButtonWidget(
                                    label: "I'm Family",
                                    subtitle:
                                        'Share moments with your loved one',
                                    icon: Icons.family_restroom_rounded,
                                    isSelected: _selectedRole == 'family',
                                    isLoading:
                                        _isLoading && _selectedRole == 'family',
                                    onTap: () => _selectRole('family'),
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              children: [
                                RoleButtonWidget(
                                  label: "I'm the Senior",
                                  subtitle:
                                      'Stay connected with your loved ones',
                                  icon: Icons.elderly_rounded,
                                  isSelected: _selectedRole == 'senior',
                                  isLoading:
                                      _isLoading && _selectedRole == 'senior',
                                  onTap: () => _selectRole('senior'),
                                ),
                                const SizedBox(height: 14),
                                RoleButtonWidget(
                                  label: "I'm Family",
                                  subtitle: 'Share moments with your loved one',
                                  icon: Icons.family_restroom_rounded,
                                  isSelected: _selectedRole == 'family',
                                  isLoading:
                                      _isLoading && _selectedRole == 'family',
                                  onTap: () => _selectRole('family'),
                                ),
                              ],
                            ),
                    ),
                    // Footer
                    AnimatedBuilder(
                      animation: _buttonsFade,
                      builder: (context, child) => Opacity(
                        opacity: _buttonsFade.value * 0.6,
                        child: child,
                      ),
                      child: Text(
                        'By continuing, you agree to our Terms & Privacy Policy',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 11,
                          color: const Color(0xFFA8A090),
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showInviteCodeSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _InviteCodeSheet(),
    );
  }
}

class _InviteCodeSheet extends StatefulWidget {
  const _InviteCodeSheet();

  @override
  State<_InviteCodeSheet> createState() => _InviteCodeSheetState();
}

class _InviteCodeSheetState extends State<_InviteCodeSheet> {
  // TODO: Replace with Riverpod/Bloc for production — invite code validation
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verifyCode() async {
    if (_codeController.text.trim().length < 4) return;
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) {
      final code = _codeController.text.trim();
      Navigator.pop(context);
      Navigator.pushNamed(
        context,
        AppRoutes.nestRoleAfterInviteScreen,
        arguments: {'inviteCode': code},
      );
    }
  }

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
      decoration: const BoxDecoration(
        color: Color(0xFFFDFDFD),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
            'Enter Your Invite Code',
            style: GoogleFonts.nunitoSans(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF2C2417),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Enter the invite code shared with you',
            style: GoogleFonts.nunitoSans(
              fontSize: 14,
              color: const Color(0xFF6B5E4E),
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _codeController,
            textCapitalization: TextCapitalization.characters,
            style: GoogleFonts.nunitoSans(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF2C2417),
              letterSpacing: 8,
            ),
            decoration: InputDecoration(
              hintText: 'NEST-XXXXXX',
              hintStyle: GoogleFonts.nunitoSans(
                fontSize: 22,
                color: const Color(0xFFE8E0D0),
                letterSpacing: 8,
              ),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFE8E0D0), width: 1.5),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF5DA399), width: 2),
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _verifyCode,
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
                      'Verify Code',
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
