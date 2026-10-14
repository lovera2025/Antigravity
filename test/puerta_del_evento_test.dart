// Lo que se ve en Recepción de un evento particular y de uno masivo, sin
// pantalla ni base: quiénes aparecen, con qué datos, la búsqueda, los filtros y
// qué hace Enter.
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/recepcion/services/lista_puerta.dart';
import 'package:arguello_events/features/recepcion/services/puerta_del_evento.dart';
import 'package:arguello_events/models/cliente.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/evento.dart';
import 'package:arguello_events/models/invitado.dart';
import 'package:arguello_events/models/sillas_reparto.dart';

const _ev = 'e0000000-0000-4000-8000-000000000001';
final _hora = DateTime.utc(2026, 12, 12, 1, 41); // 22:41 en Argentina

ContratoAlumno _alumno(
  String id,
  String nombre, {
  List<int> mesas = const [],
  int extras = 0,
  int sillas = 0,
  List<String> acomp = const [],
  int? cantidadAcomp,
  String? musica,
  String? division = '5° B',
}) =>
    ContratoAlumno(
      id: id,
      eventoId: _ev,
      nombreAlumno: nombre,
      cantidadAcompanantes: cantidadAcomp ?? acomp.length,
      nombresAcompanantes: acomp,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      sillasExtraCantidad: sillas,
      sillasExtraPrecioTotal: 8000.0 * sillas,
      numeroMesa:
          mesas.isEmpty ? null : MesasExtraUtils.formatearAsignacionMesas(mesas),
      cursoDivision: division,
      musicaElegida: musica,
    );

Invitado _fila(
  String id,
  String nombre, {
  String dni = '',
  String? mesa,
  bool adentro = false,
}) =>
    Invitado(
      id: id,
      eventoId: _ev,
      nombreCompleto: nombre,
      dni: dni,
      numeroMesa: mesa,
      estadoIngreso:
          adentro ? EstadoIngreso.ingresado : EstadoIngreso.pendiente,
      updatedAt: _hora,
    );

SillasReparto _reparto(String contrato, {required int principal, required int sillas, required int mesas}) =>
    SillasReparto(
      id: 'r-$contrato',
      contratoAlumnoId: contrato,
      sillasPrincipal: principal,
      sillasExtra: sillas,
      mesas: mesas,
      createdAt: _hora,
      updatedAt: _hora,
    );

/// Una institución chica ya sorteada.
List<ContratoAlumno> _sorteada() => [
      _alumno('perez', 'PÉREZ, JUAN MARTÍN',
          mesas: [12], sillas: 2, acomp: ['GÓMEZ, ANA', 'PÉREZ, LUIS'],
          musica: 'Tusa · Karol G'),
      _alumno('acosta', 'ACOSTA, LUCÍA',
          mesas: [14, 15], extras: 1, sillas: 3, division: '5° A'),
      _alumno('benitez', 'BENÍTEZ, TOMÁS', mesas: [13], acomp: ['BENÍTEZ, SOL']),
      _alumno('baja', '[BAJA] RÍOS, MARTA', mesas: [16]),
    ];

/// La misma, antes del sorteo.
List<ContratoAlumno> _sinSortear() => [
      _alumno('perez', 'PÉREZ, JUAN MARTÍN',
          sillas: 2, acomp: ['GÓMEZ, ANA', 'PÉREZ, LUIS'], musica: 'Tusa · Karol G'),
      _alumno('acosta', 'ACOSTA, LUCÍA', extras: 1, sillas: 3, division: '5° A'),
      _alumno('benitez', 'BENÍTEZ, TOMÁS', acomp: ['BENÍTEZ, SOL']),
      _alumno('baja', '[BAJA] RÍOS, MARTA'),
    ];

GrupoPuerta _grupo(PuertaDelEvento p, String nombre) =>
    p.grupos.firstWhere((g) => g.titular.nombre == nombre);

