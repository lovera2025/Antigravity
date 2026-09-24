import 'dart:math';

import '../../../models/contrato_alumno.dart';
import '../../common/utils/currency_extensions.dart';
import 'mesas_extra_utils.dart';
import 'sorteo_mesas_motor.dart';

/// Cuánta gente tiene una familia y cuántos asientos le tocan.
class OcupacionAsientos {
  /// El alumno más sus acompañantes.
  final int personas;
  final int mesas;
  final int sillasExtra;

  const OcupacionAsientos({
    required this.personas,
    required this.mesas,
    required this.sillasExtra,
  });

  int get asientos => SalonMesas.sillasPorMesa * mesas + sillasExtra;
  int get faltan => max(0, personas - asientos);
  bool get entran => faltan == 0;

  /// Qué sumar si no entran: sillas mientras alcancen (2 por mesa), y si no,
  /// una mesa extra.
  String? get sugerencia {
    if (entran) return null;
    final sillasQueQuedan =
        SalonMesas.maxSillasExtraPara(mesas) - sillasExtra;
    if (faltan <= sillasQueQuedan) {
      return faltan == 1
          ? 'Falta 1 asiento: sumá 1 silla extra'
          : 'Faltan $faltan asientos: sumá $faltan sillas extra';
    }
    return mesas == 1
        ? 'No entran en 1 mesa: hace falta una mesa extra'
        : 'No entran en $mesas mesas: hace falta otra mesa extra';
  }

  /// "3 de 8 lugares": personas (alumno + acompañantes) de los lugares que le
  /// tocan.
  String get texto => '$personas de $asientos lugares';
}

/// Los precios que más se repiten en el evento, para avisar cuando alguien
/// quedó cargado distinto. Si hay empate no hay "habitual" y no se avisa nada.
class PreciosHabituales {
  final double? mesaExtra;
  final double? sillaExtra;

  const PreciosHabituales({this.mesaExtra, this.sillaExtra});

  factory PreciosHabituales.de(Iterable<ContratoAlumno> alumnos) {
    final mesas = <int, int>{};
    final sillas = <int, int>{};
    for (final a in alumnos) {
      if (a.esBajaTemporal) continue;
      final um = SalonMesas.precioUnitarioMesa(a);
      if (um != null) mesas.update(um.round(), (v) => v + 1, ifAbsent: () => 1);
      final us = SalonMesas.precioUnitarioSilla(a);
      if (us != null) sillas.update(us.round(), (v) => v + 1, ifAbsent: () => 1);
    }
    return PreciosHabituales(
      mesaExtra: _moda(mesas)?.toDouble(),
      sillaExtra: _moda(sillas)?.toDouble(),
    );
  }

  static int? _moda(Map<int, int> cuenta) {
    if (cuenta.isEmpty) return null;
    final maximo = cuenta.values.reduce(max);
    final ganadores = cuenta.entries.where((e) => e.value == maximo).toList();
    return ganadores.length == 1 ? ganadores.first.key : null;
  }
}

enum TipoAvisoSalon {
  precioMesa,
  precioSillas,
  sillasDeMas,
  mesasNoCoinciden,
  pagosDeOtraMesa,
  numeroIlegible,
  personasNoEntran,
}

/// Algo para mirar antes de sortear. Ninguno bloquea: solo piden revisar.
class AvisoSalon {
  final String alumnoId;
  final String alumno;
  final TipoAvisoSalon tipo;
  final String detalle;

  const AvisoSalon({
    required this.alumnoId,
    required this.alumno,
    required this.tipo,
    required this.detalle,
  });
}

/// Cómo queda el salón para cada alumno: sus mesas, sus sillas extra y cuánta
/// gente entra. Todo sale de su cuenta y de los números guardados, sin guardar
/// nada nuevo; la Planilla, la grilla, el sorteo y Editar alumno usan esto
/// mismo para decir siempre lo mismo.
class SalonMesas {
  SalonMesas._();

  static const int sillasPorMesa = 8;
  static const int maxSillasExtraPorMesa = 2;

  /// Mesas que le corresponden: la base más las extra de su cuenta.
  static int mesas(ContratoAlumno a) =>
      MesasExtraUtils.cantidadMesasFisicasSorteo(a);

  static int mesasExtra(ContratoAlumno a) => mesas(a) - 1;

