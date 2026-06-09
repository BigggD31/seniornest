import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ── Brand Colors ──────────────────────────────────────────────
  static const Color primary = Color(0xFF5DA399);
  static const Color primaryLight = Color(0xFF7DBDB5);
  static const Color primaryMuted = Color(0xff5da39940);
  static const Color gold = Color(0xFFD4AA00);
  static const Color goldLight = Color(0xffd4aa0020);
  static const Color goldMuted = Color(0xffd4aa0066);

  // ── Surface & Background ──────────────────────────────────────
  static const Color background = Color(0xFFFDFDFD);
  static const Color surfaceWarm = Color(0xFFF5F0E8);
  static const Color surfaceCard = Color(0xFFFAF7F2);
  static const Color cardBorder = Color(0xFFE8E0D0);
  static const Color cardBorderActive = Color(0xFF5DA399);

  // ── Text ──────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF2C2417);
  static const Color textSecondary = Color(0xFF6B5E4E);
  static const Color textMuted = Color(0xFFA8A090);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // ── Semantic ──────────────────────────────────────────────────
  static const Color success = Color(0xFF5DA399);
  static const Color warning = Color(0xFFD4AA00);
  static const Color error = Color(0xFFC0392B);
  static const Color errorLight = Color(0xffc0392b20);

  // ── Dark Mode ─────────────────────────────────────────────────
  static const Color darkBackground = Color(0xFF1A1612);
  static const Color darkSurface = Color(0xFF242018);
  static const Color darkSurfaceVariant = Color(0xFF2E2820);
  static const Color darkCardBorder = Color(0xFF3D3428);
  static const Color darkTextPrimary = Color(0xFFF5EDD8);
  static const Color darkTextSecondary = Color(0xFFB8A888);
  static const Color darkTextMuted = Color(0xFF6B5E4E);

  // Nav bar specific dark colors
  static const Color darkNavBackground = Color(0xFF1C1C1E);
  static const Color darkNavBorder = Color(0xFF2C2C2E);
  static const Color darkNavInactive = Color(0xFFE0E0E0);

  // ── Light Theme ───────────────────────────────────────────────
  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: const ColorScheme.light(
      primary: primary,
      onPrimary: textOnPrimary,
      primaryContainer: Color(0xFFD0EEEA),
      onPrimaryContainer: Color(0xFF003733),
      secondary: gold,
      onSecondary: textOnPrimary,
      secondaryContainer: Color(0xFFFFF0A0),
      onSecondaryContainer: Color(0xFF3A2E00),
      surface: background,
      onSurface: textPrimary,
      surfaceContainerHighest: surfaceWarm,
      onSurfaceVariant: textSecondary,
      outline: cardBorder,
      outlineVariant: Color(0xFFF0E8D8),
      error: error,
      onError: textOnPrimary,
      shadow: Color(0x14000000),
    ),
    scaffoldBackgroundColor: background,
    textTheme: _buildTextTheme(isDark: false),
    appBarTheme: AppBarThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: GoogleFonts.nunitoSans(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: textPrimary,
      ),
      iconTheme: const IconThemeData(color: textPrimary),
    ),
    cardTheme: CardThemeData(
      color: surfaceCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: cardBorder, width: 1.5),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: false,
      border: const UnderlineInputBorder(
        borderSide: BorderSide(color: cardBorder, width: 1.5),
      ),
      enabledBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: cardBorder, width: 1.5),
      ),
      focusedBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: primary, width: 2),
      ),
      labelStyle: GoogleFonts.nunitoSans(fontSize: 13, color: textMuted),
      hintStyle: GoogleFonts.nunitoSans(fontSize: 14, color: textMuted),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: textOnPrimary,
        minimumSize: const Size(double.infinity, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
        textStyle: GoogleFonts.nunitoSans(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: background,
      indicatorColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return GoogleFonts.nunitoSans(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: primary,
          );
        }
        return GoogleFonts.nunitoSans(
          fontSize: 11,
          fontWeight: FontWeight.w400,
          color: textMuted,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: primary, size: 24);
        }
        return const IconThemeData(color: Color(0xFFA8A090), size: 24);
      }),
    ),
    dividerTheme: const DividerThemeData(
      color: cardBorder,
      thickness: 1,
      space: 0,
    ),
    extensions: const [SeniorNestColors()],
  );

  // ── Dark Theme ────────────────────────────────────────────────
  static ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: primary,
      onPrimary: textOnPrimary,
      primaryContainer: Color(0xFF003733),
      onPrimaryContainer: Color(0xFFD0EEEA),
      secondary: gold,
      onSecondary: darkBackground,
      secondaryContainer: Color(0xFF3A2E00),
      onSecondaryContainer: Color(0xFFFFF0A0),
      surface: darkSurface,
      onSurface: darkTextPrimary,
      surfaceContainerHighest: darkSurfaceVariant,
      onSurfaceVariant: darkTextSecondary,
      outline: darkCardBorder,
      outlineVariant: Color(0xFF2A2218),
      error: error,
      onError: textOnPrimary,
      shadow: Color(0x40000000),
    ),
    scaffoldBackgroundColor: darkBackground,
    textTheme: _buildTextTheme(isDark: true),
    appBarTheme: AppBarThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: GoogleFonts.nunitoSans(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: darkTextPrimary,
      ),
      iconTheme: const IconThemeData(color: darkTextPrimary),
    ),
    cardTheme: CardThemeData(
      color: darkSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: darkCardBorder, width: 1.5),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: false,
      border: const UnderlineInputBorder(
        borderSide: BorderSide(color: darkCardBorder, width: 1.5),
      ),
      enabledBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: darkCardBorder, width: 1.5),
      ),
      focusedBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: primary, width: 2),
      ),
      labelStyle: GoogleFonts.nunitoSans(fontSize: 13, color: darkTextMuted),
      hintStyle: GoogleFonts.nunitoSans(fontSize: 14, color: darkTextMuted),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: textOnPrimary,
        minimumSize: const Size(double.infinity, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
        textStyle: GoogleFonts.nunitoSans(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: darkNavBackground,
      indicatorColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return GoogleFonts.nunitoSans(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: primary,
          );
        }
        return GoogleFonts.nunitoSans(
          fontSize: 11,
          fontWeight: FontWeight.w400,
          color: darkNavInactive,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: primary, size: 24);
        }
        return const IconThemeData(color: darkNavInactive, size: 24);
      }),
    ),
    dividerTheme: const DividerThemeData(
      color: darkCardBorder,
      thickness: 1,
      space: 0,
    ),
    extensions: const [SeniorNestColors()],
  );

  static TextTheme _buildTextTheme({required bool isDark}) {
    final baseColor = isDark ? darkTextPrimary : textPrimary;
    final mutedColor = isDark ? darkTextSecondary : textSecondary;
    return TextTheme(
      displayLarge: GoogleFonts.nunitoSans(
        fontSize: 36,
        fontWeight: FontWeight.w700,
        color: baseColor,
      ),
      displayMedium: GoogleFonts.nunitoSans(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        color: baseColor,
      ),
      displaySmall: GoogleFonts.nunitoSans(
        fontSize: 26,
        fontWeight: FontWeight.w600,
        color: baseColor,
      ),
      headlineLarge: GoogleFonts.nunitoSans(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: baseColor,
      ),
      headlineMedium: GoogleFonts.nunitoSans(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: baseColor,
      ),
      headlineSmall: GoogleFonts.nunitoSans(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: baseColor,
      ),
      titleLarge: GoogleFonts.nunitoSans(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: baseColor,
      ),
      titleMedium: GoogleFonts.nunitoSans(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: baseColor,
      ),
      titleSmall: GoogleFonts.nunitoSans(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: baseColor,
      ),
      bodyLarge: GoogleFonts.nunitoSans(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: baseColor,
      ),
      bodyMedium: GoogleFonts.nunitoSans(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: baseColor,
      ),
      bodySmall: GoogleFonts.nunitoSans(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: mutedColor,
      ),
      labelLarge: GoogleFonts.nunitoSans(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: baseColor,
      ),
      labelMedium: GoogleFonts.nunitoSans(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: mutedColor,
      ),
      labelSmall: GoogleFonts.nunitoSans(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: mutedColor,
      ),
    );
  }
}

