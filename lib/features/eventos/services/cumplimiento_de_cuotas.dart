import 'dart:math';

import '../../../core/utils/ar_time.dart';
import '../../../models/contrato_alumno.dart';
import 'cobro_abono_acumulado.dart';
import 'mora_congelada.dart';
import 'mora_cuota_calculator.dart';

/// Días de atraso que no cuentan como atraso. El usuario lo dejó en 0 (12-nov-
/// 2026): un día tarde ya es "pagó tarde", lo mismo que se le cobró de mora.
/// Se cambia acá y en ningún otro lado.
const int kToleranciaDiasDeAtraso = 0;

/// Una cuota de la base de un alumno, con su vencimiento y el día en que quedó
/// cubierta.
class AtrasoDeCuota {
  final int numero;
  final DateTime vencimiento;

  /// El día (Argentina) en que sus pagos la cubrieron. Null: sin cubrir al corte.
  final DateTime? cubierta;

  /// La cuota ya venció al corte. Las que no vencieron no suman ni restan.
  final bool vencida;

  /// Días de atraso, ya sin los que estuvo congelada. 0 si no venció, o si se
  /// cubrió en término.
  final int dias;

  const AtrasoDeCuota({
    required this.numero,
    required this.vencimiento,
    required this.cubierta,
    required this.vencida,
    required this.dias,
  });
}

/// Cómo cumplió un alumno con las cuotas de su contrato, según **sus pagos**.
///
/// Sale de las fechas de los pagos y no de los campos de la mora
/// (`mora_pendiente_tracked`, el ajuste, el "ya usado", la eximición): esos
/// tuvieron correcciones y perdones; las fechas de los pagos, no. Es el mismo
/// criterio de `PagoAlumno.desdePagos`.
///
/// - Cuenta solo la cuota base: las mesas extra y las sillas no tienen
///   vencimiento.
/// - El vencimiento de cada cuota es el de la mora
///   ([MoraCuotaCalculator.vencimientoCuotaDesdeRegAr]).
/// - El día de cada pago es su `fecha_pago` en hora de Argentina: un cobro
///   cargado tarde con la fecha corregida vale por el día en que entró la plata.
/// - Los días que la mora estuvo congelada no son atraso. Un perdón o una
///   eximición **no** borran el atraso: pagó la mora, pero pagó tarde.
class CumplimientoDeCuotas {
  final int totalCuotas;

  /// Cuotas con vencimiento anterior al corte.
  final int vencidas;

  /// De las vencidas, las que tienen un día de atraso o más.
  final int tarde;

  /// La suma de los días de atraso de todas.
  final int diasDeAtraso;

  /// Vencidas y sin cubrir al corte.
  final int impagas;

  /// Cuotas cubiertas al corte, vencidas o no.
  final int cubiertas;

  /// El día en que quedó cubierta la última cuota. Null si falta alguna.
  final DateTime? canceloEl;

  final List<AtrasoDeCuota> detalle;

  const CumplimientoDeCuotas({
    required this.totalCuotas,
    required this.vencidas,
    required this.tarde,
    required this.diasDeAtraso,
    required this.impagas,
    required this.cubiertas,
    required this.canceloEl,
    required this.detalle,
  });

  /// Vencidas que pagó, pero tarde.
  int get pagadasTarde =>
      detalle.where((d) => d.dias > 0 && d.cubierta != null).length;

  /// Vencidas pagadas en término.
  int get enTermino => vencidas - tarde;

