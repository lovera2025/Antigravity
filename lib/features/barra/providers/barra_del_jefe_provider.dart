import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../main.dart' show supabaseProvider;
import '../datos/barra_local.dart';
import '../datos/barra_nube.dart';
import '../datos/barra_repositorio.dart';

/// Si la barra corre en la web (el iPhone del jefe): sin base, sin cola de subida y sin
/// Bluetooth; se lee y se escribe directo en la nube. Los tests lo ponen en `true`
/// (`kIsWeb` no se puede), y el arnés `tool/barra_web_prueba.dart` también.
final enLaWebProvider = Provider<bool>((ref) => kIsWeb);

/// La barra de la fiesta como la ve este equipo: en la PC y la tablet, la base y la
/// cola de subida ([BarraLocal]: las cajas, las ventas y las anulaciones de todas las
/// cajas que bajaron); **en la web, la nube directo** ([BarraNube], etapa 8). La lee
/// Recepción para saber qué vales de silla anuló la barra (6.4.0) y BARRA del jefe. Los
/// tests la reemplazan.
///
/// Aparte de `barra_providers.dart` a propósito: ese trae la impresora por Bluetooth, y
/// esto lo usa también la página del celular de la puerta.
///
/// **Siempre `supabaseProvider`, nunca el singleton de Supabase:** la ventana del tótem
/// inyecta el suyo (`test/barra_en_la_web_test.dart` lo vigila).
final barraDelJefeProvider = Provider<BarraDelJefe>(
  (ref) => ref.watch(enLaWebProvider) ? BarraNube(ref.watch(supabaseProvider)) : BarraLocal(),
);
