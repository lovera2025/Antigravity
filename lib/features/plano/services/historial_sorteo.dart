import '../../../models/contrato_alumno.dart';
import '../../../models/movimiento_mesas.dart';
import '../../../models/plano_evento.dart';
import '../../../models/sorteo_mesas_registro.dart';
import '../../eventos/services/mesas_extra_utils.dart';
import '../../eventos/services/registro_sorteo.dart';
import 'cambios_de_mesa.dart';

enum TipoRenglonHistorial {
  sorteo,
  sorteoDeshecho,
  sorteoRestaurado,
  cambio,
  mover,
  deshacer,
  fijada,
  libre,
}

/// Un renglón del Historial: algo que se hizo con las mesas de la fiesta.
class RenglonHistorial {
  final TipoRenglonHistorial tipo;

  /// Null si no quedó anotado cuándo (una fijada cargada sin fecha).
  final DateTime? cuando;
  final String titulo;
  final List<String> detalle;
  final String? quien;

  /// El cambio, si este renglón es uno que se puede volver atrás.
  final MovimientoMesas? movimiento;

  /// Ya se volvió atrás.
  final bool deshecho;

  /// Por qué ya no se puede deshacer, en palabras. Null si se puede (o si el
  /// renglón no es un cambio).
  final String? noSeDeshacePorque;

  const RenglonHistorial({
    required this.tipo,
    required this.cuando,
    required this.titulo,
    this.detalle = const [],
    this.quien,
    this.movimiento,
    this.deshecho = false,
    this.noSeDeshacePorque,
  });

  bool get sePuedeDeshacer =>
      movimiento != null && !deshecho && noSeDeshacePorque == null;
}

/// Una familia cuyas mesas de hoy no son las que dice el registro: alguien las
/// cambió a mano, en Editar alumno.
class CambioSinRegistro {
  final String nombre;
  final String hoy;
  final String segunElRegistro;

  const CambioSinRegistro({
    required this.nombre,
    required this.hoy,
    required this.segunElRegistro,
  });
}

/// Todo lo que pasó con las mesas de una fiesta, para responder "¿quién cambió
/// esta mesa y por qué?": los sorteos, los cambios con motivo, las mesas fijas
/// y libres, y lo que se tocó a mano sin dejar registro.
class HistorialSorteo {
  /// Del más nuevo al más viejo.
  final List<RenglonHistorial> renglones;
  final List<CambioSinRegistro> sinRegistro;

  const HistorialSorteo({required this.renglones, required this.sinRegistro});

  bool get vacio => renglones.isEmpty && sinRegistro.isEmpty;

  static String _numeros(String? texto) {
    final l = MesasExtraUtils.numerosMesaDesdeTexto(texto).toList()..sort();
    return l.isEmpty ? 'sin mesa' : l.join(', ');
  }

  static String _familias(int n) => n == 1 ? '1 familia' : '$n familias';

