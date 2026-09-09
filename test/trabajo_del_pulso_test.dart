// El pulso es un aviso entre PCs, y lo que llega por la red es dato, no orden.
//
// Cuando una PC termina de subir manda un broadcast diciendo qué tablas tocó y
// qué borró, para que la otra baje solo eso en vez de esperar hasta un minuto a
// que le toque el turno. El mensaje lo escribió otro proceso, así que el
// receptor no puede confiar en su forma: una tabla inventada sería una consulta
// a algo que no existe, y un id cualquiera sería un `delete` local contra la
// base de producción.
//
// Y hay un detalle que se olvida fácil: un broadcast **le vuelve también a quien
// lo mandó**. Sin descartar el eco, cada PC saldría a bajar lo que acaba de
// subir, en un ida y vuelta que no termina nunca.
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/core/services/sync_engine.dart';

/// Las que el motor sabe bajar. Una tabla fuera de esta lista no existe para él.
const conocidas = {
  'presupuestos',
  'presupuesto_servicios',
  'eventos',
  'eventos_servicios',
  'contratos_alumnos',
};

const idA = '3878119d-0567-45ba-a979-f87878869831';
const idB = '6ddc710f-a12d-4990-b686-e27112df61c9';

void main() {
  group('trabajoDelPulso', () {
    test('el caso normal: la otra PC tocó un presupuesto', () {
      final trabajo = trabajoDelPulso(
        {
          'origen': 'pc-1757000000000',
          'tablas': ['presupuestos', 'presupuesto_servicios'],
          'borrados': <String, dynamic>{},
        },
        yo: 'pc-1757999999999',
        tablasConocidas: conocidas,
      );

      expect(trabajo.tablas, {'presupuestos', 'presupuesto_servicios'});
      expect(trabajo.borrados, isEmpty);
      expect(trabajo.estaVacio, isFalse);
    });

    test('el eco propio se descarta', () {
      final trabajo = trabajoDelPulso(
        {
          'origen': 'pc-1757999999999',
          'tablas': ['presupuestos'],
        },
        yo: 'pc-1757999999999',
        tablasConocidas: conocidas,
      );

      expect(
        trabajo.estaVacio,
        isTrue,
        reason: 'si no, la PC baja lo que acaba de subir, en loop',
      );
    });

    test('sin saber quién soy, no se descarta nada', () {
      // `InstalacionId` puede no haber resuelto todavía. Bajar de más es
      // inocuo; tomar un aviso ajeno por propio sería perderse el cambio.
      final trabajo = trabajoDelPulso(
        {
          'origen': 'pc-1757999999999',
          'tablas': ['presupuestos'],
        },
        yo: null,
        tablasConocidas: conocidas,
      );

      expect(trabajo.tablas, {'presupuestos'});
    });

    test('las tablas que el motor no conoce no entran', () {
      final trabajo = trabajoDelPulso(
        {
          'origen': 'otra',
          'tablas': [
            'presupuestos',
            'pg_catalog.pg_tables',
            'tabla_que_no_existe',
            '',
            null,
          ],
        },
        yo: 'yo',
        tablasConocidas: conocidas,
      );

      expect(trabajo.tablas, {'presupuestos'});
    });

    test('los borrados llegan por tabla, y solo con forma de UUID', () {
      final trabajo = trabajoDelPulso(
        {
          'origen': 'otra',
          'tablas': ['presupuestos'],
          'borrados': {
            'presupuestos': [idA, idB],
            'eventos': [idA],
          },
        },
        yo: 'yo',
        tablasConocidas: conocidas,
      );

      expect(trabajo.borrados['presupuestos'], {idA, idB});
      expect(trabajo.borrados['eventos'], {idA});
    });

    test('un id que no es UUID no llega a ser un delete', () {
      final trabajo = trabajoDelPulso(
        {
          'origen': 'otra',
          'borrados': {
            'presupuestos': ['', '1', "' OR 1=1 --", null, idA],
          },
        },
        yo: 'yo',
        tablasConocidas: conocidas,
      );

      expect(
        trabajo.borrados['presupuestos'],
        {idA},
        reason: 'lo demás no tiene forma de id: no se toca la base con eso',
      );
    });

    test('borrados sobre una tabla desconocida se ignoran enteros', () {
      final trabajo = trabajoDelPulso(
        {
          'origen': 'otra',
          'borrados': {
            'perfiles': [idA],
            'auth.users': [idB],
          },
        },
        yo: 'yo',
        tablasConocidas: conocidas,
      );

      expect(trabajo.estaVacio, isTrue);
    });

    test('un mensaje con cualquier forma produce trabajo vacío', () {
      for (final basura in <Object?>[
        null,
        'un string',
        42,
        <Object?>[],
        {'origen': 'otra'},
        {'origen': 'otra', 'tablas': 'presupuestos'},
        {'origen': 'otra', 'tablas': null, 'borrados': 'nada'},
      ]) {
        final trabajo = trabajoDelPulso(
          basura,
          yo: 'yo',
          tablasConocidas: conocidas,
        );
        expect(
          trabajo.estaVacio,
          isTrue,
          reason: 'con $basura no hay nada que hacer, y no se rompe nada',
        );
      }
    });
  });
}
