import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class WelcomeToastWidget extends StatefulWidget {
  const WelcomeToastWidget({
    super.key,
    required this.name,
    required this.onDismiss,
  });

  final String name;
  final VoidCallback onDismiss;

  @override
  State<WelcomeToastWidget> createState() => _WelcomeToastWidgetState();
}

class _WelcomeToastWidgetState extends State<WelcomeToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();

    _slideAnim = Tween<double>(
      begin: -60,
      end: 0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fadeAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        _controller.reverse().then((_) => widget.onDismiss());
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, _slideAnim.value),
        child: Opacity(opacity: _fadeAnim.value, child: child),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF5DA399),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF5DA399).withAlpha(64),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.favorite_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Welcome back, ${widget.name}! Your family is thinking of you 💛',
                style: GoogleFonts.nunitoSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                  height: 1.4,
                ),
              ),
            ),
            GestureDetector(
              onTap: () =>
                  _controller.reverse().then((_) => widget.onDismiss()),
              child: const Icon(
                Icons.close_rounded,
                color: Colors.white70,
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
