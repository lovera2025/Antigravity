// Lo que la pantalla del plano muestra de una fiesta: las familias con sus
// mesas y sillas, lo que mide y los avisos, calculado con los datos del
// momento.
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/modelo/estado_plano.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/plano_de_la_fiesta.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';
import 'package:arguello_events/models/sillas_reparto.dart';

ContratoAlumno alumno(
  String id, {
  int extras = 0,
  int sillas = 0,
  List<int> mesas = const [],
  String? division = '5° A',
  bool baja = false,
}) =>
    ContratoAlumno(
      id: id,
      eventoId: 'e',
      nombreAlumno: '${baja ? '[BAJA] ' : ''}${id.toUpperCase()}, ALUMNO',
      cantidadAcompanantes: 0,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      sillasExtraCantidad: sillas,
      sillasExtraPrecioTotal: 8000.0 * sillas,
      numeroMesa:
          mesas.isEmpty ? null : MesasExtraUtils.formatearAsignacionMesas(mesas),
      cursoDivision: division,
    );

SillasReparto reparto(String id, {required int principal, required int sillas, required int mesas}) =>
    SillasReparto(
      id: 'r-$id',
      contratoAlumnoId: id,
      sillasPrincipal: principal,
      sillasExtra: sillas,
      mesas: mesas,
      createdAt: DateTime.utc(2026, 10, 1),
      updatedAt: DateTime.utc(2026, 10, 1),
    );

