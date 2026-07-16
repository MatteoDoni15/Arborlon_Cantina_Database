import 'package:flutter/material.dart';

/// Colori e stile dell'app: tonalita' "vino".
class AppTheme {
  static const seed = Color(0xFF7B1E3B); // bordeaux

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFFAF6F2),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // NB: niente Size.fromHeight qui — una larghezza minima infinita
          // manda in errore il layout dei FilledButton dentro le Row
          // (vincolo insanabile). Chi vuole il bottone a tutta larghezza
          // lo avvolge in SizedBox(width: double.infinity).
          minimumSize: const Size(64, 52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }
}
