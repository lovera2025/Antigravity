import 'dart:math';

import '../../../core/utils/ar_time.dart';
import '../../../models/contrato_alumno.dart';
import '../../../models/sillas_reparto.dart';
import '../../../models/sorteo_mesas_registro.dart';
import 'cobro_abono_acumulado.dart';
import 'mesas_extra_utils.dart';
import 'registro_sorteo.dart';
import 'salon_mesas.dart';

/// Las mesas (la del contrato y las adicionales) y las sillas extra que una
/// familia tiene cargadas en su cuenta, pagadas o no.
class LugaresCargados {
  final int mesas;
  final int sillas;

  const LugaresCargados(this.mesas, this.sillas);

  /// Quien no figura en lo anotado al sortear: tenía solo la mesa del contrato.
  static const soloElContrato = LugaresCargados(1, 0);

  factory LugaresCargados.de(ContratoAlumno a) =>
      LugaresCargados(SalonMesas.mesas(a), SalonMesas.sillasExtra(a));

  bool get tieneAdicionales => mesas > 1 || sillas > 0;

  /// Como viaja en el renglón del sorteo: "2,1".
  String get texto => '$mesas,$sillas';

  /// Null si el texto no se entiende: ante la duda, quien lo lee decide.
  static LugaresCargados? deTexto(String? texto) {
    final partes = (texto ?? '').split(',');
    if (partes.length != 2) return null;
    final m = int.tryParse(partes[0].trim());
    final s = int.tryParse(partes[1].trim());
    if (m == null || s == null || m < 1 || s < 0) return null;
    return LugaresCargados(m, s);
  }

  @override
  bool operator ==(Object other) =>
      other is LugaresCargados && other.mesas == mesas && other.sillas == sillas;

  @override
  int get hashCode => Object.hash(mesas, sillas);

  @override
  String toString() => 'LugaresCargados($texto)';
}

enum EstadoDeLosLugares {
  /// La fiesta no tiene un sorteo del jefe en pie: no hay "después del sorteo".
  sinSorteo,

  /// Se sorteó antes de esta regla (o desde un equipo con una versión anterior)
  /// y el jefe todavía no aceptó la lista de PRECIOS: todo va con descuento.
  sinAnotar,

  /// El sorteo anotó qué tenía cada familia.
  anotados,
}

/// Lo que cada familia tenía cargado cuando se sorteó su fiesta.
///
/// **La regla (17-nov-2026):** las entradas de la mesa adicional y de las sillas
/// extra que la familia ya tenía al sorteo van con el descuento de PRECIOS, y
/// las compra cuando quiera. Lo que agregue después paga el precio del día,
/// sin descuento (la anticipada mientras rige).
class FotoDeLosLugares {
  final EstadoDeLosLugares estado;
  final Map<String, LugaresCargados> _porAlumno;

  /// Cuándo fue el sorteo: el primer renglón del jefe que sigue en pie.
  final DateTime? sorteoEl;

  /// De cuándo es lo anotado. Distinto de [sorteoEl] solo tras restaurar.
  final DateTime? del;

  const FotoDeLosLugares._(
    this.estado,
    this._porAlumno, {
    this.sorteoEl,
    this.del,
  });

  static const sinSorteo =
      FotoDeLosLugares._(EstadoDeLosLugares.sinSorteo, {});

  /// Para las pruebas y las muestras: una foto ya armada.
  factory FotoDeLosLugares.anotada(
    Map<String, LugaresCargados> porAlumno, {
    DateTime? sorteoEl,
  }) =>
      FotoDeLosLugares._(
        EstadoDeLosLugares.anotados,
        porAlumno,
        sorteoEl: sorteoEl,
        del: sorteoEl,
      );

  /// Lo que tenía [alumnoId] al sorteo. **Null: no hay nada anotado y todo lo
  /// suyo va con descuento**, como antes de la regla. Con los lugares anotados,
  /// quien no figura tenía solo la mesa del contrato (también quien entró a la
  /// fiesta después del sorteo).
  LugaresCargados? de(String alumnoId) => estado == EstadoDeLosLugares.anotados
      ? _porAlumno[alumnoId] ?? LugaresCargados.soloElContrato
      : null;
}

/// Un lugar de una fiesta ya sorteada del que no hay huella de antes del
/// sorteo: lo que el jefe revisa en PRECIOS antes de aceptar.
class LugarEnDuda {
  final String alumnoId;
  final String nombre;

  /// Mesas adicionales (8 entradas cada una) o, si no, sillas extra.
  final bool esMesa;
  final int cantidad;

