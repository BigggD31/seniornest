import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../routes/app_routes.dart';
import '../profile_photo_picker_screen/profile_photo_picker_screen.dart' show kProfilePhotoKey;
import '../../services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'dart:convert';
import '../splash_screen/widgets/nest_logo_widget.dart';

class SaveMessagesPromptScreen extends StatefulWidget {
  const SaveMessagesPromptScreen({super.key});

  @override
  State<SaveMessagesPromptScreen> createState() =>
      _SaveMessagesPromptScreenState();
}

class _SaveMessagesPromptScreenState extends State<SaveMessagesPromptScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  bool _isLoading = false;
  bool _isAuthLoading = false;
  StreamSubscription? _authSub;
  String? _authError;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null && args['signInMode'] == true) {
        _showCreateAccountSheet();
      }
    });
    _fadeAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
        );
    _animController.forward();

    // Listen for successful auth (native Apple Sign-In)
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      // Navigation handled by onSuccess callback — not here
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _continueAsGuest() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_guest', true);
    await prefs.setBool('onboarding_complete', true);
    await prefs.setBool('first_load', true);
    await prefs.setBool('has_onboarded', true);

    if (mounted) {
      setState(() => _isLoading = false);
      Navigator.pushReplacementNamed(
        context,
        AppRoutes.familyFeedScreen,
        arguments: {'role': prefs.getString('user_role') ?? 'senior'},
      );
    }
  }

  Future<void> _navigateToHome({String? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
    await prefs.setBool('first_load', true);
    await prefs.setBool('has_onboarded', true);

    // Small delay to ensure Supabase auth session is fully established
    await Future.delayed(const Duration(milliseconds: 500));

    // Always update profile first regardless of whether nest exists
    final supabaseClient = Supabase.instance.client;
    final checkUserId = userId ?? supabaseClient.auth.currentUser?.id;
    if (checkUserId != null) {
      try {
        // For returning users: read from Supabase first to get real data
        // This prevents stale SharedPreferences from overwriting Supabase
        final existingProfile = await supabaseClient
            .from('user_profiles')
            .select('display_name, role, relation_type, avatar_url')
            .eq('id', checkUserId)
            .maybeSingle();

        String name = prefs.getString('display_name') ?? '';
        String role = prefs.getString('user_role') ?? 'senior';
        String relationshipType = prefs.getString('relationship') ?? '';

        if (existingProfile != null) {
          final supabaseName = existingProfile['display_name'] as String? ?? '';
          final supabaseRole = existingProfile['role'] as String? ?? '';
          final supabaseRelation = existingProfile['relation_type'] as String? ?? '';
          // If Supabase already has real data, use it (returning user)
          if (supabaseName.isNotEmpty) {
            name = supabaseName;
            await prefs.setString('display_name', name);
          }
          if (supabaseRole.isNotEmpty && supabaseRole != 'senior') {
            role = supabaseRole;
            await prefs.setString('user_role', role);
          }
          if (supabaseRelation.isNotEmpty) {
            relationshipType = supabaseRelation;
            await prefs.setString('relation_type', supabaseRelation);
            await prefs.setString('relationship', supabaseRelation);
          }
          // Restore profile photo from Supabase on sign-in
          final avatarUrl = existingProfile['avatar_url'] as String? ?? '';
          if (avatarUrl.isNotEmpty) {
            await prefs.setString(kProfilePhotoKey, avatarUrl);
            print('PROFILE_PHOTO: restored from Supabase for user $checkUserId');
          }
        }

        // Only write to Supabase if we have real data
        if (name.isNotEmpty) {
          final updateData = <String, dynamic>{
            'display_name': name,
            'full_name': name,
            'role': role,
          };
          if (relationshipType.isNotEmpty) {
            updateData['relation_type'] = relationshipType.toLowerCase();
          }
          await supabaseClient.from('user_profiles').update(updateData).eq('id', checkUserId);
          print('NEST_DEBUG: profile updated at top of _navigateToHome');
        }
      } catch (e) {
        print('NEST_DEBUG: profile update error = \$e');
      }
    }

    // If user already has a valid nest, skip nest creation and go straight to Home Feed
    if (checkUserId != null) {
      try {
        final existingMembership = await supabaseClient
            .from('nest_members')
            .select('nest_id')
            .eq('user_id', checkUserId)
            .maybeSingle();
        if (existingMembership != null) {
          final existingNestId = existingMembership['nest_id'] as String;
          await prefs.setString('nest_id', existingNestId);
          if (mounted) {
            Navigator.pushNamedAndRemoveUntil(
              context,
              '/family-feed-screen',
              (route) => false,
              arguments: {'role': prefs.getString('user_role') ?? 'senior'},
            );
          }
          return;
        }
      } catch (_) {}
    }

    // Generate invite code if not already set
    final existingCode = prefs.getString('invite_code') ?? '';
    if (existingCode.isEmpty || !RegExp(r'^NEST-[0-9]{6}$').hasMatch(existingCode)) {
      final digits = (100000 + (DateTime.now().millisecondsSinceEpoch % 900000)).toString();
      await prefs.setString('invite_code', 'NEST-' + digits);
    }

    // Create nest in Supabase now that auth session is ready
    final supabase = Supabase.instance.client;
    final effectiveUserId = userId ?? supabase.auth.currentUser?.id;
    print('NEST_DEBUG: _navigateToHome effectiveUserId = $effectiveUserId');

    if (effectiveUserId != null) {
      // We already confirmed via the database above that this user has no
      // existing nest membership — clear any stale local nest_id left over
      // from a different account previously signed in on this same device.
      await prefs.remove('nest_id');
      final existingNestId = prefs.getString('nest_id') ?? '';
      if (existingNestId.isEmpty) {
        try {
          final inviteCode = prefs.getString('invite_code') ?? '';
          final nestName = prefs.getString('nest_name') ?? 'My Family';
          final name = prefs.getString('display_name') ?? '';
          final role = prefs.getString('user_role') ?? 'senior';

          // Upsert profile first
          final relationshipType = prefs.getString('relationship') ?? 'Family';
          await supabase.from('user_profiles').update({
            'display_name': name,
            'full_name': name,
            'role': role,
            'relation_type': relationshipType.toLowerCase(),
          }).eq('id', effectiveUserId);
          print('NEST_DEBUG: profile updated');

          // Create nest
          await supabase.from('nests').insert({
            'name': nestName,
            'created_by': effectiveUserId,
            'invite_code': inviteCode,
          });
          
          // Now fetch it back — we know it exists
          final nestResponse = await supabase
              .from('nests')
              .select('id')
              .eq('created_by', effectiveUserId)
              .eq('invite_code', inviteCode)
              .single();

          final nestId = nestResponse['id'] as String;
          await prefs.setString('nest_id', nestId);
          print('NEST_DEBUG: nest created = $nestId');

          // Add as member
          await supabase.from('nest_members').upsert({
            'nest_id': nestId,
            'user_id': effectiveUserId,
          });
          print('NEST_DEBUG: nest_member added');
        } catch (e) {
          print('NEST_DEBUG: error = $e');
        }
      } else {
        print('NEST_DEBUG: nest already exists = $existingNestId');
      }
    } else {
      print('NEST_DEBUG: effectiveUserId still null in _navigateToHome');
    }

    if (mounted) {
      Navigator.pushReplacementNamed(
        context,
        AppRoutes.familyFeedScreen,
        arguments: {'role': prefs.getString('user_role') ?? 'senior'},
      );
    }
  }

  // ── Google Sign-In ────────────────────────────────────────────────────────
  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isAuthLoading = true;
      _authError = null;
    });
    final result = await AuthService.signInWithGoogle();
    if (!mounted) return;
    setState(() => _isAuthLoading = false);

    if (result.isCancelled) return;
    if (!result.isSuccess) {
      setState(() => _authError = result.errorMessage);
      return;
    }
    await _navigateToHome(userId: result.user?.id);
  }

  // ── Apple Sign-In ─────────────────────────────────────────────────────────
  Future<void> _handleAppleSignIn() async {
    setState(() {
      _isAuthLoading = true;
      _authError = null;
    });
    final result = await AuthService.signInWithApple();
    if (!mounted) return;
    setState(() => _isAuthLoading = false);

    if (result.isCancelled) return;
    if (!result.isSuccess) {
      setState(() => _authError = result.errorMessage);
      return;
    }
    await _navigateToHome(userId: result.user?.id);
  }

  // ── Email form ────────────────────────────────────────────────────────────
  void _showEmailAuthSheet({bool isSignIn = false}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EmailAuthSheet(
        isSignIn: isSignIn,
        onSuccess: ({String? userId}) {
          Navigator.pop(ctx);
          _navigateToHome(userId: userId);
        },
      ),
    );
  }

  // ── Auth bottom sheet ─────────────────────────────────────────────────────
  void _showCreateAccountSheet() {
    setState(() => _authError = null);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AuthOptionsSheet(
        isAuthLoading: _isAuthLoading,
        authError: _authError,
        onGoogleTap: () {
          Navigator.pop(ctx);
          _handleGoogleSignIn();
        },
        onAppleTap: () {
          Navigator.pop(ctx);
          _handleAppleSignIn();
        },
        onEmailSignUp: () {
          Navigator.pop(ctx);
          _showEmailAuthSheet(isSignIn: false);
        },
        onEmailSignIn: () {
          Navigator.pop(ctx);
          _showEmailAuthSheet(isSignIn: true);
        },
      ),
    );
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
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: isTablet ? 60 : 28,
                vertical: 32,
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
                        NestLogoWidget(size: isTablet ? 160.0 : 140.0),
                        SizedBox(height: isTablet ? 36 : 28),
                        // Main question
                        Text(
                          'Would you like to save your messages and stories?',
                          style: GoogleFonts.nunitoSans(
                            fontSize: isTablet ? 26 : 22,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF2C2417),
                            height: 1.3,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        // Warning card
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3CD),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFFD4AA00).withAlpha(120),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.warning_amber_rounded,
                                color: Color(0xFFD4AA00),
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Without creating an account, all your messages, stories, and activity will be lost when you close the app.',
                                  style: GoogleFonts.nunitoSans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF5C4A00),
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 36),
                        // Auth error (shown if auth fails before sheet opens)
                        if (_authError != null) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF0F0),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFE05C5C).withAlpha(80),
                              ),
                            ),
                            child: Text(
                              _authError!,
                              style: GoogleFonts.nunitoSans(
                                fontSize: 13,
                                color: const Color(0xFFC0392B),
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                        // Create Free Account button
                        SizedBox(
                          width: double.infinity,
                          height: 58,
                          child: ElevatedButton(
                            onPressed: (_isLoading || _isAuthLoading)
                                ? null
                                : _showCreateAccountSheet,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF5DA399),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 2,
                            ),
                            child: _isAuthLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.person_add_rounded,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        'Create Free Account',
                                        style: GoogleFonts.nunitoSans(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Sign-up options hint
                        Text(
                          'Sign up with Google, Apple, or email & password',
                          style: GoogleFonts.nunitoSans(
                            fontSize: 13,
                            color: const Color(0xFF9E8E7E),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        // Continue as Guest button
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: OutlinedButton(
                            onPressed: (_isLoading || _isAuthLoading)
                                ? null
                                : _continueAsGuest,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                color: Color(0xFFCCC0B0),
                                width: 1.5,
                              ),
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
                                      color: Color(0xFF5DA399),
                                    ),
                                  )
                                : Text(
                                    'Continue as Guest',
                                    style: GoogleFonts.nunitoSans(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF6B5E4E),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'You can always create an account later from your profile.',
                          style: GoogleFonts.nunitoSans(
                            fontSize: 12,
                            color: const Color(0xFFA8A090),
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Auth Options Bottom Sheet ─────────────────────────────────────────────────
class _AuthOptionsSheet extends StatelessWidget {
  const _AuthOptionsSheet({
    required this.isAuthLoading,
    required this.authError,
    required this.onGoogleTap,
    required this.onAppleTap,
    required this.onEmailSignUp,
    required this.onEmailSignIn,
  });

  final bool isAuthLoading;
  final String? authError;
  final VoidCallback onGoogleTap;
  final VoidCallback onAppleTap;
  final VoidCallback onEmailSignUp;
  final VoidCallback onEmailSignIn;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFDF9F4),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        MediaQuery.of(context).padding.bottom + 32,
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
                color: const Color(0xFFDDD5C8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Create your account',
            style: GoogleFonts.nunitoSans(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF2C2417),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Your messages and stories will be saved securely.',
            style: GoogleFonts.nunitoSans(
              fontSize: 13,
              color: const Color(0xFF9E8E7E),
            ),
          ),
          const SizedBox(height: 20),
          // Google button
          _buildSocialButton(
            onTap: isAuthLoading ? null : onGoogleTap,
            icon: SizedBox(
              width: 20,
              height: 20,
              child: CustomPaint(painter: _GoogleLogoPainter()),
            ),
            label: 'Continue with Google',
            bgColor: Colors.white,
            borderColor: const Color(0xFFDDD5C8),
            textColor: const Color(0xFF2C2417),
          ),
          const SizedBox(height: 8),
          // Apple button
          _buildSocialButton(
            onTap: isAuthLoading ? null : onAppleTap,
            icon: const Icon(Icons.apple, color: Colors.white, size: 20),
            label: 'Continue with Apple',
            bgColor: const Color(0xFF1C1C1E),
            borderColor: const Color(0xFF1C1C1E),
            textColor: Colors.white,
          ),
          const SizedBox(height: 8),
          // Email button
          _buildSocialButton(
            onTap: isAuthLoading ? null : onEmailSignUp,
            icon: const Icon(
              Icons.email_outlined,
              color: Color(0xFF5DA399),
              size: 20,
            ),
            label: 'Sign up with Email',
            bgColor: const Color(0xFF5DA399),
            borderColor: const Color(0xFF5DA399),
            textColor: Colors.white,
          ),
          const SizedBox(height: 14),
          // Sign in link
          Center(
            child: GestureDetector(
              onTap: isAuthLoading ? null : onEmailSignIn,
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
    );
  }

  Widget _buildSocialButton({
    required VoidCallback? onTap,
    required Widget icon,
    required String label,
    required Color bgColor,
    required Color borderColor,
    required Color textColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 48,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 10),
            Text(
              label,
              style: GoogleFonts.nunitoSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Google logo painter ───────────────────────────────────────────────────────
class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2;
    final double cy = size.height / 2;
    final double r = size.width / 2;

    final colors = [
      (const Color(0xFF4285F4), -0.1, 0.5),
      (const Color(0xFF34A853), 0.5, 1.1),
      (const Color(0xFFFBBC05), 1.1, 1.6),
      (const Color(0xFFEA4335), 1.6, 2.2),
    ];

    for (final c in colors) {
      final paint = Paint()
        ..color = c.$1
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.18;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.72),
        c.$2 * 3.14159,
        (c.$3 - c.$2) * 3.14159,
        false,
        paint,
      );
    }

    final whitePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(cx, cy - size.height * 0.18, r, size.height * 0.36),
      whitePaint,
    );

    final bluePaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(cx, cy - size.height * 0.18, r * 0.72, size.height * 0.36),
      bluePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Email Auth Bottom Sheet ───────────────────────────────────────────────────
class _EmailAuthSheet extends StatefulWidget {
  const _EmailAuthSheet({required this.isSignIn, required this.onSuccess});
  final bool isSignIn;
  final Function({String? userId}) onSuccess;

  @override
  State<_EmailAuthSheet> createState() => _EmailAuthSheetState();
}

class _EmailAuthSheetState extends State<_EmailAuthSheet> {
  late bool _isSignIn;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _isSignIn = widget.isSignIn;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please enter your email and password.');
      return;
    }
    if (!email.contains('@')) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = _isSignIn
        ? await AuthService.signInWithEmail(email: email, password: password)
        : await AuthService.signUpWithEmail(email: email, password: password);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (!result.isSuccess) {
      setState(() => _error = result.errorMessage);
      return;
    }

    // Pass user ID directly from signup response
    final userId = result.user?.id;
    print('NEST_DEBUG: signup response userId = ' + (userId ?? 'NULL'));
    widget.onSuccess(userId: userId);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
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
            // Handle
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
              _isSignIn ? 'Welcome back 👋' : 'Create your account',
              style: GoogleFonts.nunitoSans(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF2C2417),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _isSignIn
                  ? 'Sign in to your SeniorNest account.'
                  : 'Set up your family nest in minutes.',
              style: GoogleFonts.nunitoSans(
                fontSize: 13,
                color: const Color(0xFF9E8E7E),
              ),
            ),
            const SizedBox(height: 20),
            if (_error != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0F0),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFE05C5C).withAlpha(80),
                  ),
                ),
                child: Text(
                  _error!,
                  style: GoogleFonts.nunitoSans(
                    fontSize: 13,
                    color: const Color(0xFFC0392B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            // Email field
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              style: GoogleFonts.nunitoSans(
                fontSize: 15,
                color: const Color(0xFF2C2417),
              ),
              decoration: InputDecoration(
                hintText: 'Email address',
                hintStyle: GoogleFonts.nunitoSans(
                  fontSize: 15,
                  color: const Color(0xFFBBAA99),
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
                    color: Color(0xFF5DA399),
                    width: 2,
                  ),
                ),
                prefixIcon: const Icon(
                  Icons.email_outlined,
                  color: Color(0xFF9E8E7E),
                  size: 20,
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Password field
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              style: GoogleFonts.nunitoSans(
                fontSize: 15,
                color: const Color(0xFF2C2417),
              ),
              decoration: InputDecoration(
                hintText: 'Password',
                hintStyle: GoogleFonts.nunitoSans(
                  fontSize: 15,
                  color: const Color(0xFFBBAA99),
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
                    color: Color(0xFF5DA399),
                    width: 2,
                  ),
                ),
                prefixIcon: const Icon(
                  Icons.lock_outline_rounded,
                  color: Color(0xFF9E8E7E),
                  size: 20,
                ),
                suffixIcon: GestureDetector(
                  onTap: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  child: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: const Color(0xFF9E8E7E),
                    size: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Submit button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5DA399),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _isSignIn ? 'Sign In' : 'Create Account',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 14),
            // Toggle sign-in / sign-up
            Center(
              child: GestureDetector(
                onTap: () => setState(() {
                  _isSignIn = !_isSignIn;
                  _error = null;
                }),
                child: RichText(
                  text: TextSpan(
                    style: GoogleFonts.nunitoSans(
                      fontSize: 13,
                      color: const Color(0xFF9E8E7E),
                    ),
                    children: [
                      TextSpan(
                        text: _isSignIn
                            ? "Don't have an account? "
                            : 'Already have an account? ',
                      ),
                      TextSpan(
                        text: _isSignIn ? 'Sign Up' : 'Sign In',
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
    );
  }
}
