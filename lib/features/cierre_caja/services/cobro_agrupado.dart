import '../../../core/utils/pago_interes_mora.dart';
import '../../mi_empresa/models/ingreso_detallado.dart';
import '../models/medio_pago_caja.dart';

/// Ventana temporal que define "un mismo cobro".
///
/// No es un número elegido de cero: es el mismo umbral con el que
/// `ContratosRepository.getUltimosPagosLote` (`contratos_repository.dart:664`) ya
/// define el último lote de pagos de un contrato. Usar el mismo valor hace que la
/// pantalla de caja y la reimpresión de recibos coincidan en qué considera un cobro.
///
/// Por qué 10 s y no otra cosa: las líneas de un cobro se escriben en un `for`
/// secuencial, cada una con su propio `ArTime.nowUtcIso()`
/// (`contratos_repository.dart:212`), a milisegundos de distancia. Un bucket por
/// minuto partiría en dos un cobro que cruza 09:36:59,9 → 09:37:00,1; una ventana
/// de 2-3 minutos fusionaría un recobro genuino del mismo alumno, que tiene que
/// quedar como una fila aparte.
const Duration kVentanaCobro = Duration(seconds: 10);

/// Las líneas de un mismo cobro, agrupadas en una fila.
///
/// Un cobro con plan + mora escribe 4-5 filas en `pagos_contrato_alumno`, todas
/// con el mismo alumno y la misma hora. Esta clase las junta para que la pantalla
/// y los papeles muestren **una fila por cobro** con el monto total.
///
/// El medio de pago **no** forma parte de la identidad del grupo: un cobro es un
/// cobro aunque se haya pagado mitad en efectivo y mitad por transferencia. El
/// grupo lleva el desglose ([montoEfectivo] / [montoTransferencia]) y [parte]
/// proyecta la porción de un medio para las vistas que cuentan plata de un tipo.
class CobroAgrupado {
  /// Nombre del alumno (o cliente, en las fuentes que no son de contratos).
  final String alumno;

  /// Instante **más viejo** del grupo. Se usa el más viejo y no el más nuevo para
  /// que la hora mostrada sea determinista y no cambie si mañana se agrega una
  /// línea al final del lote.
  final DateTime fecha;

  final List<IngresoDetallado> lineas;

  /// `true` cuando este grupo es la proyección ([parte]) de un cobro que era
  /// mixto.
  ///
  /// Hace falta guardarlo porque después de proyectar las líneas son de un solo
  /// medio y [esMixto] daría `false`: sin este dato, la tarjeta de EFECTIVO no
  /// podría avisar que el monto que muestra es solo una parte del cobro y no
  /// coincide con el recibo del alumno.
  final bool parteDeMixto;

  const CobroAgrupado({
    required this.alumno,
    required this.fecha,
    required this.lineas,
    this.parteDeMixto = false,
  });

  double get monto => _r2(lineas.fold<double>(0, (s, i) => s + i.monto));

  double get montoEfectivo => _r2(
    lineas
        .where((i) => !esTransferenciaCaja(i.medioPago))
        .fold<double>(0, (s, i) => s + i.monto),
  );

  double get montoTransferencia => _r2(
    lineas
        .where((i) => esTransferenciaCaja(i.medioPago))
        .fold<double>(0, (s, i) => s + i.monto),
  );

  /// El cobro tiene plata en los dos medios a la vez.
  bool get esMixto => montoEfectivo > 0.004 && montoTransferencia > 0.004;

  /// `'Efectivo'` | `'Transferencia'`, o `null` si es mixto.
  ///
  /// Se decide por el monto y no por el rótulo de la primera línea: una línea en
  /// cero de un medio no debería definir el medio del cobro.
  String? get medioUnico {
    if (esMixto) return null;
    if (montoTransferencia > 0.004) return 'Transferencia';
    if (montoEfectivo > 0.004) return 'Efectivo';
    return lineas.isEmpty ? null : medioPagoLabel(lineas.first.medioPago);
  }

  /// Colegio del alumno, o `null` cuando la fila no lo tiene.
  ///
  /// Getter y no campo: todas las líneas de un cobro son del mismo contrato, así
  /// que alcanza con la primera, y así el dato viaja solo a través de [parte] sin
  /// depender de que alguien se acuerde de copiarlo.
  String? get institucion => lineas.isEmpty ? null : lineas.first.institucion;

