import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../main.dart' show supabaseProvider;
import '../../caja_sesiones/providers/app_role_provider.dart';
import '../central/barra_con_la_red.dart';
import '../cuentas/reglas_de_la_barra.dart';
import '../datos/barra_local.dart';
import '../datos/barra_nube.dart';
import '../datos/barra_repositorio.dart';

/// Si la barra corre en la web (el iPhone del jefe): sin base, sin cola de subida y sin
/// Bluetooth; se lee y se escribe directo en la nube. Los tests lo ponen en `true`
/// (`kIsWeb` no se puede), y el arnés `tool/barra_web_prueba.dart` también.
final enLaWebProvider = Provider<bool>((ref) => kIsWeb);

/// **La página del iPhone de la barra** (28-nov-2026): corre en el navegador (sin
/// impresora: [enLaWebProvider] en true), pero lo de las cajas le llega al momento por el
/// wifi de la notebook, no de la nube. Lo pone en true solo esa página, para que lo que
/// dice la pantalla sea cierto.
final enLaPaginaDeLaBarraProvider = Provider<bool>((ref) => false);

/// La hora de este equipo para la barra: con ella se sabe **la noche de hoy** (el día de
/// operación, `cuentas/dia_de_operacion.dart`), qué fiestas siguen a la vista y si la
/// central vuelve sola. Las ventanas de prueba la adelantan para vender pasada la
/// medianoche; los tests la fijan.
final relojDeLaBarraProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Por dónde sale a la red del salón lo que escribe este equipo (la central de la barra).
/// Sin central prendida ni cliente arrancado, no sale nada.
final avisoALaRedProvider = Provider<AvisoALaRed>((ref) => AvisoALaRed());

/// La barra de este equipo (la PC o la tablet): la base y la cola de subida, **más la red
/// del salón** ([BarraConLaRed]): lo que escribe la caja también se le pasa a la central.
/// La usan la cajera y, en la PC, el jefe.
final barraDeEsteEquipoProvider = Provider<BarraConLaRed>((ref) {
  final base = BarraLocal();
  return BarraConLaRed(
    caja: base,
    jefe: base,
    red: base,
    aviso: ref.watch(avisoALaRedProvider),
    // La segunda llave: lo que no le toca a quien usa este aparato no se guarda.
    rolDeQuienUsa: () => ref.read(rolEnLaBarraProvider),
  );
});

/// **Quién usa la barra en este aparato** (26-nov-2026): el jefe en modo jefe, o la
/// cajera, la encargada o el repositor según su PIN y sus permisos. Null: nadie de la
/// barra. Las pantallas y el guardado preguntan por acá ([ReglasDeLaBarra]).
final rolEnLaBarraProvider = Provider<RolEnLaBarra?>((ref) {
  if (ref.watch(esRolJefeProvider)) return RolEnLaBarra.jefe;
  final estado = ref.watch(appRoleProvider);
  if (!estado.esBarra) return null;
  return ReglasDeLaBarra.dePermisos(estado.permisos);
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
