import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../routes/app_routes.dart';
import '../../widgets/keyboard_done_bar.dart';
import '../../core/app_state.dart';
import './widgets/heartbeat_painter_widget.dart';
import './widgets/nest_logo_widget.dart';

// Sep 26 2026: rebuilt as a full-bleed photo hero, matching the approved
// Landing-Fullbleed Claude Design mockup D Von signed off on -- but this
// only ever applied to the first-time pitch. Sep 27 2026: the rebuild had
// also put the returning-user ("just signed out") screen behind the same
// hero photo, which was never the intent -- that screen keeps its own
// longstanding look (the pale cream/gold/clay gradient with the Nest
// logo), completely separate from the new photo-hero Landing screen.
// Every other real behavior (invite code entry, sign-in fallback, Get
// Started routing, the banner passed in via route arguments) is
// preserved unchanged below.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const String _heroAsset = 'assets/images/landing_hero_porch.jpg';
  static const String _iconAsset = 'assets/images/nest_icon_transparent.png';

  static const Color _teal = Color(0xFF5DA399);
  static const Color _gold = Color(0xFFC8922A);
  static const Color _ink = Color(0xFF2C2417);

  // Seeded synchronously from the already-resolved app-wide notifier --
  // see appIsReturningUserNotifier in app_state.dart. Correct on the very
  // first build, so this screen never flashes the full first-time pitch
  // before switching to the leaner returning-user view.
  bool _isReturningUser = appIsReturningUserNotifier.value;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
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
  }

  void _showInviteCodeSheet(BuildContext context) {
    final TextEditingController codeController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        // Never had a KeyboardDoneBar at all until now -- found during a
        // full audit of every showModalBottomSheet call in the app
        // (Aug 18 2026). This exact field (the invite code entry point)
        // was relying on the parent screen's ambient
        // KeyboardDoneBarOverlay, which is architecturally hidden behind
        // any modal, so it never actually showed here despite being one
        // of the most frequently tested fields this whole session.
        return KeyboardDoneBar(
          alreadyPaddedForKeyboard: true,
          child: Padding(
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
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Returning-user (just-signed-out) screen is wholly separate from the
    // hero-photo first-time pitch below -- its own Scaffold, own
    // background, never the marketing photo.
    if (_isReturningUser) {
      return _buildReturningUserScreen(context);
    }

    return Scaffold(
      backgroundColor: _ink,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Full-bleed hero photo -- carries the entire screen, matching
          // the approved Landing-Fullbleed mockup. First-time pitch only.
          Image.asset(
            _heroAsset,
            fit: BoxFit.cover,
            alignment: const Alignment(0, -0.55),
          ),

          // Top scrim -- just enough for the status bar / small mark to read.
          Container(
            height: 160,
            alignment: Alignment.topCenter,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x8C140F08), Color(0x00140F08)],
              ),
            ),
          ),

          // Small icon mark, no wordmark -- D Von's direct ask removing the
          // "SeniorNest" wordmark from this board's photo.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Align(
                alignment: Alignment.topCenter,
                child: Image.asset(
                  _iconAsset,
                  width: 44,
                  height: 44,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.favorite_rounded,
                    color: _gold,
                    size: 36,
                  ),
                ),
              ),
            ),
          ),

          // Bottom scrim -- carries all the copy.
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.42, 1.0],
                colors: [
                  Color(0x00140F08),
                  Color(0xB8140F08),
                  Color(0xF0140F08),
                ],
              ),
            ),
          ),

          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                child: _buildFirstTimeContent(context),
              ),
            ),
          ),

          const KeyboardDoneBarOverlay(),
        ],
      ),
    );
  }

  Widget _buildReturningUserScreen(BuildContext context) {
    // Shown only when this device just signed out. This is the
    // longstanding "welcome back" screen -- pale cream/gold/clay
    // gradient, the Nest logo, static heartbeat line -- restored to its
    // own Scaffold after the Sep 26 hero-photo rebuild wrongly put it
    // behind the same marketing photo used for the first-time pitch.
    // Not animated (the original ran its logo/heartbeat entrance on
    // AnimationControllers this rebuilt class no longer has) -- the
    // static mark reads the same to someone just signing back in.
    final size = MediaQuery.of(context).size;
    final isTablet = size.width >= 600;
    final logoSize = isTablet ? 285.0 : 266.0;

    return Scaffold(
      backgroundColor: const Color(0xFFE9F1EE),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE9F1EE), Color(0xFFF3E7C4), Color(0xFFF8E9E1)],
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
                    SizedBox(height: size.height * 0.04),
                    NestLogoWidget(size: logoSize),
                    const SizedBox(height: 2),
                    SizedBox(
                      width: isTablet ? 260 : 200,
                      height: 28,
                      child: CustomPaint(
                        painter: HeartbeatPainterWidget(
                          progress: 1.0,
                          color: const Color(0xFFE8A0A0),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'Welcome back',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.nunitoSans(
                        fontSize: isTablet ? 22 : 20,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF2C2417),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Sign in to pick up right where you left off.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.nunitoSans(
                        fontSize: 14,
                        color: const Color(0xFF6B5E4E),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 26),
                    GestureDetector(
                      onTap: () {
                        Navigator.pushNamed(
                          context,
                          '/save-messages-prompt-screen',
                          arguments: {'signInMode': true},
                        );
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF5DA399), Color(0xFF7DBDB5)],
                          ),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF5DA399).withValues(alpha: 0.35),
                              blurRadius: 18,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Text(
                          'Sign In',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.nunitoSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    // Fallback for a different person picking up the same
                    // device (e.g. a shared family phone) -- drops back
                    // to the full first-time pitch for this session
                    // without needing a separate page.
                    GestureDetector(
                      onTap: () {
                        setState(() => _isReturningUser = false);
                      },
                      child: RichText(
                        text: TextSpan(
                          style: GoogleFonts.nunitoSans(
                            fontSize: 13,
                            color: const Color(0xFF9E8E7E),
                          ),
                          children: [
                            const TextSpan(text: 'New here? '),
                            TextSpan(
                              text: 'Get Started',
                              style: GoogleFonts.nunitoSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF5DA399),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: size.height * 0.04),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFirstTimeContent(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'One tap, one family, one smile.',
          textAlign: TextAlign.center,
          style: GoogleFonts.nunitoSans(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            height: 1.22,
            shadows: const [Shadow(blurRadius: 10, color: Color(0x59000000))],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'CHECK-INS · MESSAGES · LEGACY STORIES · SAFETY',
          textAlign: TextAlign.center,
          style: GoogleFonts.nunitoSans(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: Colors.white.withValues(alpha: 0.82),
          ),
        ),

        const SizedBox(height: 18),

        // Nest Owner note
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 14),
          decoration: BoxDecoration(
            color: _gold.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: _gold.withValues(alpha: 0.55), width: 1.5),
          ),
          child: Text(
            'One person pays — everyone else joins free',
            textAlign: TextAlign.center,
            style: GoogleFonts.nunitoSans(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),

        const SizedBox(height: 18),

        // CTAs side by side, matching the approved mockup exactly --
        // Get Started (primary) and I have an invite code (secondary),
        // not a separate small invite-code pill above the CTA.
        Row(
          children: [
            Expanded(
              flex: 11,
              child: GestureDetector(
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
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: _teal,
                    borderRadius: BorderRadius.circular(100),
                    boxShadow: [
                      BoxShadow(
                        color: _teal.withValues(alpha: 0.45),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Get Started',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 10,
              child: GestureDetector(
                onTap: () => _showInviteCodeSheet(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.5),
                  ),
                  child: Text(
                    'I have an invite code',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.nunitoSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        Text(
          'No commitment • Cancel anytime',
          style: GoogleFonts.nunitoSans(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.65),
          ),
        ),

        const SizedBox(height: 6),

        // Always present here, unlike the returning-user view above -- this
        // branch is also what a fresh install or a different device shows
        // to someone who already has an account but never explicitly
        // signed out on this exact device, so
        // just_signed_out/appIsReturningUserNotifier wouldn't have caught
        // them. Without this, that person would have no way back into
        // their account from this screen at all.
        GestureDetector(
          onTap: () {
            Navigator.pushNamed(
              context,
              '/save-messages-prompt-screen',
              arguments: {'signInMode': true},
            );
          },
          child: RichText(
            text: TextSpan(
              style: GoogleFonts.nunitoSans(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.65),
              ),
              children: [
                const TextSpan(text: 'Already have an account? '),
                TextSpan(
                  text: 'Sign In',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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
                  ? const Color(0xFF8B6914).withValues(alpha: 0.6)
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
