import 'package:flutter/material.dart';

/// Light-first premium palette: warm neutrals, charcoal type, restrained brass accent.
abstract final class AppColors {
  static const background = Color(0xFFF8F6F1);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFF1EDE4);
  static const border = Color(0xFFE4DED2);
  static const charcoal = Color(0xFF2A2A2A);
  static const charcoalMuted = Color(0xFF6B6760);
  static const brass = Color(0xFF8C6A2F);
  static const brassSoft = Color(0xFFF3EADA);

  static const ready = Color(0xFF2E7D5B);
  static const inProgress = Color(0xFF3B6EA8);
  static const attention = Color(0xFF9A6B12);
  static const delayed = Color(0xFFB4541E);
  static const blocked = Color(0xFFB12E2E);
  static const neutral = Color(0xFF6B6760);
}

abstract final class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brass,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.charcoal,
      onPrimary: AppColors.surface,
      secondary: AppColors.brass,
      onSecondary: AppColors.surface,
      surface: AppColors.surface,
      onSurface: AppColors.charcoal,
      outline: AppColors.border,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      dividerColor: AppColors.border,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.charcoal,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      textTheme: const TextTheme().apply(
        bodyColor: AppColors.charcoal,
        displayColor: AppColors.charcoal,
      ),
    );
  }
}
