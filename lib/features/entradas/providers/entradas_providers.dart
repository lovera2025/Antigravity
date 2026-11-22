import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/evento.dart';
import '../../barra/providers/barra_del_jefe_provider.dart' show enLaWebProvider;
import '../../common/widgets/operational_sync_coordinator.dart'
    show operationalSyncRevisionProvider;
import '../cuentas/cierre_de_entradas.dart';
import '../cuentas/para_rendir.dart';
import '../cuentas/precio_de_entradas.dart';
import '../datos/entradas_local.dart';
import '../datos/entradas_repositorio.dart';
import '../../eventos/repositories/eventos_repository.dart' show eventosRepositoryProvider;
import '../services/fiestas_que_vienen.dart';

/// La venta de entradas de este equipo (la PC o la tablet): la base y la cola
/// de subida. Los tests la reemplazan por una en memoria.
final entradasDeEsteEquipoProvider =
    Provider<EntradasLocal>((ref) => EntradasLocal());

/// Lo que se lee de la venta de entradas de una fiesta, para todos.
final entradasDeLaFiestaProvider = Provider<EntradasDeLaFiesta>(
  (ref) => ref.watch(entradasDeEsteEquipoProvider),
);

/// La caja de quien vende: abrir, vender y cerrar. Las pantallas la usan solo
/// con `puedeVenderEntradasProvider`.
final entradasDeLaCajaProvider = Provider<EntradasDeLaCaja>(
  (ref) => ref.watch(entradasDeEsteEquipoProvider),
);

/// Lo del jefe: el precio, anular y "Pago verificado". Las pantallas lo llaman
/// solo en modo jefe (`esRolJefeProvider`), con la doble llave.
final entradasDelJefeProvider = Provider<EntradasDelJefe>(
  (ref) => ref.watch(entradasDeEsteEquipoProvider),
);

/// **La web no vende entradas ni carga sus precios** (6.9.0): no tiene la base
/// del equipo. Lo que es de la venta se ve apagado, con [kEntradasDesdeLaPc].
final entradasEnEsteEquipoProvider =
    Provider<bool>((ref) => !ref.watch(enLaWebProvider));

const kEntradasDesdeLaPc = 'La venta de entradas se maneja desde la PC o la tablet';

/// El momento de ahora en el reloj de Argentina: decide si rige la anticipada.
/// Los tests lo fijan.
final hoyEnArgentinaProvider = Provider<DateTime Function()>(
  (ref) => PrecioDeEntradas.hoyEnArgentina,
);

/// Las fiestas que vienen (los eventos masivos por hacer), para PRECIOS →
/// "¿Poner estos precios también en otras fiestas?" (22-nov-2026). Se lee
/// recién al guardar. Las pruebas lo reemplazan: si no, abriría la base.
final fiestasParaLosPreciosProvider = Provider<Future<List<Evento>> Function()>(
  (ref) => () async => fiestasQueVienen(
        await ref.read(eventosRepositoryProvider).getAll(modalidad: 'masivo'),
        DateTime.now(),
      ),
);

/// El precio de la fiesta, para mostrarlo. Se vuelve a leer con
/// `ref.invalidate` después de guardar.
final configDeEntradasProvider =
    FutureProvider.family<ConfigEntradas?, String>(
  (ref, eventoId) => ref.watch(entradasDeLaFiestaProvider).config(eventoId),
);

/// Las cajas de entradas de una fiesta con sus cuentas, para ENTRADAS del
/// cierre de caja. Se relee cuando baja algo de otro equipo, **se descarta al
/// dejar de mirarla** (al volver, lee de nuevo) y **lo invalida cada pantalla que
/// escribe en este equipo** ([avisarQueCambioLaVenta]). **Solo en el equipo**
/// (`entradasEnEsteEquipoProvider`): la web no tiene esa base.
final cajasDeEntradasDeLaFiestaProvider = FutureProvider.autoDispose
    .family<CajasDeEntradasDeLaFiesta, String>((ref, eventoId) async {
  ref.watch(operationalSyncRevisionProvider);
  final entradas = ref.watch(entradasDeLaFiestaProvider);
  return CajasDeEntradasDeLaFiesta.de(
    config: await entradas.config(eventoId),
    cajas: await entradas.cajas(eventoId),
    ventas: await entradas.ventas(eventoId),
    anulaciones: await entradas.anulaciones(eventoId),
  );
});

/// Las entradas para rendir de una fiesta, ya contadas (`ParaRendir`): quién se
/// llevó entradas para vender por su cuenta, qué rindió, qué devolvió y qué le
/// queda (21-nov-2026). La mira PARA RENDIR. Como las cajas: se relee cuando
/// baja algo de otro equipo, **se descarta al dejar de mirarla** y **la
/// invalida cada pantalla que escribe en este equipo** ([avisarQueCambioLaVenta]):
/// una rendición es una venta, y anularla en VENTAS le devuelve las entradas a
/// quien las llevó. **Solo en el equipo**: la web no tiene esa base.
final paraRendirDeLaFiestaProvider =
    FutureProvider.autoDispose.family<ParaRendir, String>((ref, eventoId) async {
  ref.watch(operationalSyncRevisionProvider);
  final entradas = ref.watch(entradasDeLaFiestaProvider);
  return ParaRendir.de(
    movimientos: await entradas.paraRendir(eventoId),
    ventas: await entradas.ventas(eventoId),
    anulaciones: await entradas.anulaciones(eventoId),
  );
});

/// Lo escrito en este equipo no baja de ningún lado: quien abre una caja, vende,
/// anula, cierra o cambia el precio avisa, y ENTRADAS del cierre de
/// caja vuelve a leer (revisión del 15-nov: seguía mostrando "abierta" una caja
/// recién cerrada en la misma PC). Desde el 21-nov-2026 también PARA RENDIR:
/// dar, rendir, anular una rendición o lo que no volvió cambian lo que se ve ahí.
void avisarQueCambioLaVenta(WidgetRef ref, String eventoId) {
  ref.invalidate(cajasDeEntradasDeLaFiestaProvider(eventoId));
  ref.invalidate(paraRendirDeLaFiestaProvider(eventoId));
}
