// Cómo lee el tótem la lista de la nube desde la sección 8 (`lista_del_totem.dart`):
// por la función `totem_lista` con la clave del tótem, nunca por la tabla.
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/features/totem/services/lista_del_totem.dart';
import 'package:arguello_events/models/invitado.dart';

const _ev = 'e0000000-0000-4000-8000-00000000000a';
const _otro = 'e0000000-0000-4000-8000-00000000000b';

/// Lo que devuelve `totem_lista`: sin DNI ni intentos.
final _filas = [
  {
    'id': 'i0000000-0000-4000-8000-000000000001',
    'evento_id': _ev,
    'nombre_completo': 'GÓMEZ, LAURA',
    'numero_mesa': '12',
    'estado_ingreso': 'ingresado',
    'created_at': '2026-12-12T22:00:00+00:00',
    'updated_at': '2026-12-12T22:41:00+00:00',
  },
  {
    'id': 'i0000000-0000-4000-8000-000000000002',
    'evento_id': _ev,
    'nombre_completo': 'PÉREZ, JUAN',
    'numero_mesa': null,
    'estado_ingreso': 'pendiente',
    'created_at': '2026-12-12T22:00:00+00:00',
    'updated_at': null,
  },
];

class _Nube {
  final llamadas = <(String, Map<String, dynamic>)>[];
  Object Function()? contestar;

  Future<dynamic> llamar(String funcion, Map<String, dynamic> params) async {
    llamadas.add((funcion, params));
    final c = contestar;
    return c == null ? _filas : c();
  }
}

void main() {
  late _Nube nube;
  late List<String> clavesPedidas;
  late List<String> clavesMalas;
  String? clave;

  ListaDelTotem armar() => ListaDelTotem(
        llamar: nube.llamar,
        clave: (id) async {
          clavesPedidas.add(id);
          return clave;
        },
        claveMala: (id) async => clavesMalas.add(id),
      );

  setUp(() {
    nube = _Nube();
    clavesPedidas = [];
    clavesMalas = [];
    clave = 'la-clave';
  });

  test('lee por la función, con el evento y la clave', () async {
    final lista = await armar().leer(_ev);
    expect(nube.llamadas, hasLength(1));
    expect(nube.llamadas.single.$1, 'totem_lista');
    expect(nube.llamadas.single.$2, {'p_evento': _ev, 'p_clave': 'la-clave'});
    expect([for (final i in lista) i.nombreCompleto],
        ['GÓMEZ, LAURA', 'PÉREZ, JUAN']);
    expect(lista.first.estadoIngreso, EstadoIngreso.ingresado);
    expect(lista.first.numeroMesa, '12');
    expect(lista.first.updatedAt, DateTime.utc(2026, 12, 12, 22, 41));
    expect(lista.first.dni, '', reason: 'la función no manda el DNI');
  });

  test('la clave se pide una vez por evento', () async {
    final l = armar();
    await l.leer(_ev);
    await l.leer(_ev);
    expect(clavesPedidas, [_ev]);
    await l.leer(_otro);
    expect(clavesPedidas, [_ev, _otro]);
  });

  test('sin clave no lee, y avisa que es por la clave', () async {
    clave = null;
    await expectLater(armar().leer(_ev), throwsA(isA<SinClaveDelTotem>()));
    clave = '  ';
    await expectLater(armar().leer(_ev), throwsA(isA<SinClaveDelTotem>()));
    expect(nube.llamadas, isEmpty);
  });

  test('con una clave mala tira, la olvida y la próxima la pide de nuevo',
      () async {
    final l = armar();
    nube.contestar = () => throw const PostgrestException(
          message: 'La clave del tótem no es la de este evento',
          code: '28000',
        );
    await expectLater(l.leer(_ev), throwsA(isA<PostgrestException>()));
    expect(clavesMalas, [_ev]);

    nube.contestar = null;
    clave = 'la-nueva';
    final lista = await l.leer(_ev);
    expect(lista, hasLength(2));
    expect(clavesPedidas, [_ev, _ev]);
    expect(nube.llamadas.last.$2['p_clave'], 'la-nueva');
  });

  test('sin internet tira, pero no olvida la clave', () async {
    final l = armar();
    await l.leer(_ev);
    nube.contestar = () => throw Exception('SocketException: Failed host lookup');
    await expectLater(l.leer(_ev), throwsException);
    expect(clavesMalas, isEmpty);
    nube.contestar = null;
    await l.leer(_ev);
    expect(clavesPedidas, [_ev], reason: 'la clave sigue siendo buena');
  });

  test('nunca devuelve una lista vacía por no poder: lo que no es una lista, '
      'tira', () async {
    nube.contestar = () => {'error': 'algo'};
    await expectLater(armar().leer(_ev), throwsFormatException);
  });

  test('una lista vacía de verdad (nadie en la puerta) sí vale', () async {
    nube.contestar = () => <dynamic>[];
    expect(await armar().leer(_ev), isEmpty);
  });

  test('con un id que no es de evento no pregunta nada', () async {
    await expectLater(armar().leer('corto'), throwsArgumentError);
    expect(clavesPedidas, isEmpty);
    expect(nube.llamadas, isEmpty);
  });
}
