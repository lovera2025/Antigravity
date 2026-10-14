// El camino que dibuja el tótem desde el ingreso hasta la mesa de la familia
// (`CaminoALaMesa`, paso 4b de la 6.0.0): por los pasillos, sin pisar otras
// mesas ni el escenario o las barras, y hasta el borde de la mesa.
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/totem/services/camino_a_la_mesa.dart';
import 'package:arguello_events/features/totem/services/plano_de_la_llegada.dart';

const _caja = RectPlano(0, 0, 1000, 600);

ArmadoSalon _salon({
  required List<MesaPlano> mesas,
  List<SectorPlano> sectores = const [],
  PuntoPlano? ingreso,
  List<HojaPlano> hojas = const [HojaPlano(id: 'A', titulo: 'A', caja: _caja)],
}) =>
    ArmadoSalon(
      clave: 'prueba',
      nombre: 'Prueba',
      hojas: hojas,
      mesas: mesas,
      sectores: sectores,
      ingreso: ingreso,
    );

MesaPlano _mesa(int n, double x, double y, {String hoja = 'A'}) =>
    MesaPlano(numero: n, hoja: hoja, x: x, y: y);

/// La distancia de [p] al tramo de [a] a [b].
double _alTramo(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final largo2 = ab.distanceSquared;
  if (largo2 == 0) return (p - a).distance;
  final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / largo2).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

/// Ningún tramo pasa por arriba de otra mesa de la hoja.
void _noPisaMesas(List<Offset> ruta, ArmadoSalon armado, int destino) {
  final hoja = armado.mesa(destino)!.hoja;
  for (var i = 1; i < ruta.length; i++) {
    for (final m in armado.mesasDeHoja(hoja)) {
      if (m.numero == destino) continue;
      expect(
        _alTramo(Offset(m.x, m.y), ruta[i - 1], ruta[i]),
        greaterThanOrEqualTo(armado.radio),
        reason: 'el tramo $i a la mesa $destino pisa la mesa ${m.numero}',
      );
    }
  }
}

void _terminaEnElBorde(List<Offset> ruta, ArmadoSalon armado, int destino) {
  final m = armado.mesa(destino)!;
  expect(
    (ruta.last - Offset(m.x, m.y)).distance,
    moreOrLessEquals(armado.radio * CaminoALaMesa.alBorde, epsilon: 0.5),
  );
}

