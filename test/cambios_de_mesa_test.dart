// Tocar las mesas a mano: fijar y dejar libres antes del sorteo, cambiar o
// mover familias después, y deshacer.
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/services/cambios_de_mesa.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/movimiento_mesas.dart';
import 'package:arguello_events/models/plano_evento.dart';

ContratoAlumno alumno(
  String id, {
  int extras = 0,
  int sillas = 0,
  List<int> mesas = const [],
  String division = '5° A',
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

void main() {
  final ahora = DateTime.utc(2026, 11, 10, 15);
  // Páginas 4 y 5: 100 mesas; la 49 y la 51 son cortes (las del medio).
  final armado = ArmadosPredefinidos.normal2aPaginas45();
  // Técnica: comunes hasta la 130 y pasto desde la 131.
  final tecnica = ArmadosPredefinidos.tecnica1a1b();

  group('un tramo de mesas pegadas', () {
    test('seguidas y pegadas, sí; cruzando un corte, no', () {
      expect(CambiosDeMesa.tramoDesde(armado, 10, 3).mesas, [10, 11, 12]);
      final corte = CambiosDeMesa.tramoDesde(armado, 49, 2);
      expect(corte.mesas, isNull);
      expect(corte.problema, contains('la 49 y la 50 no están juntas'));
      // La última mesa: después no hay más.
      final fin = CambiosDeMesa.tramoDesde(armado, 100, 2);
      expect(fin.mesas, isNull);
      expect(fin.problema,
          'Después de la 100 no hay más mesas: hacen falta 2 seguidas. Elegí otra.');
      expect(CambiosDeMesa.tramoDesde(armado, 500, 1).problema,
          'La mesa 500 no está en este armado.');
    });
  });

  group('fijar', () {
    test('fija todas las mesas de la familia, juntas, con motivo y quién', () {
      final r = CambiosDeMesa.fijar(
        armado: armado,
        config: ConfigPlano.vacia,
        alumnos: [alumno('gomez', extras: 1)],
        alumnoId: 'gomez',
        desdeMesa: 20,
        motivo: ' Silla de ruedas ',
        por: 'Jefe',
        ahora: ahora,
      );
      expect(r.sePuede, isTrue);
      expect(r.mesas, [20, 21]);
      final f = r.config!.fijadas;
      expect(f.keys, {20, 21});
      expect(f[20]!.alumnoId, 'gomez');
      expect(f[20]!.motivo, 'Silla de ruedas');
      expect(f[20]!.por, 'Jefe');
      expect(f[20]!.cuando, ahora);
    });

    test('volver a fijar la misma familia mueve sus fijadas', () {
      const antes = ConfigPlano(fijadas: {
        20: MesaFijada(alumnoId: 'gomez'),
        21: MesaFijada(alumnoId: 'gomez'),
        30: MesaFijada(alumnoId: 'sosa'),
      });
      final r = CambiosDeMesa.fijar(
        armado: armado,
        config: antes,
        alumnos: [alumno('gomez', extras: 1), alumno('sosa')],
        alumnoId: 'gomez',
        desdeMesa: 21,
        motivo: 'Cerca del ingreso',
        por: null,
        ahora: ahora,
      );
      expect(r.config!.fijadasPorAlumno, {
        'gomez': [21, 22],
        'sosa': [30],
      });
    });

    test('sin motivo no se fija', () {
      final r = CambiosDeMesa.fijar(
        armado: armado,
        config: ConfigPlano.vacia,
        alumnos: [alumno('gomez')],
        alumnoId: 'gomez',
        desdeMesa: 20,
        motivo: '  ',
        por: null,
        ahora: ahora,
      );
      expect(r.sePuede, isFalse);
      expect(r.problema, 'Escribí por qué se le fija la mesa.');
    });

    test('lo que no se puede, dicho en palabras', () {
      String? problema({
        required List<ContratoAlumno> alumnos,
        ConfigPlano config = ConfigPlano.vacia,
        String id = 'gomez',
        int desde = 20,
      }) =>
          CambiosDeMesa.fijar(
            armado: armado,
            config: config,
            alumnos: alumnos,
            alumnoId: id,
            desdeMesa: desde,
            motivo: 'x',
            por: null,
            ahora: ahora,
          ).problema;

      expect(problema(alumnos: [alumno('gomez', baja: true)]),
          'Esa familia ya no está en la fiesta.');
      expect(problema(alumnos: const [], id: 'nadie'),
          'Esa familia ya no está en la fiesta.');
      expect(problema(alumnos: [alumno('gomez', mesas: [5])]),
          'GOMEZ ya tiene mesa. Para cambiarla de lugar usá Mover.');
      expect(
        problema(alumnos: [alumno('gomez'), alumno('sosa', mesas: [20])]),
        'La mesa 20 ya la tiene SOSA.',
      );
      expect(
        problema(
          alumnos: [alumno('gomez')],
          config: const ConfigPlano(libres: {20: MesaLibre()}),
        ),
        'La mesa 20 se dejó libre a propósito. Volvé a usarla primero.',
      );
      expect(
        problema(
          alumnos: [alumno('gomez'), alumno('sosa')],
          config: const ConfigPlano(fijadas: {20: MesaFijada(alumnoId: 'sosa')}),
        ),
        'La mesa 20 ya está fijada para SOSA.',
      );
      // Dos mesas que cruzan un corte.
      expect(
        problema(alumnos: [alumno('gomez', extras: 1)], desde: 49),
        contains('no hay 2 mesas pegadas'),
      );
      // Una baja conserva su mesa, igual que para el sorteo: si acá no
      // contara, el sorteo después no daría la fijada.
      expect(
        problema(
          alumnos: [alumno('gomez'), alumno('sosa', mesas: [20], baja: true)],
        ),
        'La mesa 20 la conserva SOSA, que está de baja. Si no vuelve, sacale '
        'la mesa en Editar alumno.',
      );
      // Con algo escrito en su mesa que no se entiende, ya tiene mesa.
      expect(
        problema(alumnos: [
          alumno('gomez').copyWith(numeroMesa: 'VIP'),
        ]),
        'GOMEZ tiene escrito "VIP" en su mesa. Corregilo en Editar alumno '
        'antes de fijarle una.',
      );
    });

    test('quitar las fijadas de una familia, o la de una sola mesa', () {
      const config = ConfigPlano(fijadas: {
        20: MesaFijada(alumnoId: 'gomez'),
        21: MesaFijada(alumnoId: 'gomez'),
        30: MesaFijada(alumnoId: 'fantasma'),
      });
      final sinGomez = CambiosDeMesa.quitarFijadas(config, 'gomez');
      expect(sinGomez.mesas, [20, 21]);
      expect(sinGomez.config!.fijadas.keys, {30});
      expect(CambiosDeMesa.quitarFijadas(config, 'sosa').sePuede, isFalse);
      // La de una familia que ya no está: por mesa.
      final sin30 = CambiosDeMesa.quitarFijadaDeMesa(config, 30);
      expect(sin30.config!.fijadas.keys, {20, 21});
      expect(CambiosDeMesa.quitarFijadaDeMesa(config, 99).sePuede, isFalse);
    });
  });

  group('dejar libre', () {
    test('una mesa vacía queda libre, con su motivo', () {
      final r = CambiosDeMesa.dejarLibre(
        armado: armado,
        config: ConfigPlano.vacia,
        alumnos: const [],
        mesa: 50,
        motivo: 'Columna',
        por: 'Jefe',
        ahora: ahora,
      );
      expect(r.mesas, [50]);
      final l = r.config!.libres[50]!;
      expect((l.motivo, l.por, l.cuando), ('Columna', 'Jefe', ahora));
    });

    test('el motivo puede faltar', () {
      final r = CambiosDeMesa.dejarLibre(
        armado: armado,
        config: ConfigPlano.vacia,
        alumnos: const [],
        mesa: 50,
        motivo: '  ',
        por: null,
        ahora: ahora,
      );
      expect(r.config!.libres[50]!.motivo, isNull);
    });

    test('solo una mesa vacía y sin fijar', () {
      String? problema(int mesa, {ConfigPlano config = ConfigPlano.vacia}) =>
          CambiosDeMesa.dejarLibre(
            armado: armado,
            config: config,
            alumnos: [alumno('sosa', mesas: [20])],
            mesa: mesa,
            motivo: null,
            por: null,
            ahora: ahora,
          ).problema;
      expect(problema(20), 'La mesa 20 la tiene SOSA. Movela primero a otra.');
      expect(
        problema(21, config: const ConfigPlano(fijadas: {21: MesaFijada(alumnoId: 'x')})),
        'La mesa 21 está fijada para una familia. Quitá la fijada primero.',
      );
      expect(problema(22, config: const ConfigPlano(libres: {22: MesaLibre()})),
          'La mesa 22 ya está libre.');
      expect(problema(900), 'La mesa 900 no está en este armado.');
    });

    test('volver a usarla la saca de las libres', () {
      const config = ConfigPlano(libres: {50: MesaLibre(), 51: MesaLibre()});
      expect(CambiosDeMesa.volverAUsar(config, 50).config!.libres.keys, {51});
      expect(CambiosDeMesa.volverAUsar(config, 7).sePuede, isFalse);
    });
  });

  group('cambiar dos familias de lugar', () {
    final alumnos = [
      alumno('gomez', extras: 1, sillas: 3, mesas: [12, 13]),
      alumno('sosa', extras: 1, mesas: [40, 41], division: '5° B'),
      alumno('vega', mesas: [60]),
      alumno('ruiz'),
    ];

    test('se cruzan los números de las dos', () {
      final c = CambiosDeMesa.intercambiar(
        armado: armado,
        config: ConfigPlano.vacia,
        alumnos: alumnos,
        alumnoId: 'gomez',
        otroId: 'sosa',
      );
      expect(c.sePuede, isTrue);
      expect(c.tipo, TipoMovimientoMesas.intercambio);
      expect(c.antes, {'gomez': '12, 13', 'sosa': '40, 41'});
      expect(c.despues, {'gomez': '40, 41', 'sosa': '12, 13'});
      expect(c.avisos, [
        'Son de divisiones distintas: 5° A y 5° B.',
        'Las sillas extra de GOMEZ van a sus mesas nuevas.',
      ]);
      expect(c.hayQueAvisarALaFamilia, isFalse);
      expect(c.config, isNull);
    });

    test('si una ya retiró las entradas, hay que avisarle', () {
      final c = CambiosDeMesa.intercambiar(
        armado: armado,
        config: ConfigPlano.vacia,
        alumnos: alumnos,
        alumnoId: 'gomez',
        otroId: 'sosa',
        yaRetiraron: {'sosa'},
      );
      expect(c.hayQueAvisarALaFamilia, isTrue);
      expect(c.avisos.join('\n'), contains('SOSA ya retiró sus entradas'));
    });

    test('avisa si alguna queda fuera del bloque de su división', () {
      final c = CambiosDeMesa.intercambiar(
        armado: armado,
        config: const ConfigPlano(bloques: [
          BloqueDivision('5A', 1, 24),
          BloqueDivision('5B', 25, 49),
        ]),
        alumnos: alumnos,
        alumnoId: 'gomez',
        otroId: 'sosa',
      );
      expect(c.avisos, containsAll([
        'GOMEZ queda fuera del bloque de 5° A (mesas 1 a 24).',
        'SOSA queda fuera del bloque de 5° B (mesas 25 a 49).',
      ]));
    });

    test('las fijadas siguen a la familia, con su motivo', () {
      final c = CambiosDeMesa.intercambiar(
        armado: armado,
        config: const ConfigPlano(fijadas: {
          12: MesaFijada(alumnoId: 'gomez', motivo: 'Silla de ruedas'),
          13: MesaFijada(alumnoId: 'gomez', motivo: 'Silla de ruedas'),
          60: MesaFijada(alumnoId: 'vega'),
        }),
        alumnos: alumnos,
        alumnoId: 'gomez',
        otroId: 'sosa',
      );
      expect(c.config!.fijadasPorAlumno, {
        'gomez': [40, 41],
        'vega': [60],
      });
      expect(c.config!.fijadas[40]!.motivo, 'Silla de ruedas');
      expect(
        c.avisos,
        contains('GOMEZ tenía mesas fijadas: pasan a ser las nuevas, con el '
            'mismo motivo.'),
      );
    });

    test('una baja no se cambia de lugar', () {
      final c = CambiosDeMesa.intercambiar(
        armado: armado,
        config: ConfigPlano.vacia,
        alumnos: [
          alumno('gomez', mesas: [12]),
          alumno('sosa', mesas: [40], baja: true),
        ],
        alumnoId: 'gomez',
        otroId: 'sosa',
      );
      expect(c.problema, startsWith('SOSA está de baja: no se la cambia'));
    });

    test('lo que no se puede', () {
      String? problema(String a, String b) => CambiosDeMesa.intercambiar(
            armado: armado,
            config: ConfigPlano.vacia,
            alumnos: alumnos,
            alumnoId: a,
            otroId: b,
          ).problema;
      expect(
        problema('gomez', 'vega'),
        'GOMEZ tiene 2 mesas y VEGA tiene 1 mesa: para cambiar tienen que '
        'tener la misma cantidad. Usá Mover.',
      );
      expect(problema('gomez', 'ruiz'), 'RUIZ todavía no tiene mesa.');
      expect(problema('gomez', 'gomez'), 'Elegí otra familia.');
      expect(problema('gomez', 'nadie'),
          'Una de las familias ya no está en la fiesta.');
    });
  });

  group('mover una familia a mesas libres', () {
    final alumnos = [
      alumno('gomez', extras: 1, mesas: [12, 13]),
      alumno('sosa', mesas: [40]),
      alumno('ruiz'),
    ];

    CambioDeMesas mover(int desde, {ConfigPlano config = ConfigPlano.vacia, String id = 'gomez', Set<String> retiraron = const {}}) =>
        CambiosDeMesa.mover(
          armado: armado,
          config: config,
          alumnos: alumnos,
          alumnoId: id,
          desdeMesa: desde,
          yaRetiraron: retiraron,
        );

    test('pasa con todas sus mesas, juntas', () {
      final c = mover(20);
      expect(c.sePuede, isTrue);
      expect(c.tipo, TipoMovimientoMesas.mover);
      expect(c.antes, {'gomez': '12, 13'});
      expect(c.despues, {'gomez': '20, 21'});
      expect(c.avisos, isEmpty);
    });

    test('puede correrse una sola mesa: una de las nuevas ya era suya', () {
      final c = mover(13);
      expect(c.sePuede, isTrue);
      expect(c.despues, {'gomez': '13, 14'});
    });

    test('lo que no se puede', () {
      expect(mover(12).problema, 'GOMEZ ya está en esas mesas.');
      expect(
        mover(39).problema,
        'La mesa 40 es de SOSA. Para cambiar de lugar con esa familia usá '
        'Cambiar.',
      );
      expect(mover(49).problema, contains('no están juntas'));
      expect(
        mover(20, config: const ConfigPlano(libres: {21: MesaLibre()})).problema,
        'La mesa 21 se dejó libre a propósito. Volvé a usarla primero.',
      );
      expect(
        mover(20, config: const ConfigPlano(fijadas: {20: MesaFijada(alumnoId: 'ruiz')})).problema,
        'La mesa 20 está fijada para RUIZ.',
      );
      expect(mover(20, id: 'ruiz').problema, 'RUIZ todavía no tiene mesa.');
      expect(mover(20, id: 'nadie').problema,
          'Esa familia ya no está en la fiesta.');
    });

    test('ir a una mesa fijada para ella misma vale, y sigue fijada ahí', () {
      final c = mover(
        20,
        config: const ConfigPlano(fijadas: {
          20: MesaFijada(alumnoId: 'gomez'),
          21: MesaFijada(alumnoId: 'gomez'),
        }),
      );
      expect(c.sePuede, isTrue);
      expect(c.config!.fijadas.keys, {20, 21});
    });

    test('sus fijadas pasan a las mesas nuevas', () {
      final c = mover(
        30,
        config: const ConfigPlano(fijadas: {
          12: MesaFijada(alumnoId: 'gomez', motivo: 'Cerca del ingreso'),
          13: MesaFijada(alumnoId: 'gomez', motivo: 'Cerca del ingreso'),
        }),
      );
      expect(c.config!.fijadasPorAlumno, {'gomez': [30, 31]});
      expect(c.config!.fijadas[31]!.motivo, 'Cerca del ingreso');
    });

    test('la mesa de una baja no está libre', () {
      final c = CambiosDeMesa.mover(
        armado: armado,
        config: ConfigPlano.vacia,
        alumnos: [
          alumno('gomez', mesas: [12]),
          alumno('sosa', mesas: [20], baja: true),
        ],
        alumnoId: 'gomez',
        desdeMesa: 20,
      );
      expect(c.problema, startsWith('La mesa 20 la conserva SOSA, que está de baja'));
    });

    test('avisa si va al pasto, si sale de su bloque y si ya retiró', () {
      final c = CambiosDeMesa.mover(
        armado: tecnica,
        config: const ConfigPlano(bloques: [BloqueDivision('5A', 1, 40)]),
        alumnos: [alumno('gomez', mesas: [10])],
        alumnoId: 'gomez',
        desdeMesa: 131,
        yaRetiraron: {'gomez'},
      );
      expect(c.sePuede, isTrue);
      expect(c.avisos, [
        'GOMEZ pasa a mesas del pasto.',
        'GOMEZ queda fuera del bloque de 5° A (mesas 1 a 40).',
        'GOMEZ ya retiró sus entradas: hay que avisarle y reimprimir la '
            'planilla de entrega.',
      ]);
      expect(c.hayQueAvisarALaFamilia, isTrue);
    });
  });

  group('lo confirmado tiene que ser lo que se guarda', () {
    CambioDeMesas cambio(int mesaDeSosa, {Set<String> retiraron = const {}}) =>
        CambiosDeMesa.intercambiar(
          armado: armado,
          config: ConfigPlano.vacia,
          alumnos: [
            alumno('gomez', mesas: [8]),
            alumno('sosa', mesas: [mesaDeSosa]),
          ],
          alumnoId: 'gomez',
          otroId: 'sosa',
          yaRetiraron: retiraron,
        );

    test('con los mismos datos, es el mismo cambio', () {
      expect(cambio(20).esElMismoQue(cambio(20)), isTrue);
    });

    test('si la otra PC movió a una de las dos, ya no es el mismo', () {
      // Se mostró "GÓMEZ: 8 → 20" y ahora daría "GÓMEZ: 8 → 35".
      expect(cambio(35).esElMismoQue(cambio(20)), isFalse);
    });

    test('si mientras tanto una retiró sus entradas, tampoco', () {
      // Falta mostrarle el tilde "Le aviso a la familia".
      expect(cambio(20, retiraron: {'sosa'}).esElMismoQue(cambio(20)), isFalse);
    });

    test('otro tipo de cambio no es el mismo', () {
      final mudanza = CambiosDeMesa.mover(
        armado: armado,
        config: ConfigPlano.vacia,
        alumnos: [alumno('gomez', mesas: [8])],
        alumnoId: 'gomez',
        desdeMesa: 20,
      );
      expect(mudanza.esElMismoQue(cambio(20)), isFalse);
    });

    test('los renglones y lo que se dice al terminar', () {
      String apellido(String id) => id.toUpperCase();
      final c = cambio(20);
      expect(c.renglones(apellido), ['GOMEZ: 8 → 20', 'SOSA: 20 → 8']);
      expect(c.textoHecho(apellido), 'GOMEZ y SOSA cambiaron de lugar.');
      final mudanza = CambiosDeMesa.mover(
        armado: armado,
        config: ConfigPlano.vacia,
        alumnos: [alumno('gomez', extras: 1, mesas: [8, 9])],
        alumnoId: 'gomez',
        desdeMesa: 20,
      );
      expect(mudanza.renglones(apellido), ['GOMEZ: 8, 9 → 20, 21']);
      expect(mudanza.textoHecho(apellido), 'GOMEZ pasó a la 20 y la 21.');
    });
  });

  group('el renglón que queda escrito', () {
    test('lleva el antes, el después, el motivo, los avisos y quién', () {
      final c = CambiosDeMesa.mover(
        armado: armado,
        config: ConfigPlano.vacia,
        alumnos: [alumno('gomez', sillas: 1, mesas: [12])],
        alumnoId: 'gomez',
        desdeMesa: 20,
      );
      final m = c.movimiento(
        id: 'm1',
        eventoId: 'e',
        motivo: ' Pidió estar cerca de la pista ',
        hechoPor: 'Operador',
        ahora: ahora,
      );
      expect(m.tipo, TipoMovimientoMesas.mover);
      expect(m.antes, {'gomez': '12'});
      expect(m.despues, {'gomez': '20'});
      expect(m.motivo, 'Pidió estar cerca de la pista');
      expect(m.avisos, ['Las sillas extra de GOMEZ van a sus mesas nuevas.']);
      expect(m.hechoPor, 'Operador');
      expect(m.deshaceId, isNull);
      // Va y vuelve de la base igual.
      final vuelta = MovimientoMesas.fromMap(m.toMap());
      expect(vuelta.despues, m.despues);
      expect(vuelta.avisos, m.avisos);
    });
  });

  group('deshacer un cambio', () {
    MovimientoMesas mov(
      String id,
      TipoMovimientoMesas tipo,
      Map<String, String?> antes,
      Map<String, String?> despues, {
      String? deshace,
    }) =>
        MovimientoMesas(
          id: id,
          eventoId: 'e',
          tipo: tipo,
          antes: antes,
          despues: despues,
          motivo: 'x',
          deshaceId: deshace,
          createdAt: ahora,
        );

    final cambio = mov(
      'm1',
      TipoMovimientoMesas.intercambio,
      {'gomez': '12, 13', 'sosa': '40, 41'},
      {'gomez': '40, 41', 'sosa': '12, 13'},
    );

    test('si nada cambió después, vuelve todo a como estaba', () {
      final c = CambiosDeMesa.deshacer(
        movimiento: cambio,
        movimientos: [cambio],
        alumnos: [
          alumno('gomez', extras: 1, mesas: [40, 41]),
          alumno('sosa', extras: 1, mesas: [12, 13]),
        ],
      );
      expect(c.sePuede, isTrue);
      expect(c.tipo, TipoMovimientoMesas.deshacer);
      expect(c.deshaceId, 'm1');
      expect(c.antes, cambio.despues);
      expect(c.despues, cambio.antes);
    });

    test('si una de las familias cambió de mesa después, ya no', () {
      final c = CambiosDeMesa.deshacer(
        movimiento: cambio,
        movimientos: [cambio],
        alumnos: [
          alumno('gomez', extras: 1, mesas: [40, 41]),
          alumno('sosa', extras: 1, mesas: [70, 71]),
        ],
      );
      expect(c.problema, contains('Las mesas de SOSA cambiaron después'));
    });

    test('si otra familia tomó la mesa a la que hay que volver, ya no', () {
      final mudanza = mov(
        'm2',
        TipoMovimientoMesas.mover,
        {'gomez': '12'},
        {'gomez': '20'},
      );
      final c = CambiosDeMesa.deshacer(
        movimiento: mudanza,
        movimientos: [mudanza],
        alumnos: [
          alumno('gomez', mesas: [20]),
          alumno('vega', mesas: [12]),
        ],
      );
      expect(c.problema, 'La mesa 12 ahora es de VEGA: ya no se puede deshacer.');
    });

    test('un cambio no se deshace dos veces, y un deshacer no se deshace', () {
      final deshecho = mov(
        'm3',
        TipoMovimientoMesas.deshacer,
        cambio.despues,
        cambio.antes,
        deshace: 'm1',
      );
      final alumnos = [
        alumno('gomez', extras: 1, mesas: [12, 13]),
        alumno('sosa', extras: 1, mesas: [40, 41]),
      ];
      expect(
        CambiosDeMesa.deshacer(
          movimiento: cambio,
          movimientos: [cambio, deshecho],
          alumnos: alumnos,
        ).problema,
        'Este cambio ya se deshizo.',
      );
      expect(
        CambiosDeMesa.deshacer(
          movimiento: deshecho,
          movimientos: [cambio, deshecho],
          alumnos: alumnos,
        ).problema,
        contains('ya es un deshacer'),
      );
    });

    test('si alguna se dio de baja, ya no', () {
      final c = CambiosDeMesa.deshacer(
        movimiento: cambio,
        movimientos: [cambio],
        alumnos: [
          alumno('gomez', extras: 1, mesas: [40, 41], baja: true),
          alumno('sosa', extras: 1, mesas: [12, 13]),
        ],
      );
      expect(c.problema, 'Una de las familias ya no está en la fiesta.');
    });

    test('avisa si alguna ya retiró las entradas', () {
      final c = CambiosDeMesa.deshacer(
        movimiento: cambio,
        movimientos: [cambio],
        alumnos: [
          alumno('gomez', extras: 1, mesas: [40, 41]),
          alumno('sosa', extras: 1, mesas: [12, 13]),
        ],
        yaRetiraron: {'gomez'},
      );
      expect(c.hayQueAvisarALaFamilia, isTrue);
      expect(c.avisos.single, contains('GOMEZ ya retiró sus entradas'));
    });

    final mudanza = mov(
      'm5',
      TipoMovimientoMesas.mover,
      {'gomez': '12'},
      {'gomez': '20'},
    );

    test('si la mesa a la que hay que volver se dejó libre, ya no', () {
      final c = CambiosDeMesa.deshacer(
        movimiento: mudanza,
        movimientos: [mudanza],
        alumnos: [alumno('gomez', mesas: [20])],
        config: const ConfigPlano(libres: {12: MesaLibre()}),
      );
      expect(c.problema,
          'La mesa 12 se dejó libre después de este cambio: ya no se puede deshacer.');
    });

    test('si se fijó para otra familia, tampoco', () {
      final c = CambiosDeMesa.deshacer(
        movimiento: mudanza,
        movimientos: [mudanza],
        alumnos: [alumno('gomez', mesas: [20]), alumno('vega')],
        config: const ConfigPlano(fijadas: {12: MesaFijada(alumnoId: 'vega')}),
      );
      expect(c.problema, contains('se fijó para otra familia'));
    });

    test('si la tomó alguien que después se dio de baja, tampoco', () {
      final c = CambiosDeMesa.deshacer(
        movimiento: mudanza,
        movimientos: [mudanza],
        alumnos: [
          alumno('gomez', mesas: [20]),
          alumno('vega', mesas: [12], baja: true),
        ],
      );
      expect(c.problema, 'La mesa 12 ahora es de VEGA: ya no se puede deshacer.');
    });

    test('mover y deshacer deja las fijadas como estaban', () {
      const config = ConfigPlano(fijadas: {
        12: MesaFijada(alumnoId: 'gomez', motivo: 'Movilidad reducida'),
      });
      final ida = CambiosDeMesa.mover(
        armado: armado,
        config: config,
        alumnos: [alumno('gomez', mesas: [12])],
        alumnoId: 'gomez',
        desdeMesa: 20,
      );
      expect(ida.config!.fijadasPorAlumno, {'gomez': [20]});
      final renglon = ida.movimiento(
        id: 'm6',
        eventoId: 'e',
        motivo: 'x',
        hechoPor: null,
        ahora: ahora,
      );
      final vuelta = CambiosDeMesa.deshacer(
        movimiento: renglon,
        movimientos: [renglon],
        alumnos: [alumno('gomez', mesas: [20])],
        config: ida.config!,
      );
      expect(vuelta.sePuede, isTrue);
      expect(vuelta.despues, {'gomez': '12'});
      expect(vuelta.config!.fijadasPorAlumno, {'gomez': [12]});
      expect(vuelta.config!.fijadas[12]!.motivo, 'Movilidad reducida');
    });

    test('un renglón que no se lee entero no se deshace a ciegas', () {
      for (final roto in [
        mov('r1', TipoMovimientoMesas.mover, {'gomez': '12'}, const {}),
        mov('r2', TipoMovimientoMesas.mover, const {}, const {}),
        mov('r3', TipoMovimientoMesas.mover, {'gomez': '12'}, {'sosa': '20'}),
      ]) {
        final c = CambiosDeMesa.deshacer(
          movimiento: roto,
          movimientos: [roto],
          alumnos: [alumno('gomez', mesas: [20]), alumno('sosa', mesas: [20])],
        );
        expect(c.problema, 'Este renglón no se puede leer entero: no se deshace.',
            reason: roto.id);
      }
    });
  });
}