  /// Sillas extra que figuran en su cuenta. Sin precio no cuentan: es lo mismo
  /// que muestra el estado de cuenta (`pdf_service.dart`, sillas con precio).
  static int sillasExtra(ContratoAlumno a) =>
      a.sillasExtraPrecioTotal > 0.01 ? max(0, a.sillasExtraCantidad) : 0;

  static int maxSillasExtraPara(int mesas) => maxSillasExtraPorMesa * mesas;

  static int maxSillasExtra(ContratoAlumno a) => maxSillasExtraPara(mesas(a));

  static double? precioUnitarioMesa(ContratoAlumno a) {
    final extra = mesasExtra(a);
    if (a.mesaExtraPrecio <= 0.01 || extra < 1) return null;
    return a.mesaExtraPrecio / extra;
  }

  static double? precioUnitarioSilla(ContratoAlumno a) {
    if (a.sillasExtraPrecioTotal <= 0.01 || a.sillasExtraCantidad < 1) {
      return null;
    }
    return a.sillasExtraPrecioTotal / a.sillasExtraCantidad;
  }

  static OcupacionAsientos ocupacion(ContratoAlumno a) => OcupacionAsientos(
        personas: 1 +
            max(a.cantidadAcompanantes, a.nombresAcompanantes.length),
        mesas: mesas(a),
        sillasExtra: sillasExtra(a),
      );

