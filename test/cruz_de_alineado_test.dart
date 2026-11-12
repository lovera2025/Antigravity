// La cruz para alinear (6.7.1): mientras se arrastra una mesa o un sector en
// Acomodar, dos líneas por su medio, verdes cuando queda en línea con otra
// cosa. Y lo arrastrado queda justo en la línea cuando está a menos de medio
// paso.
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/services/cruz_de_alineado.dart';
import 'package:arguello_events/features/plano/services/editar_armado.dart';
import 'package:arguello_events/features/plano/services/sesion_acomodo.dart';

import 'helpers/salon_de_prueba.dart';

/// El salón de prueba (escenario al medio arriba, pasarela al medio) con una
/// barra corrida: su medio está en (81,3; 91).
ArmadoSalon _salon() {
  final base = salonDePrueba();
  return ArmadoSalon(
    clave: base.clave,
    nombre: base.nombre,
    radio: base.radio,
    hojas: base.hojas,
    mesas: base.mesas,
    sectores: [
      ...base.sectores,
      const SectorPlano(
        tipo: TipoSector.barra,
        texto: 'Barra',
        hoja: 'A',
        caja: RectPlano(71.3, 86, 20, 10),
      ),
    ],
  );
}

void main() {
  // En el salón de prueba: 0 escenario (medio 50; 4), 1 pasarela (medio 50; 38),
  // 2 la barra.
  const barra = 2;

  group('la cruz', () {
    test('pasa por el medio de lo que se arrastra', () {
      final c = CruzDeAlineado.de(_salon(), sector: barra)!;
      expect(c.hoja, 'A');
      expect(c.x, closeTo(81.3, 1e-9));
      expect(c.y, closeTo(91, 1e-9));
      expect(c.enLineaX, isFalse);
      expect(c.enLineaY, isFalse);
    });

    test('se pone verde cuando queda en línea con el medio de otro sector',
        () {
      final a = EditarArmado.moverSector(_salon(), barra, 40, 86,
          ajustar: false);
      final c = CruzDeAlineado.de(a, sector: barra)!;
      // El medio de la barra quedó en x = 50, como el escenario y la pasarela.
      expect(c.enLineaX, isTrue);
      expect(c.enLineaY, isFalse);
    });

    test('y con el medio del playón, si la hoja trae su borde', () {
      // Un playón en trapecio: de 10 a 90 a lo ancho y de 0 a 110 a lo largo.
      // Su medio está en (50; 55).
      final base = _salon();
      final conBorde = ArmadoSalon(
        clave: base.clave,
        nombre: base.nombre,
        radio: base.radio,
        hojas: [
          base.hojas.first.copyWith(
            contorno: const ContornoPlano([
              (x: 20, y: 0),
              (x: 80, y: 0),
              (x: 90, y: 110),
              (x: 10, y: 110),
            ]),
          ),
        ],
        mesas: base.mesas,
        sectores: base.sectores,
      );
      final a = EditarArmado.moverSector(conBorde, barra, 71.3, 50,
          ajustar: false);
      expect(CruzDeAlineado.de(a, sector: barra)!.enLineaY, isTrue);
      // Sin el borde no hay un medio que valga: la hoja crece al arrastrar.
      final sinBorde = EditarArmado.moverSector(_salon(), barra, 71.3, 50,
          ajustar: false);
      expect(CruzDeAlineado.de(sinBorde, sector: barra)!.enLineaY, isFalse);
    });

    test('un sector no se alinea con las mesas; una mesa, sí', () {
      // La barra con su medio en y = 20, la fila de las mesas 1 a 4.
      final a = EditarArmado.moverSector(_salon(), barra, 71.3, 15,
          ajustar: false);
      expect(CruzDeAlineado.de(a, sector: barra)!.enLineaY, isFalse);
      // La mesa 1 está en la fila de la 2 y en la columna de la 8.
      final m = CruzDeAlineado.de(_salon(), mesa: 1)!;
      expect(m.enLineaX, isTrue);
      expect(m.enLineaY, isTrue);
    });

    test('lo que no existe no tiene cruz', () {
      expect(CruzDeAlineado.de(_salon(), mesa: 99), isNull);
      expect(CruzDeAlineado.de(_salon(), sector: 9), isNull);
      expect(CruzDeAlineado.de(_salon()), isNull);
    });
  });

  group('lo que falta para quedar en línea', () {
    test('cerca de la línea, dice cuánto; lejos, nada', () {
      // El medio de la barra a 0,3 del medio del escenario.
      final a = EditarArmado.moverSector(_salon(), barra, 40.3, 86,
          ajustar: false);
      final cerca = CruzDeAlineado.loQueFalta(a, sector: barra, margen: 0.5);
      expect(cerca.dx, closeTo(-0.3, 1e-9));
      expect(cerca.dy, 0);
      final lejos = CruzDeAlineado.loQueFalta(a, sector: barra, margen: 0.2);
      expect(lejos.dx, 0);
    });
  });

  group('arrastrando en Acomodar', () {
    SesionAcomodo sesion() => SesionAcomodo(base: _salon());

    test('mientras se arrastra hay cruz, y al soltar se va', () {
      final s = sesion();
      expect(s.cruz, isNull);
      s.empezarArrastre();
      s.arrastrarSector(barra, 60, 86);
      expect(s.cruz, isNotNull);
      s.terminarArrastre();
      expect(s.cruz, isNull);
    });

    test('cerca de la línea del escenario, queda justo en línea', () {
      final s = sesion();
      final a = s.actual;
      // Un cuarto de metro, en unidades del plano.
      final paso = a.aUnidades(EditarArmado.ajusteM);
      s.empezarArrastre();
      // De a un cuarto de metro desde 71,3 no se llega justo a 40; el medio
      // quedaría a menos de medio paso del medio del escenario.
      final pasos = ((40 - 71.3) / paso).round();
      s.arrastrarSector(barra, 71.3 + pasos * paso, 86);
      final caja = s.actual.sectores[barra].caja;
      expect(caja.centroX, closeTo(50, 1e-9));
      expect(s.cruz!.enLineaX, isTrue);
      s.terminarArrastre();
      expect(s.actual.sectores[barra].caja.centroX, closeTo(50, 1e-9));
    });

    test('lejos de toda línea, se mueve como siempre', () {
      final s = sesion();
      final paso = s.actual.aUnidades(EditarArmado.ajusteM);
      s.empezarArrastre();
      s.arrastrarSector(barra, 71.3 - 8 * paso, 86);
      expect(s.actual.sectores[barra].caja.x, closeTo(71.3 - 8 * paso, 1e-9));
      expect(s.cruz!.enLineaX, isFalse);
    });

    test('una mesa arrastrada queda en la fila de las otras', () {
      final s = sesion();
      final paso = s.actual.aUnidades(EditarArmado.ajusteM);
      s.empezarArrastre();
      // La mesa 9 (10; 60), hacia la fila de la 8 (y = 40): de a un cuarto de
      // metro no cae justo ahí, pero queda a menos de medio paso.
      final pasos = ((40 - 60) / paso).round();
      s.arrastrarMesa(9, 10, 60 + pasos * paso);
      final m = s.actual.mesa(9)!;
      expect(m.y, closeTo(40, 1e-9));
      expect(s.cruz!.enLineaY, isTrue);
    });
  });
}
