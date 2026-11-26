import 'package:flutter/foundation.dart' show immutable;

import '../../../core/utils/ar_time.dart';
import '../../common/utils/dia_de_la_fiesta.dart' show kLaFiestaSigueHasta;
import '../datos/barra_repositorio.dart';

/// **El día de operación de la barra** (25-nov-2026): la noche a la que pertenece una
/// caja. Es el día en que se abrió, **en hora de Argentina y con el corte al mediodía**
/// ([kLaFiestaSigueHasta]): una caja abierta a las 18 del 4-dic es del 4-dic aunque venda
/// hasta las 8 del 5. **Las ventas van con su caja**, aunque sean de madrugada.
///
/// Es **la única cuenta del día** de la barra: LAS CAJAS, BARRA del cierre de caja, el
/// stock, el "Quedan" de VENDER, el vale, los vales anulados de la puerta y la central la
/// sacan de acá. Sin SQL ni columnas nuevas: sale de `abierta_at`, que toda caja tiene.
/// Nada se borra: las cajas de otros días siguen en la base, aparte.
///
/// Lo pidió el usuario el 25-nov con las fotos de BARRA → CAJAS de la Técnica: las cajas
/// de prueba de otros días se sumaban con las de la noche.
@immutable
class DiaDeOperacion implements Comparable<DiaDeOperacion> {
  final int anio;
  final int mes;
  final int dia;

  const DiaDeOperacion(this.anio, this.mes, this.dia);

  /// Para una caja o una venta sin fecha que se entienda: no se pierde, va aparte.
  static const sinFecha = DiaDeOperacion(1, 1, 1);

  /// La noche de [momento], esté en la zona que esté: en hora de Argentina, 12 horas
  /// antes, sin la hora. Las 01:30 del 5-dic son del 4-dic; las 13:00 del 5, del 5.
  factory DiaDeOperacion.de(DateTime momento) {
    final t = ArTime.toAr(momento).subtract(kLaFiestaSigueHasta);
    return DiaDeOperacion(t.year, t.month, t.day);
  }

  /// La de un momento guardado (el ISO de las tablas). Null si no se entiende.
  static DiaDeOperacion? deIso(String? iso) {
    final t = iso == null ? null : DateTime.tryParse(iso);
    return t == null ? null : DiaDeOperacion.de(t);
  }

  /// La noche de una caja: la de cuando se abrió.
  static DiaDeOperacion deLaCaja(CajaBarra caja) =>
      deIso(caja.abiertaAt) ?? deIso(caja.createdAt) ?? sinFecha;

  /// Un día del calendario tal cual: la fecha de la fiesta, el día del cierre de caja.
  factory DiaDeOperacion.delCalendario(DateTime fecha) =>
      DiaDeOperacion(fecha.year, fecha.month, fecha.day);

  bool get esSinFecha => this == sinFecha;

  DateTime get _fecha => DateTime.utc(anio, mes, dia);

  static String _dos(int n) => n.toString().padLeft(2, '0');

  static const _dias = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
  static const _diasLargos = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
  static const _meses = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto',
    'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];

  /// "4/12": como lo dice el papel ("Las 3 cajas del 4/12").
  String get diaYMes => esSinFecha ? 'sin fecha' : '$dia/$mes';

  /// "04/12/2026".
  String get conAnio => esSinFecha ? 'sin fecha' : '${_dos(dia)}/${_dos(mes)}/$anio';

  /// "Vie 04/12": la marca de cada día arriba de LAS CAJAS.
  String get corto => esSinFecha ? 'Sin fecha' : '${_dias[_fecha.weekday - 1]} ${_dos(dia)}/${_dos(mes)}';

  /// "Vie 04/12/2026": la del vale.
  String get conDiaDeLaSemana =>
      esSinFecha ? 'Sin fecha' : '${_dias[_fecha.weekday - 1]} ${_dos(dia)}/${_dos(mes)}/$anio';

  /// "viernes 4 de diciembre".
  String get largo => esSinFecha ? 'sin fecha' : '${_diasLargos[_fecha.weekday - 1]} $dia de ${_meses[mes - 1]}';

  DiaDeOperacion get siguiente {
    final t = _fecha.add(const Duration(days: 1));
    return DiaDeOperacion(t.year, t.month, t.day);
  }

  DiaDeOperacion get anterior {
    final t = _fecha.subtract(const Duration(days: 1));
    return DiaDeOperacion(t.year, t.month, t.day);
  }

  bool isBefore(DiaDeOperacion otro) => compareTo(otro) < 0;

  @override
  int compareTo(DiaDeOperacion otro) {
    if (anio != otro.anio) return anio.compareTo(otro.anio);
    if (mes != otro.mes) return mes.compareTo(otro.mes);
    return dia.compareTo(otro.dia);
  }

  @override
  bool operator ==(Object other) =>
      other is DiaDeOperacion && other.anio == anio && other.mes == mes && other.dia == dia;

  @override
  int get hashCode => Object.hash(anio, mes, dia);

  @override
  String toString() => 'DiaDeOperacion($conAnio)';
}

