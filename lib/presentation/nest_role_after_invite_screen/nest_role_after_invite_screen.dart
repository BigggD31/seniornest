import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../routes/app_routes.dart';
import '../splash_screen/widgets/nest_logo_widget.dart';

class NestRoleAfterInviteScreen extends StatefulWidget {
  final String inviteCode;
  const NestRoleAfterInviteScreen({super.key, required this.inviteCode});

  @override
  State<NestRoleAfterInviteScreen> createState() =>
      _NestRoleAfterInviteScreenState();
}

class _NestRoleAfterInviteScreenState extends State<NestRoleAfterInviteScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  String? _selectedRole;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
        );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _chooseRole(String role) async {
    if (_isLoading) return;
    setState(() {
      _selectedRole = role;
      _isLoading = true;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_role', role);
    await prefs.setString('invite_code', widget.inviteCode);
    await prefs.setBool('joined_via_invite', true);

    await Future.delayed(const Duration(milliseconds: 300));

    if (mounted) {
      if (role == 'senior') {
        Navigator.pushReplacementNamed(
          context,
          AppRoutes.seniorOnboardingScreen,
        );
      } else {
        Navigator.pushReplacementNamed(
          context,
          AppRoutes.familyOnboardingScreen,
        );
      }
    }
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
          child: Stack(
            children: [
              Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: isTablet ? 60 : 28,
                    vertical: 24,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: isTablet ? 500 : 420),
                    child: FadeTransition(
                      opacity: _fadeAnim,
                      child: SlideTransition(
                        position: _slideAnim,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            SizedBox(height: isTablet ? 40 : 20),
                            NestLogoWidget(size: isTablet ? 200.0 : 180.0),
                            SizedBox(height: isTablet ? 36 : 28),
                            Text(
                              'Who are you in this Nest?',
                              style: GoogleFonts.nunitoSans(
                                fontSize: isTablet ? 26 : 22,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF2C2417),
                                height: 1.3,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Your invite code has been verified.\nNow tell us who you are.',
                              style: GoogleFonts.nunitoSans(
                                fontSize: isTablet ? 15 : 14,
                                color: const Color(0xFF9E8E7E),
                                height: 1.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: isTablet ? 48 : 40),
                            // I'm the Senior button
                            _RoleChoiceButton(
                              label: "I'm the Senior",
                              subtitle: 'Stay connected with your loved ones',
                              icon: Icons.elderly_rounded,
                              color: const Color(0xFFE8A87C),
                              isSelected: _selectedRole == 'senior',
                              isLoading:
                                  _isLoading && _selectedRole == 'senior',
                              onTap: () => _chooseRole('senior'),
                            ),
                            const SizedBox(height: 16),
                            // I'm Family button
                            _RoleChoiceButton(
                              label: "I'm Family",
                              subtitle: 'Share moments with your loved one',
                              icon: Icons.family_restroom_rounded,
                              color: const Color(0xFF5DA399),
                              isSelected: _selectedRole == 'family',
                              isLoading:
                                  _isLoading && _selectedRole == 'family',
                              onTap: () => _chooseRole('family'),
                            ),
                            const SizedBox(height: 40),
                            Text(
                              'By continuing, you agree to our Terms & Privacy Policy',
                              style: GoogleFonts.nunitoSans(
                                fontSize: 11,
                                color: const Color(0xFFA8A090),
                                height: 1.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                left: isTablet ? 20 : 8,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 48,
                    height: 48,
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
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleChoiceButton extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool isSelected;
  final bool isLoading;
  final VoidCallback onTap;

  const _RoleChoiceButton({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.isSelected,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
        decoration: BoxDecoration(
          color: isSelected ? color.withAlpha(26) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : const Color(0xFFE8E0D0),
            width: isSelected ? 2.0 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(10),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withAlpha(30),
                borderRadius: BorderRadius.circular(14),
              ),
              child: isLoading
                  ? Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: color,
                        ),
                      ),
                    )
                  : Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.nunitoSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF2C2417),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: GoogleFonts.nunitoSans(
                      fontSize: 13,
                      color: const Color(0xFF9E8E7E),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: isSelected ? color : const Color(0xFFD0C8B8),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}
