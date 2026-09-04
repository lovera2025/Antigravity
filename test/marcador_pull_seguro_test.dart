// El marcador del pull no puede pasar por encima de una fila que no se escribió.
//
// El pull incremental pide `updated_at > marcador`, así que el marcador promete
// "todo lo anterior ya está local". `_pullTable` rompía esa promesa: cuando una
// fila bajaba de la nube pero se salteaba para no pisar un cambio local sin
// subir, guardaba el marcador en "ahora" igual. Esa fila quedaba del otro lado
// del filtro y no se volvía a pedir nunca.
//
// Le pegaba justo a la fila más caliente, la que dos personas tocan a la vez: el
// operador le cobraba a un alumno —con lo que ese contrato quedaba pendiente en
// la cola de subida—, el jefe lo modificaba en su PC, el pull bajaba la versión
// del jefe, la salteaba para no pisar el cobro, y movía el marcador. Cuando el
// cobro terminaba de subir y la cola quedaba vacía, la modificación del jefe ya
// estaba atrás del marcador: el cierre de caja del operador no la mostró nunca.
//
// El mismo mecanismo dejó `presupuesto_servicios` con 18 de 203 filas, y de ahí
// salió un evento particular creado sin un solo ítem.
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/core/services/sync_engine.dart';

/// `updated_at > marca` es el filtro real del pull: esto responde si la fila
/// volvería a bajar en la próxima pasada.
bool volveriaABajar(String marca, DateTime updatedAtDeLaFila) =>
    updatedAtDeLaFila.toUtc().isAfter(DateTime.parse(marca).toUtc());

void main() {
  group('marcadorPullSeguro', () {
    const ahora = '2026-09-04T15:41:09.692922Z';

    test('sin filas retenidas avanza a ahora', () {
      expect(marcadorPullSeguro(ahora: ahora), ahora);
      expect(marcadorPullSeguro(ahora: ahora, pendienteMasVieja: null), ahora);
    });

    test('con una fila retenida, el marcador queda antes de esa fila', () {
      final fila = DateTime.utc(2026, 9, 4, 15, 30, 12, 345);

      final marca = marcadorPullSeguro(ahora: ahora, pendienteMasVieja: fila);

      expect(
        volveriaABajar(marca, fila),
        isTrue,
        reason: 'la fila salteada tiene que volver a entrar en el próximo pull',
      );
    });

    test('el marcador retenido no avanza hasta ahora', () {
      final fila = DateTime.utc(2026, 9, 4, 15, 30, 12, 345);

      final marca = marcadorPullSeguro(ahora: ahora, pendienteMasVieja: fila);

      expect(DateTime.parse(marca).isBefore(DateTime.parse(ahora)), isTrue);
    });

    test('gana la retenida más vieja', () {
      final vieja = DateTime.utc(2026, 9, 1, 22, 37, 58, 640);
      final nueva = DateTime.utc(2026, 9, 4, 15, 28, 54, 703);

      final marca = marcadorPullSeguro(ahora: ahora, pendienteMasVieja: vieja);

      expect(volveriaABajar(marca, vieja), isTrue);
      expect(
        volveriaABajar(marca, nueva),
        isTrue,
        reason: 'reteniendo por la más vieja, las posteriores también vuelven',
      );
    });

    test('normaliza a UTC aunque entre una fecha local', () {
      final local = DateTime(2026, 9, 4, 12, 0, 0);

      final marca = marcadorPullSeguro(ahora: ahora, pendienteMasVieja: local);

      expect(marca.endsWith('Z'), isTrue);
      expect(volveriaABajar(marca, local), isTrue);
    });

    test('el caso del alumno cobrado y modificado en el mismo minuto', () {
      // El jefe modificó el contrato a las 13:02:11. El operador ya le había
      // cobrado, así que esa fila estaba pendiente en la cola y el pull la
      // salteó. Antes, el marcador saltaba a "ahora" (13:02:19) y la versión del
      // jefe quedaba enterrada para siempre.
      final modificadoPorElJefe = DateTime.utc(2026, 9, 4, 13, 2, 11, 480);
      const finDelPull = '2026-09-04T13:02:19.000000Z';

      final marcaVieja = finDelPull;
      expect(
        volveriaABajar(marcaVieja, modificadoPorElJefe),
        isFalse,
        reason: 'así se perdía: el cambio del jefe nunca volvía a pedirse',
      );

      final marcaNueva = marcadorPullSeguro(
        ahora: finDelPull,
        pendienteMasVieja: modificadoPorElJefe,
      );
      expect(
        volveriaABajar(marcaNueva, modificadoPorElJefe),
        isTrue,
        reason: 'con el arreglo vuelve a bajar en cuanto se vacíe la cola',
      );
    });
  });
}
