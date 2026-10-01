import '../../../core/utils/ar_time.dart';
import '../../../models/contrato_alumno.dart';
import '../../../models/movimiento_mesas.dart';
import '../../../models/sorteo_mesas_registro.dart';
import 'mesas_extra_utils.dart';

/// Lo que dice el registro de sorteos de un evento: el último movimiento y
/// cuántos alumnos tienen hoy mesas distintas de las que dejó el registro.
class ResumenRegistroSorteo {
  /// El último renglón (sorteo, deshacer o restaurar), o `null` si nunca se
  /// registró nada en este evento.
  final SorteoMesasRegistro? ultimo;

  /// Alumnos con mesas distintas de las que dejaron los sorteos y los cambios
  /// registrados: alguien las cambió a mano (Editar alumno) después.
  final int cambiosAMano;

  /// Cambios de mesa hechos desde el plano, con su motivo, que siguen en pie
  /// (los que después se deshicieron no cuentan).
  final int cambiosConMotivo;

  const ResumenRegistroSorteo({
    this.ultimo,
    this.cambiosAMano = 0,
    this.cambiosConMotivo = 0,
  });

  static const vacio = ResumenRegistroSorteo();
}

/// El registro de sorteos, leído para responder una queja: qué salió, quién lo
/// hizo, cuándo, y si después se tocó algo a mano.
class RegistroSorteo {
  RegistroSorteo._();

  /// Las mesas que cada alumno *debería* tener hoy según lo registrado: los
  /// sorteos y, mezclados por fecha, los cambios hechos desde el plano
  /// ([movimientos]). Quien no figura no debería tener ninguna.
  ///
  /// Un sorteo o una restauración dejan los números de cada alumno que tocaron;
  /// un deshacer se los saca; un cambio de mesa deja los que dice su `despues`.
  static Map<String, Set<int>> esperado(
    List<SorteoMesasRegistro> registros, [
    List<MovimientoMesas> movimientos = const [],
  ]) {
    final pasos = <({DateTime cuando, int orden, void Function() aplicar})>[];
    final esperado = <String, Set<int>>{};
    for (final r in registros) {
      pasos.add((
        cuando: r.createdAt,
        // A la misma hora, el sorteo va antes que el cambio que lo toca.
        orden: 0,
        aplicar: () {
          for (final e in r.resultado.entries) {
            switch (r.tipo) {
              case TipoRegistroSorteo.sorteo:
              case TipoRegistroSorteo.restaurar:
                esperado[e.key] =
                    MesasExtraUtils.numerosMesaDesdeTexto(e.value).toSet();
              case TipoRegistroSorteo.deshacer:
                esperado.remove(e.key);
            }
          }
        },
      ));
    }
    for (final m in movimientos) {
      pasos.add((
        cuando: m.createdAt,
        orden: 1,
        aplicar: () {
          for (final e in m.despues.entries) {
            final numeros =
                MesasExtraUtils.numerosMesaDesdeTexto(e.value).toSet();
            if (numeros.isEmpty) {
              esperado.remove(e.key);
            } else {
              esperado[e.key] = numeros;
            }
          }
        },
      ));
    }
    pasos.sort((a, b) {
      final c = a.cuando.compareTo(b.cuando);
      return c != 0 ? c : a.orden.compareTo(b.orden);
    });
    for (final p in pasos) {
      p.aplicar();
    }
    return esperado;
  }

  /// Los cambios con motivo que siguen en pie: ni son un deshacer ni fueron
  /// deshechos después.
  ///
  /// Con [registros], además tienen que seguir rigiendo: si después se deshizo
  /// el sorteo y se sorteó de nuevo, las mesas de esas familias ya no son las
  /// que dejó el cambio, y contarlo en la planilla sería mentir.
  static List<MovimientoMesas> cambiosEnPie(
    List<MovimientoMesas> movimientos, [
    List<SorteoMesasRegistro>? registros,
  ]) {
    final deshechos = {
      for (final m in movimientos)
        if (m.deshaceId != null) m.deshaceId,
    };
    final deberian =
        registros == null ? null : esperado(registros, movimientos);
    bool rige(MovimientoMesas m) {
      if (deberian == null) return true;
      for (final e in m.despues.entries) {
        final dejo = MesasExtraUtils.numerosMesaDesdeTexto(e.value).toSet();
        final hoy = deberian[e.key] ?? const <int>{};
        if (dejo.length != hoy.length || !dejo.containsAll(hoy)) return false;
      }
      return true;
    }

    return [
      for (final m in movimientos)
        if (m.tipo != TipoMovimientoMesas.deshacer &&
            !deshechos.contains(m.id) &&
            rige(m))
          m,
    ];
  }

