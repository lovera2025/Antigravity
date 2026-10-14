// Una institución inventada, como la ve el tótem: los alumnos de
// `puerta_en_memoria.dart` pasados por la ficha del evento. La usan los tests del
// tótem y `tool/totem_muestra_test.dart`.
import 'package:arguello_events/features/recepcion/services/lista_puerta.dart';
import 'package:arguello_events/features/recepcion/services/puerta_del_evento.dart';
import 'package:arguello_events/features/totem/services/ficha_totem.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/invitado.dart';
import 'package:arguello_events/models/sillas_reparto.dart';

import 'puerta_en_memoria.dart';

/// Los alumnos de la institución, sorteada o no.
List<ContratoAlumno> alumnosDeLaFicha({bool sorteado = true}) => [
      alumnoDePrueba('perez', 'PÉREZ, JUAN MARTÍN',
          mesas: sorteado ? [12] : const [],
          sillas: 2,
          acomp: ['GÓMEZ, ANA', 'PÉREZ, LUIS'],
          musica: 'Tusa · Karol G'),
      alumnoDePrueba('acosta', 'ACOSTA, LUCÍA',
          mesas: sorteado ? [14, 15] : const [],
          extras: 1,
          sillas: 3,
          acomp: ['ACOSTA, MARÍA'],
          musica: 'Despechá · Rosalía',
          division: '5° A'),
      alumnoDePrueba('benitez', 'BENÍTEZ, TOMÁS',
          mesas: sorteado ? [13] : const [], acomp: ['BENÍTEZ, SOL']),
      alumnoDePrueba('fernandez', 'FERNÁNDEZ, MÍA',
          mesas: sorteado ? [16] : const [],
          sillas: 1,
          acomp: ['FERNÁNDEZ, JUAN'],
          musica: 'Ella · Callejero Fino'),
      alumnoDePrueba('garcia', 'GARCÍA, BRUNO',
          mesas: sorteado ? [17] : const []),
      // Sin la base paga: después del sorteo queda sin mesa.
      alumnoDePrueba('sosa', 'SOSA, EMILIA'),
      alumnoDePrueba('baja', '[BAJA] RÍOS, MARTA',
          mesas: sorteado ? [18] : const [], acomp: ['RÍOS, PEDRO']),
    ];

/// La ficha de esa institución. [repartos], por id de alumno.
FichaTotem fichaDePrueba({
  bool sorteado = true,
  Map<String, SillasReparto> repartos = const {},
}) =>
    FichaTotem.desdePuerta(
      eventoMasivo,
      PuertaDelEvento.masivo(
        alumnos: alumnosDeLaFicha(sorteado: sorteado),
        repartos: repartos,
        invitados: const [],
      ),
    );

/// El id de su lugar en la lista de la puerta: 0 el alumno, 1.. sus
/// acompañantes.
String idDe(String alumno, [int lugar = 0]) => idInvitadoPuerta(alumno, lugar);

/// La fila de la lista de la puerta de alguien de la ficha, ya adentro, como le
/// llega al tótem.
Invitado filaDe(String alumno, [int lugar = 0, FichaTotem? ficha]) {
  final f = ficha ?? fichaDePrueba();
  final p = f.de(idDe(alumno, lugar))!;
  return Invitado(
    id: p.id,
    eventoId: eventoMasivo,
    nombreCompleto: p.nombre,
    dni: '',
    numeroMesa: p.mesa,
    estadoIngreso: EstadoIngreso.ingresado,
  );
}

/// Una fila de un particular, o cargada a mano.
Invitado filaSuelta(String id, String nombre, {String? mesa}) => Invitado(
      id: id,
      eventoId: eventoParticular,
      nombreCompleto: nombre,
      dni: '30123456',
      numeroMesa: mesa,
      estadoIngreso: EstadoIngreso.ingresado,
    );
