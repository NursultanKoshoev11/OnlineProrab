import 'package:flutter/material.dart';

abstract final class OnlineProrabColors {
  static const background = Color(0xFFF6F8F6);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceSoft = Color(0xFFF0F4F1);
  static const primary = Color(0xFF315F4D);
  static const primaryDark = Color(0xFF244C3D);
  static const mint = Color(0xFFDCEDE3);
  static const text = Color(0xFF18201C);
  static const textMuted = Color(0xFF718078);
  static const border = Color(0xFFE3E9E5);
  static const warning = Color(0xFFB77722);
  static const warningSoft = Color(0xFFFFF0D9);
}

ThemeData buildOnlineProrabTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: OnlineProrabColors.primary,
    brightness: Brightness.light,
    surface: OnlineProrabColors.surface,
  );

  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(18),
    borderSide: BorderSide.none,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme.copyWith(
      primary: OnlineProrabColors.primary,
      onPrimary: Colors.white,
      surface: OnlineProrabColors.surface,
      onSurface: OnlineProrabColors.text,
    ),
    scaffoldBackgroundColor: OnlineProrabColors.background,
    appBarTheme: const AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: OnlineProrabColors.background,
      foregroundColor: OnlineProrabColors.text,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: OnlineProrabColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: OnlineProrabColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: OnlineProrabColors.surfaceSoft,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(
          color: OnlineProrabColors.primary,
          width: 1.4,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      hintStyle: const TextStyle(color: OnlineProrabColors.textMuted),
      labelStyle: const TextStyle(color: OnlineProrabColors.textMuted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: OnlineProrabColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: OnlineProrabColors.primary,
        minimumSize: const Size(0, 52),
        side: const BorderSide(color: OnlineProrabColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: OnlineProrabColors.surfaceSoft,
      selectedColor: OnlineProrabColors.primary,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      labelStyle: const TextStyle(color: OnlineProrabColors.text),
      secondaryLabelStyle: const TextStyle(color: Colors.white),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      elevation: 0,
      backgroundColor: Colors.white,
      indicatorColor: OnlineProrabColors.mint,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? OnlineProrabColors.primary
              : OnlineProrabColors.textMuted,
        ),
      ),
    ),
    dividerColor: OnlineProrabColors.border,
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 30,
        height: 1.1,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
        color: OnlineProrabColors.text,
      ),
      headlineMedium: TextStyle(
        fontSize: 25,
        height: 1.15,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.35,
        color: OnlineProrabColors.text,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: OnlineProrabColors.text,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: OnlineProrabColors.text,
      ),
      bodyLarge: TextStyle(fontSize: 16, color: OnlineProrabColors.text),
      bodyMedium: TextStyle(fontSize: 14, color: OnlineProrabColors.text),
      bodySmall: TextStyle(fontSize: 12, color: OnlineProrabColors.textMuted),
    ),
  );
}