  /// Sus números, de a tramos: primero el más grande, después los sueltos.
  static List<List<int>> tramos(ContratoAlumno a) {
    final nums = MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa);
    return SorteoMesasMotor.tramosDe(nums)
      ..sort((x, y) {
        final c = y.length.compareTo(x.length);
        return c != 0 ? c : x.first.compareTo(y.first);
      });
  }

  static String _textoTramo(List<int> t) =>
      t.length == 1 ? '${t.first}' : '${t.first}-${t.last}';

  /// Columna MESA: "12-14 (2 extra)", "12-13 + 40 (separada)", "-".
  static String textoMesas(ContratoAlumno a) {
    final texto = a.numeroMesa?.trim() ?? '';
    if (texto.isEmpty) return '-';
    final ts = tramos(a);
    if (ts.isEmpty) return texto;
    final base = ts.map(_textoTramo).join(' + ');
    if (ts.length > 1) {
      return '$base (${ts.length == 2 ? 'separada' : 'separadas'})';
    }
    final extra = ts.first.length - 1;
    return extra > 0 ? '$base ($extra extra)' : base;
  }

  /// Lo que se ve en la puerta: "12", "12-14", "12-13 y 40". Sin las notas de la
  /// planilla ("2 extra", "separada"), que a la familia no le dicen nada.
  /// `null` si todavía no tiene mesa.
  static String? textoMesasPuerta(ContratoAlumno a) {
    final texto = a.numeroMesa?.trim() ?? '';
    if (texto.isEmpty) return null;
    final ts = tramos(a);
    if (ts.isEmpty) return texto;
    final partes = ts.map(_textoTramo).toList();
    if (partes.length == 1) return partes.single;
    return '${partes.sublist(0, partes.length - 1).join(', ')} y ${partes.last}';
  }

  /// "le falta 1 mesa" / "le sobran 2 mesas", o null si coincide con la
  /// cuenta (o si todavía no tiene números). Sin ícono: la pantalla le pone ⚠
  /// y el PDF "(!)", porque la fuente de los PDF no tiene ese símbolo.
  static String? avisoMesas(ContratoAlumno a) {
    final asignadas = MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa).length;
    if (asignadas == 0) return null;
    final diferencia = mesas(a) - asignadas;
    if (diferencia == 0) return null;
    final n = diferencia.abs();
    final plural = n == 1 ? '' : 's';
    return diferencia > 0
        ? 'le falta${n == 1 ? '' : 'n'} $n mesa$plural'
        : 'le sobra${n == 1 ? '' : 'n'} $n mesa$plural';
  }

  /// Sillas extra repartidas de a 2 por mesa: primero su bloque, después las
  /// separadas. Si tiene más de las que entran, las de más no aparecen acá
  /// (lo marca [avisos]).
  static List<(int mesa, int sillas)> repartoSillas(ContratoAlumno a) {
    var resto = sillasExtra(a);
    final out = <(int, int)>[];
    for (final n in [for (final t in tramos(a)) ...t]) {
      if (resto <= 0) break;
      final k = min(maxSillasExtraPorMesa, resto);
      out.add((n, k));
      resto -= k;
    }
    return out;
  }

  /// Columna SILLAS EXTRA: la cantidad, o "-".
  static String textoSillas(ContratoAlumno a) {
    final s = sillasExtra(a);
    return s > 0 ? '$s' : '-';
  }

  /// "12 (+2) · 13 (+1)", o "3 sillas extra" si todavía no tiene mesa.
  static String textoRepartoSillas(ContratoAlumno a) {
    final s = sillasExtra(a);
    if (s == 0) return '-';
    final reparto = repartoSillas(a);
    if (reparto.isEmpty) return s == 1 ? '1 silla extra' : '$s sillas extra';
    return reparto.map((e) => '${e.$1} (+${e.$2})').join(' · ');
  }

  /// Lo que conviene mirar antes de sortear. [pagosPorContrato] permite
  /// detectar pagos a una mesa extra que no figura en la cantidad.
  static List<AvisoSalon> avisos(
    Iterable<ContratoAlumno> alumnos, {
    Map<String, List<Map<String, dynamic>>> pagosPorContrato = const {},
  }) {
    final lista = alumnos.where((a) => !a.esBajaTemporal).toList();
    final habituales = PreciosHabituales.de(lista);
    final out = <AvisoSalon>[];
    void avisar(ContratoAlumno a, TipoAvisoSalon tipo, String detalle) =>
        out.add(
          AvisoSalon(
            alumnoId: a.id,
            alumno: a.nombreAlumno,
            tipo: tipo,
            detalle: detalle,
          ),
        );

    for (final a in lista) {
      final m = mesas(a);

      final um = precioUnitarioMesa(a);
      final hm = habituales.mesaExtra;
      if (um != null && hm != null && (um - hm).abs() > 0.5) {
        avisar(
          a,
          TipoAvisoSalon.precioMesa,
          '${mesasExtra(a)} mesa(s) extra a ${um.toCurrency()} c/u '
          '(lo habitual es ${hm.toCurrency()}): el sorteo le da $m mesas',
        );
      }

      final us = precioUnitarioSilla(a);
      final hs = habituales.sillaExtra;
      if (us != null && hs != null && (us - hs).abs() > 0.5) {
        avisar(
          a,
          TipoAvisoSalon.precioSillas,
          '${a.sillasExtraCantidad} silla(s) extra a ${us.toCurrency()} c/u '
          '(lo habitual es ${hs.toCurrency()})',
        );
      }

      final s = sillasExtra(a);
      if (s > maxSillasExtra(a)) {
        avisar(
          a,
          TipoAvisoSalon.sillasDeMas,
          '$s sillas extra: con $m mesa(s) entran hasta ${maxSillasExtra(a)} '
          '(2 por mesa)',
        );
      }

      final texto = a.numeroMesa?.trim() ?? '';
      final asignadas = MesasExtraUtils.numerosMesaDesdeTexto(texto).length;
      if (texto.isNotEmpty && asignadas == 0) {
        avisar(
          a,
          TipoAvisoSalon.numeroIlegible,
          'Número de mesa "$texto" no se entiende: el sorteo no lo toca',
        );
      } else if (asignadas > 0 && asignadas != m) {
        avisar(
          a,
          TipoAvisoSalon.mesasNoCoinciden,
          asignadas < m
              ? 'Tiene $asignadas mesa(s) asignada(s) y le corresponden $m: el '
                  'sorteo le completa ${m - asignadas} sin mover las suyas'
              : 'Tiene $asignadas mesas asignadas y le corresponden $m: sacale '
                  'la que sobra desde Editar alumno',
        );
      }

      final pagos = pagosPorContrato[a.id];
      if (pagos != null && a.mesaExtraPrecio > 0.01) {
        final segunPagos =
            MesasExtraUtils.inferirCantidadMesasExtraContrato(a, pagos: pagos);
        if (segunPagos > mesasExtra(a)) {
          avisar(
            a,
            TipoAvisoSalon.pagosDeOtraMesa,
            'Tiene pagos de $segunPagos mesas extra pero figura con '
            '${mesasExtra(a)}',
          );
        }
      }

      final oc = ocupacion(a);
      if (!oc.entran) {
        avisar(
          a,
          TipoAvisoSalon.personasNoEntran,
          '${oc.personas} personas para ${oc.asientos} lugares: '
          '${oc.sugerencia}',
        );
      }
    }
    return out;
  }
}
