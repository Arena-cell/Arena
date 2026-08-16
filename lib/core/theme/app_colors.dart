import 'package:flutter/material.dart';

/// Arena's current identity palette. The interface stays monochrome and uses
/// navy only for emphasis. Green is retained as brand metadata for future use,
/// but is intentionally not exposed through the active UI aliases.
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
  static const Color secondary = navy;
  static const Color dark = arenaBlack;
  static const Color background = courtMist;
  static const Color text = arenaBlack;
  static const Color card = courtMist;
  static const Color border = Color(0x52000000);
  static const Color hint = Color(0x99000000);
  static const Color success = brandGreenMedium;
  static const Color field = courtMist;
  static const Color purple = brandGreen;
  static const Color tealText = navy;
  static const Color error = arenaBlack;
  static const Color white = courtMist;
  static const Color black = arenaBlack;
}
