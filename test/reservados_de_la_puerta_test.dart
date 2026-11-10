// Los que se sientan en una mesa reservada (los profes), en la puerta y en el
// tótem (6.5.0).
//
// El 10-nov-2026 el usuario pidió que la mesa que la empresa les regala a los
// profesores, además de estar en el plano con sus nombres, ponga a cada profe
// en el buscador de Recepción y que el tótem lo salude con su mesa encendida,
// "igual que los alumnos". Salen del plano de la fiesta; no tienen contrato.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/modelo/reserva_de_mesa.dart';
import 'package:arguello_events/features/recepcion/central/pedidos_de_la_puerta.dart';
import 'package:arguello_events/features/recepcion/services/plano_de_la_puerta.dart';
import 'package:arguello_events/features/recepcion/services/puerta_del_evento.dart';
import 'package:arguello_events/features/recepcion/services/reservados_de_la_puerta.dart';
import 'package:arguello_events/features/totem/services/bienvenidas_totem.dart';
import 'package:arguello_events/features/totem/services/contenido_bienvenida.dart';
import 'package:arguello_events/features/totem/services/ficha_totem.dart';
import 'package:arguello_events/features/totem/services/puente_ficha.dart';
import 'package:arguello_events/features/recepcion/providers/recepcion_provider.dart'
    show AlumnosDeLaPuerta;
import 'package:arguello_events/models/evento.dart';
import 'package:arguello_events/models/invitado.dart';
import 'package:arguello_events/models/plano_evento.dart';
import 'package:arguello_events/models/totem_config.dart';

import 'helpers/puerta_en_memoria.dart';

const _evento = eventoMasivo;
final _armado = ArmadosPredefinidos.normal2aPaginas45();

PlanoEvento _plano(Map<int, String?> libres) => PlanoEvento.nuevo(
      eventoId: _evento,
      armado: _armado,
      estilo: EstiloPlano.gala,
      modo: ModoSorteo.entera,
      ahora: DateTime(2026, 11, 1),
    ).copyWith(
      config: ConfigPlano.vacia.copyWith(
        libres: {
          for (final e in libres.entries) e.key: MesaLibre(motivo: e.value),
        },
      ),
      ahora: DateTime(2026, 11, 1),
    );

const _profes = 'Reservada para Profes: GARCÍA, ANA; LÓPEZ, LUIS';

List<ReservadoPuerta> _reservados([String motivo = _profes]) =>
    reservadosDeLaPuerta(_evento, _plano({20: motivo}));

Invitado _fila(String id, String nombre, {bool adentro = true}) => Invitado(
      id: id,
      eventoId: _evento,
      nombreCompleto: nombre,
      dni: '',
      estadoIngreso:
          adentro ? EstadoIngreso.ingresado : EstadoIngreso.pendiente,
      updatedAt: DateTime.utc(2026, 12, 5, 22, 30),
    );

