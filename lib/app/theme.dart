import 'package:flutter/material.dart';

/// High-contrast emergency color tokens.
/// Never rely on color alone—always pair with explicit icons and labels.
abstract final class MeshColors {
  static const Color sosRed = Color(0xFFC62828);
  static const Color hazardAmber = Color(0xFFE65100);
  static const Color verifiedGreen = Color(0xFF1B5E20);
  static const Color primaryBlue = Color(0xFF0D47A1);
  static const Color surfaceLight = Color(0xFFFAFAFA);
  static const Color cardSurface = Color(0xFFFFFFFF);
  static const Color inkPrimary = Color(0xFF111111);
  static const Color inkSecondary = Color(0xFF37474F);
  static const Color borderStrong = Color(0xFFB0BEC5);
}

ThemeData buildMeshTheme() {
  const colorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: MeshColors.primaryBlue,
    onPrimary: Colors.white,
    secondary: MeshColors.verifiedGreen,
    onSecondary: Colors.white,
    error: MeshColors.sosRed,
    onError: Colors.white,
    surface: MeshColors.surfaceLight,
    onSurface: MeshColors.inkPrimary,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: MeshColors.surfaceLight,
    appBarTheme: const AppBarTheme(
      backgroundColor: MeshColors.inkPrimary,
      foregroundColor: Colors.white,
      centerTitle: false,
      elevation: 0,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: MeshColors.cardSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: MeshColors.borderStrong, width: 1.5),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(64, 56),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 56),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 56),
        side: const BorderSide(color: MeshColors.inkPrimary, width: 1.5),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      height: 76,
      backgroundColor: Colors.white,
      indicatorColor: Color(0xFFD6E4FF),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    textTheme: const TextTheme(
      headlineSmall: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        color: MeshColors.inkPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: MeshColors.inkPrimary,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: MeshColors.inkPrimary,
      ),
      bodyMedium: TextStyle(
        fontSize: 15,
        color: MeshColors.inkSecondary,
      ),
    ),
  );
}

