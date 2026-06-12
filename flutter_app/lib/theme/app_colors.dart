// File: flutter_app/lib/theme/app_colors.dart
// =============================================================================
// Palet warna terpusat sesuai docs/wireframe_component.md bab 2
// "Strict Color Palette". WAJIB digunakan agar konsistensi visual state
// online/offline dan aktif/nonaktif terjaga lintas-halaman.
// =============================================================================

import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color primaryCanvas   = Color(0xFFF8F9FA);
  static const Color cardBackground  = Color(0xFFFFFFFF);
  static const Color stateActive     = Color(0xFFFFD700); // Relay ON
  static const Color stateInactive   = Color(0xFF9E9E9E); // Relay OFF
  static const Color statusOnline    = Color(0xFF4CAF50);
  static const Color statusOffline   = Color(0xFF757575);
  static const Color textMain        = Color(0xFF212121);
  static const Color textSub         = Color(0xFF757575);
  static const Color dividerSoft     = Color(0xFFEEEEEE);
}
