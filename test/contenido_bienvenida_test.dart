// Lo que dice la bienvenida del tótem (`contenido_bienvenida.dart`) y cuándo
// hay QR (`hayQrEnElTotem`). Cómo se ve en cada apariencia está en
// `test/escena_totem_test.dart`.
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/totem/services/bienvenidas_totem.dart';
import 'package:arguello_events/features/totem/services/contenido_bienvenida.dart';
import 'package:arguello_events/features/totem/services/ficha_totem.dart';
import 'package:arguello_events/features/totem/estilos/totem_estilo.dart';
import 'package:arguello_events/models/invitado.dart';
import 'package:arguello_events/models/totem_config.dart';

import 'helpers/ficha_de_prueba.dart';
import 'helpers/puerta_en_memoria.dart';

final _t0 = DateTime(2026, 12, 12, 22);
const _cfg = TotemConfig(eventoId: eventoMasivo);

BienvenidaTotem _tarjeta(List<Invitado> personas) => BienvenidaTotem(
      familia: personas.first.id,
      personas: personas,
      empezo: _t0,
    );

ContenidoBienvenida _armar(
  List<Invitado> personas, {
  FichaTotem? ficha,
  TotemConfig cfg = _cfg,
}) =>
    ContenidoBienvenida.armar(
      _tarjeta(personas),
      ficha: ficha ?? fichaDePrueba(),
      cfg: cfg,
    );

