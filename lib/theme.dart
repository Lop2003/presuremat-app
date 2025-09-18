import 'package:flutter/material.dart';

final ThemeData appTheme = ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: const Color(0xFF070812),
  fontFamily: 'Roboto',
  colorScheme: const ColorScheme.dark(
    primary: Color(0xFF4F8EF7),
    secondary: Color(0xFF00D4FF),
    error: Color(0xFFFF6B6B),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.transparent,
    elevation: 0,
    centerTitle: true,
    titleTextStyle: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    iconTheme: IconThemeData(color: Colors.white70),
  ),
  cardTheme: CardThemeData(
    color: const Color(0xFF0F1722),
    elevation: 6,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  ),
  listTileTheme: const ListTileThemeData(
    iconColor: Colors.white70,
    textColor: Colors.white,
    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  ),
  tabBarTheme: const TabBarThemeData(
    indicatorSize: TabBarIndicatorSize.label,
    labelColor: Colors.white,
    unselectedLabelColor: Colors.white54,
    indicator: UnderlineTabIndicator(
      borderSide: BorderSide(color: Color(0xFF00D4FF), width: 2),
    ),
  ),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: Color(0xFF0B1220),
    selectedItemColor: Color(0xFF4F8EF7),
    unselectedItemColor: Colors.white54,
    type: BottomNavigationBarType.fixed,
    showUnselectedLabels: true,
  ),
  dividerTheme: const DividerThemeData(
    color: Color(0xFF1B2433),
    thickness: 1,
    space: 24,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0xFF0B1220),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: const Color(0xFF4F8EF7),
      foregroundColor: Colors.white,
    ),
  ),
  chipTheme: ChipThemeData(
    backgroundColor: const Color(0xFF0F1722),
    disabledColor: Colors.white12,
    selectedColor: const Color(0xFF4F8EF7).withOpacity(0.2),
    secondarySelectedColor: const Color(0xFF00D4FF).withOpacity(0.2),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    labelStyle: const TextStyle(color: Colors.white),
    secondaryLabelStyle: const TextStyle(color: Colors.white),
    brightness: Brightness.dark,
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: const Color(0xFF0F1722),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  ),
  textTheme: const TextTheme(
    bodyLarge: TextStyle(color: Colors.white),
    bodyMedium: TextStyle(color: Colors.white70),
    titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
  ),
);


