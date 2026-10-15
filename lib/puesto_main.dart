import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';

import 'features/recepcion/central/cliente_central.dart';
import 'features/recepcion/central/pantalla_puesto.dart';

/// La página del celular de la puerta. No es la web de siempre: la sirve la
/// notebook central del salón (`CentralPuerta`) por el wifi del router, y anda
/// sin internet. Se arma aparte:
///
///     flutter build web -t lib/puesto_main.dart --no-web-resources-cdn
///
/// y el instalador la deja en la carpeta `puesto`, al lado del programa.
///
/// Sin Supabase ni base: todo lo que sabe se lo dice la central.
void main() {
  // Las letras vienen con la página: sin internet no hay de dónde bajarlas.
  GoogleFonts.config.allowRuntimeFetching = false;
  final cliente = ClienteCentral(
    servidor: Uri.base,
    guardado: GuardadoEnElNavegador(),
  );
  cliente.iniciar(codigoDelEnlace: Uri.base.queryParameters['c']);
  runApp(PuestoApp(cliente: cliente));
}

class PuestoApp extends StatelessWidget {
  const PuestoApp({super.key, required this.cliente});
  final ClienteCentral cliente;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Recepción — Junior Eventos',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF141418),
          useMaterial3: true,
        ),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('es', 'AR')],
        locale: const Locale('es', 'AR'),
        home: PantallaPuesto(cliente: cliente),
      );
}
