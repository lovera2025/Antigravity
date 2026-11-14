// El tema claro de la app para las muestras: lo mismo que arma `_buildTheme`
// en `lib/main.dart` (que es privado), con la Outfit que viene con la app en
// vez de pedirla a `google_fonts`. Una muestra con el tema de fábrica de
// Flutter enseñaría casillas y tarjetas que en el programa no se ven así.
import 'package:flutter/material.dart';

import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';

ThemeData temaClaroDeLaApp() {
  const dorado = Color(0xFFD4AF37);
  const fondo = Color(0xFFF2F0EB);
  const superficie = Color(0xFFFBFBF9);
  final base = ThemeData(
    brightness: Brightness.light,
    useMaterial3: true,
    colorSchemeSeed: dorado,
    scaffoldBackgroundColor: fondo,
    cardColor: superficie,
    fontFamily: FuentesPlano.linea,
  );
  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w900,
        color: Colors.black,
        letterSpacing: -0.5,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w800,
        color: Colors.black87,
        letterSpacing: 0,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(
        color: Colors.black87,
        fontSize: 16,
      ),
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontFamily: FuentesPlano.linea,
        fontSize: 20,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.2,
        color: Colors.black,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.black.withValues(alpha: 0.02),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: Colors.black12),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: Colors.black12),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: dorado, width: 1.5),
      ),
      labelStyle: const TextStyle(
        color: Colors.black54,
        fontWeight: FontWeight.w500,
      ),
      floatingLabelStyle: const TextStyle(
        color: dorado,
        fontWeight: FontWeight.bold,
      ),
    ),
    cardTheme: CardThemeData(
      color: superficie,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.05)),
      ),
    ),
  );
}