  /// Hay huella de que vino después del sorteo: viene tildado "sin
  /// descuento" (el precio del día). Sin huella de ningún lado queda para
  /// revisar, sin tildar: no se le saca el descuento a nadie por una duda.
  final bool despues;

  /// El porqué, con fecha y hora.
  final List<String> huellas;

  const LugarEnDuda({
    required this.alumnoId,
    required this.nombre,
    required this.esMesa,
    required this.cantidad,
    required this.despues,
    required this.huellas,
  });

  int get entradas => esMesa ? cantidad * SalonMesas.sillasPorMesa : cantidad;

  /// Para tildar y destildar en la lista.
  String get clave => '$alumnoId|${esMesa ? 'm' : 's'}|${despues ? 'd' : 'r'}';

  String get queEs => esMesa
      ? (cantidad == 1 ? '1 mesa adicional' : '$cantidad mesas adicionales')
      : (cantidad == 1 ? '1 silla extra' : '$cantidad sillas extra');
}

/// Qué tenía cada familia al sorteo: cómo se anota, cómo se lee y, en las
/// fiestas sorteadas antes de la regla, qué dicen las huellas. Todo es puro.
class LugaresAlSorteo {
  LugaresAlSorteo._();

  /// Lo que se anota en el renglón de un sorteo del jefe: lo cargado de cada
  /// familia en ese momento, también las de baja temporal (si vuelven, lo
  /// tenían). Solo figura quien tiene algo más que la mesa del contrato.
  static Map<String, String> sacar(Iterable<ContratoAlumno> alumnos) => {
        for (final a in alumnos)
          if (LugaresCargados.de(a).tieneAdicionales)
            a.id: LugaresCargados.de(a).texto,
      };

  /// El sorteo de la fiesta: el primer renglón del jefe que sigue en pie. Los
  /// automáticos (`MesaNuevaSola`) no cuentan: la pila puede empezar con uno.
  static SorteoMesasRegistro? primerDelJefe(
    List<SorteoMesasRegistro> registros,
  ) {
    for (final r in RegistroSorteo.sorteosEnPie(registros)) {
      if (!r.automatico) return r;
    }
    return null;
  }

  static FotoDeLosLugares vigente(List<SorteoMesasRegistro> registros) {
    final primer = primerDelJefe(registros);
    if (primer == null) return FotoDeLosLugares.sinSorteo;
    final lugares = primer.lugares;
    if (lugares == null) {
      return FotoDeLosLugares._(
        EstadoDeLosLugares.sinAnotar,
        const {},
        sorteoEl: primer.createdAt,
      );
    }
    final porAlumno = <String, LugaresCargados>{};
    for (final e in lugares.entries) {
      // Un texto que no se entiende no le saca el descuento a nadie: cuenta
      // como "todo lo que tenga".
      porAlumno[e.key] =
          LugaresCargados.deTexto(e.value) ?? const LugaresCargados(99, 99);
    }
    return FotoDeLosLugares._(
      EstadoDeLosLugares.anotados,
      porAlumno,
      sorteoEl: primer.createdAt,
      del: primer.lugaresEl ?? primer.createdAt,
    );
  }

  /// Lo que lleva el renglón de una restauración: si con ella la fiesta vuelve
  /// a tener sorteo, los lugares del sorteo que se había deshecho (restaurar no
  /// es sortear de nuevo: el día del sorteo sigue siendo aquel). Null si la
  /// fiesta ya tiene su sorteo en pie, o si aquel no los había anotado.
  static ({Map<String, String> lugares, DateTime del})? paraRestaurar(
    List<SorteoMesasRegistro> registros,
  ) {
    final orden = RegistroSorteo.enOrden(registros);
    SorteoMesasRegistro? perdido;
    SorteoMesasRegistro? anterior;
    for (var i = 1; i <= orden.length; i++) {
      final primero = primerDelJefe(orden.sublist(0, i));
      if (primero != null) {
        perdido = null;
      } else if (anterior != null) {
        perdido = anterior;
      }
      anterior = primero;
    }
    if (anterior != null) return null;
    final lugares = perdido?.lugares;
    if (perdido == null || lugares == null) return null;
    return (lugares: lugares, del: perdido.lugaresEl ?? perdido.createdAt);
  }

  // ── Las fiestas sorteadas antes de la regla ──────────────────────────────

  static DateTime? _cuando(Map<String, dynamic> pago) {
    for (final clave in const ['created_at', 'fecha_pago']) {
      final v = pago[clave];
      final cuando = v is DateTime ? v : DateTime.tryParse('${v ?? ''}');
      if (cuando != null) return cuando;
    }
    return null;
  }

  static double _monto(Map<String, dynamic> p) =>
      (p['monto_gross'] as num?)?.toDouble() ??
      (p['monto'] as num?)?.toDouble() ??
      0.0;

