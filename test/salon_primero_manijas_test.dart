import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/editar_armado.dart';
import 'package:arguello_events/features/plano/services/manijas.dart';
import 'package:arguello_events/features/plano/services/sesion_acomodo.dart';
import 'package:arguello_events/models/plano_evento.dart';

/// Las manijas del salón primero (6.1.0, etapa 3 de
/// `docs/PLAN_SALON_PRIMERO_2026-10-16.md`), sin pantalla: dónde van, cuál hay
/// bajo el dedo, y lo que hace la sesión de Acomodar al arrastrarlas. También
/// que el salón vacío se pueda guardar y que las medidas sigan al playón.
void main() {
  const surubi = PlayonReal.costaSurubi;
  final vacio = ArmarAMedida.vacio(surubi);

  int escenarioDe(ArmadoSalon a) =>
      a.sectores.indexWhere((s) => s.tipo == TipoSector.escenario);

  /// Ancho y fondo de un sector, en metros redondos a 1 cm.
  (double, double) mide(ArmadoSalon a, int i) {
    double cm(double v) => (v * 100).round() / 100;
    final c = a.sectores[i].caja;
    return (cm(a.aMetros(c.ancho)), cm(a.aMetros(c.alto)));
  }

  /// Frente, fondo y profundidad del playón, en metros redondos a 1 cm.
  (double, double, double) playon(ArmadoSalon a) {
    double cm(double v) => (v * 100).round() / 100;
    final p = ArmarAMedida.playonDe(a)!;
    return (cm(p.frenteM), cm(p.fondoM), cm(p.profundidadM));
  }

  group('dónde van', () {
    test('las de un sector: las esquinas y el medio de cada lado', () {
      final m = ManijasPlano.deSector(const RectPlano(10, 20, 100, 40));
      expect(m.length, 8);
      expect(m[Manija.no], const Offset(10, 20));
      expect(m[Manija.n], const Offset(60, 20));
      expect(m[Manija.e], const Offset(110, 40));
      expect(m[Manija.se], const Offset(110, 60));
      expect(m[Manija.o], const Offset(10, 40));
    });

    test('las del playón: sus cuatro esquinas, el medio de cada lado y el '
        'centro', () {
      final c = vacio.hojas.first.contorno!;
      final m = ManijasPlano.dePlayon(c)!;
      final p = c.puntos;
      expect(m[Manija.no], Offset(p[0].x, p[0].y));
      expect(m[Manija.ne], Offset(p[1].x, p[1].y));
      expect(m[Manija.se], Offset(p[2].x, p[2].y));
      expect(m[Manija.so], Offset(p[3].x, p[3].y));
      expect(m[Manija.s]!.dy, p[2].y);
      expect(m[Manija.s]!.dx, closeTo((p[2].x + p[3].x) / 2, 1e-9));
      final centro = ManijasPlano.centroPlayon(c)!;
      expect(centro.dx, closeTo((p[0].x + p[1].x + p[2].x + p[3].x) / 4, 1e-9));
    });

    test('un armado del Canva no tiene playón para tocar', () {
      expect(ManijasPlano.dePlayon(null), isNull);
      expect(ManijasPlano.centroPlayon(null), isNull);
      expect(
        ManijasPlano.dePlayon(const ContornoPlano([
          (x: 0, y: 0),
          (x: 10, y: 0),
          (x: 5, y: 10),
        ])),
        isNull,
      );
    });

    test('bajo el dedo: la más cercana, y ninguna si está lejos', () {
      final m = ManijasPlano.deSector(const RectPlano(0, 0, 100, 40));
      expect(ManijasPlano.en(m, const Offset(98, 21), 5), Manija.e);
      expect(ManijasPlano.en(m, const Offset(97, 3), 5), Manija.ne);
      expect(ManijasPlano.en(m, const Offset(50, 20), 5), isNull);
    });
  });

  group('la sesión de Acomodar', () {
    test('estirar un lado: de a medio metro, y un arrastre es un paso de '
        'Deshacer', () {
      final s = SesionAcomodo(base: vacio);
      final i = escenarioDe(vacio);
      final (ancho, alto) = mide(vacio, i);
      s.empezarArrastre();
      s.estirarSector(i, Manija.e, 0.6, 3);
      s.estirarSector(i, Manija.e, 1.2, 3);
      s.terminarArrastre();
      // 1,2 m cae en 1 m; la manija del este no cambia el fondo.
      expect(mide(s.actual, i), (ancho + 1, alto));
      expect(s.actual.sectores[i].caja.x, vacio.sectores[i].caja.x);
      expect(s.hayCambios, isTrue);
      s.deshacer();
      expect(mide(s.actual, i), (ancho, alto));
      expect(s.puedeDeshacer, isFalse);
    });

    test('una esquina estira los dos lados, y el de enfrente queda quieto', () {
      final s = SesionAcomodo(base: vacio);
      final i = escenarioDe(vacio);
      final (ancho, alto) = mide(vacio, i);
      final antes = vacio.sectores[i].caja;
      s.empezarArrastre();
      s.estirarSector(i, Manija.so, -2, 1);
      s.terminarArrastre();
      final c = s.actual.sectores[i].caja;
      expect(mide(s.actual, i), (ancho + 2, alto + 1));
      expect(c.derecha, closeTo(antes.derecha, 1e-9));
      expect(c.y, closeTo(antes.y, 1e-9));
    });

    test('apretar y soltar sin moverse no deja nada para deshacer', () {
      final s = SesionAcomodo(base: vacio);
      s.empezarArrastre();
      s.estirarSector(escenarioDe(vacio), Manija.e, 0.1, 0.1);
      s.terminarArrastre();
      expect(s.hayCambios, isFalse);
      expect(s.puedeDeshacer, isFalse);
    });

    test('el playón: un lado lo estira entero, una esquina corre ese punto', () {
      final s = SesionAcomodo(base: vacio);
      s.empezarArrastre();
      s.estirarPlayon('A', Manija.s, 0, 2);
      s.terminarArrastre();
      expect(playon(s.actual), (30.0, 46.0, 41.0));

      s.empezarArrastre();
      s.estirarPlayon('A', Manija.ne, 3, 0);
      s.terminarArrastre();
      final p = s.actual.hojas.first.contorno!.puntos;
      expect(p[1].x - p[0].x, closeTo(s.actual.aUnidades(33), 1e-6));
      // El fondo no se tocó.
      expect(playon(s.actual).$2, 46.0);
      s.deshacer();
      expect(playon(s.actual), (30.0, 46.0, 41.0));
    });

    test('la manija del medio corre el playón entero, sin mover los sectores',
        () {
      final s = SesionAcomodo(base: vacio);
      final antes = vacio.hojas.first.contorno!.puntos;
      s.empezarArrastre();
      s.moverPlayon('A', 3.2, -1);
      s.terminarArrastre();
      final ahora = s.actual.hojas.first.contorno!.puntos;
      for (var k = 0; k < 4; k++) {
        // 3,2 m cae en 3 m.
        expect(ahora[k].x - antes[k].x, closeTo(s.actual.aUnidades(3), 1e-6));
        expect(ahora[k].y - antes[k].y, closeTo(s.actual.aUnidades(-1), 1e-6));
      }
      expect(playon(s.actual), playon(vacio));
      for (var k = 0; k < vacio.sectores.length; k++) {
        expect(s.actual.sectores[k].caja, vacio.sectores[k].caja);
      }
    });
  });

  group('guardar el salón vacío', () {
    test('armado sin mesas, se puede guardar', () {
      final s = SesionAcomodo(base: vacio);
      s.empezarArrastre();
      s.estirarSector(escenarioDe(vacio), Manija.e, 2, 0);
      s.terminarArrastre();
      expect(s.bloqueos, isEmpty);
      expect(s.puedeGuardar, isTrue);
      expect(EditarArmado.bloqueos(s.actual), isEmpty);
    });

    // Etapa 4: VACIAR EL SALÓN es justamente eso. Lo que no se hace sin mesas
    // es sortear.
    test('un salón con mesas que se queda sin ninguna, también', () {
      final conMesas = ArmarAMedida.armar(
        const OpcionesAMedida(playon: surubi, cantidad: 3),
      ).armado;
      final s = SesionAcomodo(base: conMesas);
      for (final n in conMesas.numeros) {
        s.sacar(n);
      }
      expect(s.bloqueos, isEmpty);
      expect(s.puedeGuardar, isTrue);
    });

    test('paraGuardar lo deja pasar', () {
      final nuevo = EditarArmado.estirarSector(
        vacio,
        escenarioDe(vacio),
        Manija.e,
        2,
        0,
      );
      final r = EditarArmado.paraGuardar(
        base: vacio,
        nuevo: nuevo,
        fresco: vacio,
        config: ConfigPlano.vacia,
        alumnos: const [],
        enUsoVisto: const {},
      );
      expect(r.sePuede, isTrue);
      expect(r.armado!.mesas, isEmpty);
      // El playón no se tocó: las medidas quedan como estaban.
      expect(identical(r.config, ConfigPlano.vacia), isTrue);
    });
  });

  group('el borde parejo o a mano', () {
    test('el salón vacío, "A medida" y el estirado de un lado entero, parejos',
        () {
      expect(ArmarAMedida.esParejo(vacio), isTrue);
      expect(
        ArmarAMedida.esParejo(ArmarAMedida.armar(
          const OpcionesAMedida(playon: surubi, cantidad: 132),
        ).armado),
        isTrue,
      );
      expect(
        ArmarAMedida.esParejo(
            EditarArmado.estirarPlayon(vacio, 'A', Manija.s, 0, 3)),
        isTrue,
      );
      expect(
        ArmarAMedida.esParejo(EditarArmado.moverPlayon(vacio, 'A', 2, 2)),
        isTrue,
      );
    });

    test('una esquina corrida, a mano; un costado entero sigue parejo', () {
      expect(
        ArmarAMedida.esParejo(
            EditarArmado.estirarPlayon(vacio, 'A', Manija.ne, 0, 2)),
        isFalse,
      );
      expect(
        ArmarAMedida.esParejo(
            EditarArmado.estirarPlayon(vacio, 'A', Manija.se, 2, 0)),
        isFalse,
      );
      // Correr el costado del este agranda el frente y el fondo lo mismo: el
      // trapecio sigue parejo, más ancho.
      expect(
        ArmarAMedida.esParejo(
            EditarArmado.estirarPlayon(vacio, 'A', Manija.e, 2, 0)),
        isTrue,
      );
    });
  });

  group('las medidas siguen al playón', () {
    ConfigPlano guardar(ArmadoSalon nuevo, {ConfigPlano? config}) =>
        EditarArmado.paraGuardar(
          base: vacio,
          nuevo: nuevo,
          fresco: vacio,
          config: config ?? ConfigPlano.vacia,
          alumnos: const [],
          enUsoVisto: const {},
        ).config!;

    test('cambiado con las manijas, se guardan sus medidas, aproximadas si lo '
        'eran', () {
      final c = guardar(EditarArmado.estirarPlayon(vacio, 'A', Manija.s, 0, 2));
      expect(c.medidas.playon.frenteM, 30);
      expect(c.medidas.playon.fondoM, 46);
      expect(c.medidas.playon.profundidadM, 41);
      expect(c.medidas.playon.aproximado, isTrue);
      // Lo demás de las medidas no cambia.
      expect(c.medidas.lugarMesaM, const MedidasPlano().lugarMesaM);
    });

    test('medido con cinta, sigue sin "aproximado"', () {
      const cinta = MedidasPlano(
        playon: PlayonReal(frenteM: 30, fondoM: 46, profundidadM: 39),
      );
      final c = guardar(
        EditarArmado.estirarPlayon(vacio, 'A', Manija.e, 1, 0),
        config: const ConfigPlano(medidas: cinta),
      );
      expect(c.medidas.playon.frenteM, 31);
      expect(c.medidas.playon.fondoM, 47);
      expect(c.medidas.playon.aproximado, isFalse);
    });

    test('movido entero, las medidas no cambian', () {
      final c = guardar(EditarArmado.moverPlayon(vacio, 'A', 4, 2));
      expect(identical(c, ConfigPlano.vacia), isTrue);
    });

    test('con un lado de menos de 5 m no se tocan: volverían a las de fábrica',
        () {
      final angosto =
          EditarArmado.estirarPlayon(vacio, 'A', Manija.n, 0, 36);
      expect(playon(angosto).$3, lessThan(PlayonReal.ladoMinimoM));
      expect(identical(guardar(angosto), ConfigPlano.vacia), isTrue);
    });
  });
}