void main() {
  group('lo que dice', () {
    test('la familia: el alumno en grande, con quién viene, mesa y sillas', () {
      final c = _armar([filaDe('perez'), filaDe('perez', 1), filaDe('perez', 2)]);
      expect(c.saludo, '¡Bienvenidos!');
      expect(c.nombres, ['PÉREZ, JUAN MARTÍN']);
      expect(c.conQuien, 'con GÓMEZ, ANA y PÉREZ, LUIS');
      expect(c.acompanaA, isNull);
      expect(c.rotuloMesa, 'Mesa');
      expect(c.mesa, '12');
      expect(c.sillas, '10 sillas (8 + 2 extra)');
      expect(c.musica, 'Tusa · Karol G');
    });

    test('el alumno va primero aunque haya entrado después', () {
      final c = _armar([filaDe('perez', 1), filaDe('perez')]);
      expect(c.nombres, ['PÉREZ, JUAN MARTÍN']);
      expect(c.conQuien, 'con GÓMEZ, ANA');
    });

    test('el alumno solo: saludo de siempre, sin "con"', () {
      final c = _armar([filaDe('garcia')]);
      expect(c.saludo, '¡Bienvenido!');
      expect(c.nombres, ['GARCÍA, BRUNO']);
      expect(c.conQuien, isNull);
      expect(c.mesa, '17');
      expect(c.sillas, '8 sillas');
      expect(c.musica, isNull, reason: 'no tiene música cargada');
    });

    test('un acompañante solo: a quién acompaña', () {
      final c = _armar([filaDe('perez', 1)]);
      expect(c.nombres, ['GÓMEZ, ANA']);
      expect(c.acompanaA, 'acompaña a PÉREZ, JUAN MARTÍN');
      expect(c.mesa, '12');
      expect(c.sillas, '10 sillas (8 + 2 extra)');
      expect(c.musica, isNull, reason: 'la música es del alumno');
    });

    test('dos acompañantes sin el alumno', () {
      final c = _armar([filaDe('perez', 1), filaDe('perez', 2)]);
      expect(c.nombres, ['GÓMEZ, ANA', 'PÉREZ, LUIS']);
      expect(c.acompanaA, 'acompañan a PÉREZ, JUAN MARTÍN');
      expect(c.saludo, '¡Bienvenidos!');
    });

    test('dos mesas: "Mesas", y las sillas de cada una', () {
      final c = _armar([filaDe('acosta')]);
      expect(c.rotuloMesa, 'Mesas');
      expect(c.mesa, '14-15');
      expect(c.sillas, '14: 10 sillas · 15: 9 sillas');
      expect(c.sillas, isNot(contains('confirmar')));
    });

    test('sin sortear: el saludo sin mesa ni sillas, con la música', () {
      final ficha = fichaDePrueba(sorteado: false);
      final c = _armar(
        [filaDe('perez', 0, ficha), filaDe('perez', 1, ficha)],
        ficha: ficha,
      );
      expect(c.mesa, isNull);
      expect(c.sillas, isNull);
      expect(c.musica, 'Tusa · Karol G');
      expect(c.conQuien, 'con GÓMEZ, ANA');
    });

    test('la fila con una mesa vieja no manda: la ficha dice sin sortear', () {
      final ficha = fichaDePrueba(sorteado: false);
      final vieja = Invitado(
        id: idDe('perez'),
        eventoId: eventoMasivo,
        nombreCompleto: 'PÉREZ, JUAN MARTÍN',
        dni: '',
        numeroMesa: '12',
        estadoIngreso: EstadoIngreso.ingresado,
      );
      expect(_armar([vieja], ficha: ficha).mesa, isNull);
    });

    test('el que quedó sin mesa en un evento sorteado: sin mesa, nunca '
        '"sin mesa"', () {
      final c = _armar([filaDe('sosa')]);
      expect(c.mesa, isNull);
      expect(c.sillas, isNull);
      for (final texto in [c.saludo, ...c.nombres, c.conQuien, c.acompanaA]) {
        expect(texto ?? '', isNot(contains(RegExp('sin mesa', caseSensitive: false))));
      }
    });

    test('con la música apagada en Personalizar, no va', () {
      final c = _armar(
        [filaDe('perez')],
        cfg: _cfg.copyWith(mostrarMusica: false),
      );
      expect(c.musica, isNull);
      expect(c.mesa, '12', reason: 'lo demás sigue igual');
    });

    test('un saludo escrito a mano no se pasa al plural', () {
      final c = _armar(
        [filaDe('perez'), filaDe('perez', 1)],
        cfg: _cfg.copyWith(mensajeBienvenida: '¡Hola, promo 2026!'),
      );
      expect(c.saludo, '¡Hola, promo 2026!');
    });

    test('un particular: nombre y mesa de la fila, como siempre', () {
      final c = ContenidoBienvenida.armar(
        _tarjeta([filaSuelta('i1', 'LÓPEZ, MARTA', mesa: '4')]),
        ficha: const FichaTotem.particular(eventoParticular),
        cfg: _cfg,
      );
      expect(c.saludo, '¡Bienvenido!');
      expect(c.nombres, ['LÓPEZ, MARTA']);
      expect(c.mesa, '4');
      expect(c.sillas, isNull);
      expect(c.musica, isNull);
      expect(c.conQuien, isNull);
    });

    test('sin ficha (la web) o alguien que la ficha no tiene: la fila', () {
      final suelta = filaSuelta('a-mano', 'INVITADO ESPECIAL', mesa: '1');
      for (final ficha in [null, fichaDePrueba()]) {
        final c = ContenidoBienvenida.armar(
          _tarjeta([suelta]),
          ficha: ficha,
          cfg: _cfg,
        );
        expect(c.nombres, ['INVITADO ESPECIAL']);
        expect(c.mesa, '1');
        expect(c.sillas, isNull);
      }
    });

    test('tres que llegan juntos: sin comas entre nombres', () {
      final ficha = FichaTotem(
        eventoId: eventoMasivo,
        masivo: true,
        personas: {
          for (final (id, n, alumno) in [
            ('a', 'PÉREZ, JUAN', true),
            ('b', 'GÓMEZ, ANA', false),
            ('c', 'SOSA, EVA', false),
            ('d', 'RÍOS, LUIS', false),
          ])
            id: PersonaFicha(id: id, nombre: n, familia: 'a', esAlumno: alumno),
        },
      );
      final c = ContenidoBienvenida.armar(
        _tarjeta([
          for (final id in ['a', 'b', 'c', 'd'])
            filaSuelta(id, ficha.de(id)!.nombre),
        ]),
        ficha: ficha,
        cfg: _cfg,
      );
      expect(c.conQuien, 'con GÓMEZ, ANA · SOSA, EVA y RÍOS, LUIS');
    });
  });

  group('el QR', () {
    test('en la ventana del escritorio: solo en un particular', () {
      expect(
        hayQrEnElTotem(
          enLaVentanaDelEscritorio: true,
          ficha: const FichaTotem.particular(eventoParticular),
        ),
        isTrue,
      );
      expect(
        hayQrEnElTotem(enLaVentanaDelEscritorio: true, ficha: fichaDePrueba()),
        isFalse,
      );
    });

    test('mientras no llega la ficha, no: podría ser un masivo', () {
      expect(
        hayQrEnElTotem(enLaVentanaDelEscritorio: true, ficha: null),
        isFalse,
      );
    });

    test('en la web, como siempre: no hay ficha que pedir', () {
      expect(
        hayQrEnElTotem(enLaVentanaDelEscritorio: false, ficha: null),
        isTrue,
      );
    });
  });
}