  /// A quiénes se puede comparar contra lo registrado. Con algún sorteo
  /// registrado, a todos. Sin ninguno (mesas cargadas a mano de siempre, o un
  /// sorteo de antes de que existiera el registro), solo a las familias que
  /// figuran en algún cambio: del resto no hay nada escrito contra qué
  /// comparar, y marcarlas a todas como "cambiadas a mano" sería falso.
  static bool Function(String alumnoId) seComparaA(
    List<SorteoMesasRegistro> registros,
    List<MovimientoMesas> movimientos,
  ) {
    if (registros.isNotEmpty) return (_) => true;
    final nombradas = {
      for (final m in movimientos) ...[...m.antes.keys, ...m.despues.keys],
    };
    return nombradas.contains;
  }

  /// Repasa el registro en orden y compara con las mesas de hoy.
  ///
  /// Lo que queda de [esperado] es lo que *debería* haber hoy si nadie hubiera
  /// cambiado nada a mano. Se compara por números, no por texto: "12-14" y
  /// "12, 13, 14" son lo mismo.
  static ResumenRegistroSorteo resumir(
    List<SorteoMesasRegistro> registros,
    Iterable<ContratoAlumno> alumnos, {
    List<MovimientoMesas> movimientos = const [],
  }) {
    if (registros.isEmpty && movimientos.isEmpty) {
      return ResumenRegistroSorteo.vacio;
    }
    final ordenados = List<SorteoMesasRegistro>.from(registros)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final deberian = esperado(registros, movimientos);

    final seCompara = seComparaA(registros, movimientos);
    var cambios = 0;
    for (final a in alumnos) {
      if (!seCompara(a.id)) continue;
      final hoy = MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa).toSet();
      final deberia = deberian[a.id] ?? const <int>{};
      if (hoy.length != deberia.length || !hoy.containsAll(deberia)) cambios++;
    }
    return ResumenRegistroSorteo(
      ultimo: ordenados.isEmpty ? null : ordenados.last,
      cambiosAMano: cambios,
      cambiosConMotivo: cambiosEnPie(movimientos, registros).length,
    );
  }

  /// La línea que va arriba de la planilla: "Sorteo del 12/11/2026 21:40 hs ·
  /// Jefe", con los cambios con motivo y los hechos a mano si los hay. `null`
  /// si no hay ningún sorteo registrado.
  static String? lineaParaPlanilla(ResumenRegistroSorteo resumen) {
    final u = resumen.ultimo;
    if (u == null) return null;
    final cuando = ArTime.formatFechaHora(u.createdAt);
    final que = switch (u.tipo) {
      TipoRegistroSorteo.sorteo => 'Sorteo del $cuando',
      TipoRegistroSorteo.deshacer => 'Sorteo deshecho el $cuando',
      TipoRegistroSorteo.restaurar => 'Sorteo restaurado el $cuando',
    };
    final quien = u.hechoPor?.trim().isNotEmpty == true ? ' · ${u.hechoPor}' : '';
    final m = resumen.cambiosConMotivo;
    final conMotivo = m == 0
        ? ''
        : ' · $m ${m == 1 ? 'cambio' : 'cambios'} con motivo';
    final n = resumen.cambiosAMano;
    final aMano = n == 0
        ? ''
        : ' · $n ${n == 1 ? 'cambio' : 'cambios'} a mano después';
    return '$que$quien$conMotivo$aMano';
  }
}
