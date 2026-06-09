import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class LegacyPromptCardWidget extends StatefulWidget {
  const LegacyPromptCardWidget({
    super.key,
    required this.isDarkMode,
    required this.prompt,
    required this.onRespond,
    this.isSenior = false,
  });

  final bool isDarkMode;
  final String prompt;
  final VoidCallback onRespond;
  final bool isSenior;

  @override
  State<LegacyPromptCardWidget> createState() => _LegacyPromptCardWidgetState();
}

class _LegacyPromptCardWidgetState extends State<LegacyPromptCardWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;
  late Animation<double> _shimmerAnim;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    _shimmerAnim = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: widget.isDarkMode
              ? [const Color(0xFF2A2010), const Color(0xFF1E1A0C)]
              : [const Color(0xFFFFF9EC), const Color(0xFFFFF3D0)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFD4AA00).withAlpha(89),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFD4AA00).withAlpha(38),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.auto_stories_rounded,
                  color: Color(0xFFD4AA00),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Legacy Prompt',
                style: GoogleFonts.nunitoSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFD4AA00),
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              // Sparkle shimmer badge
              AnimatedBuilder(
                animation: _shimmerAnim,
                builder: (context, child) {
                  return ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      colors: [
                        const Color(0xFFD4AA00).withAlpha(102),
                        const Color(0xFFD4AA00),
                        const Color(0xFFD4AA00).withAlpha(102),
                      ],
                      stops: [
                        (_shimmerAnim.value - 0.3).clamp(0.0, 1.0),
                        _shimmerAnim.value.clamp(0.0, 1.0),
                        (_shimmerAnim.value + 0.3).clamp(0.0, 1.0),
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ).createShader(bounds),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '"${widget.prompt}"',
            style: GoogleFonts.nunitoSans(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: widget.isDarkMode
                  ? const Color(0xFFF5EDD8)
                  : const Color(0xFF2C2417),
              height: 1.6,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 16),
          if (widget.isSenior)
            GestureDetector(
              onTap: widget.onRespond,
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFD4AA00),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFD4AA00).withAlpha(64),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.edit_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Write Your Story',
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
            ),
        ],
      ),
    );
  }
}
