import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class MedsReminderCardWidget extends StatefulWidget {
  const MedsReminderCardWidget({
    super.key,
    required this.isDarkMode,
    required this.onTaken,
  });

  final bool isDarkMode;
  final VoidCallback onTaken;

  @override
  State<MedsReminderCardWidget> createState() => _MedsReminderCardWidgetState();
}

class _MedsReminderCardWidgetState extends State<MedsReminderCardWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;
  bool _isTaken = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = widget.isDarkMode
        ? const Color(0xFF2E2820)
        : const Color(0xFFFFF8E6);
    final borderColor = widget.isDarkMode
        ? const Color(0xFF4A3D20)
        : const Color(0xFFD4AA00).withAlpha(102);

    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (context, child) => Transform.scale(
        scale: _isTaken ? 1.0 : _pulseAnim.value,
        child: child,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _isTaken
              ? (widget.isDarkMode
                    ? const Color(0xFF1E2E1E)
                    : const Color(0xFFEAF7F0))
              : cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isTaken
                ? const Color(0xFF5DA399).withAlpha(102)
                : borderColor,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _isTaken
                    ? const Color(0xFF5DA399).withAlpha(38)
                    : const Color(0xFFD4AA00).withAlpha(38),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _isTaken
                    ? Icons.check_circle_rounded
                    : Icons.medication_rounded,
                color: _isTaken
                    ? const Color(0xFF5DA399)
                    : const Color(0xFFD4AA00),
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isTaken ? 'Medications taken ✓' : 'Daily Medications',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: widget.isDarkMode
                          ? const Color(0xFFF5EDD8)
                          : const Color(0xFF2C2417),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _isTaken
                        ? 'Great job! Your family has been notified.'
                        : 'Have you taken your medications today?',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 12,
                      color: widget.isDarkMode
                          ? const Color(0xFF8A7A5A)
                          : const Color(0xFF6B5E4E),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            if (!_isTaken) ...[
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () {
                  setState(() => _isTaken = true);
                  _pulseController.stop();
                  widget.onTaken();
                },
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4AA00),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      'Done ✓',
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
          ],
        ),
      ),
    );
  }
}
