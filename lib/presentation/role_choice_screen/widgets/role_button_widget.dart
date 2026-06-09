import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class RoleButtonWidget extends StatefulWidget {
  const RoleButtonWidget({
    super.key,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.isLoading,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  State<RoleButtonWidget> createState() => _RoleButtonWidgetState();
}

class _RoleButtonWidgetState extends State<RoleButtonWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressController;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _pressController.forward(),
      onTapUp: (_) {
        _pressController.reverse();
        widget.onTap();
      },
      onTapCancel: () => _pressController.reverse(),
      child: AnimatedBuilder(
        animation: _scaleAnim,
        builder: (context, child) =>
            Transform.scale(scale: _scaleAnim.value, child: child),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? const Color(0xFF5DA399).withAlpha(20)
                : const Color(0xFFFAF7F2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.isSelected
                  ? const Color(0xFF5DA399)
                  : const Color(0xFFE8E0D0),
              width: widget.isSelected ? 2 : 1.5,
            ),
          ),
          child: Row(
            children: [
              // Icon container
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: widget.isSelected
                      ? const Color(0xFF5DA399)
                      : const Color(0xFFE8E0D0),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: widget.isLoading
                    ? const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        ),
                      )
                    : Icon(
                        widget.icon,
                        size: 32,
                        color: widget.isSelected
                            ? Colors.white
                            : const Color(0xFF6B5E4E),
                      ),
              ),
              const SizedBox(width: 16),
              // Text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style: GoogleFonts.nunitoSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: widget.isSelected
                            ? const Color(0xFF5DA399)
                            : const Color(0xFF2C2417),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.subtitle,
                      style: GoogleFonts.nunitoSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: const Color(0xFF6B5E4E),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Chevron
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: widget.isSelected
                      ? const Color(0xFF5DA399)
                      : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: widget.isSelected
                      ? Colors.white
                      : const Color(0xFFA8A090),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