  static String _fecha(DateTime d) => ArTime.formatFechaHora(d);

  /// Los lugares de una fiesta **sorteada sin anotar** de los que no hay huella
  /// de antes del sorteo. Vacío si la fiesta no está en ese caso.
  ///
  /// Huella de que **ya lo tenía**: la mesa salió con número en el sorteo (o lo
  /// tenía de antes), o hay un pago de mesa o de sillas anterior al sorteo, o
  /// la familia eligió el reparto de sus sillas antes. Esos no se listan.
  ///
  /// Huella de que **vino después** (viene tildado): el alumno se cargó después
  /// del sorteo, o el programa le dio la mesa sola sin ningún pago de mesa
  /// hasta ese momento (solo pasa al agregarla con el sorteo hecho).
  ///
  /// Lo demás —una adicional que recibió su número después, o que sigue sin
  /// número— pudo estar cargada antes sin pagar: queda para revisar.
  static List<LugarEnDuda> enDuda({
    required List<SorteoMesasRegistro> registros,
    required Iterable<ContratoAlumno> alumnos,
    Map<String, List<Map<String, dynamic>>> pagos = const {},
    Map<String, SillasReparto> repartos = const {},
  }) {
    final primer = primerDelJefe(registros);
    if (primer == null || primer.lugares != null) return const [];
    final sorteo = primer.createdAt;
    final posteriores = [
      for (final r in RegistroSorteo.enOrden(registros))
        if (r.tipo != TipoRegistroSorteo.deshacer &&
            r.createdAt.isAfter(sorteo))
          r,
    ];

    final lista = <LugarEnDuda>[];
    final ordenados = alumnos.toList()
      ..sort((a, b) => a.nombreAlumno
          .trim()
          .toLowerCase()
          .compareTo(b.nombreAlumno.trim().toLowerCase()));
    for (final a in ordenados) {
      final hoy = LugaresCargados.de(a);
      if (!hoy.tieneAdicionales) continue;
      final nombre = a.nombreAlumno.trim();
      final creado = a.createdAt;
      final entroDespues = creado != null && creado.isAfter(sorteo);
      final suyos = pagos[a.id] ?? const <Map<String, dynamic>>[];
      List<Map<String, dynamic>> de(CobroConceptoClase clase) => [
            for (final p in suyos)
              if (pagoCuentaParaClaseCobro(p, clase)) p,
          ]..sort((x, y) => (_cuando(x) ?? sorteo).compareTo(_cuando(y) ?? sorteo));
      bool hasta(Map<String, dynamic> p, DateTime tope) {
        final c = _cuando(p);
        // Un pago sin fecha que se pueda leer cuenta como de antes: ante la
        // duda, el descuento queda.
        return c == null || !c.isAfter(tope);
      }

      void agregar({
        required bool esMesa,
        required int cantidad,
        required bool despues,
        required List<String> huellas,
      }) {
        if (cantidad <= 0) return;
        lista.add(LugarEnDuda(
          alumnoId: a.id,
          nombre: nombre,
          esMesa: esMesa,
          cantidad: cantidad,
          despues: despues,
          huellas: huellas,
        ));
      }

      // ── Las mesas adicionales ──
      final adicionales = hoy.mesas - 1;
      if (adicionales > 0) {
        final deMesa = de(CobroConceptoClase.mesa);
        final numerosHoy =
            MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa);
        // Los números que le dio un renglón posterior al sorteo: cuál y cuándo.
        final dadosDespues = <int, SorteoMesasRegistro>{};
        for (final r in posteriores) {
          final dados = MesasExtraUtils.numerosMesaDesdeTexto(r.resultado[a.id]);
          final tenia = MesasExtraUtils.numerosMesaDesdeTexto(r.antes?[a.id]);
          for (final n in dados.difference(tenia)) {
            if (numerosHoy.contains(n)) dadosDespues.putIfAbsent(n, () => r);
          }
        }
        // Un número que cambió con Mover o Cambiar no figura en ningún sorteo
        // posterior: cuenta como del sorteo.
        final conNumeroAlSorteo = numerosHoy.length - dadosDespues.length;
        final porNumero = max(0, conNumeroAlSorteo - 1);
        final pagadoAntes = deMesa
            .where((p) => hasta(p, sorteo))
            .fold<double>(0, (s, p) => s + _monto(p));
        final unidad = SalonMesas.precioUnitarioMesa(a);
        final int porPago = pagadoAntes <= 0.01
            ? 0
            : unidad == null || unidad <= 0.01
                ? 1
                : (pagadoAntes / unidad).ceil();
        final int conHuella = min(adicionales, max(porNumero, porPago));
        int resto = adicionales - conHuella;
        if (resto > 0) {
          final primerPago = deMesa.isEmpty ? null : _cuando(deMesa.first);
          final pago = primerPago == null
              ? 'Sin pagos de mesa adicional.'
              : 'Primer pago de mesa adicional: ${_fecha(primerPago)}.';
          if (entroDespues) {
            agregar(
              esMesa: true,
              cantidad: resto,
              despues: true,
              huellas: ['El alumno se cargó el ${_fecha(creado)}, después del sorteo.'],
            );
          } else {
            var seguras = 0, dudosas = 0;
            final deSeguras = <String>[], deDudosas = <String>[];
            final enOrden = dadosDespues.entries.toList()
              ..sort((x, y) => x.value.createdAt.compareTo(y.value.createdAt));
            for (final e in enOrden) {
              if (resto == 0) break;
              final r = e.value;
              final sinPagoHastaAhi = !deMesa.any((p) => hasta(p, r.createdAt));
              if (r.automatico && sinPagoHastaAhi) {
                seguras++;
                deSeguras.add(
                  'Mesa ${e.key}: el programa se la dio el ${_fecha(r.createdAt)}, '
                  'al cargarla, sin ningún pago de mesa hasta ese momento.',
                );
              } else {
                dudosas++;
                deDudosas.add(
                  'Mesa ${e.key}: recibió el número el ${_fecha(r.createdAt)}'
                  '${r.automatico ? ', con un pago posterior al sorteo' : ''}.',
                );
              }
              resto--;
            }
            if (resto > 0) {
              dudosas += resto;
              deDudosas.add(
                resto == 1
                    ? 'Una mesa adicional cargada, todavía sin número.'
                    : '$resto mesas adicionales cargadas, todavía sin número.',
              );
            }
            agregar(
              esMesa: true,
              cantidad: seguras,
              despues: true,
              huellas: deSeguras,
            );
            agregar(
              esMesa: true,
              cantidad: dudosas,
              despues: false,
              huellas: [...deDudosas, pago],
            );
          }
        }
      }

      // ── Las sillas extra ──
      if (hoy.sillas > 0) {
        final deSilla = de(CobroConceptoClase.sillas);
        final reparto = repartos[a.id];
        var conHuella = 0;
        if (deSilla.any((p) => hasta(p, sorteo))) {
          conHuella = hoy.sillas;
        } else if (reparto != null && !reparto.createdAt.isAfter(sorteo)) {
          // Eligió el reparto antes del sorteo: ya tenía sillas. Cuántas, lo
          // dice la fila solo si no se volvió a tocar después.
          conHuella = reparto.updatedAt.isAfter(sorteo)
              ? hoy.sillas
              : min(hoy.sillas, reparto.sillasExtra);
        }
        final resto = hoy.sillas - conHuella;
        if (resto > 0) {
          final primerPago = deSilla.isEmpty ? null : _cuando(deSilla.first);
          agregar(
            esMesa: false,
            cantidad: resto,
            despues: entroDespues,
            huellas: [
              if (entroDespues)
                'El alumno se cargó el ${_fecha(creado)}, después del sorteo.'
              else if (primerPago == null)
                'Sin pagos de sillas extra.'
              else
                'Primer pago de sillas extra: ${_fecha(primerPago)}, después '
                    'del sorteo.',
            ],
          );
        }
      }
    }
    return lista;
  }

  /// Lo que queda anotado cuando el jefe acepta la lista: lo que cada familia
  /// tiene hoy, menos los lugares [enDuda] que dejó tildados ([pagaEntera], por
  /// [LugarEnDuda.clave]).
  static Map<String, String> alAceptar({
    required Iterable<ContratoAlumno> alumnos,
    required List<LugarEnDuda> enDuda,
    required Set<String> pagaEntera,
  }) {
    final mesasMenos = <String, int>{};
    final sillasMenos = <String, int>{};
    for (final d in enDuda) {
      if (!pagaEntera.contains(d.clave)) continue;
      final donde = d.esMesa ? mesasMenos : sillasMenos;
      donde.update(d.alumnoId, (v) => v + d.cantidad, ifAbsent: () => d.cantidad);
    }
    final lugares = <String, String>{};
    for (final a in alumnos) {
      final hoy = LugaresCargados.de(a);
      final alSorteo = LugaresCargados(
        max(1, hoy.mesas - (mesasMenos[a.id] ?? 0)),
        max(0, hoy.sillas - (sillasMenos[a.id] ?? 0)),
      );
      if (alSorteo.tieneAdicionales) lugares[a.id] = alSorteo.texto;
    }
    return lugares;
  }
}
