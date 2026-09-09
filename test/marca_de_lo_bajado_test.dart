// El marcador del pull salía del reloj de la PC, y se compara contra el del
// servidor.
//
// `_pullTable` guardaba `DateTime.now()` de la máquina y en la pasada siguiente
// pedía `updated_at > esa marca`. Pero `updated_at` no lo escribe la app: lo
// sella Postgres con `now()`, en el servidor. Son dos relojes distintos, y la
// diferencia entre ellos entraba directo en el filtro.
//
// Con la PC adelantada el marcador queda en el futuro y las filas escritas en
// esa ventana caen del otro lado del filtro: no vuelven a pedirse nunca, sin un
// solo error en el log. Con la PC atrasada, la misma fila se re-baja siempre.
// Windows sincroniza por NTP, así que en general no se nota — pero cuando pasa,
// no avisa.
//
// La marca correcta es el `updated_at` más alto de lo que se acaba de bajar:
// sale del mismo reloj contra el que después se compara, y no cuesta un request
// extra. Y cuando no hay de dónde sacarla, no se inventa: el marcador se queda
// donde estaba.
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/core/services/sync_engine.dart';

/// `updated_at > marca` es el filtro real del pull: esto responde si la fila
/// volvería a bajar en la próxima pasada.
bool volveriaABajar(String marca, String updatedAtDeLaFila) =>
    DateTime.parse(updatedAtDeLaFila).toUtc().isAfter(
          DateTime.parse(marca).toUtc(),
        );

Map<String, dynamic> fila(String updatedAt) => {
      'id': 'x',
      'updated_at': updatedAt,
    };

void main() {
  group('marcaDeLoBajado', () {
    test('toma la fecha más alta, sin depender del orden en que vinieron', () {
      final desordenadas = [
        fila('2026-09-07T22:08:31.429740Z'),
        fila('2026-09-07T22:28:31.193341Z'), // la más nueva
        fila('2026-09-04T15:29:38.481649Z'),
      ];

      expect(
        marcaDeLoBajado(desordenadas, 'updated_at'),
        '2026-09-07T22:28:31.193341Z',
      );
    });

    test('la marca deja afuera lo que ya bajó y adentro lo que venga después', () {
      final bajadas = [
        fila('2026-09-07T22:08:31.429740Z'),
        fila('2026-09-07T22:28:31.193341Z'),
      ];

      final marca = marcaDeLoBajado(bajadas, 'updated_at')!;

      expect(
        volveriaABajar(marca, '2026-09-07T22:28:31.193341Z'),
        isFalse,
        reason: 'ya la tengo, pedirla de nuevo es tráfico al pedo',
      );
      expect(
        volveriaABajar(marca, '2026-09-07T22:28:31.193342Z'),
        isTrue,
        reason: 'un microsegundo después ya es una edición que no vi',
      );
    });

    test('el reloj de la PC no entra en la cuenta', () {
      // El caso que rompía: la PC va 5 minutos adelantada. Antes el marcador
      // quedaba en SU "ahora", o sea 5 minutos en el futuro del servidor, y todo
      // lo que se escribiera en esa ventana quedaba del otro lado del filtro.
      final relojDeLaPcAdelantado =
          DateTime.utc(2026, 9, 7, 22, 33, 31).toIso8601String();
      final loQueVino = [fila('2026-09-07T22:28:31.193341Z')];

      final marca = marcaDeLoBajado(loQueVino, 'updated_at')!;

      expect(
        DateTime.parse(marca).isBefore(DateTime.parse(relojDeLaPcAdelantado)),
        isTrue,
        reason: 'la marca sale del servidor, así que queda por detrás',
      );
      expect(
        volveriaABajar(marca, '2026-09-07T22:30:00.000000Z'),
        isTrue,
        reason:
            'una fila escrita en la ventana de desfasaje TIENE que volver a bajar',
      );
    });

    test('normaliza a UTC aunque la fila traiga una fecha con offset', () {
      // -03:00 es la hora de Córdoba; Supabase devuelve timestamptz.
      final marca = marcaDeLoBajado(
        [fila('2026-09-07T19:28:31.193341-03:00')],
        'updated_at',
      );

      expect(marca, isNotNull);
      expect(marca!.endsWith('Z'), isTrue);
      expect(
        DateTime.parse(marca),
        DateTime.utc(2026, 9, 7, 22, 28, 31, 193, 341),
      );
    });

    test('sin filas devuelve null: el marcador no se toca', () {
      expect(marcaDeLoBajado(const [], 'updated_at'), isNull);
    });

    test('con fechas nulas o ilegibles no inventa una marca', () {
      final basura = [
        {'id': 'a', 'updated_at': null},
        {'id': 'b', 'updated_at': ''},
        {'id': 'c'},
        {'id': 'd', 'updated_at': 'no soy una fecha'},
      ];

      expect(
        marcaDeLoBajado(basura, 'updated_at'),
        isNull,
        reason: 'inventar la marca acá es exactamente cómo se pierden filas',
      );
    });

    test('una fila legible entre varias rotas alcanza para marcar', () {
      final mezcla = [
        {'id': 'a', 'updated_at': null},
        fila('2026-09-07T22:28:31.193341Z'),
        {'id': 'c', 'updated_at': 'roto'},
      ];

      expect(
        marcaDeLoBajado(mezcla, 'updated_at'),
        '2026-09-07T22:28:31.193341Z',
      );
    });
  });
}
