import 'dart:math';

import '../../../models/contrato_alumno.dart';
import '../../../models/plano_evento.dart';
import '../../eventos/services/cumplimiento_de_cuotas.dart';
import '../../eventos/services/mesas_extra_utils.dart';
import '../../eventos/services/pago_para_sorteo.dart';
import '../modelo/armado_salon.dart';
import 'cambios_de_mesa.dart';
import 'mesas_del_paso.dart';

/// El salón "por orden" (6.7.0, pedido del usuario el 12-nov-2026): las mesas
/// van de la familia que mejor cumplió con sus cuotas a la que peor, desde la
/// pasarela hacia afuera; la adicional, detrás de su principal.
///
/// **No toca el sorteo.** Al prenderlo le **fija** a cada familia su mesa, por
/// el camino de las fijadas que ya existe; después el jefe aprieta SORTEO como
/// siempre y se las entrega. Antes de sortear se ve en el plano dónde quedó
/// cada una, y apagarlo borra esas fijadas. Entregadas, no llevan candado
/// (`InfoMesa.conCandado`), así que en el plano y en los papeles no se nota.
///
/// **Ninguna mesa cambia de número**: solo se decide qué familia va a cuál.
class OrdenEnElSalon {
  OrdenEnElSalon._();

  /// El motivo de una fijada puesta por el orden. Sin el puesto ni nada de
  /// cómo pagó: el motivo de una fijada lo ve cualquiera que abra el plano.
  static const motivo = MesaFijada.motivoPorOrden;

  static bool esPorOrden(MesaFijada f) => f.esPorOrden;

  /// Una semilla que depende solo de la fiesta: los empates se sortean, y
  /// apagar y volver a prender no los cambia.
  static int semillaDe(String eventoId) {
    var h = 17;
    for (final c in eventoId.codeUnits) {
      h = (h * 31 + c) & 0x3fffffff;
    }
    return h;
  }

  /// El lugar de cada familia de [orden], de la primera a la última.
  ///
  /// [mesasDe] dice cuántas mesas le da el sorteo a cada una (con el candado de
  /// lo pagado). [noUsar] son las mesas que no se reparten: las libres, las
  /// reservadas y las fijadas a mano. Una familia sin lugar queda con la lista
  /// vacía: el salón no tiene más mesas.
  static Map<String, List<int>> repartir({
    required MesasDelPaso paso,
    required List<PuestoDelOrden> orden,
    required Map<String, int> mesasDe,
    Set<int> noUsar = const {},
  }) {
    final libres = [
      for (final n in paso.enOrden)
        if (!noUsar.contains(n)) n,
    ];
    final r = <String, List<int>>{};
    for (final p in orden) {
      final cuantas = max(1, mesasDe[p.alumno.id] ?? 1);
      final suyas = <int>[];
      if (libres.isNotEmpty) {
        // La principal: la mejor mesa libre.
        suyas.add(libres.removeAt(0));
        while (suyas.length < cuantas && libres.isNotEmpty) {
          // La adicional: detrás de la anterior; si está tomada o no existe,
          // la libre más cercana de su lado; si no, la que sigue en el orden.
          final detras = paso.detras(suyas.last);
          final n = detras != null && libres.contains(detras)
              ? detras
              : paso.laMasCercana(suyas.first, libres) ?? libres.first;
          libres.remove(n);
          suyas.add(n);
        }
      }
      r[p.alumno.id] = suyas;
    }
    return r;
  }