  static CumplimientoDeCuotas de(
    ContratoAlumno a,
    Iterable<Map<String, dynamic>> pagos, {
    required DateTime corteAr,
  }) {
    final corte = _dia(corteAr);
    final n = a.totalCuotas > 0 ? a.totalCuotas : 1;
    final cuota = MoraCuotaCalculator.cuotaBaseDe(a);
    final altaAr = a.createdAt != null ? ArTime.toAr(a.createdAt!) : corte;

    final cubiertaEl = List<DateTime?>.filled(n + 1, null);
    if (cuota <= 0.01) {
      // Sin nada que pagar de base: todas cubiertas desde el alta.
      for (var k = 1; k <= n; k++) {
        cubiertaEl[k] = _dia(altaAr);
      }
    } else {
      var acumulado = 0.0;
      var llevaba = 0;
      for (final p in pagosDeBaseEnOrden(pagos)) {
        if (p.dia.isAfter(corte)) continue;
        acumulado += p.monto;
        final ahora =
            cuotasCompletasDesdeGrossAcumulado(acumulado, cuota).clamp(0, n);
        for (var k = llevaba + 1; k <= ahora; k++) {
          cubiertaEl[k] = p.dia;
        }
        if (ahora > llevaba) llevaba = ahora;
      }
    }

    final congelada = MoraCongelada.de(a.id);
    final detalle = <AtrasoDeCuota>[];
    var vencidas = 0, tarde = 0, dias = 0, impagas = 0, cubiertas = 0;
    for (var k = 1; k <= n; k++) {
      final venc = _dia(MoraCuotaCalculator.vencimientoCuotaDesdeRegAr(altaAr, k));
      final cubierta = cubiertaEl[k];
      if (cubierta != null) cubiertas++;
      final vencida = venc.isBefore(corte);
      var d = 0;
      if (vencida) {
        vencidas++;
        final hasta = cubierta ?? corte;
        d = hasta.difference(venc).inDays;
        if (d > 0) {
          d -= congelada.diasQuietos(
            cuota: k,
            vencimientoEfectivo: venc,
            al: hasta,
          );
        }
        if (d <= kToleranciaDiasDeAtraso) d = 0;
        if (d > 0) tarde++;
        if (cubierta == null) impagas++;
        dias += d;
      }
      detalle.add(AtrasoDeCuota(
        numero: k,
        vencimiento: venc,
        cubierta: cubierta,
        vencida: vencida,
        dias: d,
      ));
    }
    return CumplimientoDeCuotas(
      totalCuotas: n,
      vencidas: vencidas,
      tarde: tarde,
      diasDeAtraso: dias,
      impagas: impagas,
      cubiertas: cubiertas,
      canceloEl: cubiertas == n ? cubiertaEl[n] : null,
      detalle: detalle,
    );
  }
}

