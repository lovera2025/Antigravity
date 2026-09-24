// Lo que baja de la nube como jsonb se guarda como JSON, no como `toString()`.
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/core/services/sync_engine.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/mesa_extra_item.dart';

void main() {
  test('el detalle por mesa que baja se puede volver a leer', () {
    final nube = [
      {'n': 1, 'precio': 70000.0, 'pagado': 60000.0, 'cuotasPagadas': 6, 'liquidada': false},
      {'n': 2, 'precio': 70000.0, 'pagado': 0.0, 'cuotasPagadas': 0, 'liquidada': false},
    ];
    final guardado = valorParaSqlite(nube);
    expect(guardado, isA<String>());

    final mesas = MesaExtraItem.listFromJson(guardado);
    expect(mesas.map((m) => m.n), [1, 2]);
    expect(mesas.first.pagado, 60000);

    // Y al subir vuelve a ser la lista, no un texto.
    final payload = ContratoAlumno.payloadForRemote({'mesas_extra_estado': guardado});
    expect(payload['mesas_extra_estado'], isA<List>());
  });

  test('el formato viejo (toString) no se podía leer: por eso el cambio', () {
    final viejo = [
      {'n': 1, 'precio': 70000.0},
    ].toString();
    expect(MesaExtraItem.listFromJson(viejo), isEmpty);
  });

  test('bool a 0/1, lo demás igual', () {
    expect(valorParaSqlite(true), 1);
    expect(valorParaSqlite(false), 0);
    expect(valorParaSqlite('texto'), 'texto');
    expect(valorParaSqlite(12.5), 12.5);
    expect(valorParaSqlite(null), isNull);
    expect(valorParaSqlite(<String>[]), '[]');
  });

  test('acompañantes en JSON se siguen leyendo', () {
    final c = ContratoAlumno.fromJson({
      'id': 'x',
      'evento_id': 'e',
      'nombre_alumno': 'A',
      'monto_total_pactado': 1,
      'saldo_deudor': 1,
      'nombres_acompanantes': valorParaSqlite(['MAMÁ', 'PAPÁ']),
    });
    expect(c.nombresAcompanantes, ['MAMÁ', 'PAPÁ']);
  });
}
