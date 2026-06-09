import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ImGoodTodayOrbWidget extends StatefulWidget {
  const ImGoodTodayOrbWidget({
    super.key,
    required this.isSent,
    required this.onTap,
  });

  final bool isSent;
  final VoidCallback onTap;

  @override
  State<ImGoodTodayOrbWidget> createState() => _ImGoodTodayOrbWidgetState();
}

class _ImGoodTodayOrbWidgetState extends State<ImGoodTodayOrbWidget>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _tapController;
  late AnimationController _sentController;

  late Animation<double> _outerPulse;
  late Animation<double> _innerPulse;
  late Animation<double> _tapScale;
  late Animation<double> _sentFade;
  late Animation<double> _sentScale;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _tapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );

    _sentController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _outerPulse = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _innerPulse = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _tapScale = Tween<double>(
      begin: 1.0,
      end: 0.92,
    ).animate(CurvedAnimation(parent: _tapController, curve: Curves.easeInOut));
    _sentFade = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _sentController, curve: Curves.easeOut));
    _sentScale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _sentController, curve: Curves.elasticOut),
    );

    if (!widget.isSent) {
      _pulseController.repeat(reverse: true);
    } else {
      _sentController.forward();
    }
  }

  @override
  void didUpdateWidget(ImGoodTodayOrbWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSent && !oldWidget.isSent) {
      _pulseController.stop();
      _sentController.forward();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _tapController.dispose();
    _sentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isSent) {
      return AnimatedBuilder(
        animation: _sentController,
        builder: (context, child) => Transform.scale(
          scale: _sentScale.value,
          child: Opacity(opacity: _sentFade.value, child: child),
        ),
        child: _buildSentState(),
      );
    }

    return GestureDetector(
      onTapDown: (_) => _tapController.forward(),
      onTapUp: (_) {
        _tapController.reverse();
        widget.onTap();
      },
      onTapCancel: () => _tapController.reverse(),
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulseController, _tapController]),
        builder: (context, child) {
          return Transform.scale(
            scale: _tapScale.value,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer glow ring
                Transform.scale(
                  scale: _outerPulse.value,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFF5DA399).withAlpha(64),
                          const Color(0xFFD4AA00).withAlpha(20),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                // Inner orb
                Transform.scale(scale: _innerPulse.value, child: child),
              ],
            ),
          );
        },
        child: _buildOrbBody(),
      ),
    );
  }

  Widget _buildOrbBody() {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6EC9BE), Color(0xFF5DA399), Color(0xFF4A9088)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5DA399).withAlpha(115),
            blurRadius: 20,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: const Color(0xFFD4AA00).withAlpha(51),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.favorite_rounded, color: Colors.white, size: 22),
          const SizedBox(height: 2),
          Text(
            "I'm Good",
            style: GoogleFonts.nunitoSans(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSentState() {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE8C84A), Color(0xFFD4AA00)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD4AA00).withAlpha(89),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 22),
          const SizedBox(height: 2),
          Text(
            'Sent! ✓',
            style: GoogleFonts.nunitoSans(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
