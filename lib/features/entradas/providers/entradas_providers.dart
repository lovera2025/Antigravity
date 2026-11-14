import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../barra/providers/barra_del_jefe_provider.dart' show enLaWebProvider;
import '../datos/entradas_local.dart';
import '../datos/entradas_repositorio.dart';

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

/// El precio de la fiesta, para mostrarlo. Se vuelve a leer con
/// `ref.invalidate` después de guardar.
final configDeEntradasProvider =
    FutureProvider.family<ConfigEntradas?, String>(
  (ref, eventoId) => ref.watch(entradasDeLaFiestaProvider).config(eventoId),
);
