import 'package:flutter/material.dart';

/// Arena brand and semantic colors.
class AppColors {
  AppColors._();

  static const Color arenaBlack = Color(0xFF000000);
  static const Color navy = Color(0xFF0D2946);
  static const Color warmWhite = Color(0xFFFFFDF8);
  static const Color brandGreen = Color(0xFF9DBF45);
  static const Color brandGreenLight = Color(0xFFC7DB79);
  static const Color brandGreenMedium = Color(0xFF8FAF3F);

  // Compatibility aliases used by existing screens.
  static const Color padelPulse = brandGreen;
  static const Color courtMist = warmWhite;

  static const Color primary = navy;
  static const Color secondary = brandGreen;
  static const Color dark = navy;
  static const Color background = courtMist;
  static const Color text = navy;
  static const Color card = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFDCE3E9);
  static const Color hint = Color(0xFF607184);
  static const Color success = brandGreenMedium;
  static const Color field = courtMist;
  static const Color purple = brandGreen;
  static const Color tealText = navy;
  static const Color error = Color(0xFFB93845);
  static const Color warning = Color(0xFF966314);
  static const Color cancelled = Color(0xFF697586);
  static const Color white = courtMist;
  static const Color black = arenaBlack;
}
