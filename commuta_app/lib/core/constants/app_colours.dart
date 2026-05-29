import 'package:flutter/material.dart';

class AppColours {
  // Backgrounds
  static const Color background = Color(0xFFF8F8F6);   // warm off-white
  static const Color surface = Colors.white;

  // Morandi accents
  static const Color accent = Color(0xFF7A9E87);        // muted sage green
  static const Color accentSecondary = Color(0xFF8FA3B1); // dusty blue-grey

  // Text
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF9E9E9E);

  // DAQI severity (Morandi-adjusted) — verify DEFRA breakpoints before finalising
  static const Color daqiLow = Color(0xFF7A9E87);       // sage green
  static const Color daqiModerate = Color(0xFFD4A96A);  // muted amber
  static const Color daqiHigh = Color(0xFFCC7A6F);      // muted coral
  static const Color daqiVeryHigh = Color(0xFF9B4A42);  // deeper coral-red
}