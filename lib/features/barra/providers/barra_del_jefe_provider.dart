import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../main.dart' show supabaseProvider;
import '../central/barra_con_la_red.dart';
import '../datos/barra_local.dart';
import '../datos/barra_nube.dart';
import '../datos/barra_repositorio.dart';

/// Si la barra corre en la web (el iPhone del jefe): sin base, sin cola de subida y sin
/// Bluetooth; se lee y se escribe directo en la nube. Los tests lo ponen en `true`
/// (`kIsWeb` no se puede), y el arnés `tool/barra_web_prueba.dart` también.
final enLaWebProvider = Provider<bool>((ref) => kIsWeb);

/// Por dónde sale a la red del salón lo que escribe este equipo (la central de la barra).
/// Sin central prendida ni cliente arrancado, no sale nada.
final avisoALaRedProvider = Provider<AvisoALaRed>((ref) => AvisoALaRed());

/// La barra de este equipo (la PC o la tablet): la base y la cola de subida, **más la red
/// del salón** ([BarraConLaRed]): lo que escribe la caja también se le pasa a la central.
/// La usan la cajera y, en la PC, el jefe.
final barraDeEsteEquipoProvider = Provider<BarraConLaRed>((ref) {
  final base = BarraLocal();
  return BarraConLaRed(caja: base, jefe: base, red: base, aviso: ref.watch(avisoALaRedProvider));
});

/// La barra de la fiesta como la ve este equipo: en la PC y la tablet, la base y la
/// cola de subida (las cajas, las ventas y las anulaciones de todas las cajas que bajaron
/// de la nube o llegaron por la red del salón); **en la web, la nube directo**
/// ([BarraNube], etapa 8). La lee Recepción para saber qué vales de silla anuló la barra
/// (6.4.0) y BARRA del jefe. Los tests la reemplazan.
///
/// Aparte de `barra_providers.dart` a propósito: ese trae la impresora por Bluetooth, y
/// esto lo usa también la página del celular de la puerta.
///
/// **Siempre `supabaseProvider`, nunca el singleton de Supabase:** la ventana del tótem
/// inyecta el suyo (`test/barra_en_la_web_test.dart` lo vigila).
final barraDelJefeProvider = Provider<BarraDelJefe>(
  (ref) => ref.watch(enLaWebProvider)
      ? BarraNube(ref.watch(supabaseProvider))
      : ref.watch(barraDeEsteEquipoProvider),
);
