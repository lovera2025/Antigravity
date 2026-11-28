import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'features/barra/pagina/cliente_de_la_pagina.dart';
import 'features/barra/pagina/pagina_de_la_barra.dart';
import 'features/recepcion/central/cliente_central.dart' show GuardadoEnElNavegador;

/// **La página del iPhone de la encargada y del repositor de barra** (28-nov-2026). No
/// es la web de siempre: la sirve la notebook de la barra (`CentralBarra`) por el wifi
/// del router de la barra, y anda sin internet. Se arma aparte:
///
///     flutter build web -t lib/barra_pagina_main.dart --no-web-resources-cdn
///
/// y el instalador la deja en la carpeta `barra_pagina`, al lado del programa.
///
/// Sin Supabase ni base: todo lo que sabe se lo dice la notebook.
void main() {
  // Las letras vienen con la página: sin internet no hay de dónde bajarlas.
  GoogleFonts.config.allowRuntimeFetching = false;
  final cliente = ClienteDeLaPagina(servidor: Uri.base, guardado: GuardadoEnElNavegador());
  unawaited(cliente.iniciar());
  runApp(PaginaDeLaBarraApp(cliente: cliente));
}