  factory HistorialSorteo.armar({
    required List<SorteoMesasRegistro> registros,
    required List<MovimientoMesas> movimientos,
    required ConfigPlano config,
    required List<ContratoAlumno> alumnos,
    Set<String> yaRetiraron = const {},
  }) {
    final porId = {for (final a in alumnos) a.id: a};
    String nombre(String id) {
      final a = porId[id];
      return a == null ? 'Una familia que ya no está' : CambiosDeMesa.apellido(a);
    }

    final renglones = <RenglonHistorial>[];

    for (final r in registros) {
      final (tipo, que) = switch (r.tipo) {
        TipoRegistroSorteo.sorteo => (TipoRenglonHistorial.sorteo, 'Sorteo'),
        TipoRegistroSorteo.deshacer => (
            TipoRenglonHistorial.sorteoDeshecho,
            'Se deshizo el sorteo',
          ),
        TipoRegistroSorteo.restaurar => (
            TipoRenglonHistorial.sorteoRestaurado,
            'Se restauró el sorteo anterior',
          ),
      };
      renglones.add(RenglonHistorial(
        tipo: tipo,
        cuando: r.createdAt,
        titulo: '$que: ${_familias(r.alumnos)}',
        quien: r.hechoPor,
      ));
    }

    final deshechos = {
      for (final m in movimientos)
        if (m.deshaceId != null) m.deshaceId,
    };
    for (final m in movimientos) {
      final ids = m.despues.keys.toList();
      final (tipo, titulo) = switch (m.tipo) {
        TipoMovimientoMesas.intercambio => (
            TipoRenglonHistorial.cambio,
            'Cambiaron de lugar: ${ids.map(nombre).join(' y ')}',
          ),
        TipoMovimientoMesas.mover => (
            TipoRenglonHistorial.mover,
            '${ids.map(nombre).join(', ')} pasó a otras mesas',
          ),
        TipoMovimientoMesas.deshacer => (
            TipoRenglonHistorial.deshacer,
            'Se deshizo un cambio: ${ids.map(nombre).join(' y ')}',
          ),
      };
      final deshecho = deshechos.contains(m.id);
      String? noSePuede;
      if (m.tipo != TipoMovimientoMesas.deshacer && !deshecho) {
        noSePuede = CambiosDeMesa.deshacer(
          movimiento: m,
          movimientos: movimientos,
          alumnos: alumnos,
          config: config,
          yaRetiraron: yaRetiraron,
        ).problema;
      }
      renglones.add(RenglonHistorial(
        tipo: tipo,
        cuando: m.createdAt,
        titulo: titulo,
        detalle: [
          for (final id in ids)
            '${nombre(id)}: ${_numeros(m.antes[id])} → ${_numeros(m.despues[id])}',
          // En un deshacer, el motivo guardado es el del cambio que se volvió
          // atrás.
          if (m.motivo.trim().isNotEmpty)
            m.tipo == TipoMovimientoMesas.deshacer
                ? 'El cambio era por: ${m.motivo.trim()}'
                : 'Motivo: ${m.motivo.trim()}',
          ...m.avisos,
        ],
        quien: m.hechoPor,
        movimiento: m.tipo == TipoMovimientoMesas.deshacer ? null : m,
        deshecho: deshecho,
        noSeDeshacePorque: noSePuede,
      ));
    }

    // Las fijadas, una por familia (se fijan todas sus mesas juntas).
    final fijadasPorFamilia = <String, List<int>>{};
    for (final e in config.fijadas.entries) {
      fijadasPorFamilia.putIfAbsent(e.value.alumnoId, () => []).add(e.key);
    }
    for (final e in fijadasPorFamilia.entries) {
      final mesas = e.value..sort();
      final dato = config.fijadas[mesas.first]!;
      final motivo = dato.motivo?.trim() ?? '';
      renglones.add(RenglonHistorial(
        tipo: TipoRenglonHistorial.fijada,
        cuando: dato.cuando,
        titulo: '${mesas.length == 1 ? 'Mesa ${mesas.single} fijada' : 'Mesas ${mesas.join(', ')} fijadas'} '
            'para ${nombre(e.key)}',
        detalle: [if (motivo.isNotEmpty) 'Motivo: $motivo'],
        quien: dato.por,
      ));
    }
    for (final e in config.libres.entries) {
      final motivo = e.value.motivo?.trim() ?? '';
      renglones.add(RenglonHistorial(
        tipo: TipoRenglonHistorial.libre,
        cuando: e.value.cuando,
        titulo: 'Mesa ${e.key} libre: el sorteo no la da',
        detalle: [if (motivo.isNotEmpty) 'Motivo: $motivo'],
        quien: e.value.por,
      ));
    }

    // Lo más nuevo arriba; lo que no tiene fecha, al final.
    renglones.sort((a, b) {
      final x = a.cuando;
      final y = b.cuando;
      if (x == null && y == null) return 0;
      if (x == null) return 1;
      if (y == null) return -1;
      return y.compareTo(x);
    });

    // Lo que hoy no coincide con lo registrado. Sin ningún registro no hay
    // contra qué comparar: las mesas cargadas a mano de siempre no son un
    // "cambio".
    final sinRegistro = <CambioSinRegistro>[];
    if (registros.isNotEmpty || movimientos.isNotEmpty) {
      final deberian = RegistroSorteo.esperado(registros, movimientos);
      final seCompara = RegistroSorteo.seComparaA(registros, movimientos);
      for (final a in alumnos) {
        if (!seCompara(a.id)) continue;
        final hoy = MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa).toSet();
        final deberia = deberian[a.id] ?? const <int>{};
        if (hoy.length == deberia.length && hoy.containsAll(deberia)) continue;
        String texto(Set<int> s) =>
            s.isEmpty ? 'sin mesa' : (s.toList()..sort()).join(', ');
        sinRegistro.add(CambioSinRegistro(
          nombre: a.nombreAlumno,
          hoy: texto(hoy),
          segunElRegistro: texto(deberia),
        ));
      }
      sinRegistro.sort((a, b) => a.nombre.compareTo(b.nombre));
    }

    return HistorialSorteo(renglones: renglones, sinRegistro: sinRegistro);
  }
}
