import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Pro Tech Golf Palette
class AppColors {
  // Backgrounds
  static const Color backgroundDark = Color(0xFF0F172A); // Slate 900
  static const Color surfaceDark = Color(0xFF1E293B); // Slate 800
  static const Color surfaceLight = Color(0xFF334155); // Slate 700

  // Primaries
  static const Color primary = Color(0xFF10B981); // Emerald 500
  static const Color primaryContainer = Color(0xFF064E3B); // Emerald 900
  
  // Secondaries
  static const Color secondary = Color(0xFF3B82F6); // Blue 500
  static const Color secondaryContainer = Color(0xFF1E3A8A); // Blue 900

  // Accents
  static const Color accent = Color(0xFFF59E0B); // Amber 500 (for highlights)
  static const Color error = Color(0xFFEF4444); // Red 500
  
  // Text
  static const Color textPrimary = Color(0xFFF8FAFC); // Slate 50
  static const Color textSecondary = Color(0xFF94A3B8); // Slate 400
}

final ThemeData appTheme = ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: AppColors.backgroundDark,
  fontFamily: GoogleFonts.inter().fontFamily,
  
  colorScheme: const ColorScheme.dark(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    primaryContainer: AppColors.primaryContainer,
    secondary: AppColors.secondary,
    onSecondary: Colors.white,
    secondaryContainer: AppColors.secondaryContainer,
    surface: AppColors.surfaceDark,
    error: AppColors.error,
    onSurface: AppColors.textPrimary,
  ),

  appBarTheme: AppBarTheme(
    backgroundColor: Colors.transparent,
    elevation: 0,
    centerTitle: true,
    titleTextStyle: GoogleFonts.outfit(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
      letterSpacing: 0.5,
    ),
    iconTheme: const IconThemeData(color: AppColors.textSecondary),
  ),

  cardTheme: CardThemeData(
    color: AppColors.surfaceDark,
    elevation: 8,
    shadowColor: Colors.black.withOpacity(0.4),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  ),

  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      shadowColor: AppColors.primary.withOpacity(0.4),
      textStyle: const TextStyle(
        fontSize: 16, 
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      ),
    ),
  ),

  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.primary,
      side: const BorderSide(color: AppColors.primary, width: 2),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
    ),
  ),

  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AppColors.surfaceDark,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: AppColors.surfaceLight.withOpacity(0.5)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AppColors.primary),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
    hintStyle: const TextStyle(color: AppColors.textSecondary),
  ),
  
  // Custom Extensions can be added here if needed
);

// Helper for consistency
extension ThemeExtras on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get typography => Theme.of(this).textTheme;
}
