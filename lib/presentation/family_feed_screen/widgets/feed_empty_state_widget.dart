import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// True empty state — shown only after user has made their first real post
/// and there are genuinely no messages yet.
class FeedEmptyStateWidget extends StatefulWidget {
  const FeedEmptyStateWidget({
    super.key,
    required this.isDarkMode,
    required this.onSend,
  });

  final bool isDarkMode;
  final VoidCallback onSend;

  @override
  State<FeedEmptyStateWidget> createState() => _FeedEmptyStateWidgetState();
}

class _FeedEmptyStateWidgetState extends State<FeedEmptyStateWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _floatController;
  late Animation<double> _floatAnim;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);
    _floatAnim = Tween<double>(begin: 0.0, end: -10.0).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _floatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          // Cozy illustration — floating nest/heart
          AnimatedBuilder(
            animation: _floatAnim,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, _floatAnim.value),
              child: child,
            ),
            child: _CozyNestIllustration(isDarkMode: widget.isDarkMode),
          ),
          const SizedBox(height: 28),
          Text(
            'No photos yet 🌿',
            style: GoogleFonts.nunitoSans(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFD4AA00),
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            'Your family feed is waiting for its first moment',
            style: GoogleFonts.nunitoSans(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: widget.isDarkMode
                  ? const Color(0xFF8A7A5A)
                  : const Color(0xFF6B5E4E),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Send a warm message, photo, or voice note to get things started!',
            style: GoogleFonts.nunitoSans(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: widget.isDarkMode
                  ? const Color(0xFF6B5E4E)
                  : const Color(0xFFA8A090),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _EmptyActionButton(
                label: 'Send Something',
                icon: Icons.send_rounded,
                color: const Color(0xFF5DA399),
                onTap: widget.onSend,
              ),
              const SizedBox(width: 12),
              _EmptyActionButton(
                label: 'Invite Family',
                icon: Icons.group_add_rounded,
                color: const Color(0xFFD4AA00),
                onTap: () {},
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _EmptyActionButton extends StatefulWidget {
  const _EmptyActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_EmptyActionButton> createState() => _EmptyActionButtonState();
}

class _EmptyActionButtonState extends State<_EmptyActionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: widget.color.withAlpha(77),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, color: Colors.white, size: 18),
              const SizedBox(width: 7),
              Text(
                widget.label,
                style: GoogleFonts.nunitoSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cozy nest illustration drawn with Flutter canvas
class _CozyNestIllustration extends StatelessWidget {
  const _CozyNestIllustration({required this.isDarkMode});

  final bool isDarkMode;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      height: 160,
      child: CustomPaint(painter: _CozyNestPainter(isDarkMode: isDarkMode)),
    );
  }
}

class _CozyNestPainter extends CustomPainter {
  _CozyNestPainter({required this.isDarkMode});

  final bool isDarkMode;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Warm glow background
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [const Color(0xFFD4AA00).withAlpha(40), Colors.transparent],
        radius: 0.7,
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawCircle(Offset(w * 0.5, h * 0.45), w * 0.45, glowPaint);

    // Nest base (warm brown arc)
    final nestPaint = Paint()
      ..color = isDarkMode ? const Color(0xFF5A3E28) : const Color(0xFFC4956A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    final nestPath = Path();
    nestPath.moveTo(w * 0.15, h * 0.65);
    nestPath.quadraticBezierTo(w * 0.5, h * 0.85, w * 0.85, h * 0.65);
    canvas.drawPath(nestPath, nestPaint);

    // Nest inner arc
    final nestInnerPaint = Paint()
      ..color = isDarkMode ? const Color(0xFF4A3020) : const Color(0xFFB07840)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final nestInnerPath = Path();
    nestInnerPath.moveTo(w * 0.22, h * 0.68);
    nestInnerPath.quadraticBezierTo(w * 0.5, h * 0.80, w * 0.78, h * 0.68);
    canvas.drawPath(nestInnerPath, nestInnerPaint);

    // Heart in the nest
    final heartPaint = Paint()
      ..color = const Color(0xFFE8A0A0)
      ..style = PaintingStyle.fill;
    _drawHeart(canvas, Offset(w * 0.5, h * 0.52), 22, heartPaint);

    // Small sparkles
    final sparklePaint = Paint()
      ..color = const Color(0xFFD4AA00)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w * 0.25, h * 0.30), 3, sparklePaint);
    canvas.drawCircle(Offset(w * 0.75, h * 0.25), 2.5, sparklePaint);
    canvas.drawCircle(Offset(w * 0.80, h * 0.45), 2, sparklePaint);
    canvas.drawCircle(Offset(w * 0.20, h * 0.48), 2, sparklePaint);
  }

  void _drawHeart(Canvas canvas, Offset center, double size, Paint paint) {
    final path = Path();
    final x = center.dx;
    final y = center.dy;
    final s = size * 0.5;
    path.moveTo(x, y + s * 0.6);
    path.cubicTo(
      x - s * 1.5,
      y - s * 0.5,
      x - s * 2.5,
      y + s * 1.2,
      x,
      y + s * 2.2,
    );
    path.cubicTo(
      x + s * 2.5,
      y + s * 1.2,
      x + s * 1.5,
      y - s * 0.5,
      x,
      y + s * 0.6,
    );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
