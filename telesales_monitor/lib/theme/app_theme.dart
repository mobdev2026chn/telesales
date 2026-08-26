import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Brand Color Palette
  static const Color ink900 = Color(0xFF10180C);
  static const Color ink800 = Color(0xFF1A2314);
  static const Color ink700 = Color(0xFF3A4033);
  static const Color muted = Color(0xFF7A8172);
  static const Color lightMuted = Color(0xFF8A9285);
  static const Color paper = Color(0xFFEFECE3);
  static const Color white = Color(0xFFFFFFFF);

  // Vibrant Accents
  static const Color greenNeon = Color(0xFF3DC838);
  static const Color greenGrass = Color(0xFF7FD63B);
  static const Color limeYellow = Color(0xFFC8FF4A);
  static const Color greenDark = Color(0xFF2E9E2B);
  static const Color orangePill = Color(0xFFFF9500);
  static const Color redMissed = Color(0xFFE63946);

  // Linear Gradients
  static const LinearGradient greenGradient = LinearGradient(
    colors: [greenNeon, greenGrass, limeYellow],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardDarkGradient = LinearGradient(
    colors: [ink900, ink800],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Neo-brutalist Drop Shadows
  static List<BoxShadow> neoShadow({Color color = ink900, double offset = 4.0}) => [
        BoxShadow(
          color: color,
          offset: Offset(offset, offset),
          blurRadius: 0,
          spreadRadius: 0,
        ),
      ];

  static List<BoxShadow> neoShadowSm({Color color = ink900}) => neoShadow(color: color, offset: 3.0);

  // Border Styles
  static Border neoBorder({Color color = ink900, double width = 1.0}) => Border.all(
        color: color,
        width: width,
      );

  // Typography
  static TextStyle headline({double size = 24, Color color = ink900}) =>
      GoogleFonts.anton(fontSize: size, color: color, height: 0.98, letterSpacing: 0.5);

  static TextStyle italicSerif({double size = 16, Color color = greenDark}) =>
      GoogleFonts.playfairDisplay(fontSize: size, color: color, fontStyle: FontStyle.italic);

  static TextStyle body({double size = 13, Color color = ink900, FontWeight weight = FontWeight.w400}) =>
      GoogleFonts.archivo(fontSize: size, color: color, fontWeight: weight);

  static TextStyle bodyBold({double size = 13, Color color = ink900}) =>
      body(size: size, color: color, weight: FontWeight.w700);

  static TextStyle mono({double size = 12, Color color = ink900, FontWeight weight = FontWeight.w600}) =>
      GoogleFonts.spaceMono(fontSize: size, color: color, fontWeight: weight);

  static TextStyle label({double size = 9, Color color = muted, double letterSpacing = 0.18}) =>
      GoogleFonts.archivo(
        fontSize: size,
        color: color,
        fontWeight: FontWeight.w700,
        letterSpacing: letterSpacing,
      );
}