/// Las cajas de una fiesta, **separadas por su día de operación**: los días de la fiesta,
/// el de esta noche y las cajas de cada uno. Así una caja de prueba del 20/11 no se suma
/// con las de la noche de la fiesta, y dos "Caja 1" de días distintos no se confunden.
class CajasPorDia {
  CajasPorDia._(this._porDia, this._diaDeCaja);

  final Map<DiaDeOperacion, List<CajaBarra>> _porDia;
  final Map<String, DiaDeOperacion> _diaDeCaja;

  factory CajasPorDia.de(Iterable<CajaBarra> cajas) {
    final porDia = <DiaDeOperacion, List<CajaBarra>>{};
    final diaDeCaja = <String, DiaDeOperacion>{};
    for (final c in cajas) {
      final d = DiaDeOperacion.deLaCaja(c);
      (porDia[d] ??= []).add(c);
      diaDeCaja[c.id] = d;
    }
    return CajasPorDia._(porDia, diaDeCaja);
  }

  /// Los días con alguna caja, del más viejo al más nuevo.
  List<DiaDeOperacion> get dias => _porDia.keys.toList()..sort();

  bool get vacio => _porDia.isEmpty;

  bool tiene(DiaDeOperacion d) => _porDia.containsKey(d);

  /// Las cajas de esa noche (vacía si no hubo).
  List<CajaBarra> delDia(DiaDeOperacion d) => List.unmodifiable(_porDia[d] ?? const <CajaBarra>[]);

  Set<String> idsDelDia(DiaDeOperacion d) => {for (final c in _porDia[d] ?? const <CajaBarra>[]) c.id};

  /// Las cajas todavía abiertas de esa noche.
  List<CajaBarra> abiertasDelDia(DiaDeOperacion d) => [for (final c in delDia(d)) if (c.abierta) c];

  /// La noche de la caja [cajaId], si está.
  DiaDeOperacion? diaDe(String cajaId) => _diaDeCaja[cajaId];

  /// **La noche de una venta: la de su caja**, aunque se haya vendido de madrugada. Si su
  /// caja todavía no llegó a este equipo, la de su hora (con el mismo corte al mediodía).
  DiaDeOperacion diaDeLaVenta(VentaBarra v) =>
      _diaDeCaja[v.cajaBarraId] ?? DiaDeOperacion.deIso(v.createdAt) ?? DiaDeOperacion.sinFecha;

  /// Las ventas de esa noche, en el orden en que vienen.
  List<VentaBarra> ventasDelDia(Iterable<VentaBarra> ventas, DiaDeOperacion d) =>
      [for (final v in ventas) if (diaDeLaVenta(v) == d) v];

  /// Con qué noche se abre una pantalla de la barra:
  /// 1. [preferido] (el día del cierre de caja), si tuvo cajas;
  /// 2. **esta noche**, si tiene cajas;
  /// 3. la última noche con cajas, si es de después de esta (una tablet con el reloj
  ///    corrido): esas son las de ahora;
  /// 4. esta noche, si es la noche de la fiesta ([fechaDeLaFiesta]): antes de abrir la
  ///    primera caja se ve vacía, y no con las cajas de prueba de otro día;
  /// 5. la última noche con cajas;
  /// 6. sin ninguna caja, esta noche.
  DiaDeOperacion inicial({
    required DateTime ahora,
    DateTime? fechaDeLaFiesta,
    DiaDeOperacion? preferido,
  }) {
    if (preferido != null && tiene(preferido)) return preferido;
    final hoy = DiaDeOperacion.de(ahora);
    if (tiene(hoy)) return hoy;
    final todos = dias;
    if (todos.isNotEmpty && hoy.isBefore(todos.last)) return todos.last;
    if (fechaDeLaFiesta != null && DiaDeOperacion.delCalendario(fechaDeLaFiesta) == hoy) return hoy;
    return todos.isEmpty ? hoy : todos.last;
  }
}

/// De las [abiertas] de una fiesta, las de la noche de [ahora]: las únicas que cuentan al
/// abrir otra caja ("La caja 1 ya está abierta"). Una caja de prueba de una noche
/// anterior que quedó abierta ya no avisa. Una "de después" sí cuenta: es de esta noche
/// con el reloj de otra tablet corrido.
List<CajaBarra> abiertasDeEstaNoche(Iterable<CajaBarra> abiertas, DateTime ahora) {
  final hoy = DiaDeOperacion.de(ahora);
  return [for (final c in abiertas) if (c.abierta && !DiaDeOperacion.deLaCaja(c).isBefore(hoy)) c];
}

/// Si una fiesta con fecha [fechaDeLaFiesta] tiene todavía cajas abiertas **de su noche**
/// entre [cajas]: mientras tanto sigue a la vista de la cajera y de la encargada, aunque
/// pase el mediodía. Una caja de prueba de otro día que quedó abierta no cuenta.
bool quedanCajasDeSuNoche(Iterable<CajaBarra> cajas, DateTime fechaDeLaFiesta) {
  final noche = DiaDeOperacion.delCalendario(fechaDeLaFiesta);
  return cajas.any((c) => c.abierta && DiaDeOperacion.deLaCaja(c) == noche);
}
