// La ficha del evento que el tótem recibe de la ventana principal
// (`ficha_totem.dart`): quién es alumno, con quién viene, su mesa, sus sillas y
// su música. Sin pantalla ni base.
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/recepcion/services/puerta_del_evento.dart';
import 'package:arguello_events/features/totem/services/ficha_totem.dart';
import 'package:arguello_events/models/sillas_reparto.dart';

import 'helpers/ficha_de_prueba.dart';
import 'helpers/puerta_en_memoria.dart';

void main() {
  group('un masivo sorteado', () {
    final ficha = fichaDePrueba();

    test('es masivo y trae al alumno y a sus acompañantes con nombre', () {
      expect(ficha.masivo, isTrue);
      final perez = ficha.de(idDe('perez'))!;
      expect(perez.nombre, 'PÉREZ, JUAN MARTÍN');
      expect(perez.esAlumno, isTrue);
      final ana = ficha.de(idDe('perez', 1))!;
      expect(ana.nombre, 'GÓMEZ, ANA');
      expect(ana.esAlumno, isFalse);
      expect(ficha.de(idDe('perez', 2))!.nombre, 'PÉREZ, LUIS');
    });

    test('la familia es el alumno: él y sus acompañantes se saludan juntos', () {
      expect(ficha.familiaDe(idDe('perez')), idDe('perez'));
      expect(ficha.familiaDe(idDe('perez', 1)), idDe('perez'));
      expect(ficha.familiaDe(idDe('perez', 2)), idDe('perez'));
      expect(ficha.familiaDe(idDe('benitez', 1)), idDe('benitez'));
      // Quien no está en la ficha es su propia familia.
      expect(ficha.familiaDe('cargado-a-mano'), 'cargado-a-mano');
    });

    test('el acompañante sabe a quién acompaña', () {
      expect(ficha.de(idDe('perez', 1))!.titular, 'PÉREZ, JUAN MARTÍN');
      expect(ficha.de(idDe('perez'))!.titular, isNull);
    });

    test('mesa y, debajo, las sillas de la familia', () {
      final perez = ficha.de(idDe('perez'))!;
      expect(perez.mesa, '12');
      expect(perez.sillas, '10 sillas (8 + 2 extra)');
      // El acompañante va a la misma mesa, con las mismas sillas.
      expect(ficha.de(idDe('perez', 1))!.mesa, '12');
      expect(ficha.de(idDe('perez', 1))!.sillas, '10 sillas (8 + 2 extra)');
      expect(ficha.de(idDe('benitez'))!.sillas, '8 sillas');
    });

    test('con dos mesas, las sillas de cada una y sin "a confirmar"', () {
      final acosta = ficha.de(idDe('acosta'))!;
      expect(acosta.mesa, '14-15');
      expect(acosta.sillas, '14: 10 sillas · 15: 9 sillas');
      // Recepción avisa que la familia no eligió el reparto; el salón no.
      expect(acosta.sillas, isNot(contains('confirmar')));
    });

    test('con el reparto que eligió la familia', () {
      final elegido = fichaDePrueba(repartos: {
        'acosta': SillasReparto(
          id: 'r-acosta',
          contratoAlumnoId: 'acosta',
          sillasPrincipal: 1,
          sillasExtra: 3,
          mesas: 2,
          createdAt: horaDeIngreso,
          updatedAt: horaDeIngreso,
        ),
      });
      expect(elegido.de(idDe('acosta'))!.sillas, '14: 9 sillas · 15: 10 sillas');
    });

    test('la música va solo en el alumno', () {
      expect(ficha.de(idDe('perez'))!.musica, 'Tusa · Karol G');
      expect(ficha.de(idDe('perez', 1))!.musica, isNull);
      expect(ficha.de(idDe('garcia'))!.musica, isNull);
    });

    test('el que quedó sin mesa no tiene mesa ni sillas', () {
      final sosa = ficha.de(idDe('sosa'))!;
      expect(sosa.mesa, isNull);
      expect(sosa.sillas, isNull);
    });

    test('los dados de baja no están, ni sus acompañantes', () {
      expect(ficha.de(idDe('baja')), isNull);
      expect(ficha.de(idDe('baja', 1)), isNull);
      expect(ficha.personas.values.map((p) => p.nombre),
          isNot(contains(contains('RÍOS'))));
    });
  });

  test('un masivo sin sortear: nadie tiene mesa ni sillas', () {
    final ficha = fichaDePrueba(sorteado: false);
    expect(ficha.masivo, isTrue);
    expect(ficha.personas, isNotEmpty);
    for (final p in ficha.personas.values) {
      expect(p.mesa, isNull, reason: p.nombre);
      expect(p.sillas, isNull, reason: p.nombre);
    }
    // La música, si está cargada, sí.
    expect(ficha.de(idDe('perez'))!.musica, 'Tusa · Karol G');
  });

  test('un particular no trae personas: el tótem usa la fila', () {
    final ficha = FichaTotem.desdePuerta(
      eventoParticular,
      PuertaDelEvento.particular([filaSuelta('i1', 'LÓPEZ, MARTA', mesa: '4')]),
    );
    expect(ficha.masivo, isFalse);
    expect(ficha.personas, isEmpty);
    expect(ficha.familiaDe('i1'), 'i1');
  });

  test('lo cargado a mano en la lista de un masivo no entra en la ficha', () {
    final ficha = FichaTotem.desdePuerta(
      eventoMasivo,
      PuertaDelEvento.masivo(
        alumnos: alumnosDeLaFicha(),
        invitados: [filaSuelta('a-mano', 'INVITADO ESPECIAL', mesa: '1')],
      ),
    );
    expect(ficha.de('a-mano'), isNull);
    expect(ficha.familiaDe('a-mano'), 'a-mano');
  });

  group('por el puente', () {
    test('ida y vuelta, igual', () {
      final ficha = fichaDePrueba();
      final vuelta = FichaTotem.decodificar(ficha.codificar())!;
      expect(vuelta.eventoId, ficha.eventoId);
      expect(vuelta.masivo, isTrue);
      expect(vuelta.personas.keys, unorderedEquals(ficha.personas.keys));
      for (final p in ficha.personas.values) {
        final q = vuelta.de(p.id)!;
        expect(
          [q.nombre, q.familia, q.esAlumno, q.mesa, q.sillas, q.musica, q.titular],
          [p.nombre, p.familia, p.esAlumno, p.mesa, p.sillas, p.musica, p.titular],
        );
      }
    });

    test('un particular, también', () {
      final vuelta = FichaTotem.decodificar(
        const FichaTotem.particular(eventoParticular).codificar(),
      )!;
      expect(vuelta.masivo, isFalse);
      expect(vuelta.personas, isEmpty);
    });

    test('lo que no se puede leer no rompe: el tótem sigue con la que tenía', () {
      expect(FichaTotem.decodificar(null), isNull);
      expect(FichaTotem.decodificar(''), isNull);
      expect(FichaTotem.decodificar('no es json'), isNull);
      expect(FichaTotem.decodificar('[1, 2]'), isNull);
      expect(FichaTotem.decodificar('{"masivo": true}'), isNull);
      // Una persona rota se saltea; las demás quedan.
      final ficha = FichaTotem.decodificar(
        '{"evento_id": "e", "masivo": true, "personas": '
        '[{"id": 3}, {"id": "x", "n": "PÉREZ, JUAN", "a": true}]}',
      )!;
      expect(ficha.personas.keys, ['x']);
      expect(ficha.de('x')!.familia, 'x');
    });

    test('una institución de 1.200 personas viaja en menos de 250 KB', () {
      final alumnos = [
        for (var i = 0; i < 400; i++)
          alumnoDePrueba(
            'alumno-$i',
            'APELLIDOLARGO$i, NOMBRE SEGUNDO',
            mesas: [i % 140 + 1],
            sillas: 2,
            acomp: ['ACOMPAÑANTE UNO $i', 'ACOMPAÑANTE DOS $i'],
            musica: 'Una canción bastante larga · Un artista',
          ),
      ];
      final ficha = FichaTotem.desdePuerta(
        eventoMasivo,
        PuertaDelEvento.masivo(alumnos: alumnos, invitados: const []),
      );
      expect(ficha.personas.length, 1200);
      final kb = ficha.codificar().length / 1024;
      expect(kb, lessThan(250));
      expect(FichaTotem.decodificar(ficha.codificar())!.personas.length, 1200);
    });
  });

  group('el plano de la fiesta', () {
    final salon = ArmadosPredefinidos.normal2aPagina3();
    PuertaDelEvento masivo() => PuertaDelEvento.masivo(
          alumnos: alumnosDeLaFicha(),
          invitados: const [],
        );

    test('va y vuelve por el puente, con sus mesas, hojas e ingreso', () {
      final ficha = FichaTotem.desdePuerta(eventoMasivo, masivo(), plano: salon);
      final vuelta = FichaTotem.decodificar(ficha.codificar())!.plano!;
      expect(vuelta.numeros, salon.numeros);
      expect(vuelta.hojas.map((h) => h.id), salon.hojas.map((h) => h.id));
      expect(vuelta.sectores.length, salon.sectores.length);
      expect(vuelta.ingreso!.x, salon.ingreso!.x);
      for (final m in salon.mesas) {
        expect(vuelta.mesa(m.numero)!.x, m.x);
        expect(vuelta.mesa(m.numero)!.y, m.y);
      }
    });

    test('un particular no lleva plano, aunque se lo pasen', () {
      final ficha = FichaTotem.desdePuerta(
        eventoParticular,
        PuertaDelEvento.particular(const []),
        plano: salon,
      );
      expect(ficha.plano, isNull);
      expect(FichaTotem.decodificar(ficha.codificar())!.plano, isNull);
    });

    test('un plano que no se puede leer no tira la ficha: va sin plano', () {
      for (final roto in ['"plano": 3', '"plano": {"mesas": "no"}',
          '"plano": {"hojas": [], "mesas": []}']) {
        final ficha = FichaTotem.decodificar(
          '{"evento_id": "e", "masivo": true, "personas": '
          '[{"id": "x", "n": "PÉREZ, JUAN", "a": true}], $roto}',
        );
        expect(ficha, isNotNull, reason: roto);
        expect(ficha!.plano, isNull, reason: roto);
        expect(ficha.de('x'), isNotNull, reason: roto);
      }
    });

    test('un salón de 140 mesas suma menos de 25 KB', () {
      final sinPlano = FichaTotem.desdePuerta(eventoMasivo, masivo());
      final conPlano =
          FichaTotem.desdePuerta(eventoMasivo, masivo(), plano: salon);
      final kb =
          (conPlano.codificar().length - sinPlano.codificar().length) / 1024;
      expect(kb, lessThan(25));
    });
  });
}