DateTime _dia(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime? _hora(Object? v) => switch (v) {
      final DateTime d => d,
      final String s => DateTime.tryParse(s),
      _ => null,
    };

/// Un pago de la cuota base, con el día (Argentina) en que entró la plata.
typedef PagoDeBase = ({DateTime dia, double monto, String concepto});

/// Los pagos que cuentan para la cuota base (`pagoCuentaParaClaseCobro`: sin
/// anulados, sin interés por mora, sin cargo por canal, sin mesas ni sillas),
/// por `fecha_pago` y, a igualdad, por `created_at`. Un pago sin fecha no entra.
List<PagoDeBase> pagosDeBaseEnOrden(Iterable<Map<String, dynamic>> pagos) {
  final filas = <({DateTime fecha, DateTime creado, PagoDeBase pago})>[];
  for (final p in pagos) {
    if (!pagoCuentaParaClaseCobro(p, CobroConceptoClase.base)) continue;
    final creado = _hora(p['created_at']);
    final fecha = _hora(p['fecha_pago']) ?? creado;
    if (fecha == null) continue;
    final monto = (p['monto_gross'] as num?)?.toDouble() ??
        (p['monto'] as num?)?.toDouble() ??
        0.0;
    filas.add((
      fecha: fecha,
      creado: creado ?? fecha,
      pago: (
        dia: _dia(ArTime.toAr(fecha)),
        monto: monto,
        concepto: p['concepto']?.toString() ?? '',
      ),
    ));
  }
  filas.sort((x, y) {
    final c = x.fecha.compareTo(y.fecha);
    return c != 0 ? c : x.creado.compareTo(y.creado);
  });
  return [for (final f in filas) f.pago];
}

// ── El plan de la mayoría, y el plan nuevo ──────────────────────────────────

/// El plan que tiene la mayoría de los alumnos de una fiesta. Sirve para
/// reconocer un **plan nuevo**: la app no guarda cuándo se rehízo un plan
/// (`updated_at` cambia con cada cobro), así que se deduce.
///
/// Cuando se rehace un plan, a las cuotas del principio se les suman los
/// recargos y se junta todo: el total de la cuota base de ese contrato queda
/// más alto que el de sus compañeros, y en menos cuotas.
class PlanDeLaFiesta {
  /// La cantidad de cuotas más repetida.
  final int cuotas;

  /// El total de cuota base (sin mesas ni sillas) más repetido.
  final double totalBase;

  /// El mes de alta más repetido, como año × 12 + mes. Null si nadie lo tiene.
  final int? mesDeAlta;

  const PlanDeLaFiesta({
    required this.cuotas,
    required this.totalBase,
    required this.mesDeAlta,
  });

  static double totalBaseDe(ContratoAlumno a) =>
      (a.montoTotalPactado - a.mesaExtraPrecio - a.sillasExtraPrecioTotal)
          .clamp(0.0, double.infinity)
          .roundToDouble();

  static int? mesDeAltaDe(ContratoAlumno a) {
    final c = a.createdAt;
    if (c == null) return null;
    final ar = ArTime.toAr(c);
    return ar.year * 12 + ar.month;
  }

  /// De los alumnos de la fiesta que no están de baja. En un empate gana el
  /// valor que marca a menos gente como plan nuevo (menos cuotas, total más
  /// alto): la duda va a favor de la familia.
  factory PlanDeLaFiesta.de(Iterable<ContratoAlumno> alumnos) {
    final activos = [for (final a in alumnos) if (!a.esBajaTemporal) a];
    num? moda(Iterable<num> valores, {required bool ganaElMenor}) {
      final veces = <num, int>{};
      for (final v in valores) {
        veces[v] = (veces[v] ?? 0) + 1;
      }
      num? mejor;
      var cuantas = 0;
      for (final e in veces.entries) {
        final gana = e.value > cuantas ||
            (e.value == cuantas &&
                mejor != null &&
                (ganaElMenor ? e.key < mejor : e.key > mejor));
        if (gana) {
          mejor = e.key;
          cuantas = e.value;
        }
      }
      return mejor;
    }

    return PlanDeLaFiesta(
      cuotas: moda(
            activos.map((a) => a.totalCuotas > 0 ? a.totalCuotas : 1),
            ganaElMenor: true,
          )?.toInt() ??
          1,
      totalBase: moda(
            activos.map(totalBaseDe),
            ganaElMenor: false,
          )?.toDouble() ??
          0,
      mesDeAlta: moda(
        activos.map(mesDeAltaDe).whereType<int>(),
        ganaElMenor: true,
      )?.toInt(),
    );
  }

  /// Es de plan nuevo el contrato que cumple **las tres**: menos cuotas que la
  /// mayoría, un total de cuota base mayor, y el alta en el mismo mes que la
  /// mayoría (quien se anotó meses después también tiene menos cuotas y otro
  /// precio, pero porque entró tarde: se mide como cualquiera).
  bool esPlanNuevo(ContratoAlumno a) {
    final suyas = a.totalCuotas > 0 ? a.totalCuotas : 1;
    return suyas < cuotas &&
        totalBaseDe(a) > totalBase + 0.5 &&
        mesDeAlta != null &&
        mesDeAltaDe(a) == mesDeAlta;
  }

  /// Otra cantidad de cuotas que la mayoría sin ser plan nuevo (un contado en
  /// entregas, un alta tardía, más cuotas): se mide por su cumplimiento, y la
  /// lista lo marca para que el jefe lo mire.
  bool esPlanDistinto(ContratoAlumno a) =>
      (a.totalCuotas > 0 ? a.totalCuotas : 1) != cuotas && !esPlanNuevo(a);
}

final _reCuotaDeN = RegExp(r'\((\d+)(?:\s*[-–]\s*\d+)?\s*/\s*(\d+)\)');

/// Cuándo empezó el plan de hoy de un alumno: su primer pago de base cuyo
/// concepto lleva ese plan ("Cuota Base (1/3)", con 3 cuotas hoy). Si ningún
/// concepto lo dice, su primer pago de base. Null si no tiene ninguno.
DateTime? inicioDelPlan(ContratoAlumno a, Iterable<Map<String, dynamic>> pagos) {
  final enOrden = pagosDeBaseEnOrden(pagos);
  if (enOrden.isEmpty) return null;
  final suyas = a.totalCuotas > 0 ? a.totalCuotas : 1;
  for (final p in enOrden) {
    final m = _reCuotaDeN.firstMatch(p.concepto);
    if (m != null && int.tryParse(m.group(2)!) == suyas) return p.dia;
  }
  return enOrden.first.dia;
}

// ── El orden ────────────────────────────────────────────────────────────────

/// Los tres grupos, de mejor a peor (regla del usuario, 12-nov-2026). Primero
/// manda el grupo; después, el orden de adentro.
enum GrupoDeCumplimiento {
  /// Cero días de atraso en todas sus cuotas vencidas.
  nuncaTarde(1),

  /// Algún día de atraso.
  pagoTarde(2),

  /// Rehízo su plan: va último aunque hoy no deba nada.
  planNuevo(3);

  const GrupoDeCumplimiento(this.numero);
  final int numero;
}

/// El lugar de una familia en el orden, con lo que lo explica.
class PuestoDelOrden {
  final ContratoAlumno alumno;

  /// 1 es quien mejor cumplió.
  final int puesto;
  final GrupoDeCumplimiento grupo;
  final CumplimientoDeCuotas cumplimiento;

  /// La puso adelante el jefe: su respaldo es esa decisión, no el cumplimiento.
  final bool aMano;

  /// Solo en [GrupoDeCumplimiento.planNuevo].
  final DateTime? inicioDelPlan;
  final bool planDistinto;

  /// Con cuántas otras familias empató: entre ellas decidió el azar.
  final int empatadas;

  /// El día del corte, para escribir las fechas.
  final DateTime corte;

  const PuestoDelOrden({
    required this.alumno,
    required this.puesto,
    required this.grupo,
    required this.cumplimiento,
    required this.aMano,
    required this.inicioDelPlan,
    required this.planDistinto,
    required this.empatadas,
    required this.corte,
  });

  /// Por qué quedó en ese lugar, en una oración.
  String get frase => fraseDelPuesto(
        grupo: grupo,
        cumplimiento: cumplimiento,
        aMano: aMano,
        inicioDelPlan: inicioDelPlan,
        empatadas: empatadas,
        corte: corte,
      );
}

class OrdenPorCumplimiento {
  OrdenPorCumplimiento._();

  /// Las familias de [entran], de la que mejor cumplió a la que peor.
  ///
  /// [alumnos] es **la fiesta entera**: de ahí sale el plan de la mayoría.
  /// [entran] son los ids que se ordenan (los que el sorteo va a sentar); sin
  /// él, todos los activos con algo pagado de la cuota base, que es quien entra
  /// al sorteo. [siempre] van primero, ordenadas entre sí por la misma regla;
  /// [nunca] no figuran.
  ///
  /// El azar entra **solo en los empates**: con el mismo [rng], el mismo orden.
  static List<PuestoDelOrden> de({
    required List<ContratoAlumno> alumnos,
    required Map<String, List<Map<String, dynamic>>> pagos,
    required DateTime corteAr,
    required Random rng,
    Set<String>? entran,
    Set<String> siempre = const {},
    Set<String> nunca = const {},
  }) {
    final corte = _dia(corteAr);
    final plan = PlanDeLaFiesta.de(alumnos);
    final filas = <_Fila>[];
    final enOrden = [...alumnos]..sort((x, y) => x.id.compareTo(y.id));
    for (final a in enOrden) {
      if (a.esBajaTemporal || nunca.contains(a.id)) continue;
      final suyos = pagos[a.id] ?? const <Map<String, dynamic>>[];
      if (entran != null) {
        if (!entran.contains(a.id)) continue;
      } else if (grossHistoricoClaseCobro(suyos, CobroConceptoClase.base) <=
          0.01) {
        continue;
      }
      final c = CumplimientoDeCuotas.de(a, suyos, corteAr: corte);
      final nuevo = plan.esPlanNuevo(a);
      final grupo = nuevo
          ? GrupoDeCumplimiento.planNuevo
          : c.diasDeAtraso > 0
              ? GrupoDeCumplimiento.pagoTarde
              : GrupoDeCumplimiento.nuncaTarde;
      final inicio = nuevo ? inicioDelPlan(a, suyos) : null;
      filas.add(_Fila(
        alumno: a,
        grupo: grupo,
        cumplimiento: c,
        aMano: siempre.contains(a.id),
        inicio: inicio,
        planDistinto: plan.esPlanDistinto(a),
        clave: _clave(grupo, c, inicio, a, siempre.contains(a.id)),
      ));
    }
    // Los empates, al azar: se mezclan y después se ordena con un orden
    // estable por la clave.
    final mezcladas = [...filas]..shuffle(rng);
    final orden = <_Fila>[];
    final porClave = <String, List<_Fila>>{};
    for (final f in mezcladas) {
      porClave.putIfAbsent(f.clave.join('|'), () => []).add(f);
    }
    final claves = porClave.values.toList()
      ..sort((x, y) => _comparar(x.first.clave, y.first.clave));
    for (final grupo in claves) {
      orden.addAll(grupo);
    }
    return [
      for (var i = 0; i < orden.length; i++)
        PuestoDelOrden(
          alumno: orden[i].alumno,
          puesto: i + 1,
          grupo: orden[i].grupo,
          cumplimiento: orden[i].cumplimiento,
          aMano: orden[i].aMano,
          inicioDelPlan: orden[i].inicio,
          planDistinto: orden[i].planDistinto,
          empatadas: porClave[orden[i].clave.join('|')]!.length - 1,
          corte: corte,
        ),
    ];
  }

  /// Los números por los que se ordena, de menor a mayor.
  ///
  /// - Grupo 1: primero quien ya canceló, por el día en que canceló; después
  ///   quien está al día, con más cuotas cubiertas adelante.
  /// - Grupo 2: menos días de atraso; a igualdad, más cuotas en término.
  /// - Grupo 3: el plan que empezó antes; a igualdad, más cuotas.
  static List<int> _clave(
    GrupoDeCumplimiento grupo,
    CumplimientoDeCuotas c,
    DateTime? inicio,
    ContratoAlumno a,
    bool aMano,
  ) {
    int dia(DateTime d) => d.year * 10000 + d.month * 100 + d.day;
    final adentro = switch (grupo) {
      GrupoDeCumplimiento.nuncaTarde => c.canceloEl != null
          ? [0, dia(c.canceloEl!)]
          : [1, -c.cubiertas],
      GrupoDeCumplimiento.pagoTarde => [c.diasDeAtraso, -c.enTermino],
      GrupoDeCumplimiento.planNuevo => [
          inicio == null ? 99999999 : dia(inicio),
          -(a.totalCuotas > 0 ? a.totalCuotas : 1),
        ],
    };
    return [aMano ? 0 : 1, grupo.numero, ...adentro];
  }

  static int _comparar(List<int> x, List<int> y) {
    for (var i = 0; i < x.length && i < y.length; i++) {
      final c = x[i].compareTo(y[i]);
      if (c != 0) return c;
    }
    return x.length.compareTo(y.length);
  }
}

class _Fila {
  final ContratoAlumno alumno;
  final GrupoDeCumplimiento grupo;
  final CumplimientoDeCuotas cumplimiento;
  final bool aMano;
  final DateTime? inicio;
  final bool planDistinto;
  final List<int> clave;

  const _Fila({
    required this.alumno,
    required this.grupo,
    required this.cumplimiento,
    required this.aMano,
    required this.inicio,
    required this.planDistinto,
    required this.clave,
  });
}

// ── La oración del porqué ───────────────────────────────────────────────────

const _meses = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

String _fecha(DateTime d, DateTime corte) =>
    '${d.day} de ${_meses[d.month - 1]}'
    '${d.year == corte.year ? '' : ' de ${d.year}'}';

/// Por qué una familia quedó en su lugar, en una oración corta y natural: lo
/// pidió el usuario (12-nov-2026) "para tener un argumento si se quejan". No
/// dice "mora" ni "deuda", y ningún número que no esté en los datos.
String fraseDelPuesto({
  required GrupoDeCumplimiento grupo,
  required CumplimientoDeCuotas cumplimiento,
  required bool aMano,
  required DateTime? inicioDelPlan,
  required int empatadas,
  required DateTime corte,
}) {
  final c = cumplimiento;
  String cuotas(int n) => n == 1 ? '1 cuota' : '$n cuotas';
  final String base;
  if (aMano) {
    return 'Elegida a mano.';
  } else if (grupo == GrupoDeCumplimiento.planNuevo) {
    base = inicioDelPlan == null
        ? 'Rehízo su plan de pago.'
        : 'Rehízo su plan de pago el ${_fecha(inicioDelPlan, corte)}.';
  } else if (grupo == GrupoDeCumplimiento.nuncaTarde) {
    base = c.canceloEl != null
        ? 'Nunca pagó tarde y terminó de pagar el ${_fecha(c.canceloEl!, corte)}.'
        : 'Nunca pagó tarde. Lleva ${c.cubiertas} de ${cuotas(c.totalCuotas)} '
            '${c.cubiertas == 1 ? 'paga' : 'pagas'}.';
  } else {
    final dias = c.diasDeAtraso == 1
        ? '1 día de atraso en total'
        : '${c.diasDeAtraso} días de atraso en total';
    final debe = c.impagas == 1
        ? 'debe 1 cuota vencida'
        : 'debe ${c.impagas} cuotas vencidas';
    if (c.pagadasTarde > 0 && c.impagas > 0) {
      base = 'Pagó tarde ${cuotas(c.pagadasTarde)} y $debe: $dias.';
    } else if (c.pagadasTarde > 0) {
      base = 'Pagó tarde ${cuotas(c.pagadasTarde)}: $dias.';
    } else {
      base = '${debe[0].toUpperCase()}${debe.substring(1)}: $dias.';
    }
  }
  if (empatadas <= 0) return base;
  return '$base ${empatadas == 1 ? 'Empató con otra familia' : 'Empató con otras $empatadas familias'}'
      ': entre ellas se sorteó.';
}
