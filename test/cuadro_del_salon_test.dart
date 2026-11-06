import 'dart:math' as math;
import 'dart:ui';

import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/totem/services/camino_a_la_mesa.dart';
import 'package:arguello_events/features/totem/services/cuadro_del_salon.dart';
import 'package:flutter_test/flutter_test.dart';

/// La unidad de la escena para una pantalla, como la calcula `EscenaTotem`.
double uDe(Size s) => math.min(s.width, s.height * 9 / 16) / 27;

const vertical = Size(1080, 1920);
const apaisada = Size(1920, 1080);

CuadroDelSalon cuadro(
  ArmadoSalon a,
  Size pantalla, {
  LugarElegido elegido = LugarElegido.automatico,
}) =>
    CuadroDelSalon.para(a, pantalla: pantalla, u: uDe(pantalla), elegido: elegido)!;

/// Dos bloques de mesas separados por un pasillo ancho, sin pista ni sectores.
ArmadoSalon dosBloques() {
  final mesas = <MesaPlano>[];
  var n = 1;
  for (final x0 in [100.0, 1100.0]) {
    for (var f = 0; f < 6; f++) {
      for (var c = 0; c < 4; c++) {
        mesas.add(MesaPlano(numero: n++, hoja: 'A', x: x0 + c * 105, y: 100 + f * 105));
      }
    }
  }
  return ArmadoSalon(
    clave: 'prueba@1',
    nombre: 'Dos bloques',
    hojas: const [HojaPlano(id: 'A', titulo: 'A', caja: RectPlano(40, 40, 1440, 680))],
    mesas: mesas,
  );
}

/// Un salón cuadrado lleno de mesas: no hay hueco ni franja.
ArmadoSalon cuadradoLleno() {
  final mesas = <MesaPlano>[];
  var n = 1;
  for (var f = 0; f < 10; f++) {
    for (var c = 0; c < 10; c++) {
      mesas.add(MesaPlano(numero: n++, hoja: 'A', x: 60 + c * 105, y: 60 + f * 105));
    }
  }
  return ArmadoSalon(
    clave: 'lleno@1',
    nombre: 'Lleno',
    hojas: const [HojaPlano(id: 'A', titulo: 'A', caja: RectPlano(0, 0, 1065, 1065))],
    mesas: mesas,
  );
}