  /// Resumen corto de qué se pagó: `"cuota base 4/9, int. mora Jul"`.
  ///
  /// Es contexto, no plata: es lo primero que se sacrifica cuando el papel no
  /// entra. Nunca devuelve vacío.
  String get resumenConceptos => _resumenDe(lineas);

  /// El mismo cobro con **solo** su parte de un medio.
  ///
  /// Conserva [alumno] y [fecha] para que la fila proyectada muestre la misma hora
  /// que la fila de la lista principal. El resumen de conceptos, en cambio, se
  /// recalcula sobre las líneas que quedan: en la tarjeta de EFECTIVO tiene que
  /// describir la plata que está en el cajón, no la del cobro completo.
  CobroAgrupado parte({required bool transferencia}) => CobroAgrupado(
    alumno: alumno,
    fecha: fecha,
    lineas: lineas
        .where((i) => esTransferenciaCaja(i.medioPago) == transferencia)
        .toList(),
    parteDeMixto: esMixto,
  );
}

/// Agrupa las líneas de ingreso en un cobro por alumno.
///
/// [ingresos] puede venir en cualquier orden; la salida queda ordenada por hora
/// **descendente** (lo más reciente primero), igual que la lista de movimientos.
///
/// Solo se agrupan las filas de contratos de alumnos (`fuente == 'Masivo'`). Los
/// cobros de eventos particulares y de alquiler pasan como grupos de una línea:
/// esas tablas no tienen `sesion_caja_id`, así que nunca pertenecen a una sesión
/// de caja y solo aparecen en la vista de diagnóstico del jefe, donde dos cobros
/// distintos del mismo cliente en el mismo segundo no tienen por qué ser el mismo.
List<CobroAgrupado> agruparIngresosPorCobro(
  List<IngresoDetallado> ingresos, {
  Duration ventana = kVentanaCobro,
}) {
  final ordenados = List<IngresoDetallado>.from(ingresos)
    ..sort((a, b) => b.fecha.compareTo(a.fecha));

  final cerrados = <List<IngresoDetallado>>[];
  // Grupo abierto por alumno. Hace falta un mapa y no solo comparar con la fila
  // anterior porque un cobro masivo recorre varios alumnos en el mismo segundo y
  // las filas de uno pueden quedar intercaladas con las de otro.
  final abiertos = <String, List<IngresoDetallado>>{};

  for (final i in ordenados) {
    if (i.fuente != 'Masivo') {
      cerrados.add([i]);
      continue;
    }
    final clave = _claveAlumno(i);
    final grupo = abiertos[clave];
    // Todos los registros del lote tienen que quedar dentro de la ventana
    // medida desde el más reciente. Comparar con `grupo.last` encadenaba saltos:
    // 18 s, 9 s y 0 s terminaban juntos aunque el lote abarcara 18 segundos.
    // `getUltimosPagosLote` usa exactamente esta semántica: último pago menos
    // diez segundos.
    if (grupo != null &&
        grupo.first.fecha.difference(i.fecha).abs() <= ventana) {
      grupo.add(i);
      continue;
    }
    if (grupo != null) cerrados.add(grupo);
    abiertos[clave] = [i];
  }
  cerrados.addAll(abiertos.values);

  final grupos = cerrados.map((lineas) {
    var masVieja = lineas.first.fecha;
    for (final l in lineas) {
      if (l.fecha.isBefore(masVieja)) masVieja = l.fecha;
    }
    return CobroAgrupado(
      alumno: lineas.first.alumnoOCliente,
      fecha: masVieja,
      lineas: lineas,
    );
  }).toList();

  grupos.sort((a, b) => _masNueva(b).compareTo(_masNueva(a)));
  return grupos;
}