// ── Theme Extension for custom colors ─────────────────────────
class SeniorNestColors extends ThemeExtension<SeniorNestColors> {
  const SeniorNestColors({
    this.gold = const Color(0xFFD4AA00),
    this.goldLight = const Color(0xffd4aa0020),
    this.surfaceWarm = const Color(0xFFF5F0E8),
    this.cardBorder = const Color(0xFFE8E0D0),
    this.orbGradientStart = const Color(0xFF5DA399),
    this.orbGradientEnd = const Color(0xFFD4AA00),
  });

  final Color gold;
  final Color goldLight;
  final Color surfaceWarm;
  final Color cardBorder;
  final Color orbGradientStart;
  final Color orbGradientEnd;

  @override
  SeniorNestColors copyWith({
    Color? gold,
    Color? goldLight,
    Color? surfaceWarm,
    Color? cardBorder,
    Color? orbGradientStart,
    Color? orbGradientEnd,
  }) {
    return SeniorNestColors(
      gold: gold ?? this.gold,
      goldLight: goldLight ?? this.goldLight,
      surfaceWarm: surfaceWarm ?? this.surfaceWarm,
      cardBorder: cardBorder ?? this.cardBorder,
      orbGradientStart: orbGradientStart ?? this.orbGradientStart,
      orbGradientEnd: orbGradientEnd ?? this.orbGradientEnd,
    );
  }

  @override
  SeniorNestColors lerp(SeniorNestColors? other, double t) {
    if (other == null) return this;
    return SeniorNestColors(
      gold: Color.lerp(gold, other.gold, t)!,
      goldLight: Color.lerp(goldLight, other.goldLight, t)!,
      surfaceWarm: Color.lerp(surfaceWarm, other.surfaceWarm, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      orbGradientStart: Color.lerp(
        orbGradientStart,
        other.orbGradientStart,
        t,
      )!,
      orbGradientEnd: Color.lerp(orbGradientEnd, other.orbGradientEnd, t)!,
    );
  }
}
