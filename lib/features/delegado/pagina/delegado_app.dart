import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../delegado_providers.dart';
import 'pagina_del_delegado.dart';

/// `?delegado&clave=…`: la página del link del delegado (6.8.0). Sin usuario.
///
/// Va clara y con Outfit, que viene con la app: en el celular del delegado no
/// puede depender de bajar una letra.
class DelegadoApp extends ConsumerWidget {
  final String clave;
  const DelegadoApp({required this.clave, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final base = ThemeData(
      brightness: Brightness.light,
      useMaterial3: true,
      colorSchemeSeed: const Color(0xFF1E57B8),
    );
    return MaterialApp(
      title: 'Acompañantes y música — Junior Eventos',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        textTheme: GoogleFonts.outfitTextTheme(base.textTheme),
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('es', 'AR')],
      locale: const Locale('es', 'AR'),
      home: PaginaDelDelegado(
        clave: clave,
        nube: ref.watch(nubeDelDelegadoProvider),
      ),
    );
  }
}