/// Cobros de un solo medio, listos para una tarjeta o para un bloque del papel.
///
/// Agrupa sobre **todos** los ingresos y después proyecta. Ese orden es lo que
/// hace que un cobro mixto aporte a cada bucket su parte y que la suma de las
/// filas de un bucket dé exactamente el bruto de ese bucket — la propiedad que
/// permite cotejar el papel contra la plata.
List<CobroAgrupado> cobrosDeMedio(
  List<IngresoDetallado> ingresos, {
  required bool transferencia,
  Duration ventana = kVentanaCobro,
}) => agruparIngresosPorCobro(ingresos, ventana: ventana)
    .map((c) => c.parte(transferencia: transferencia))
    .where((c) => c.lineas.isNotEmpty)
    .toList();

DateTime _masNueva(CobroAgrupado g) {
  var v = g.lineas.first.fecha;
  for (final l in g.lineas) {
    if (l.fecha.isAfter(v)) v = l.fecha;
  }
  return v;
}

/// Identidad del alumno para agrupar.
///
/// Se prefiere el id del contrato: agrupar por nombre fusionaría dos alumnos
/// homónimos del mismo colegio —`nombre_alumno` es texto libre y en una cohorte
/// escolar los homónimos son normales— y eso pondría la plata de una familia en
/// la fila de otra, en el papel con el que se cuenta la caja. El nombre queda
/// como respaldo solo para filas viejas, previas a la columna.
String _claveAlumno(IngresoDetallado i) {
  final id = i.contratoAlumnoId?.trim();
  if (id != null && id.isNotEmpty) return 'c:$id';
  return 'n:${foldDiacriticosLatin(i.alumnoOCliente.trim().toLowerCase())}';
}

double _r2(double v) => double.parse(v.toStringAsFixed(2));

// ── Resumen de conceptos ────────────────────────────────────────────────────
//
// Los rótulos que se leen acá los generan `ConceptoPagoDisplay` y
// `MoraConceptoRotulo`, así que las formas son conocidas y acotadas. La idea es
// clasificar y contar, no parsear: si aparece un rótulo nuevo, cae en el último
// fragmento y sigue mostrando algo útil en vez de romperse.

enum _Clase { cuotaBase, mesa, sillas, mora, recargo, otro }

/// `(4/9)` y `(1–3/9)`. El rótulo usa guion largo U+2013; se aceptan los dos.
final RegExp _reCuota = RegExp(r'\((\d+)(?:[–-](\d+))?/(\d+)\)');

/// `(vto Jun 2026)` y `(vto May, Jun, Jul)`.
final RegExp _reVto = RegExp(r'\(vto ([^)]+)\)');

const _mesesOrden = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

String _resumenDe(List<IngresoDetallado> lineas) {
  if (lineas.isEmpty) return '—';

  var cuotas = 0;
  String? cuotaUnica;
  var mesas = 0;
  String? mesaUnica;
  var sillas = false;
  var recargo = false;
  var parcial = false;
  final mesesMora = <String>[];
  var hayMora = false;
  final otros = <String>[];

  for (final l in lineas) {
    final c = l.concepto.trim();
    switch (_clasificar(l)) {
      case _Clase.mora:
        hayMora = true;
        mesesMora.addAll(_mesesDe(c));
      case _Clase.recargo:
        recargo = true;
      case _Clase.mesa:
        if (_esParcial(c)) parcial = true;
        final m = _reCuota.firstMatch(c);
        mesas += m == null ? 1 : _cuentaCuotas(m);
        mesaUnica ??= m == null ? null : '${m.group(1)}/${m.group(3)}';
      case _Clase.sillas:
        if (_esParcial(c)) parcial = true;
        sillas = true;
      case _Clase.cuotaBase:
        if (_esParcial(c)) parcial = true;
        final m = _reCuota.firstMatch(c);
        cuotas += m == null ? 1 : _cuentaCuotas(m);
        cuotaUnica ??= m == null ? null : '${m.group(1)}/${m.group(3)}';
      case _Clase.otro:
        if (c.isNotEmpty) otros.add(c.toLowerCase());
    }
  }

  final frags = <String>[];
  if (cuotas > 0) {
    final base = cuotas == 1 && cuotaUnica != null
        ? 'cuota base $cuotaUnica'
        : cuotas == 1
        ? 'cuota base'
        : 'cuota base ×$cuotas';
    frags.add(parcial ? 'parcial $base' : base);
  }
  if (mesas > 0) {
    frags.add(
      mesas == 1 && mesaUnica != null ? 'mesa $mesaUnica' : 'mesa ×$mesas',
    );
  }
  if (sillas) frags.add('sillas');
  if (hayMora) {
    final meses = _comprimirMeses(mesesMora);
    frags.add(meses.isEmpty ? 'int. mora' : 'int. mora $meses');
  }
  if (recargo) frags.add('recargo');
  frags.addAll(otros);

  if (frags.isEmpty) {
    // Ningún patrón conocido: mejor el concepto crudo más corto que nada.
    final crudos =
        lineas.map((l) => l.concepto.trim()).where((s) => s.isNotEmpty).toList()
          ..sort((a, b) => a.length.compareTo(b.length));
    return crudos.isEmpty ? '—' : crudos.first;
  }
  if (frags.length <= 3) return frags.join(', ');
  return '${frags.take(3).join(', ')} +${frags.length - 3} más';
}

