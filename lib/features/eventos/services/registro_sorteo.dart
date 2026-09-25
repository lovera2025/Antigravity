import '../../../core/utils/ar_time.dart';
import '../../../models/contrato_alumno.dart';
import '../../../models/sorteo_mesas_registro.dart';
import 'mesas_extra_utils.dart';

/// Lo que dice el registro de sorteos de un evento: el último movimiento y
/// cuántos alumnos tienen hoy mesas distintas de las que dejó el registro.
class ResumenRegistroSorteo {
  /// El último renglón (sorteo, deshacer o restaurar), o `null` si nunca se
  /// registró nada en este evento.
  final SorteoMesasRegistro? ultimo;

  /// Alumnos con mesas distintas de las que dejaron los sorteos registrados:
  /// alguien las cambió a mano (Editar alumno) después.
  final int cambiosAMano;

  const ResumenRegistroSorteo({this.ultimo, this.cambiosAMano = 0});

  static const vacio = ResumenRegistroSorteo();
}

/// El registro de sorteos, leído para responder una queja: qué salió, quién lo
/// hizo, cuándo, y si después se tocó algo a mano.
class RegistroSorteo {
  RegistroSorteo._();

  /// Repasa el registro en orden y compara con las mesas de hoy.
  ///
  /// Un sorteo o una restauración dejan los números de cada alumno que tocaron;
  /// un deshacer se los saca. Lo que queda es lo que *debería* haber hoy si
  /// nadie hubiera cambiado nada a mano. Se compara por números, no por texto:
  /// "12-14" y "12, 13, 14" son lo mismo.
  static ResumenRegistroSorteo resumir(
    List<SorteoMesasRegistro> registros,
    Iterable<ContratoAlumno> alumnos,
  ) {
    if (registros.isEmpty) return ResumenRegistroSorteo.vacio;
    final ordenados = List<SorteoMesasRegistro>.from(registros)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final esperado = <String, Set<int>>{};
    for (final r in ordenados) {
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
    }

    var cambios = 0;
    for (final a in alumnos) {
      final hoy = MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa).toSet();
      final deberia = esperado[a.id] ?? const <int>{};
      if (hoy.length != deberia.length || !hoy.containsAll(deberia)) cambios++;
    }
    return ResumenRegistroSorteo(ultimo: ordenados.last, cambiosAMano: cambios);
  }

  /// La línea que va arriba de la planilla: "Sorteo del 12/11/2026 21:40 hs ·
  /// Jefe", con los cambios a mano si los hay. `null` si no hay registro.
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
    final n = resumen.cambiosAMano;
    final cambios = n == 0
        ? ''
        : ' · $n ${n == 1 ? 'cambio' : 'cambios'} a mano después';
    return '$que$quien$cambios';
  }
}
