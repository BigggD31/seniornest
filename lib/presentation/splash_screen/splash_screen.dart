import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../routes/app_routes.dart';
import './widgets/heartbeat_painter_widget.dart';
import './widgets/nest_logo_widget.dart';
import '../../widgets/keyboard_done_bar.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _taglineController;
  late AnimationController _heartbeatController;
  late AnimationController _pulseController;
  late AnimationController _contentController;

  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _taglineOpacity;
  late Animation<Offset> _taglineSlide;
  late Animation<double> _heartbeatProgress;
  late Animation<double> _pulseScale;
  late Animation<double> _contentOpacity;
  late Animation<Offset> _contentSlide;

  @override
  void initState() {
    super.initState();
    _checkExistingSession();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    // Shows a banner passed from a redirect (e.g. a removed member trying
    // to rejoin) once this screen is fully built and stable -- showing it
    // any earlier gets torn down before it ever really appears.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      final bannerMessage = args?['bannerMessage'] as String?;
      if (bannerMessage != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(bannerMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 30),
          ),
        );
      }
    });
    _setupAnimations();
    _startSequence();
  }

  void _setupAnimations() {
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _taglineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _heartbeatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _contentController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _logoScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.elasticOut),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );
    _taglineOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _taglineController, curve: Curves.easeOut),
    );
    _taglineSlide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _taglineController,
            curve: Curves.easeOutCubic,
          ),
        );
    _heartbeatProgress = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _heartbeatController, curve: Curves.easeInOut),
    );
    _pulseScale = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _contentOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _contentController, curve: Curves.easeOut),
    );
    _contentSlide =
        Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _contentController,
            curve: Curves.easeOutCubic,
          ),
        );
  }

  Future<void> _startSequence() async {
    await Future.delayed(const Duration(milliseconds: 300));
    _logoController.forward();
    await Future.delayed(const Duration(milliseconds: 600));
    _heartbeatController.forward();
    await Future.delayed(const Duration(milliseconds: 400));
    _taglineController.forward();
    await Future.delayed(const Duration(milliseconds: 500));
    _contentController.forward();
  }

  void _showInviteCodeSheet(BuildContext context) {
    final TextEditingController codeController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFFFDF9F4),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDDD5C8),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Enter Your Invite Code',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF2C2417),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Type your NEST123456 or lifetime invite code below.',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 13,
                    color: const Color(0xFF9E8E7E),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: codeController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  style: GoogleFonts.nunitoSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF2C2417),
                    letterSpacing: 1.5,
                  ),
                  decoration: InputDecoration(
                    hintText: 'e.g. NEST123456',
                    hintStyle: GoogleFonts.nunitoSans(
                      fontSize: 15,
                      color: const Color(0xFFBBAA99),
                      letterSpacing: 0.5,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFDDD5C8)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFDDD5C8)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: Color(0xFF8B6914),
                        width: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _InviteCodeSubmitButton(
                  codeController: codeController,
                  onValidCode: (code) {
                    Navigator.pop(sheetContext);
                    Navigator.pushNamed(
                      context,
                      AppRoutes.nestRoleAfterInviteScreen,
                      arguments: {'inviteCode': code},
                    );
                  },
                  onVipCode: () {
                    Navigator.pop(sheetContext);
                    // Both "I'm the Senior" and "I'm Family" are valid
                    // here -- neither has an invite code attached, so
                    // family_onboarding_screen.dart correctly treats
                    // either choice as creating a brand-new nest as its
                    // owner, never joining someone else's existing one.
                    // (Previously this skipped straight to senior
                    // onboarding, which was too narrow -- a VIP redeemer
                    // setting up a nest for their own senior relative,
                    // picking "I'm Family," is just as valid a nest-owner
                    // path as picking "I'm the Senior" themselves.)
                    Navigator.pushNamed(
                      context,
                      AppRoutes.roleChoiceScreen,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _showSignInLink = false;

  Future<void> _checkExistingSession() async {
    try {
      // REMOVED (Aug 11 2026): this used to independently re-check session +
      // onboarding + nest membership on every mount and navigate straight to
      // Home or role-choice on its own -- a second, complete, uncoordinated
      // copy of main.dart's _resolveInitialRoute(), missing its entitlement
      // check entirely. main.dart only ever routes here when it has
      // determined the person is NOT signed in; the only way this screen
      // could ever find a real session afterward was the exact race
      // main.dart's routing had (checking isSignedIn before the persisted
      // session finished restoring on a fast app reopen). That race is now
      // fixed at its actual origin, in main.dart, by awaiting the restored
      // session before deciding the route at all -- so a genuinely
      // signed-in-and-onboarded person is never sent here in the first
      // place, and this screen doesn't need to guess again. Two independent
      // deciders racing each other, each able to navigate on their own, was
      // the actual reason the visible sequence on relaunch was different
      // every time (branded screen, subscribe screen, or neither, in no
      // consistent order) -- if this comes back, it means something is
      // once again routing here for a signed-in user, and the fix belongs
      // in main.dart's routing decision, not a second copy of it here.
      final prefs = await SharedPreferences.getInstance();
      // No active session — check if they just signed out, to show Sign In link
      final justSignedOut = prefs.getBool('just_signed_out') ?? false;
      if (justSignedOut && mounted) {
        setState(() => _showSignInLink = true);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _logoController.dispose();
    _taglineController.dispose();
    _heartbeatController.dispose();
    _pulseController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTablet = size.width >= 600;
    final logoSize = isTablet ? 285.0 : 266.0;

    return Scaffold(
      backgroundColor: const Color(0xFFFDF9F4),
      body: Stack(
        children: [
          Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFDF9F4), Color(0xFFFAF3EC), Color(0xFFF7EDE4)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SizedBox(
              width: isTablet ? 440 : double.infinity,
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.symmetric(
                  horizontal: isTablet ? 40 : 24,
                  vertical: 4,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Top spacer — very tight, logo near top
                    SizedBox(height: size.height * 0.005),

                    // ── Logo ──
                    AnimatedBuilder(
                      animation: Listenable.merge([
                        _logoController,
                        _pulseController,
                      ]),
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _logoScale.value * _pulseScale.value,
                          child: Opacity(
                            opacity: _logoOpacity.value,
                            child: NestLogoWidget(size: logoSize),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 2),

                    // ── Heartbeat line ──
                    AnimatedBuilder(
                      animation: _heartbeatProgress,
                      builder: (context, child) {
                        return SizedBox(
                          width: isTablet ? 260 : 200,
                          height: 28,
                          child: CustomPaint(
                            painter: HeartbeatPainterWidget(
                              progress: _heartbeatProgress.value,
                              color: const Color(0xFFE8A0A0),
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 2),

                    // ── Tagline ──
                    AnimatedBuilder(
                      animation: _taglineController,
                      builder: (context, child) {
                        return SlideTransition(
                          position: _taglineSlide,
                          child: Opacity(
                            opacity: _taglineOpacity.value,
                            child: child,
                          ),
                        );
                      },
                      child: Text(
                        'One tap, one smile, one family',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.nunitoSans(
                          fontSize: isTablet ? 18 : 16,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFFD4AA00),
                          fontStyle: FontStyle.italic,
                          height: 1.4,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // ── Content: pricing + note + benefits + CTA ──
                    AnimatedBuilder(
                      animation: _contentController,
                      builder: (context, child) {
                        return SlideTransition(
                          position: _contentSlide,
                          child: Opacity(
                            opacity: _contentOpacity.value,
                            child: child,
                          ),
                        );
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          // Invite code button (smaller, replaces pricing box)
                          GestureDetector(
                            onTap: () {
                              _showInviteCodeSheet(context);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 20,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF8B6914),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                'I have an invite code',
                                style: GoogleFonts.nunitoSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 6),

                          // Nest Owner note
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              vertical: 6,
                              horizontal: 14,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF3E8),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFE8A0A0).withAlpha(80),
                                width: 1.0,
                              ),
                            ),
                            child: Text(
                              'One person (the Nest Owner) pays. Invite unlimited family members for free.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.nunitoSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFFB07040),
                                height: 1.4,
                              ),
                            ),
                          ),

                          const SizedBox(height: 8),

                          // Benefits grid
                          GridView.count(
                            crossAxisCount: 2,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 2.8,
                            children: const [
                              _BenefitTile(
                                icon: Icons.favorite_rounded,
                                label: 'Daily Check-ins',
                                iconColor: Color(0xFFE8A0A0),
                              ),
                              _BenefitTile(
                                icon: Icons.auto_stories_rounded,
                                label: 'Legacy Stories',
                                iconColor: Color(0xFFD4AA00),
                              ),
                              _BenefitTile(
                                icon: Icons.chat_bubble_rounded,
                                label: 'Easy Messages',
                                iconColor: Color(0xFF5DA399),
                              ),
                              _BenefitTile(
                                icon: Icons.shield_rounded,
                                label: 'Family Safety',
                                iconColor: Color(0xFF7DBDB5),
                              ),
                            ],
                          ),

                          const SizedBox(height: 8),

                          // Get Started button
                          GestureDetector(
                            onTap: () {
                              Navigator.pushNamed(
                                context,
                                AppRoutes.subscribeNestScreen,
                                arguments: {
                                  'returnRoute': AppRoutes.roleChoiceScreen,
                                  'returnArgs': <String, dynamic>{},
                                },
                              );
                            },
                            child: AnimatedBuilder(
                              animation: _pulseController,
                              builder: (context, child) {
                                return Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF5DA399),
                                        Color(0xFF7DBDB5),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(18),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF5DA399)
                                            .withOpacity(
                                              0.35 + _pulseScale.value * 0.05,
                                            ),
                                        blurRadius: 18,
                                        offset: const Offset(0, 5),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'Get Started',
                                        style: GoogleFonts.nunitoSans(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(
                                        Icons.arrow_forward_rounded,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),

                          // Bottom note
                          Padding(
                            padding: const EdgeInsets.only(top: 5, bottom: 8),
                            child: Text(
                              'No commitment • Cancel anytime',
                              style: GoogleFonts.nunitoSans(
                                fontSize: 11,
                                color: const Color(0xFFA8A090),
                              ),
                            ),
                          ),
                          if (_showSignInLink)
                            Padding(
                              padding: const EdgeInsets.only(top: 4, bottom: 8),
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.pushNamed(
                                    context,
                                    '/save-messages-prompt-screen',
                                    arguments: {'signInMode': true},
                                  );
                                },
                                // Matches the treatment already used on the
                                // sign-in screen itself: only "Sign In" is
                                // bold/teal/underlined, the rest reads as
                                // plain sentence text. Previously the whole
                                // phrase here was bold+underlined, which
                                // made it stand out from everything else on
                                // this page (no other text on this screen is
                                // underlined) and didn't match how the same
                                // link looks one screen later.
                                child: RichText(
                                  text: TextSpan(
                                    style: GoogleFonts.nunitoSans(
                                      fontSize: 13,
                                      color: const Color(0xFF9E8E7E),
                                    ),
                                    children: [
                                      const TextSpan(text: 'Already have an account? '),
                                      TextSpan(
                                        text: 'Sign In',
                                        style: GoogleFonts.nunitoSans(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF5DA399),
                                          decoration: TextDecoration.underline,
                                          decorationColor: const Color(0xFF5DA399),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
          const KeyboardDoneBarOverlay(),
        ],
      ),
    );
  }
}

class _BenefitTile extends StatelessWidget {
  const _BenefitTile({
    required this.icon,
    required this.label,
    required this.iconColor,
  });

  final IconData icon;
  final String label;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF9F4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEDE5D8), width: 1.5),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 16),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.nunitoSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF2C2417),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _InviteCodeSubmitButton extends StatefulWidget {
  final TextEditingController codeController;
  final void Function(String code) onValidCode;
  final VoidCallback onVipCode;

  const _InviteCodeSubmitButton({
    required this.codeController,
    required this.onValidCode,
    required this.onVipCode,
  });

  @override
  State<_InviteCodeSubmitButton> createState() =>
      _InviteCodeSubmitButtonState();
}

class _InviteCodeSubmitButtonState extends State<_InviteCodeSubmitButton> {
  bool _isValidating = false;
  String? _errorText;

  Future<void> _handleContinue() async {
    final rawCode = widget.codeController.text.trim();
    if (rawCode.isEmpty || _isValidating) return;
    final code = rawCode.toUpperCase();
    final normalizedCode = code.replaceAll(RegExp(r'[^A-Z0-9]'), '');

    // Real, trackable, limited-use VIP codes -- replaces the single
    // hardcoded VIP218460 that had unlimited uses and zero tracking.
    // This screen runs BEFORE sign-up -- no account exists yet, on
    // purpose, for every user, always. So this only checks the code is
    // real and still has uses left; actual redemption happens once
    // onboarding actually creates an account.
    if (normalizedCode.startsWith('VIP')) {
      setState(() {
        _isValidating = true;
        _errorText = null;
      });
      try {
        final supabase = Supabase.instance.client;
        final valid = await supabase.rpc(
          'check_vip_code_valid',
          params: {'p_code': normalizedCode},
        );
        if (valid == true) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('vip_code', normalizedCode);
          // Explicitly clear any leftover invite state from a previous
          // session on this device -- confirmed real bug: without this, a
          // stale joined_via_invite=true and nest_id from earlier invite-
          // code testing silently connected a brand-new VIP redemption to
          // that OLD nest instead of creating its own new one. The regular
          // invite path always sets these fresh for its own scenario; VIP
          // never had the same protection.
          await prefs.setBool('joined_via_invite', false);
          await prefs.remove('nest_id');
          await prefs.remove('invite_code');
          // nest_name has this same gap -- see the matching comment in
          // role_choice_screen.dart's _selectRole for the full explanation.
          await prefs.remove('nest_name');
          widget.onVipCode();
          return;
        }
        setState(() {
          _isValidating = false;
          _errorText = 'This VIP code is invalid or has already been fully used.';
        });
        return;
      } catch (e) {
        setState(() {
          _isValidating = false;
          _errorText = "Couldn't verify that code -- please try again.";
        });
        return;
      }
    }

    setState(() {
      _isValidating = true;
      _errorText = null;
    });

    try {
      final supabase = Supabase.instance.client;
      final result = await supabase.rpc(
        'lookup_nest_by_invite_code',
        params: {'p_code': code},
      );

      if (!mounted) return;

      final bool nestFound = result is List && result.isNotEmpty;

      if (nestFound) {
        widget.onValidCode(code);
      } else {
        setState(() {
          _isValidating = false;
          _errorText =
              "We couldn't find a nest with that code. Double-check and try again.";
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isValidating = false;
        _errorText = 'Something went wrong checking that code. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_errorText != null) ...[
          Text(
            _errorText!,
            style: GoogleFonts.nunitoSans(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFC0693E),
            ),
          ),
          const SizedBox(height: 10),
        ],
        GestureDetector(
          onTap: _handleContinue,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              color: _isValidating
                  ? const Color(0xFF8B6914).withOpacity(0.6)
                  : const Color(0xFF8B6914),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: _isValidating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                      ),
                    )
                  : Text(
                      'Continue',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