_Clase _clasificar(IngresoDetallado l) {
  final lk = l.lineKind?.trim();
  final c = l.concepto;
  // `line_kind` cuando está (exacto) y las heurísticas de concepto cuando es
  // null (filas previas a la columna) — el mismo layering que ya usa
  // `moraCobradaDelPeriodoVigente` en pago_interes_mora.dart.
  if (lk == kLineKindInteresMora || esPagoInteresMoraPorConcepto(c)) {
    return _Clase.mora;
  }
  if (lk == kLineKindCargoCanal || esPagoCargoCanalPorConcepto(c)) {
    return _Clase.recargo;
  }
  final f = foldDiacriticosLatin(c.toLowerCase());
  if (f.contains('costo por transferencia')) return _Clase.recargo;
  if (f.contains('mesa')) return _Clase.mesa;
  if (f.contains('silla')) return _Clase.sillas;
  if (f.contains('cuota') || f.contains('entrega')) return _Clase.cuotaBase;
  return _Clase.otro;
}

bool _esParcial(String concepto) =>
    foldDiacriticosLatin(concepto.toLowerCase()).contains('entrega parcial');

int _cuentaCuotas(RegExpMatch m) {
  final desde = int.tryParse(m.group(1) ?? '');
  final hasta = int.tryParse(m.group(2) ?? '');
  if (desde == null) return 1;
  if (hasta == null || hasta < desde) return 1;
  return hasta - desde + 1;
}

/// Meses de un rótulo de mora, normalizados a `May` / `Jun`.
///
/// `MoraConceptoRotulo` escribe `(vto Jun 2026)` cuando es una cuota y
/// `(vto May, Jun, Jul)` cuando son varias (`mora_concepto_rotulo.dart:256`).
List<String> _mesesDe(String concepto) {
  final m = _reVto.firstMatch(concepto);
  if (m == null) return const [];
  return m
      .group(1)!
      .split(',')
      .map((p) => p.trim().split(' ').first)
      .where((p) => p.isNotEmpty)
      .map((p) => p[0].toUpperCase() + p.substring(1).toLowerCase())
      .toList();
}

/// `[May, Jun, Jul]` → `May–Jul`; `[May, Jul]` → `May, Jul`.
String _comprimirMeses(List<String> meses) {
  final idx = <int>{};
  for (final m in meses) {
    final i = _mesesOrden.indexOf(m.toLowerCase());
    if (i >= 0) idx.add(i);
  }
  if (idx.isEmpty) return meses.isEmpty ? '' : meses.toSet().join(', ');
  final orden = idx.toList()..sort();
  final partes = <String>[];
  var i = 0;
  while (i < orden.length) {
    var j = i;
    while (j + 1 < orden.length && orden[j + 1] == orden[j] + 1) {
      j++;
    }
    final desde = _cap(_mesesOrden[orden[i]]);
    if (j - i >= 2) {
      partes.add('$desde–${_cap(_mesesOrden[orden[j]])}');
    } else {
      for (var k = i; k <= j; k++) {
        partes.add(_cap(_mesesOrden[orden[k]]));
      }
    }
    i = j + 1;
  }
  return partes.join(', ');
}

String _cap(String s) => s[0].toUpperCase() + s.substring(1);