void main() {
  final alumnos = [
    alumnoDePrueba('perez', 'PÉREZ, JUAN', mesas: [12], acomp: ['GÓMEZ, ANA']),
  ];

  group('quiénes salen del plano', () {
    test('uno por nombre, con su mesa y para quién es', () {
      final r = _reservados();
      expect(r.map((x) => x.nombre), ['GARCÍA, ANA', 'LÓPEZ, LUIS']);
      expect(r.map((x) => x.mesa).toSet(), {20});
      expect(r.map((x) => x.para).toSet(), {'Profes'});
      expect(r.map((x) => x.id).toSet(), hasLength(2));
    });

    test('el id es fijo: no cambia con mayúsculas, acentos ni espacios', () {
      final a = idInvitadoReserva(_evento, 20, 'GARCÍA, ANA');
      expect(idInvitadoReserva(_evento, 20, '  garcia,  ana '), a);
      // Otra mesa, otra fiesta u otra persona, otro id.
      expect(idInvitadoReserva(_evento, 21, 'GARCÍA, ANA'), isNot(a));
      expect(idInvitadoReserva('otra', 20, 'GARCÍA, ANA'), isNot(a));
      expect(idInvitadoReserva(_evento, 20, 'GARCÍA, EVA'), isNot(a));
      expect(a, hasLength(36));
    });

    test('una mesa que no se usa, o reservada sin nombres, no pone a nadie',
        () {
      expect(
        reservadosDeLaPuerta(
          _evento,
          _plano({20: 'Columna', 21: null, 22: 'Reservada para Profes'}),
        ),
        isEmpty,
      );
      expect(reservadosDeLaPuerta(_evento, null), isEmpty);
    });

    test('una mesa que el armado ya no tiene, tampoco', () {
      expect(reservadosDeLaPuerta(_evento, _plano({9999: _profes})), isEmpty);
    });

    test('un nombre repetido en la misma mesa va una sola vez', () {
      final r = _reservados('Reservada para Profes: GARCÍA, ANA; garcia, ana');
      expect(r, hasLength(1));
    });
  });

  group('en Recepción', () {
    PuertaDelEvento puerta({List<Invitado> invitados = const []}) =>
        PuertaDelEvento.masivo(
          alumnos: alumnos,
          invitados: invitados,
          reservados: _reservados(),
        );

    test('un grupo por mesa, con su distinción y su mesa', () {
      final p = puerta();
      final g = p.grupos.singleWhere((g) => g.reservadaPara != null);
      expect(g.reservadaPara, 'Profes');
      expect(g.personas.map((x) => x.nombre), ['GARCÍA, ANA', 'LÓPEZ, LUIS']);
      expect(g.personas.map((x) => x.mesa).toSet(), {'20'});
      // No son alumnos ni acompañan a nadie; tampoco están cargados a mano.
      expect(g.personas.any((x) => x.esAlumno), isFalse);
      expect(g.personas.any((x) => x.acompanaA != null), isFalse);
      expect(g.cargadoAMano, isFalse);
      expect(g.contratoId, isNull);
      expect(g.puedeSumarSilla, isFalse);
      // Cuentan en el total de la noche, con la familia del alumno.
      expect(p.total, 4);
    });

    test('se los encuentra por el nombre y por la mesa', () {
      final p = puerta();
      expect(p.buscar('lopez').single.reservadaPara, 'Profes');
      expect(p.buscar('20').single.reservadaPara, 'Profes');
      final enter = p.alApretarEnter('ana garcia');
      expect(enter.persona?.nombre, 'GARCÍA, ANA');
    });

    test('quien entró figura adentro, por su id fijo', () {
      final ana = _reservados().first;
      final p = puerta(invitados: [_fila(ana.id, ana.nombre)]);
      final g = p.grupos.singleWhere((g) => g.reservadaPara != null);
      expect(g.titular.ingresado, isTrue);
      expect(g.acompanantes.single.ingresado, isFalse);
      expect(p.adentro, 1);
      // Y no aparece dos veces, como cargada a mano.
      expect(p.grupos.where((g) => g.cargadoAMano), isEmpty);
    });

    test('a quien se sacó de la mesa después de entrar no se lo esconde', () {
      final ana = _reservados().first;
      final p = PuertaDelEvento.masivo(
        alumnos: alumnos,
        invitados: [_fila(ana.id, ana.nombre)],
        reservados: _reservados('Reservada para Profes: LÓPEZ, LUIS'),
      );
      final aMano = p.grupos.singleWhere((g) => g.cargadoAMano);
      expect(aMano.titular.nombre, 'GARCÍA, ANA');
    });

    test('sin reservadas, la lista es la de siempre', () {
      final con = PuertaDelEvento.masivo(alumnos: alumnos, invitados: const []);
      expect(con.grupos.where((g) => g.reservadaPara != null), isEmpty);
      expect(con.total, 2);
    });

    test('viaja al celular con su distinción', () {
      final ana = _reservados().first;
      final ida = puerta(invitados: [_fila(ana.id, ana.nombre)]);
      final vuelta = PuertaDelEvento.fromJson(
        jsonDecode(jsonEncode(ida.toJson())) as Map<String, dynamic>,
        eventoId: _evento,
      );
      final g = vuelta.grupos.singleWhere((g) => g.reservadaPara != null);
      expect(g.reservadaPara, 'Profes');
      expect(g.personas.map((x) => x.nombre), ['GARCÍA, ANA', 'LÓPEZ, LUIS']);
      expect(g.titular.mesa, '20');
      expect(g.titular.ingresado, isTrue);
      // Una central de antes no manda la distinción: es una familia más.
      final viejo = jsonDecode(jsonEncode(ida.toJson())) as Map<String, dynamic>;
      for (final x in viejo['grupos'] as List) {
        (x as Map).remove('reservada');
      }
      expect(
        PuertaDelEvento.fromJson(viejo, eventoId: _evento)
            .grupos
            .where((g) => g.reservadaPara != null),
        isEmpty,
      );
    });

    test('no se les suma una silla de la noche: no tienen contrato', () {
      final g = puerta().grupos.singleWhere((g) => g.reservadaPara != null);
      final d = decidirSilla(
        pedido: PedidoPuerta(
          id: 'x',
          que: QuePide.sumarSilla,
          personaId: g.titular.id,
          silla: const DatosSilla(vale: '1-1'),
        ),
        grupo: g,
        deLaNoche: const [],
      );
      expect(d.haceAlgo, isFalse);
      expect(d.aviso, 'Las sillas de la noche son de las familias de alumnos.');
    });

    test('en el plano de la recepcionista, su mesa lleva quiénes se sientan',
        () {
      final salon = SalonParaLaPuerta.de(_armado, const TotemConfig(eventoId: _evento))!;
      final p = puerta();
      final g = p.grupos.singleWhere((g) => g.reservadaPara != null);
      expect(salon.tieneMesaDe(g), isTrue);
      expect(salon.deLaFamilia(g), isNotNull);
      final entero = salon.entero(p);
      expect(entero.familiaDeMesa[20], same(g));
      expect(entero.estado.info(20).ocupante?.nombre, 'GARCÍA +1');
      // Nadie entró todavía: su mesa está entre las que faltan.
      expect(entero.faltan, contains(20));
    });
  });

  group('en el tótem', () {
    FichaTotem ficha() => FichaTotem.desdePuerta(
          _evento,
          PuertaDelEvento.masivo(
            alumnos: alumnos,
            invitados: const [],
            reservados: _reservados(),
          ),
          plano: _armado,
        );

    test('la ficha los conoce: su mesa, su distinción y con quién se sientan',
        () {
      final f = ficha();
      final r = _reservados();
      final ana = f.de(r[0].id)!;
      final luis = f.de(r[1].id)!;
      expect(ana.nombre, 'GARCÍA, ANA');
      expect(ana.mesa, '20');
      expect(ana.grupo, 'Profes');
      expect(ana.esAlumno, isFalse);
      expect(ana.titular, isNull);
      // Se saludan juntos si llegan juntos.
      expect(f.familiaDe(luis.id), f.familiaDe(ana.id));
      // Y viaja por el puente a la ventana del tótem.
      final vuelta = FichaTotem.decodificar(f.codificar())!;
      expect(vuelta.de(ana.id)!.grupo, 'Profes');
      expect(vuelta.de(ana.id)!.mesa, '20');
    });

    test('un profe solo: su nombre, "Profes" y su mesa', () {
      final r = _reservados();
      final c = ContenidoBienvenida.armar(
        BienvenidaTotem(
          familia: r[0].id,
          personas: [_fila(r[0].id, r[0].nombre)],
          empezo: DateTime(2026, 12, 5, 22, 30),
        ),
        ficha: ficha(),
        cfg: const TotemConfig(eventoId: _evento),
      );
      expect(c.nombres, ['GARCÍA, ANA']);
      expect(c.acompanaA, 'Profes');
      expect(c.mesa, '20');
      expect(c.conQuien, isNull);
    });

    test('dos que llegan juntos: los dos nombres, una sola mesa', () {
      final r = _reservados();
      final c = ContenidoBienvenida.armar(
        BienvenidaTotem(
          familia: r[0].id,
          personas: [
            _fila(r[0].id, r[0].nombre),
            _fila(r[1].id, r[1].nombre),
          ],
          empezo: DateTime(2026, 12, 5, 22, 30),
        ),
        ficha: ficha(),
        cfg: const TotemConfig(eventoId: _evento),
      );
      expect(c.nombres, ['GARCÍA, ANA', 'LÓPEZ, LUIS']);
      expect(c.acompanaA, 'Profes');
      expect(c.mesa, '20');
    });

    test('a un alumno y a su acompañante se los saluda como siempre', () {
      final f = ficha();
      final alumno = f.personas.values.singleWhere((p) => p.esAlumno);
      expect(alumno.grupo, isNull);
      final acomp = f.personas.values
          .singleWhere((p) => !p.esAlumno && p.grupo == null);
      expect(acomp.titular, 'PÉREZ, JUAN');
    });

    test('la ficha que arma la PC para la ventana del tótem los trae', () async {
      final f = await armarFichaTotem(
        _evento,
        leerEvento: (id) async => Evento(
          id: id,
          clienteId: 'c',
          tipo: 'Recepción',
          fechaEvento: DateTime(2026, 12, 5),
          estado: EstadoEvento.confirmado,
          modalidad: 'masivo',
        ),
        leerAlumnos: (_) async => AlumnosDeLaPuerta(alumnos, const {}),
        leerPlano: (_) async => _armado,
        leerReservados: (id) async => reservadosDeLaPuerta(id, _plano({20: _profes})),
      );
      expect(f.personas.values.where((p) => p.grupo == 'Profes'), hasLength(2));
      // Si no se pueden leer, la ficha va sin ellos y no se cae.
      final sin = await armarFichaTotem(
        _evento,
        leerEvento: (id) async => Evento(
          id: id,
          clienteId: 'c',
          tipo: 'Recepción',
          fechaEvento: DateTime(2026, 12, 5),
          estado: EstadoEvento.confirmado,
          modalidad: 'masivo',
        ),
        leerAlumnos: (_) async => AlumnosDeLaPuerta(alumnos, const {}),
        leerReservados: (_) async => throw StateError('base cerrada'),
      );
      expect(sin.personas.values.where((p) => p.grupo != null), isEmpty);
      expect(sin.personas, isNotEmpty);
    });
  });

  test('lo que se escribe debajo de la mesa en la pantalla', () {
    expect(const ReservaDeMesa('Profes').rotuloEnPantalla, 'Profes');
    expect(
      const ReservaDeMesa('Profes', ['GARCÍA, ANA']).rotuloEnPantalla,
      'GARCÍA',
    );
    expect(
      const ReservaDeMesa('Profes', ['GARCÍA, ANA', 'LÓPEZ, LUIS', 'Eva Díaz'])
          .rotuloEnPantalla,
      'GARCÍA +2',
    );
    // Un nombre sin coma va entero.
    expect(
      const ReservaDeMesa('Profes', ['Eva Díaz']).rotuloEnPantalla,
      'Eva Díaz',
    );
  });
}