void main() {
  group('particular', () {
    final p = PuertaDelEvento.particular([
      _fila('i3', 'SOSA, ELENA', dni: '33000222', mesa: '4'),
      _fila('i1', 'LÓPEZ, MARTA', dni: '30123456', mesa: '4', adentro: true),
      _fila('i2', 'RÍOS, PABLO', dni: '28555111', mesa: '7'),
    ]);

    test('una persona por fila, por nombre, con DNI y mesa', () {
      expect(p.masivo, isFalse);
      expect(p.sorteado, isTrue);
      expect(p.grupos.map((g) => g.titular.nombre),
          ['LÓPEZ, MARTA', 'RÍOS, PABLO', 'SOSA, ELENA']);
      expect(p.grupos.first.titular.dni, '30123456');
      expect(p.grupos.first.titular.mesa, '4');
      expect(p.grupos.every((g) => g.cargadoAMano), isTrue);
      expect(p.grupos.every((g) => g.acompanantes.isEmpty), isTrue);
    });

    test('el progreso', () {
      expect(p.total, 3);
      expect(p.adentro, 1);
      expect(p.faltan, 2);
      expect(p.cuantos(FiltroPuerta.adentro), 1);
    });

    test('se busca por DNI con cuatro cifras o más, y por mesa con menos', () {
      expect(p.buscar('3012').single.titular.nombre, 'LÓPEZ, MARTA');
      expect(p.buscar('4').map((g) => g.titular.nombre),
          ['LÓPEZ, MARTA', 'SOSA, ELENA']);
      // "55" no es una mesa de nadie, y con dos cifras no se mira el DNI.
      expect(p.buscar('55'), isEmpty);
    });
  });

  group('masivo sin sortear', () {
    final p = PuertaDelEvento.masivo(alumnos: _sinSortear(), invitados: const []);

    test('están todos menos los de baja, con el aviso de que no se sorteó', () {
      expect(p.masivo, isTrue);
      expect(p.sorteado, isFalse);
      expect(p.bajas, 1);
      expect(p.grupos.map((g) => g.titular.nombre),
          ['ACOSTA, LUCÍA', 'BENÍTEZ, TOMÁS', 'PÉREZ, JUAN MARTÍN']);
    });

    test('sin mesa ni sillas, aunque tengan sillas compradas', () {
      for (final g in p.grupos) {
        expect(g.titular.mesa, isNull);
        expect(g.sillas, isNull);
        expect(g.sinMesa, isFalse, reason: 'no se sorteó: no es que le falte');
        expect(g.sillasAConfirmar, isFalse);
      }
    });

    test('acompañantes y música solo si están cargados', () {
      final perez = _grupo(p, 'PÉREZ, JUAN MARTÍN');
      expect(perez.acompanantes.map((a) => a.nombre), ['GÓMEZ, ANA', 'PÉREZ, LUIS']);
      expect(perez.acompanantes.first.acompanaA, 'PÉREZ, JUAN MARTÍN');
      expect(perez.musica, 'Tusa · Karol G');
      final acosta = _grupo(p, 'ACOSTA, LUCÍA');
      expect(acosta.acompanantes, isEmpty);
      expect(acosta.musica, isNull);
      expect(acosta.division, '5° A');
    });

    test('nadie tiene fila todavía: se cuenta igual y se puede ingresar', () {
      expect(p.total, 6);
      expect(p.adentro, 0);
      expect(p.personas.every((x) => x.fila == null), isTrue);
      final r = p.alApretarEnter('acosta');
      expect(r.ingresa, isTrue);
      expect(r.persona!.id, idInvitadoPuerta('acosta', 0));
    });

    test('los ids son los mismos que arma la lista de la puerta', () {
      final perez = _grupo(p, 'PÉREZ, JUAN MARTÍN');
      expect(perez.titular.id, idInvitadoPuerta('perez', 0));
      expect(perez.acompanantes.map((a) => a.id),
          [idInvitadoPuerta('perez', 1), idInvitadoPuerta('perez', 2)]);
    });

    test('acompañantes sin nombre: se cuentan aparte, sin fila', () {
      final q = PuertaDelEvento.masivo(
        alumnos: [_alumno('x', 'VEGA, ANA', acomp: ['VEGA, LUZ'], cantidadAcomp: 3)],
        invitados: const [],
      );
      expect(q.grupos.single.acompanantes, hasLength(1));
      expect(q.grupos.single.acompanantesSinNombre, 2);
    });
  });

  group('masivo sorteado', () {
    test('la mesa y, debajo, las sillas que le tocan', () {
      final p = PuertaDelEvento.masivo(alumnos: _sorteada(), invitados: const []);
      expect(p.sorteado, isTrue);
      final perez = _grupo(p, 'PÉREZ, JUAN MARTÍN');
      expect(perez.titular.mesa, '12');
      expect(perez.acompanantes.first.mesa, '12');
      expect(perez.sillas, '10 sillas (8 + 2 extra)');
      expect(_grupo(p, 'BENÍTEZ, TOMÁS').sillas, '8 sillas');
    });

    test('con dos mesas, cuántas sillas en cada una, con el reparto de siempre '
        'mientras la familia no eligió', () {
      final p = PuertaDelEvento.masivo(alumnos: _sorteada(), invitados: const []);
      final acosta = _grupo(p, 'ACOSTA, LUCÍA');
      expect(acosta.titular.mesa, '14-15');
      expect(acosta.sillas, '14: 10 sillas · 15: 9 sillas');
      expect(acosta.sillasAConfirmar, isTrue);
    });

    test('con el reparto que eligió la familia', () {
      final p = PuertaDelEvento.masivo(
        alumnos: _sorteada(),
        repartos: {'acosta': _reparto('acosta', principal: 1, sillas: 3, mesas: 2)},
        invitados: const [],
      );
      final acosta = _grupo(p, 'ACOSTA, LUCÍA');
      expect(acosta.sillas, '14: 9 sillas · 15: 10 sillas');
      expect(acosta.sillasAConfirmar, isFalse);
    });

    test('un alumno sin mesa en un evento sorteado lo dice', () {
      final p = PuertaDelEvento.masivo(
        alumnos: [..._sorteada(), _alumno('sinmesa', 'ZAPATA, IVÁN')],
        invitados: const [],
      );
      final z = _grupo(p, 'ZAPATA, IVÁN');
      expect(z.sinMesa, isTrue);
      expect(z.titular.mesa, isNull);
      expect(z.sillas, isNull);
    });

    test('quién entró sale de la lista de la puerta, por el id fijo', () {
      final p = PuertaDelEvento.masivo(
        alumnos: _sorteada(),
        invitados: [
          _fila(idInvitadoPuerta('perez', 0), 'PÉREZ, JUAN MARTÍN',
              mesa: '12', adentro: true),
          _fila(idInvitadoPuerta('perez', 1), 'GÓMEZ, ANA', mesa: '12'),
        ],
      );
      final perez = _grupo(p, 'PÉREZ, JUAN MARTÍN');
      expect(perez.titular.ingresado, isTrue);
      expect(perez.titular.textoHora, isNotNull);
      expect(perez.acompanantes[0].ingresado, isFalse);
      expect(perez.acompanantes[0].fila, isNotNull);
      expect(perez.acompanantes[1].fila, isNull);
      expect(p.adentro, 1);
    });

    test('lo cargado a mano va al final; lo que quedó de una baja o de un '
        'acompañante quitado no aparece', () {
      final p = PuertaDelEvento.masivo(
        alumnos: _sorteada(),
        invitados: [
          _fila('a-mano-0000-4000-8000-000000000001', 'DJ INVITADO', dni: '20111222'),
          _fila(idInvitadoPuerta('baja', 0), '[BAJA] RÍOS, MARTA', mesa: '16'),
          _fila(idInvitadoPuerta('benitez', 2), 'ACOMPAÑANTE QUITADO', mesa: '13'),
        ],
      );
      expect(p.grupos.last.titular.nombre, 'DJ INVITADO');
      expect(p.grupos.last.cargadoAMano, isTrue);
      expect(p.personas.map((x) => x.nombre),
          isNot(contains('[BAJA] RÍOS, MARTA')));
      expect(p.personas.map((x) => x.nombre),
          isNot(contains('ACOMPAÑANTE QUITADO')));
      expect(p.grupos.where((g) => g.cargadoAMano), hasLength(1));
    });
  });

  group('la búsqueda', () {
    final p = PuertaDelEvento.masivo(alumnos: _sorteada(), invitados: const []);

    test('en cualquier orden, sin acentos, mayúsculas ni coma', () {
      for (final q in ['juan perez', 'perez juan', 'PÉREZ, JUAN', 'martin']) {
        expect(p.buscar(q).map((g) => g.titular.nombre), ['PÉREZ, JUAN MARTÍN'],
            reason: q);
      }
    });

    test('un número es una mesa; se puede mezclar con el nombre', () {
      expect(p.buscar('15').single.titular.nombre, 'ACOSTA, LUCÍA');
      expect(p.buscar('13').single.titular.nombre, 'BENÍTEZ, TOMÁS');
      expect(p.buscar('perez 13'), isEmpty);
      expect(p.buscar('benitez 13'), hasLength(1));
    });

    test('buscar a un acompañante muestra a su familia entera', () {
      final g = p.buscar('ana gomez').single;
      expect(g.titular.nombre, 'PÉREZ, JUAN MARTÍN');
      expect(g.acompanantes, hasLength(2));
    });

    test('vacía, están todos', () {
      expect(p.buscar('   '), hasLength(p.grupos.length));
    });

    test('normalizar', () {
      expect(normalizarPuerta('PÉREZ, Juan  Martín'), 'perez juan martin');
      expect(normalizarPuerta('Muñoz-Ibáñez'), 'munoz ibanez');
    });
  });

  group('los filtros', () {
    final p = PuertaDelEvento.masivo(
      alumnos: _sorteada(),
      invitados: [
        _fila(idInvitadoPuerta('perez', 0), 'PÉREZ, JUAN MARTÍN', adentro: true),
      ],
    );

    test('Faltan deja a la familia que tiene a alguien afuera', () {
      expect(p.buscar('', filtro: FiltroPuerta.faltan).map((g) => g.titular.nombre),
          ['ACOSTA, LUCÍA', 'BENÍTEZ, TOMÁS', 'PÉREZ, JUAN MARTÍN']);
    });

    test('Faltan saca a la familia que ya entró entera', () {
      final q = PuertaDelEvento.masivo(
        alumnos: _sorteada(),
        invitados: [
          _fila(idInvitadoPuerta('benitez', 0), 'BENÍTEZ, TOMÁS', adentro: true),
          _fila(idInvitadoPuerta('benitez', 1), 'BENÍTEZ, SOL', adentro: true),
        ],
      );
      expect(q.buscar('', filtro: FiltroPuerta.faltan).map((g) => g.titular.nombre),
          ['ACOSTA, LUCÍA', 'PÉREZ, JUAN MARTÍN']);
      expect(q.alApretarEnter('benitez', filtro: FiltroPuerta.faltan).aviso,
          'No hay nadie con esa búsqueda.');
    });

    test('Adentro deja a la familia que tiene a alguien adentro', () {
      expect(p.buscar('', filtro: FiltroPuerta.adentro).map((g) => g.titular.nombre),
          ['PÉREZ, JUAN MARTÍN']);
      expect(p.cuantos(FiltroPuerta.adentro), 1);
      expect(p.cuantos(FiltroPuerta.faltan), 5);
      expect(p.cuantos(FiltroPuerta.todos), 6);
    });
  });

  group('Enter', () {
    final p = PuertaDelEvento.masivo(
      alumnos: _sorteada(),
      invitados: [
        _fila(idInvitadoPuerta('benitez', 0), 'BENÍTEZ, TOMÁS',
            mesa: '13', adentro: true),
      ],
    );

    test('con una sola persona sin entrar, la ingresa', () {
      final r = p.alApretarEnter('lucia');
      expect(r.ingresa, isTrue);
      expect(r.persona!.nombre, 'ACOSTA, LUCÍA');
      expect(r.aviso, isNull);
    });

    test('la que coincide es ella, no su familia', () {
      // "juan perez" coincide con Juan; Ana y Luis van en su grupo pero no
      // coinciden: Enter ingresa a Juan.
      final r = p.alApretarEnter('juan perez');
      expect(r.ingresa, isTrue);
      expect(r.persona!.nombre, 'PÉREZ, JUAN MARTÍN');
    });

    test('con varias sin entrar no hace nada y dice cuántas', () {
      final r = p.alApretarEnter('12');
      expect(r.ingresa, isFalse);
      expect(r.cantidad, 3);
      expect(r.aviso, contains('Hay 3 sin ingresar'));
    });

    test('si la única que coincide ya entró, dice a qué hora', () {
      final r = p.alApretarEnter('tomas');
      expect(r.ingresa, isFalse);
      expect(r.aviso, startsWith('BENÍTEZ, TOMÁS ya ingresó a las '));
    });

    test('Benítez Sol sigue afuera: "13" la ingresa a ella', () {
      final r = p.alApretarEnter('13');
      expect(r.ingresa, isTrue);
      expect(r.persona!.nombre, 'BENÍTEZ, SOL');
    });

    test('sin nadie, lo dice; sin nada escrito, no hace nada', () {
      expect(p.alApretarEnter('zzz').aviso, 'No hay nadie con esa búsqueda.');
      final vacio = p.alApretarEnter('  ');
      expect(vacio.ingresa, isFalse);
      expect(vacio.aviso, isNull);
    });

    test('respeta el filtro', () {
      expect(p.alApretarEnter('lucia', filtro: FiltroPuerta.adentro).ingresa,
          isFalse);
    });
  });

  group('muchos', () {
    test('1.100 personas: el progreso y la búsqueda andan', () {
      final alumnos = [
        for (var i = 0; i < 400; i++)
          _alumno('a$i', 'ALUMNO$i, NOMBRE',
              mesas: [i + 1], acomp: ['ACOMP$i, UNO', 'ACOMP$i, DOS']),
      ];
      final p = PuertaDelEvento.masivo(alumnos: alumnos, invitados: const []);
      expect(p.total, 1200);
      expect(p.faltan, 1200);
      expect(p.buscar('alumno399').single.titular.mesa, '400');
      // "400" es la mesa, que es la del alumno 399.
      expect(p.alApretarEnter('400 dos').persona!.nombre, 'ACOMP399, DOS');
    });

    test('sin nadie, el progreso es cero sin dividir por cero', () {
      final p = PuertaDelEvento.masivo(alumnos: const [], invitados: const []);
      expect(p.total, 0);
      expect(p.adentro, 0);
      expect(p.sorteado, isFalse);
    });
  });

  test('el selector dice si el evento es particular o masivo', () {
    Evento ev(String modalidad) => Evento(
          id: _ev,
          clienteId: 'c',
          tipo: 'Egresados',
          fechaEvento: DateTime(2026, 12, 12),
          estado: EstadoEvento.confirmado,
          modalidad: modalidad,
          cliente: Cliente(id: 'c', nombreCompleto: 'ESCUELA NORMAL'),
        );
    expect(etiquetaEventoRecepcion(ev('masivo')), endsWith('· masivo'));
    expect(etiquetaEventoRecepcion(ev('masivo')), startsWith('ESCUELA NORMAL — '));
    expect(etiquetaEventoRecepcion(ev('particular')), endsWith('· particular'));
  });
}
