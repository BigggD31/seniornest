import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../routes/app_routes.dart';
import './widgets/heartbeat_painter_widget.dart';
import './widgets/nest_logo_widget.dart';

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
                  'Type your NEST-XXXXXX or lifetime invite code below.',
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
                    hintText: 'e.g. NEST-ABC123',
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
                StatefulBuilder(
                  builder: (ctx, setSheetState) {
                    return GestureDetector(
                      onTap: () {
                        final code = codeController.text.trim();
                        if (code.isEmpty) return;
                        Navigator.pop(sheetContext);
                        if (code.toUpperCase().contains('VIP')) {
                          Navigator.pushNamed(
                            context,
                            AppRoutes.roleChoiceScreen,
                          );
                        } else if (code.toUpperCase().contains('NEST')) {
                          Navigator.pushNamed(
                            context,
                            AppRoutes.nestRoleAfterInviteScreen,
                            arguments: {'inviteCode': code},
                          );
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8B6914),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: Text(
                            'Continue',
                            style: GoogleFonts.nunitoSans(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
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

  Future<void> _checkExistingSession() async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        final prefs = await SharedPreferences.getInstance();
        final hasOnboarded = prefs.getBool('has_onboarded') ?? false;
        if (hasOnboarded && mounted) {
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/family-feed-screen',
                (route) => false,
              );
            }
          });
        }
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
      body: Container(
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