void main() {
  final normal = ArmadosPredefinidos.normal2aPagina3();

  group('automático', () {
    test('en la Normal apaisada, el cuadro va en la pista de baile', () {
      final c = cuadro(normal, apaisada);
      expect(c.lugar, LugarDelCuadro.pista);
      final pista = normal.sectores.firstWhere((s) => s.tipo == TipoSector.pista).caja;
      final s = c.salon.width / normal.hoja('A')!.caja.ancho;
      final enPantalla = Rect.fromLTWH(
        c.salon.left + (pista.x - 80) * s,
        c.salon.top + (pista.y - 250) * s,
        pista.ancho * s,
        pista.alto * s,
      );
      expect(enPantalla.contains(c.cuadro.topLeft), isTrue);
      expect(enPantalla.contains(c.cuadro.bottomRight), isTrue);
      expect(c.alCostado, isFalse);
    });

    test('en la Normal vertical, la pista no alcanza: el cuadro va arriba, '
        'en lo que deja el salón', () {
      final c = cuadro(normal, vertical);
      expect(c.lugar, LugarDelCuadro.franjaLibre);
      expect(c.cuadro.bottom, lessThanOrEqualTo(c.panel.top));
      expect(c.cuadro.width, greaterThan(900));
      expect(c.cuadro.height, greaterThan(900));
      expect(c.alCostado, isFalse);
    });

    test('sin pista, el hueco entre los bloques gana si es lo mejor', () {
      final a = dosBloques();
      // Una tele cuadrada: el salón la llena a lo ancho y deja poco abajo.
      const pantalla = Size(1500, 900);
      final c = cuadro(a, pantalla);
      expect(c.lugar, LugarDelCuadro.hueco);
      // El cuadro no toca ninguna mesa con sus sillas.
      final s = c.salon.width / a.hoja('A')!.caja.ancho;
      final r = a.radio * CaminoALaMesa.conSillas * s;
      for (final m in a.mesas) {
        final centro = Offset(
          c.salon.left + (m.x - 40) * s,
          c.salon.top + (m.y - 40) * s,
        );
        final px = centro.dx.clamp(c.cuadro.left, c.cuadro.right);
        final py = centro.dy.clamp(c.cuadro.top, c.cuadro.bottom);
        expect((Offset(px, py) - centro).distance, greaterThanOrEqualTo(r - 0.01),
            reason: 'la mesa ${m.numero} toca el cuadro');
      }
    });

    test('si nada alcanza, se fuerza una franja y el salón se achica', () {
      final a = cuadradoLleno();
      const pantalla = Size(1000, 1000);
      final c = cuadro(a, pantalla);
      expect(c.lugar, LugarDelCuadro.franjaForzada);
      final u = uDe(pantalla);
      expect(c.cuadro.height, greaterThanOrEqualTo(u * CuadroDelSalon.altoMinimoEnU - 0.01));
      expect(c.cuadro.bottom, lessThanOrEqualTo(c.panel.top));
      // Más chico que si ocupara todo.
      final disponible = 1000 - u * CuadroDelSalon.abajoEnU - u * CuadroDelSalon.margenEnU;
      expect(c.panel.height, lessThan(disponible));
    });

    test('en una apaisada sin lugar, la franja forzada va a la izquierda', () {
      final a = cuadradoLleno();
      final c = cuadro(a, const Size(1200, 700));
      expect(c.lugar, isIn([LugarDelCuadro.franjaLibre, LugarDelCuadro.franjaForzada]));
      expect(c.alCostado, isTrue);
      expect(c.cuadro.right, lessThanOrEqualTo(c.panel.left));
    });
  });

  group('elegido', () {
    test('cada lado deja el cuadro de ese lado, sin pisar el panel', () {
      for (final pantalla in [vertical, apaisada]) {
        for (final lado in [
          LugarElegido.arriba,
          LugarElegido.abajo,
          LugarElegido.izquierda,
          LugarElegido.derecha,
        ]) {
          final c = cuadro(normal, pantalla, elegido: lado);
          final razon = '$lado en $pantalla';
          expect(c.cuadro.overlaps(c.panel), isFalse, reason: razon);
          switch (lado) {
            case LugarElegido.arriba:
              expect(c.cuadro.bottom, lessThanOrEqualTo(c.panel.top), reason: razon);
            case LugarElegido.abajo:
              expect(c.cuadro.top, greaterThanOrEqualTo(c.panel.bottom), reason: razon);
            case LugarElegido.izquierda:
              expect(c.cuadro.right, lessThanOrEqualTo(c.panel.left), reason: razon);
              expect(c.alCostado, isTrue, reason: razon);
            case LugarElegido.derecha:
              expect(c.cuadro.left, greaterThanOrEqualTo(c.panel.right), reason: razon);
              expect(c.alCostado, isTrue, reason: razon);
            case LugarElegido.automatico:
          }
          expect(c.cuadro.width, greaterThan(0), reason: razon);
          expect(c.cuadro.height, greaterThan(0), reason: razon);
        }
      }
    });

    test('la clave se guarda y se lee; una desconocida es automático', () {
      for (final l in LugarElegido.values) {
        expect(LugarElegido.deClave(l.clave), l);
      }
      expect(LugarElegido.automatico.clave, isNull);
      expect(LugarElegido.deClave('cualquiera'), LugarElegido.automatico);
      expect(LugarElegido.deClave('automatico'), LugarElegido.automatico);
      expect(LugarElegido.deClave(null), LugarElegido.automatico);
    });
  });

  group('las medidas', () {
    test('el radio en pantalla es el de la mesa por la escala del salón', () {
      final c = cuadro(normal, apaisada);
      expect(c.radioPx, closeTo(normal.radio * c.salon.width / 1760, 1e-9));
      expect(c.salon.width / c.salon.height, closeTo(1760 / 1230, 1e-6));
    });

    test('todo queda dentro de la pantalla y arriba de "N más en camino"', () {
      for (final pantalla in [vertical, apaisada, const Size(360, 640), const Size(640, 360)]) {
        final u = uDe(pantalla);
        final c = cuadro(normal, pantalla);
        final abajo = pantalla.height - u * CuadroDelSalon.abajoEnU + 0.01;
        expect(c.panel.left, greaterThanOrEqualTo(-0.01));
        expect(c.panel.right, lessThanOrEqualTo(pantalla.width + 0.01));
        expect(c.panel.bottom, lessThanOrEqualTo(abajo), reason: '$pantalla');
        expect(c.cuadro.bottom, lessThanOrEqualTo(abajo), reason: '$pantalla');
      }
    });

    test('lo mismo da lo mismo', () {
      expect(cuadro(normal, vertical), cuadro(normal, vertical));
      expect(cuadro(normal, vertical) == cuadro(normal, apaisada), isFalse);
    });
  });

  group('la hoja', () {
    test('se muestra la del ingreso, aunque tenga menos mesas', () {
      final a = ArmadoSalon(
        clave: 'x@1',
        nombre: 'x',
        hojas: const [
          HojaPlano(id: 'A', titulo: 'A', caja: RectPlano(0, 0, 500, 500)),
          HojaPlano(id: 'B', titulo: 'B', caja: RectPlano(0, 0, 500, 500)),
        ],
        mesas: const [
          MesaPlano(numero: 1, hoja: 'A', x: 100, y: 100),
          MesaPlano(numero: 2, hoja: 'A', x: 300, y: 100),
          MesaPlano(numero: 3, hoja: 'B', x: 100, y: 100),
        ],
        sectores: const [
          SectorPlano(
            tipo: TipoSector.ingreso,
            texto: 'Ingreso',
            hoja: 'B',
            caja: RectPlano(200, 400, 100, 50),
          ),
        ],
      );
      expect(CuadroDelSalon.hojaPrincipal(a), 'B');
    });

    test('sin ingreso, la de más mesas', () {
      final a = ArmadoSalon(
        clave: 'x@1',
        nombre: 'x',
        hojas: const [
          HojaPlano(id: 'A', titulo: 'A', caja: RectPlano(0, 0, 500, 500)),
          HojaPlano(id: 'B', titulo: 'B', caja: RectPlano(0, 0, 500, 500)),
        ],
        mesas: const [
          MesaPlano(numero: 1, hoja: 'A', x: 100, y: 100),
          MesaPlano(numero: 2, hoja: 'B', x: 100, y: 100),
          MesaPlano(numero: 3, hoja: 'B', x: 300, y: 100),
        ],
      );
      expect(CuadroDelSalon.hojaPrincipal(a), 'B');
    });
  });

  group('sin qué mostrar', () {
    test('sin plano o sin mesas, null', () {
      expect(CuadroDelSalon.para(null, pantalla: vertical, u: 40), isNull);
      final vacio = ArmadoSalon(
        clave: 'vacio@1',
        nombre: 'Salón vacío',
        hojas: const [HojaPlano(id: 'A', titulo: 'A', caja: RectPlano(0, 0, 900, 600))],
        mesas: const [],
      );
      expect(CuadroDelSalon.para(vacio, pantalla: vertical, u: 40), isNull);
    });

    test('una pantalla sin tamaño no rompe', () {
      expect(CuadroDelSalon.para(normal, pantalla: Size.zero, u: 0), isNull);
      expect(CuadroDelSalon.para(normal, pantalla: const Size(10, 10), u: 0.3), isNotNull);
    });
  });
}
