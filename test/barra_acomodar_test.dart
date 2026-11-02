// La barra de Acomodar (etapa 4 de docs/PLAN_NUMEROS_EN_ORDEN_2026-10-29.md): antes
// del sorteo reacomoda en vivo, después estira sin cambiar ninguna mesa.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/editar_armado.dart';
import 'package:arguello_events/features/plano/services/sesion_acomodo.dart';
import 'package:arguello_events/models/plano_evento.dart';

import 'helpers/salon_puerto_viejo.dart';

List<String> _mesaPorMesa(ArmadoSalon a) => [
      for (final m in a.mesas) '${m.numero} ${m.hoja} ${m.x} ${m.y}',
    ];

double _aRect(RectPlano r, MesaPlano m) {
  final dx = max(max(r.x - m.x, 0.0), m.x - r.derecha);
  final dy = max(max(r.y - m.y, 0.0), m.y - r.abajo);
  return sqrt(dx * dx + dy * dy);
}

void main() {
  final puertoViejo = armadoDePuertoViejo();

  /// Puerto Viejo al soltar la barra en [lugarM].
  SesionAcomodo aDistancia(double lugarM, {int cantidad = 35}) {
    final s = SesionAcomodo(base: puertoViejo);
    s.moverLaBarra(cantidad, lugarM);
    s.soltarLaBarra();
    return s;
  }

  group('antes del sorteo', () {
    test('reacomoda en vivo: ninguna mesa sobre un sector ni fuera del hormigón',
        () {
      final s = SesionAcomodo(base: puertoViejo);
      expect(s.barraReacomoda, isTrue);
      for (final lugar in [2.0, 2.5, 3.0, 3.5]) {
        final r = s.moverLaBarra(35, lugar)!;
        expect(r.faltan, 0, reason: 'a $lugar m');
        final a = s.actual;
        expect(a.numeros, [for (var n = 1; n <= 35; n++) n]);
        final borde = a.hojas.first.contorno!;
        for (final m in a.mesas) {
          expect(borde.contieneCirculo(m.x, m.y, a.radio), isTrue,
              reason: 'a $lugar m, la ${m.numero} se sale del hormigón');
          for (final x in a.sectores) {
            expect(_aRect(x.caja, m), greaterThanOrEqualTo(a.radio - 1e-6),
                reason: 'a $lugar m, la ${m.numero} pisa ${x.texto}');
          }
        }
      }
      s.soltarLaBarra();
    });

    test('numeradas en serpentina: ordenar no cambia nada', () {
      for (final lugar in [2.0, 2.5, 3.0]) {
        final a = aDistancia(lugar).actual;
        expect(ArmarAMedida.ordenarNumeros(a).cambio, isEmpty, reason: '$lugar');
      }
    });

    test('arrastrar sin soltar no agrega pasos; soltar agrega uno; Deshacer vuelve',
        () {
      final s = SesionAcomodo(base: puertoViejo);
      expect(s.puedeDeshacer, isFalse);
      s.moverLaBarra(35, 2.2);
      s.moverLaBarra(35, 2.4);
      s.moverLaBarra(35, 2.6);
      expect(s.moviendoLaBarra, isTrue);
      expect(s.puedeDeshacer, isFalse);
      expect(s.puedeGuardar, isFalse, reason: 'en el medio de un arrastre');
      s.soltarLaBarra();
      expect(s.moviendoLaBarra, isFalse);
      expect(s.puedeDeshacer, isTrue);
      expect(s.rehecho, isTrue);
      expect(s.lugarDeLaBarra, 2.6);
      expect(s.puedeGuardar, isTrue);

      s.deshacer();
      expect(s.puedeDeshacer, isFalse);
      expect(_mesaPorMesa(s.actual), _mesaPorMesa(puertoViejo));
      expect(s.rehecho, isFalse);
      expect(s.lugarDeLaBarra, isNull);
    });

    test('dos soltadas son dos pasos', () {
      final s = aDistancia(2.5);
      final a25 = _mesaPorMesa(s.actual);
      s.moverLaBarra(35, 3.0);
      s.soltarLaBarra();
      s.deshacer();
      expect(_mesaPorMesa(s.actual), a25);
      expect(s.lugarDeLaBarra, 2.5);
    });

    test('siempre cuenta desde lo que había al apretar, no desde el paso anterior',
        () {
      final s = SesionAcomodo(base: puertoViejo);
      s.moverLaBarra(35, 4.5);
      s.moverLaBarra(35, 2.5);
      s.soltarLaBarra();
      expect(_mesaPorMesa(s.actual), _mesaPorMesa(aDistancia(2.5).actual));
    });

    test('a una distancia que no entra dice cuántas faltan', () {
      final s = SesionAcomodo(base: puertoViejo);
      final r = s.moverLaBarra(200, 5.0)!;
      expect(r.faltan, greaterThan(0));
      expect(s.actual.mesas.length, r.puestas);
      s.soltarLaBarra();
    });

    test('la barra y ACOMODAR a la misma distancia dan lo mismo, mesa por mesa', () {
      final conBarra = aDistancia(3.0).actual;
      final conBoton = SesionAcomodo(base: puertoViejo)..acomodar(35, lugarM: 3.0);
      expect(_mesaPorMesa(conBarra), _mesaPorMesa(conBoton.actual));
    });

    test('sin alumnos no reacomoda', () {
      final s = SesionAcomodo(base: puertoViejo);
      expect(s.moverLaBarra(0, 3.0), isNull);
      expect(s.moviendoLaBarra, isFalse);
    });

    test('descartar la olvida', () {
      final s = aDistancia(3.0);
      s.descartar();
      expect(s.lugarDeLaBarra, isNull);
      expect(_mesaPorMesa(s.actual), _mesaPorMesa(puertoViejo));
    });
  });

  group('al guardar', () {
    ConfigPlano guardar(
      SesionAcomodo s, {
      ConfigPlano config = ConfigPlano.vacia,
    }) =>
        EditarArmado.paraGuardar(
          base: s.base,
          nuevo: s.actual,
          fresco: s.base,
          config: config,
          alumnos: const [],
          enUsoVisto: EditarArmado.enUso(const [], config),
          rehecho: s.rehecho,
          lugarBarraM: s.lugarDeLaBarra,
        ).config!;

    test('la distancia queda en Medidas', () {
      expect(guardar(aDistancia(3.0)).medidas.lugarMesaM, 3.0);
    });

    test('sin tocar la barra, Medidas no cambia', () {
      final s = SesionAcomodo(base: puertoViejo);
      s.agregar('A');
      const config = ConfigPlano(medidas: MedidasPlano(lugarMesaM: 2.4));
      expect(guardar(s, config: config).medidas.lugarMesaM, 2.4);
    });

    test('se quitan las fijadas, las libres y los bloques, como al acomodar', () {
      const config = ConfigPlano(
        fijadas: {3: MesaFijada(alumnoId: 'x')},
        libres: {12: MesaLibre()},
        bloques: [BloqueDivision('5A', 1, 20)],
      );
      final r = guardar(aDistancia(3.0), config: config);
      expect(r.fijadas, isEmpty);
      expect(r.libres, isEmpty);
      expect(r.bloques, isEmpty);
    });

    test('lo guardado se vuelve a abrir igual', () {
      final s = aDistancia(3.0);
      final guardado = EditarArmado.comoSeGuarda(s.actual, s.base, ordenar: true);
      final otra = SesionAcomodo(base: guardado);
      expect(otra.faltaOrdenar, isFalse);
      expect(otra.distanciaDelSalon, closeTo(3.0, 1e-9));
    });

    test('ACOMODAR OTRA VEZ con la distancia de Medidas da lo mismo que la barra',
        () {
      final s = aDistancia(3.0);
      final medidas = guardar(s).medidas;
      final otra = SesionAcomodo(base: puertoViejo, medidas: medidas);
      otra.acomodar(35, lugarM: medidas.lugarMesaM);
      expect(_mesaPorMesa(otra.actual), _mesaPorMesa(s.actual));
    });
  });

  group('después del sorteo, o en el Canva', () {
    test('con familias con mesa no reacomoda', () {
      final s = SesionAcomodo(base: puertoViejo, haySorteo: true);
      expect(s.barraReacomoda, isFalse);
      expect(s.moverLaBarra(35, 3.0), isNull);
      expect(_mesaPorMesa(s.actual), _mesaPorMesa(puertoViejo));
      expect(s.puedeDeshacer, isFalse);
    });

    test('estirar no cambia ningún número ni ninguna familia', () {
      final s = SesionAcomodo(base: puertoViejo, haySorteo: true);
      s.probarSeparar({...puertoViejo.numeros}, 3.5);
      expect(s.previa!.armado.numeros, puertoViejo.numeros);
    });

    test('en un armado del Canva no reacomoda', () {
      final s = SesionAcomodo(base: ArmadosPredefinidos.todos.first);
      expect(s.barraReacomoda, isFalse);
      expect(s.moverLaBarra(35, 3.0), isNull);
    });
  });
}
