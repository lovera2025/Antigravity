import 'dart:math' as math;

import '../modelo/armado_salon.dart';
import '../modelo/medidas_salon.dart';

/// Lo que ocupan las mesas de una hoja, con su lugar alrededor.
class OcupaHoja {
  final String hoja;
  final double anchoM;
  final double altoM;

  const OcupaHoja(this.hoja, this.anchoM, this.altoM);

  double get m2 => anchoM * altoM;
}

/// Dos mesas que quedaron más cerca de lo que piden.
class ParApretado {
  final int a;
  final int b;
  final double distanciaM;

  /// El círculo que pide cada una.
  final double lugarA;
  final double lugarB;

  const ParApretado({
    required this.a,
    required this.b,
    required this.distanciaM,
    required this.lugarA,
    required this.lugarB,
  });

  /// De centro a centro, lo que necesitan entre las dos.
  double get pideM => (lugarA + lugarB) / 2;

  double get faltaM => pideM - distanciaM;

  /// A cuál le falta el lugar: la que pide más (la de las sillas extra). Si
  /// piden lo mismo, las dos: están demasiado juntas.
  List<int> get sinLugar {
    if (lugarA > lugarB + MedirSalon.toleranciaM) return [a];
    if (lugarB > lugarA + MedirSalon.toleranciaM) return [b];
    return [a, b];
  }
}

/// Las mesas que no tienen el lugar que piden.
class SinLugar {
  final List<ParApretado> apretadas;
  final List<int> fueraDelHormigon;

  const SinLugar(this.apretadas, this.fueraDelHormigon);

  static const ninguna = SinLugar([], []);

  bool get hay => apretadas.isNotEmpty || fueraDelHormigon.isNotEmpty;

  /// Las mesas a las que les falta lugar: la que pide más de cada par
  /// apretado, y las que salen del hormigón.
  Set<int> get mesas => {
        for (final p in apretadas) ...p.sinLugar,
        ...fueraDelHormigon,
      };
}

/// Las cuentas en metros sobre un armado. Todo se calcula al mostrar: nada de
/// esto se guarda.
class MedirSalon {
  MedirSalon._();

  /// Lo que se tolera antes de avisar: un centímetro.
  static const double toleranciaM = 0.01;

  /// Qué mesas no tienen el lugar que piden, con las medidas de la fiesta y
  /// las sillas extra que lleva cada mesa hoy.
  ///
  /// En un armado del Canva (sin el borde del hormigón) las mesas comunes
  /// están donde las puso el jefe: ahí solo se avisa por las que llevan
  /// sillas extra.
  static SinLugar revisar(
    ArmadoSalon armado,
    MedidasPlano medidas,
    int Function(int numero) sillasExtraDe,
  ) {
    double lugarDe(int n) => medidas.lugarM(sillasExtraDe(n));
    return SinLugar(
      apretadas(
        armado,
        lugarDe,
        soloSiPideMasDe: armado.tieneBorde ? null : medidas.lugarMesaM,
      ),
      fueraDelHormigon(armado, lugarDe),
    );
  }

  /// Por hoja, el rectángulo que ocupan las mesas con un círculo de [lugarM]
  /// alrededor de cada una. Las del pasto no cuentan.
  static List<OcupaHoja> ocupa(ArmadoSalon armado, {required double lugarM}) {
    final r = <OcupaHoja>[];
    for (final h in armado.hojas) {
      final mesas = armado.mesasDeHoja(h.id).where((m) => !m.pasto).toList();
      if (mesas.isEmpty) continue;
      var x0 = double.infinity, x1 = -double.infinity;
      var y0 = double.infinity, y1 = -double.infinity;
      for (final m in mesas) {
        x0 = math.min(x0, m.x);
        x1 = math.max(x1, m.x);
        y0 = math.min(y0, m.y);
        y1 = math.max(y1, m.y);
      }
      r.add(OcupaHoja(
        h.id,
        armado.aMetros(x1 - x0) + lugarM,
        armado.aMetros(y1 - y0) + lugarM,
      ));
    }
    return r;
  }

  static double ocupaM2(ArmadoSalon armado, {required double lugarM}) =>
      ocupa(armado, lugarM: lugarM).fold(0.0, (s, o) => s + o.m2);

  /// Los pares de mesas de una misma hoja que están más cerca de lo que piden
  /// entre las dos: la mitad del lugar de una más la mitad del de la otra.
  ///
  /// Con [soloSiPideMasDe], un par donde ninguna de las dos pide más que eso
  /// no se mira. Es para los armados del Canva: ahí las mesas comunes están
  /// donde las puso el jefe, y solo se avisa cuando una lleva sillas extra.
  static List<ParApretado> apretadas(
    ArmadoSalon armado,
    double Function(int numero) lugarDe, {
    double? soloSiPideMasDe,
  }) {
    final r = <ParApretado>[];
    for (final h in armado.hojas) {
      final mesas = armado.mesasDeHoja(h.id);
      final lugar = [for (final m in mesas) lugarDe(m.numero)];
      for (var i = 0; i < mesas.length; i++) {
        for (var j = i + 1; j < mesas.length; j++) {
          if (soloSiPideMasDe != null &&
              lugar[i] <= soloSiPideMasDe + toleranciaM &&
              lugar[j] <= soloSiPideMasDe + toleranciaM) {
            continue;
          }
          final pide = (lugar[i] + lugar[j]) / 2;
          final d = armado.aMetros(mesas[i].distanciaA(mesas[j]));
          if (d < pide - toleranciaM) {
            r.add(ParApretado(
              a: mesas[i].numero,
              b: mesas[j].numero,
              distanciaM: d,
              lugarA: lugar[i],
              lugarB: lugar[j],
            ));
          }
        }
      }
    }
    return r;
  }

  /// Las mesas cuyo lugar sale del borde del hormigón. Solo en las hojas que
  /// lo tienen dibujado; las del pasto no cuentan.
  static List<int> fueraDelHormigon(
    ArmadoSalon armado,
    double Function(int numero) lugarDe,
  ) {
    final r = <int>[];
    for (final h in armado.hojas) {
      final borde = h.contorno;
      if (borde == null) continue;
      for (final m in armado.mesasDeHoja(h.id)) {
        if (m.pasto) continue;
        final radio = armado.aUnidades(lugarDe(m.numero) / 2);
        if (!borde.contieneCirculo(m.x, m.y, radio)) r.add(m.numero);
      }
    }
    return r;
  }

  static const _largosRegla = [0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0];

  /// La regla que conviene dibujar: el largo redondo más grande que no pasa
  /// de [maxPx] en pantalla.
  static ({double metros, double px}) reglaPara(
    double pxPorUnidad,
    double metrosPorUnidad, {
    double maxPx = 160,
  }) {
    final pxPorMetro = pxPorUnidad / metrosPorUnidad;
    var metros = _largosRegla.first;
    for (final l in _largosRegla) {
      if (l * pxPorMetro <= maxPx) metros = l;
    }
    return (metros: metros, px: metros * pxPorMetro);
  }

  /// "2 m", "2,5 m", "0,5 m": con coma y sin ceros de más.
  static String metros(double m, {int decimales = 1}) {
    final t = m.toStringAsFixed(decimales);
    final limpio = t.contains('.')
        ? t.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
        : t;
    return '${limpio.replaceFirst('.', ',')} m';
  }
}
