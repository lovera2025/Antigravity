// El aviso entre PCs y el del tótem llegan con dos formas según por dónde
// salieron (docs/SPEC_pulso_por_el_socket_2026-11-07.md).
//
// Por el socket (lo normal, con el canal unido) Supabase reenvía el mensaje tal
// cual: los datos vienen sueltos, más `type` y `event`, que agrega la librería.
// Por REST (el canal de quien manda todavía no se unió) el servidor los envuelve
// en `payload`. Hasta la 6.4.0 la app leía solo `payload`: lo del socket, que es
// casi todo, se tiraba sin error, y la otra PC se enteraba recién al volver a
// la ventana o con la red de 5 minutos.
//
// Las pruebas del motor con la forma del socket están en
// sync_en_reposo_test.dart y borrados_de_otra_pc_test.dart.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/core/services/cuerpo_del_broadcast.dart';
import 'package:arguello_events/core/services/sync_engine.dart';
import 'package:arguello_events/models/invitado.dart';

String _leer(String ruta) =>
    File(ruta).readAsStringSync().replaceAll('\r\n', '\n');

/// El motor descarta un id que no es UUID: tiene que tener 36 letras.
const _pago = 'e27b01aa-0000-4000-8000-000000000009';

void main() {
  /// Lo que manda `_emitirPulso`, después de que la librería le agrega `type` y
  /// `event` al mismo mapa (`RealtimeChannel.send`).
  Map<String, dynamic> pulso() => {
        'origen': 'pc-del-jefe',
        'tablas': ['pagos_contrato_alumno', 'contratos_alumnos'],
        'borrados': {
          'pagos_contrato_alumno': [_pago],
        },
      };

  Map<String, dynamic> porElSocket(Map<String, dynamic> datos) => {
        ...datos,
        'type': 'broadcast',
        'event': 'cambios',
      };

  /// Por REST la librería ya le agregó `type` y `event` al mapa antes de
  /// mandarlo, y el servidor lo envuelve.
  Map<String, dynamic> porRest(Map<String, dynamic> datos) => {
        'type': 'broadcast',
        'event': 'cambios',
        'payload': porElSocket(datos),
      };

  group('cuerpoDelBroadcast', () {
    test('las dos formas dan el mismo cuerpo', () {
      expect(cuerpoDelBroadcast(porElSocket(pulso())), pulso());
      expect(cuerpoDelBroadcast(porRest(pulso())), pulso());
    });

    test('del socket, type y event no quedan en el cuerpo', () {
      final c = cuerpoDelBroadcast(porElSocket(pulso()))!;
      expect(c.containsKey('type'), isFalse);
      expect(c.containsKey('event'), isFalse);
    });

    test('no toca el mensaje que recibe', () {
      final m = porElSocket(pulso());
      cuerpoDelBroadcast(m);
      expect(m['type'], 'broadcast');
      expect(m['event'], 'cambios');
    });

    test('un payload que no es un mapa da null: no se adivina', () {
      expect(cuerpoDelBroadcast({'payload': 'hola', 'type': 'broadcast'}), isNull);
      expect(cuerpoDelBroadcast({'payload': 3}), isNull);
      expect(cuerpoDelBroadcast({'payload': ['a']}), isNull);
    });

    test('un mensaje vacío da un cuerpo vacío', () {
      expect(cuerpoDelBroadcast({}), isEmpty);
      expect(cuerpoDelBroadcast({'type': 'broadcast', 'event': 'x'}), isEmpty);
    });

    test('el trabajo del pulso sale igual por el socket que por REST', () {
      final tablas = {'pagos_contrato_alumno', 'contratos_alumnos'};
      final socket = trabajoDelPulso(
        cuerpoDelBroadcast(porElSocket(pulso())),
        yo: 'esta-pc',
        tablasConocidas: tablas,
      );
      final rest = trabajoDelPulso(
        cuerpoDelBroadcast(porRest(pulso())),
        yo: 'esta-pc',
        tablasConocidas: tablas,
      );
      expect(socket.tablas, tablas);
      expect(socket.tablas, rest.tablas);
      expect(socket.borrados, {
        'pagos_contrato_alumno': {_pago},
      });
      expect(socket.borrados, rest.borrados);
      expect(socket.soloLatido, isFalse);
    });

    test('el eco propio por el socket no da trabajo', () {
      final t = trabajoDelPulso(
        cuerpoDelBroadcast(porElSocket(pulso())),
        yo: 'pc-del-jefe',
        tablasConocidas: {'pagos_contrato_alumno', 'contratos_alumnos'},
      );
      expect(t.estaVacio, isTrue);
    });

    test('el aviso del tótem, por el socket, se lee entero', () {
      final invitado = Invitado(
        id: 'i1',
        eventoId: 'e1',
        nombreCompleto: 'GÓMEZ, LAURA',
        dni: '30111222',
        numeroMesa: '12',
        estadoIngreso: EstadoIngreso.ingresado,
      );
      final aviso = invitado.paraAviso();
      final llegado = {...aviso, 'type': 'broadcast', 'event': 'checkin'};
      final leido = Invitado.fromJson(cuerpoDelBroadcast(llegado)!);
      expect(leido.id, 'i1');
      expect(leido.nombreCompleto, 'GÓMEZ, LAURA');
      expect(leido.numeroMesa, '12');

      final borrado = cuerpoDelBroadcast(
          {'id': 'i1', 'type': 'broadcast', 'event': 'guest_removed'});
      expect(borrado, {'id': 'i1'});
    });
  });

  group('quien recibe lee con cuerpoDelBroadcast', () {
    test('el motor', () {
      final s = _leer('lib/core/services/sync_engine.dart');
      final i = s.indexOf('void _alRecibirPulso(');
      final recibir = s.substring(i, s.indexOf('\n  }\n', i));
      expect(recibir, contains('cuerpoDelBroadcast(mensaje)'));
      expect(recibir, isNot(contains("mensaje['payload']")),
          reason: 'así se tiraba todo lo que llegaba por el socket');
    });

    test('el tótem', () {
      final s = _leer('lib/features/totem/totem_display.dart');
      expect(s, isNot(contains("payload['payload']")),
          reason: 'así el tótem de la web no saludaba al instante con '
              'Recepción abierta');
      expect(RegExp(r'cuerpoDelBroadcast\(').allMatches(s).length, 2,
          reason: 'checkin y guest_removed');
      // Ahora que el canal se atiende, al tótem de la PC de Recepción le llega
      // todo dos veces: una baja vieja del canal no saca lo que marcó el puente.
      final i = s.indexOf("event: 'guest_removed'");
      final baja = s.substring(i, s.indexOf('});', i));
      expect(baja, contains('vinoPorElPuente(id)'));
    });
  });

  group('la regla: ningún aviso nuestro lleva una clave payload', () {
    test('el aviso del tótem', () {
      final invitado = Invitado(
        id: 'i1',
        eventoId: 'e1',
        nombreCompleto: 'GÓMEZ, LAURA',
        dni: '30111222',
        estadoIngreso: EstadoIngreso.pendiente,
      );
      expect(invitado.paraAviso().containsKey('payload'), isFalse);
      expect(Invitado.sinDatosPrivados(invitado.toJson()).containsKey('payload'),
          isFalse);
      expect(invitado.toJson().containsKey('payload'), isFalse);
    });

    test('el pulso arma solo sus cuatro claves', () {
      final s = _leer('lib/core/services/sync_engine.dart');
      final i = s.indexOf('Future<void> _emitirPulso(');
      final emitir = s.substring(i, s.indexOf('\n  }\n', i));
      expect(emitir, isNot(contains("'payload'")));
    });
  });
}
