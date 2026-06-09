import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CelebrationsCardWidget extends StatelessWidget {
  const CelebrationsCardWidget({
    super.key,
    required this.isDarkMode,
    required this.todayEvents,
    required this.upcomingEvents,
  });

  final bool isDarkMode;
  final List<CelebrationEvent> todayEvents;
  final List<CelebrationEvent> upcomingEvents;

  @override
  Widget build(BuildContext context) {
    final cardBg = isDarkMode
        ? const Color(0xFF2A1F18)
        : const Color(0xFFFFF8F0);
    final cardBorder = isDarkMode
        ? const Color(0xFF5C3D28)
        : const Color(0xFFFFD580);
    final textPrimary = isDarkMode
        ? const Color(0xFFFFF0D6)
        : const Color(0xFF2C1A0E);
    final textSecondary = isDarkMode
        ? const Color(0xFFCCA870)
        : const Color(0xFF7A5C3A);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cardBorder, width: 1.8),
        boxShadow: [
          BoxShadow(
            color: isDarkMode
                ? const Color(0xFFFF9500).withAlpha(30)
                : const Color(0xFFFFB347).withAlpha(50),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Festive gradient header
          _FestiveHeader(isDarkMode: isDarkMode),
          // Today section
          if (todayEvents.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Row(
                children: [
                  const Text('🎂', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 5),
                  Text(
                    'TODAY',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: isDarkMode
                          ? const Color(0xFFFF8C42)
                          : const Color(0xFFE05C00),
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ),
            ...todayEvents.map(
              (e) => _buildEventRow(
                e,
                textPrimary,
                textSecondary,
                isToday: true,
                isDarkMode: isDarkMode,
              ),
            ),
          ],
          // Upcoming section
          if (upcomingEvents.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Row(
                children: [
                  const Text('📅', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 5),
                  Text(
                    'UPCOMING',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: textSecondary,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ),
            ...upcomingEvents.map(
              (e) => _buildEventRow(
                e,
                textPrimary,
                textSecondary,
                isToday: false,
                isDarkMode: isDarkMode,
              ),
            ),
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildEventRow(
    CelebrationEvent event,
    Color textPrimary,
    Color textSecondary, {
    required bool isToday,
    required bool isDarkMode,
  }) {
    final isBirthday = event.type == CelebrationEventType.birthday;
    final iconColor = isBirthday
        ? const Color(0xFFE05C5C)
        : const Color(0xFFD4609A);
    final bgColor = isBirthday
        ? const Color(0xFFFFE0E0)
        : const Color(0xFFFFE0F0);
    final darkBgColor = isBirthday
        ? const Color(0xFF4A1A1A)
        : const Color(0xFF3A1A2E);
    final icon = isBirthday ? Icons.cake_rounded : Icons.favorite_rounded;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDarkMode
              ? darkBgColor.withAlpha(120)
              : bgColor.withAlpha(100),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDarkMode
                ? iconColor.withAlpha(60)
                : iconColor.withAlpha(40),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isDarkMode
                    ? iconColor.withAlpha(50)
                    : iconColor.withAlpha(30),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.name,
                    style: GoogleFonts.nunitoSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  Text(
                    isBirthday ? 'Birthday 🎂' : 'Anniversary 💕',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 12,
                      color: textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (!isToday)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isDarkMode
                      ? const Color(0xFF3D2A10)
                      : const Color(0xFFFFF0D0),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDarkMode
                        ? const Color(0xFFCC8833)
                        : const Color(0xFFFFB347),
                    width: 1,
                  ),
                ),
                child: Text(
                  event.dateLabel,
                  style: GoogleFonts.nunitoSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isDarkMode
                        ? const Color(0xFFFFB347)
                        : const Color(0xFFB06000),
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF6B6B), Color(0xFFFF8E53)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '🎉 Today!',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FestiveHeader extends StatelessWidget {
  const _FestiveHeader({required this.isDarkMode});
  final bool isDarkMode;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDarkMode
                ? [
                    const Color(0xFF7B3F00),
                    const Color(0xFF5C2D00),
                    const Color(0xFF7B3F00),
                  ]
                : [
                    const Color(0xFFFF8C42),
                    const Color(0xFFFF6B6B),
                    const Color(0xFFFFB347),
                  ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
        child: Stack(
          children: [
            // Confetti dots
            ..._buildConfettiDots(isDarkMode),
            // Header content
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(40),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(
                      child: Text('🎉', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Celebrations',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.3,
                      shadows: [
                        Shadow(
                          color: Colors.black.withAlpha(60),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  const Text('🎊', style: TextStyle(fontSize: 18)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildConfettiDots(bool isDarkMode) {
    final colors = isDarkMode
        ? [
            Colors.orange.withAlpha(60),
            Colors.yellow.withAlpha(50),
            Colors.red.withAlpha(40),
            Colors.amber.withAlpha(55),
            Colors.deepOrange.withAlpha(45),
          ]
        : [
            Colors.white.withAlpha(80),
            Colors.yellow.withAlpha(100),
            Colors.white.withAlpha(60),
            Colors.yellow.withAlpha(80),
            Colors.white.withAlpha(70),
            Colors.pink.withAlpha(60),
          ];

    final positions = [
      [0.08, 0.2],
      [0.18, 0.75],
      [0.35, 0.15],
      [0.55, 0.8],
      [0.72, 0.25],
      [0.85, 0.65],
      [0.92, 0.3],
    ];

    final sizes = [5.0, 4.0, 6.0, 3.5, 5.5, 4.0, 3.0];

    return List.generate(positions.length, (i) {
      final color = colors[i % colors.length];
      final isSquare = i % 3 == 0;
      return Positioned.fill(
        child: FractionallySizedBox(
          alignment: Alignment(
            positions[i][0] * 2 - 1,
            positions[i][1] * 2 - 1,
          ),
          widthFactor: 0.05,
          heightFactor: 0.3,
          child: Transform.rotate(
            angle: (i * 0.7) % (math.pi),
            child: Container(
              width: sizes[i],
              height: sizes[i],
              decoration: BoxDecoration(
                color: color,
                borderRadius: isSquare
                    ? BorderRadius.circular(1)
                    : BorderRadius.circular(sizes[i]),
              ),
            ),
          ),
        ),
      );
    });
  }
}

enum CelebrationEventType { birthday, anniversary }

class CelebrationEvent {
  const CelebrationEvent({
    required this.name,
    required this.type,
    required this.dateLabel,
    required this.daysUntil,
  });

  final String name;
  final CelebrationEventType type;
  final String dateLabel;
  final int daysUntil;
}
