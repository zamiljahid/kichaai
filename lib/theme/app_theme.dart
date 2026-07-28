import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Light "Pine & Marigold" palette. Token NAMES are kept identical to the old
/// dark theme so every screen re-colours automatically — only the values change:
///   deepBlue  → pine green (primary)
///   fuchsia   → marigold  (warm accent, used sparingly)
///   bgDark    → warm oat canvas
///   glassWhite→ solid white card/chip fill
class AppColors {
  static const Color black = Color(0xFF000000);
  static const Color deepBlue = Color(0xFF0F5D45); // pine — primary
  static const Color fuchsia = Color(0xFFD98A0B);  // deep marigold — accent
  static const Color ivory = Color(0xFFFDFBF6);    // near-white text on coloured surfaces

  static const Color bgDark = Color(0xFFF6F3EB);   // warm oat canvas
  static const Color bgMid = Color(0xFFFFFFFF);    // card surface
  static const Color glassWhite = Color(0xFFFFFFFF); // solid light card/chip fill
  static const Color glassBorder = Color(0xFFE7E2D6); // warm hairline
  static const Color glassBlue = Color(0x140F5D45);   // pine tint 8%
  static const Color glassBorderBlue = Color(0x330F5D45);

  static const Color textPrimary = Color(0xFF10231C);   // deep pine-ink
  static const Color textSecondary = Color(0xFF3A4A43);
  static const Color textMuted = Color(0xFF6B7C74);

  static LinearGradient get bgGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF7F4EC), Color(0xFFEFF3EE), Color(0xFFF7F4EC)],
        stops: [0.0, 0.5, 1.0],
      );

  static LinearGradient get blueGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF12735A), Color(0xFF0A3D2E)],
      );

  static LinearGradient get fuchsiaGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF4A524), Color(0xFFD98A0B)],
      );

  static LinearGradient get cardGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFFFFF), Color(0xFFFCFAF4)],
      );
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.bgDark,
      colorScheme: const ColorScheme.light(
        primary: AppColors.deepBlue,
        secondary: AppColors.fuchsia,
        surface: AppColors.bgMid,
        onPrimary: AppColors.ivory,
        onSecondary: Color(0xFF3D2A00),
        onSurface: AppColors.textPrimary,
      ),
      textTheme: GoogleFonts.notoSansBengaliTextTheme().copyWith(
        displayLarge: GoogleFonts.notoSansBengali(
          color: AppColors.textPrimary,
          fontSize: 32,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        displayMedium: GoogleFonts.notoSansBengali(
          color: AppColors.textPrimary,
          fontSize: 28,
          fontWeight: FontWeight.w700,
        ),
        headlineLarge: GoogleFonts.notoSansBengali(
          color: AppColors.textPrimary,
          fontSize: 24,
          fontWeight: FontWeight.w600,
        ),
        headlineMedium: GoogleFonts.notoSansBengali(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        titleLarge: GoogleFonts.notoSansBengali(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: GoogleFonts.notoSansBengali(
          color: AppColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: GoogleFonts.notoSansBengali(
          color: AppColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w400,
        ),
        bodyMedium: GoogleFonts.notoSansBengali(
          color: AppColors.textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        bodySmall: GoogleFonts.notoSansBengali(
          color: AppColors.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
        labelLarge: GoogleFonts.notoSansBengali(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.notoSansBengali(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.glassWhite,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.glassBorder, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.glassBorder, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.deepBlue, width: 1.5),
        ),
        hintStyle: GoogleFonts.notoSansBengali(
          color: AppColors.textMuted,
          fontSize: 14,
        ),
        labelStyle: GoogleFonts.notoSansBengali(
          color: AppColors.textSecondary,
          fontSize: 14,
        ),
      ),
    );
  }
}