void main() {
  group('de dónde sale', () {
    test('del ingreso del armado, si está en esa hoja', () {
      final a = _salon(
        mesas: [_mesa(1, 800, 300)],
        ingreso: const PuntoPlano('A', 100, 50),
      );
      expect(CaminoALaMesa.ingresoEn(a, 'A'), const Offset(100, 50));
    });

    test('si no, del sector "Ingreso" de la hoja', () {
      final a = _salon(
        mesas: [_mesa(1, 800, 300)],
        ingreso: const PuntoPlano('B', 100, 50),
        sectores: const [
          SectorPlano(
            tipo: TipoSector.ingreso,
            texto: 'Ingreso',
            hoja: 'A',
            caja: RectPlano(20, 20, 100, 40),
          ),
        ],
      );
      expect(CaminoALaMesa.ingresoEn(a, 'A'), const Offset(70, 40));
    });

    test('sin ingreso no hay camino, y la mesa igual se marca', () {
      final a = _salon(mesas: [_mesa(1, 800, 300)]);
      expect(CaminoALaMesa.ingresoEn(a, 'A'), isNull);
      expect(CaminoALaMesa.trazar(a, 1), isNull);
      final g = PlanoDeLaLlegada.para(a, mesa: '1', nombre: 'X')!;
      expect(g.ruta, isNull);
      expect(g.mesas, {1});
    });

    test('con el ingreso en otra hoja, esa mesa va sin camino', () {
      final a = _salon(
        hojas: const [
          HojaPlano(id: 'A', titulo: 'A', caja: _caja),
          HojaPlano(id: 'B', titulo: 'B', caja: _caja),
        ],
        mesas: [_mesa(1, 800, 300), _mesa(2, 800, 300, hoja: 'B')],
        ingreso: const PuntoPlano('A', 100, 300),
      );
      expect(CaminoALaMesa.trazar(a, 1), isNotNull);
      expect(CaminoALaMesa.trazar(a, 2), isNull);
    });
  });

  test('sin nada en el medio, derecho hasta el borde de la mesa', () {
    final a = _salon(
      mesas: [_mesa(1, 800, 300)],
      ingreso: const PuntoPlano('A', 100, 300),
    );
    final ruta = CaminoALaMesa.trazar(a, 1)!;
    expect(ruta, hasLength(2));
    expect(ruta.first, const Offset(100, 300));
    _terminaEnElBorde(ruta, a, 1);
  });

  test('sale del borde del cartel del ingreso, sin tacharlo', () {
    const cartel = RectPlano(60, 260, 120, 80);
    final a = _salon(
      mesas: [_mesa(1, 800, 300)],
      sectores: const [
        SectorPlano(
          tipo: TipoSector.ingreso,
          texto: 'Ingreso',
          hoja: 'A',
          caja: cartel,
        ),
      ],
    );
    final ruta = CaminoALaMesa.trazar(a, 1)!;
    expect(ruta.first.dx, moreOrLessEquals(cartel.derecha, epsilon: 0.5));
    expect(ruta.first.dy, moreOrLessEquals(300, epsilon: 0.5));
    _terminaEnElBorde(ruta, a, 1);
  });

  test('esquiva una mesa puesta en el medio', () {
    final a = _salon(
      mesas: [_mesa(1, 800, 300), _mesa(2, 450, 300)],
      ingreso: const PuntoPlano('A', 100, 300),
    );
    final ruta = CaminoALaMesa.trazar(a, 1)!;
    expect(ruta.length, greaterThanOrEqualTo(3));
    _noPisaMesas(ruta, a, 1);
    _terminaEnElBorde(ruta, a, 1);
  });

  test('rodea una barra y no la pisa', () {
    const barra = RectPlano(430, 60, 60, 480);
    final a = _salon(
      mesas: [_mesa(1, 800, 300)],
      ingreso: const PuntoPlano('A', 100, 300),
      sectores: const [
        SectorPlano(tipo: TipoSector.barra, texto: 'Barra', hoja: 'A', caja: barra),
      ],
    );
    final ruta = CaminoALaMesa.trazar(a, 1)!;
    final rect = Rect.fromLTWH(barra.x, barra.y, barra.ancho, barra.alto);
    for (var i = 1; i < ruta.length; i++) {
      for (var k = 0; k <= 50; k++) {
        final p = Offset.lerp(ruta[i - 1], ruta[i], k / 50)!;
        expect(rect.contains(p), isFalse, reason: 'tramo $i pisa la barra');
      }
    }
  });

  test('la pista se cruza: no tapa', () {
    final a = _salon(
      mesas: [_mesa(1, 800, 300)],
      ingreso: const PuntoPlano('A', 100, 300),
      sectores: const [
        SectorPlano(
          tipo: TipoSector.pista,
          texto: 'Pista',
          hoja: 'A',
          caja: RectPlano(300, 150, 300, 300),
        ),
      ],
    );
    expect(CaminoALaMesa.trazar(a, 1), hasLength(2));
  });

  test('si no hay paso, en línea recta', () {
    // La mesa 1, rodeada de mesas pegadas: no se puede llegar sin pisarlas.
    final a = _salon(
      mesas: [
        _mesa(1, 700, 300),
        for (var i = 0; i < 8; i++)
          _mesa(
            2 + i,
            700 + 76 * math.cos(i * math.pi / 4),
            300 + 76 * math.sin(i * math.pi / 4),
          ),
      ],
      ingreso: const PuntoPlano('A', 100, 300),
    );
    final ruta = CaminoALaMesa.trazar(a, 1)!;
    expect(ruta, hasLength(2));
    _terminaEnElBorde(ruta, a, 1);
  });

  test('en el salón de la Normal, a cada mesa sin pisar otra', () {
    final a = ArmadosPredefinidos.normal2aPagina3();
    for (final m in a.mesas) {
      final ruta = CaminoALaMesa.trazar(a, m.numero);
      expect(ruta, isNotNull, reason: '${m.numero}');
      _noPisaMesas(ruta!, a, m.numero);
      _terminaEnElBorde(ruta, a, m.numero);
    }
  });

  test('en un playón de 284 mesas, rápido', () {
    final armado = ArmarAMedida.armar(
      const OpcionesAMedida(
        playon: PlayonReal.costaSurubi,
        cantidad: 284,
        lugarM: 2,
      ),
    ).armado;
    final h = armado.hojas.first;
    final a = armado.copyWith(sectores: [
      ...armado.sectores,
      SectorPlano(
        tipo: TipoSector.ingreso,
        texto: 'Ingreso',
        hoja: h.id,
        caja: RectPlano(h.caja.x, h.caja.y, 60, 30),
      ),
    ]);
    final ultima = a.mesas.last.numero;
    final reloj = Stopwatch()..start();
    final ruta = CaminoALaMesa.trazar(a, ultima);
    reloj.stop();
    expect(ruta, isNotNull);
    _terminaEnElBorde(ruta!, a, ultima);
    expect(reloj.elapsedMilliseconds, lessThan(500));
  });
}