  /// Prender: calcula el orden con los pagos de hoy y le fija a cada familia
  /// su mesa. Lo que ya estaba fijado a mano o libre no se toca, y esas
  /// familias quedan con lo suyo.
  ///
  /// Prendido, volver a prender con otro [recorrido] lo reparte de nuevo: lo
  /// que había puesto el orden se reemplaza entero.
  static CambioDeConfig prender({
    required String eventoId,
    required ArmadoSalon armado,
    required ConfigPlano config,
    required List<ContratoAlumno> alumnos,
    required Map<String, List<Map<String, dynamic>>> pagos,
    required DateTime hoyAr,
    required DateTime ahora,
    ModoSorteo modo = ModoSorteo.entera,
    RecorridoDelOrden recorrido = RecorridoDelOrden.columnas,
    String? por,
  }) {
    // Por división cada familia va en el bloque de la suya, y este orden no
    // mira los bloques: dejaría familias fuera de su división.
    if (modo == ModoSorteo.bloques) {
      return const CambioDeConfig.noSePuede(
        'Esta fiesta se sortea por división, y esto todavía no sabe respetar '
        'el bloque de cada una. Se puede usar con toda la escuela junta.',
      );
    }
    final conMesa = alumnos.any((a) =>
        !a.esBajaTemporal &&
        MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa).isNotEmpty);
    if (conMesa) {
      return CambioDeConfig.noSePuede(
        // Prendido y sorteado: quiso cambiar el recorrido.
        config.frente?.prendido == true
            ? 'Ya se sorteó con esto tildado. Para cambiarlo hay que deshacer '
                'el sorteo entero.'
            : 'Ya hay familias con mesa. Se tilda antes de sortear: para '
                'usarlo hay que deshacer el sorteo entero.',
      );
    }
    final paso = MesasDelPaso.de(armado, recorrido: recorrido);
    if (paso == null) {
      return const CambioDeConfig.noSePuede(
        'Este salón no tiene pasarela ni escenario dibujados: no hay desde '
        'dónde ordenar las mesas.',
      );
    }
    final aMano = {
      for (final e in config.fijadas.entries)
        if (!esPorOrden(e.value)) e.key: e.value,
    };
    final conFijadaAMano = {for (final f in aMano.values) f.alumnoId};
    final orden = OrdenPorCumplimiento.de(
      alumnos: alumnos,
      pagos: pagos,
      corteAr: hoyAr,
      rng: Random(semillaDe(eventoId)),
      nunca: conFijadaAMano,
    );
    if (orden.isEmpty) {
      return const CambioDeConfig.noSePuede(
        'No hay ninguna familia para ordenar: nadie tiene algo pagado de la '
        'cuota base.',
      );
    }
    final extras = extrasPorAlumno(alumnos, pagosPorAlumno(alumnos, pagos));
    final lugares = repartir(
      paso: paso,
      orden: orden,
      mesasDe: {
        for (final p in orden)
          p.alumno.id: extras[p.alumno.id]?.mesasConElSorteoDeHoy ?? 1,
      },
      noUsar: {...config.libres.keys, ...aMano.keys},
    );
    final fijadas = <int, MesaFijada>{...aMano};
    for (final p in orden) {
      for (final n in lugares[p.alumno.id] ?? const <int>[]) {
        fijadas[n] = MesaFijada(
          alumnoId: p.alumno.id,
          motivo: motivo,
          por: por,
          cuando: ahora,
        );
      }
    }
    return CambioDeConfig.ok(
      config.copyWith(
        fijadas: fijadas,
        frente: OrdenDelPlano(
          prendido: true,
          el: ahora,
          por: por,
          recorrido: recorrido,
          lugares: [
            for (final p in orden)
              LugarPorOrden(
                alumnoId: p.alumno.id,
                puesto: p.puesto,
                grupo: p.grupo.numero,
                mesas: lugares[p.alumno.id] ?? const [],
                frase: p.frase,
              ),
          ],
        ),
      ),
      [for (final l in lugares.values) ...l]..sort(),
    );
  }

  /// Apagar: saca las fijadas que puso el orden. Con familias ya sentadas no
  /// se puede: el orden ya se usó, y lo guardado queda como respaldo.
  static CambioDeConfig apagar({
    required ConfigPlano config,
    required List<ContratoAlumno> alumnos,
  }) {
    final conMesa = alumnos.any((a) =>
        !a.esBajaTemporal &&
        MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa).isNotEmpty);
    if (conMesa) {
      return const CambioDeConfig.noSePuede(
        'Ya se sorteó con esto tildado. Para cambiarlo hay que deshacer el '
        'sorteo entero.',
      );
    }
    final quitadas = [
      for (final e in config.fijadas.entries)
        if (esPorOrden(e.value)) e.key,
    ]..sort();
    return CambioDeConfig.ok(
      config.copyWith(
        fijadas: {
          for (final e in config.fijadas.entries)
            if (!esPorOrden(e.value)) e.key: e.value,
        },
        // El recorrido elegido queda: el botón lo recuerda.
        frente: OrdenDelPlano(
          prendido: false,
          recorrido:
              config.frente?.recorrido ?? RecorridoDelOrden.columnas,
        ),
      ),
      quitadas,
    );
  }
}