void main() {
  final aMedida = ArmarAMedida.armar(
    const OpcionesAMedida(playon: PlayonReal.costaSurubi, cantidad: 40),
  ).armado;
  final pagina3 = ArmadosPredefinidos.normal2aPagina3();

  group('las mesas que necesita la fiesta', () {
    test('la del contrato más las agregadas, sin las bajas', () {
      expect(
        PlanoDeLaFiesta.mesasQueNecesita([
          alumno('a'),
          alumno('b', extras: 2),
          alumno('c', extras: 1, baja: true),
        ]),
        4,
      );
      expect(PlanoDeLaFiesta.mesasQueNecesita(const []), 0);
    });
  });

  group('las familias en el plano', () {
    test('las que ya tienen mesa, también una baja que la conserva', () {
      final o = PlanoDeLaFiesta.ocupantes([
        alumno('a', mesas: [3]),
        alumno('b'),
        alumno('c', mesas: [9], baja: true),
      ], const {});
      // La baja conserva su lugar: el sorteo no da la 9 a nadie.
      expect(o.map((x) => x.id), ['a', 'c']);
      expect(o.first.numeros, [3]);
      expect(o.first.apellido, 'A');
    });

    test('una baja con mesa se dibuja ocupada y se avisa para liberarla', () {
      final p = PlanoDeLaFiesta.desde(
        armado: pagina3,
        config: ConfigPlano.vacia,
        alumnos: [
          alumno('a', mesas: [3]),
          alumno('c', mesas: [9, 10], baja: true),
        ],
      );
      expect(p.estado.info(9).estado, EstadoMesa.ocupada);
      // No cuenta para las mesas que la fiesta necesita.
      expect(p.mesasNecesarias, 1);
      final a = p.avisos.single;
      expect(a.texto,
          'C, ALUMNO está de baja y conserva las mesas 9, 10: si no vuelve, '
          'sacásela en Editar alumno.');
      expect((a.mesa, a.grave), (9, false));
    });

    test('las sillas extra van a sus mesas según el reparto que rige hoy', () {
      final a = alumno('a', extras: 1, sillas: 3, mesas: [12, 13]);
      // Sin elegir: el de siempre, la principal primero.
      expect(
        PlanoDeLaFiesta.ocupanteDe(a, null).sillasExtraPorMesa,
        {12: 2, 13: 1},
      );
      // La familia eligió una en la principal y dos en la adicional.
      expect(
        PlanoDeLaFiesta.ocupanteDe(
          a,
          reparto('a', principal: 1, sillas: 3, mesas: 2),
        ).sillasExtraPorMesa,
        {12: 1, 13: 2},
      );
      // Una elección vieja (con otra cantidad de sillas) ya no vale.
      expect(
        PlanoDeLaFiesta.ocupanteDe(
          a,
          reparto('a', principal: 0, sillas: 2, mesas: 2),
        ).sillasExtraPorMesa,
        {12: 2, 13: 1},
      );
    });
  });

  group('el titular', () {
    test('entran: verde, y dice cuántas necesita la fiesta', () {
      final p = PlanoDeLaFiesta.desde(
        armado: aMedida,
        config: ConfigPlano.vacia,
        alumnos: [for (var i = 0; i < 38; i++) alumno('f$i')],
      );
      expect(p.semaforo, SemaforoPlano.entran);
      expect(p.titular, 'Entran las 38');
      expect(p.avisos, isEmpty);
      expect(p.detalle, startsWith('40 mesas · ocupa '));
      expect(p.detalle, endsWith('en el playón entran hasta 284'));
    });

    test('faltan: rojo, con cuántas', () {
      final p = PlanoDeLaFiesta.desde(
        armado: aMedida,
        config: ConfigPlano.vacia,
        alumnos: [for (var i = 0; i < 46; i++) alumno('f$i')],
      );
      expect(p.faltan, 6);
      expect(p.semaforo, SemaforoPlano.faltan);
      expect(p.titular, 'Faltan 6 mesas');
      expect(p.avisos.first.texto,
          'Faltan 6 mesas: la fiesta necesita 46 y este armado tiene 40. '
          'Se agregan en Personalizar → Acomodar.');
      expect(p.avisos.first.grave, isTrue);
    });

    test('con el pasto alcanza: entran, y se sabe que lo usa', () {
      final tecnica = ArmadosPredefinidos.tecnica1a1b();
      final p = PlanoDeLaFiesta.desde(
        armado: tecnica,
        config: ConfigPlano.vacia,
        alumnos: [for (var i = 0; i < 140; i++) alumno('f$i')],
      );
      expect(p.faltan, 0);
      expect(p.usaPasto, isTrue);
      expect(p.detalle, startsWith('130 mesas y 20 de pasto'));
    });

    test('sin familias, el salón está listo', () {
      final p = PlanoDeLaFiesta.desde(
        armado: aMedida,
        config: ConfigPlano.vacia,
        alumnos: const [],
      );
      expect(p.titular, 'Salón listo');
    });

    test('la capacidad sigue a las medidas de la fiesta', () {
      final p = PlanoDeLaFiesta.desde(
        armado: aMedida,
        config: const ConfigPlano(medidas: MedidasPlano(lugarMesaM: 2.5)),
        alumnos: const [],
      );
      expect(p.capacidadPlayon, 180);
    });
  });

  group('los avisos', () {
    test('una mesa con diez sillas: un solo aviso, con todas sus vecinas', () {
      // En el armado a medida las mesas están a 2 m justos.
      final p = PlanoDeLaFiesta.desde(
        armado: aMedida,
        config: ConfigPlano.vacia,
        alumnos: [
          alumno('a', sillas: 2, mesas: [8]),
          alumno('b', mesas: [20]),
        ],
      );
      final apretada = p.avisos.single;
      expect(apretada.mesa, 8);
      expect(apretada.grave, isFalse);
      expect(apretada.texto,
          'La mesa 8 lleva 10 sillas y queda apretada: le faltan 15 cm.');
      // No es para frenar el sorteo.
      expect(p.semaforo, SemaforoPlano.entran);
      expect(p.sinLugar.mesas, {8});
    });

    test('dos familias en la misma mesa: grave, y lleva a la mesa', () {
      final p = PlanoDeLaFiesta.desde(
        armado: pagina3,
        config: ConfigPlano.vacia,
        alumnos: [
          alumno('gomez', mesas: [5]),
          alumno('sosa', mesas: [5]),
        ],
      );
      final a = p.avisos.single;
      expect(a.texto, 'La mesa 5 la tienen 2 familias: GOMEZ, SOSA.');
      expect((a.mesa, a.grave), (5, true));
      expect(p.titular, 'Hay 1 cosa para revisar');
    });

    test('una mesa que el armado no tiene', () {
      final p = PlanoDeLaFiesta.desde(
        armado: pagina3,
        config: ConfigPlano.vacia,
        alumnos: [alumno('gomez', mesas: [200])],
      );
      expect(p.avisos.single.texto,
          'GOMEZ tiene la mesa 200, que no está en este armado.');
      expect(p.avisos.single.mesa, isNull);
    });

    test('fijadas y libres que ya no cierran', () {
      final p = PlanoDeLaFiesta.desde(
        armado: pagina3,
        config: const ConfigPlano(
          fijadas: {
            // Para una familia que está: se dibuja.
            10: MesaFijada(alumnoId: 'gomez', motivo: 'Silla de ruedas'),
            // Para una que se dio de baja y para una que ya no figura.
            11: MesaFijada(alumnoId: 'baja'),
            12: MesaFijada(alumnoId: 'fantasma'),
            // En una mesa que este armado no tiene.
            300: MesaFijada(alumnoId: 'gomez'),
          },
          libres: {78: MesaLibre(), 400: MesaLibre()},
        ),
        alumnos: [alumno('gomez'), alumno('baja', baja: true)],
      );
      expect(p.estado.info(10).estado, EstadoMesa.fijada);
      expect(p.estado.info(10).fijadaPara!.apellido, 'GOMEZ');
      expect(p.estado.info(11).estado, EstadoMesa.vacia);
      expect(p.estado.info(78).estado, EstadoMesa.libre);
      final textos = p.avisos.map((a) => a.texto).join('\n');
      expect(textos, contains('La mesa 300 está fijada para GOMEZ, pero este armado no la tiene.'));
      expect(textos, contains('La mesa 11 está fijada para una familia que ya no está'));
      expect(textos, contains('La mesa 12 está fijada para una familia que ya no está'));
      expect(textos, contains('La mesa 400 está marcada como libre'));
      expect(p.avisos.firstWhere((a) => a.texto.contains('La mesa 11')).mesa, 11);
    });

    test('divisiones escritas de dos formas: avisa, sin frenar', () {
      final p = PlanoDeLaFiesta.desde(
        armado: pagina3,
        config: ConfigPlano.vacia,
        alumnos: [
          alumno('a', mesas: [1], division: '1'),
          alumno('b', mesas: [2], division: '1RA'),
        ],
      );
      expect(p.avisos.single.texto, contains('se parecen'));
      expect(p.avisos.single.grave, isFalse);
    });

    test('en el Canva, sin sillas extra, no hay nada que avisar', () {
      final p = PlanoDeLaFiesta.desde(
        armado: pagina3,
        config: ConfigPlano.vacia,
        alumnos: [for (var i = 1; i <= 78; i++) alumno('f$i', mesas: [i])],
      );
      expect(p.avisos, isEmpty);
      expect(p.titular, 'Entran las 78');
    });
  });

  group('el orden y los colores de las divisiones', () {
    test('sigue el orden guardado en el plano', () {
      final alumnos = [
        alumno('a', mesas: [1], division: '5° A'),
        alumno('b', mesas: [2], division: '5° B'),
      ];
      expect(
        PlanoDeLaFiesta.desde(
          armado: pagina3,
          config: ConfigPlano.vacia,
          alumnos: alumnos,
        ).estado.divisiones,
        ['5A', '5B'],
      );
      expect(
        PlanoDeLaFiesta.desde(
          armado: pagina3,
          config: const ConfigPlano(ordenDivisiones: ['5B', '5A']),
          alumnos: alumnos,
        ).estado.divisiones,
        ['5B', '5A'],
      );
    });
  });
}
