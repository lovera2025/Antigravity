import 'package:arguello_events/features/recepcion/central/pedidos_de_la_puerta.dart';
import 'package:arguello_events/features/tele/fluidez.dart';
import 'package:arguello_events/features/totem/services/bienvenidas_totem.dart';
import 'package:arguello_events/models/invitado.dart';
import 'package:flutter_test/flutter_test.dart';

/// La tele es el tótem (24-nov-2026): a quién saluda cada tele. Sin pantalla:
/// la cola del tótem ([IngresosTotem]) con el filtro que le pone la tele.
final _ahora = DateTime(2026, 12, 12, 22, 41);
const _evento = 'e0000000-0000-4000-8000-00000000000a';

Invitado _fila(String id, {bool adentro = true}) => Invitado(
      id: id,
      eventoId: _evento,
      nombreCompleto: id.toUpperCase(),
      dni: '',
      estadoIngreso: adentro ? EstadoIngreso.ingresado : EstadoIngreso.pendiente,
      updatedAt: _ahora,
    );

BienvenidaDeLaNoche _b(int? tele, {bool saludar = true, Duration hace = Duration.zero}) =>
    BienvenidaDeLaNoche(tele: tele, saludar: saludar, cuando: _ahora.subtract(hace));

/// La cola de una tele, saludando con las bienvenidas de [bienvenidas].
IngresosTotem _tele(int numero, Map<String, BienvenidaDeLaNoche> bienvenidas) =>
    IngresosTotem()
      ..seSaluda = (i) =>
          seSaludaEnLaTele(bienvenidas[i.id], miTele: numero, ahora: _ahora);

void main() {
  group('seSaludaEnLaTele', () {
    test('lo de cada tele, en su tele; "Las dos", en las dos', () {
      expect(seSaludaEnLaTele(_b(1), miTele: 1), isTrue);
      expect(seSaludaEnLaTele(_b(1), miTele: 2), isFalse);
      expect(seSaludaEnLaTele(_b(2), miTele: 2), isTrue);
      expect(seSaludaEnLaTele(_b(kLasDosTeles), miTele: 1), isTrue);
      expect(seSaludaEnLaTele(_b(kLasDosTeles), miTele: 2), isTrue);
      // Un celular sin "Tu tele": en todas.
      expect(seSaludaEnLaTele(_b(null), miTele: 2), isTrue);
    });

    test('sin bienvenida (lo que baja de la nube, lo que ya estaba), no se saluda', () {
      expect(seSaludaEnLaTele(null, miTele: 1), isFalse);
    });

    test('lo que llegó tarde o hace más de un minuto, tampoco', () {
      expect(seSaludaEnLaTele(_b(1, saludar: false), miTele: 1), isFalse);
      expect(
        seSaludaEnLaTele(_b(1, hace: const Duration(minutes: 2)), miTele: 1, ahora: _ahora),
        isFalse,
      );
      expect(
        seSaludaEnLaTele(_b(1, hace: const Duration(seconds: 30)), miTele: 1, ahora: _ahora),
        isTrue,
      );
    });

    test('la bienvenida viaja con cuánto hace, no con la hora: los relojes de las '
        'teles pueden no coincidir', () {
      final b = _b(2, hace: const Duration(seconds: 20));
      final json = b.toJson(_ahora);
      // La Tele 2 tiene el reloj una hora atrasado.
      final otraHora = _ahora.subtract(const Duration(hours: 1));
      final llegada = BienvenidaDeLaNoche.fromJson(json, otraHora)!;
      expect(otraHora.difference(llegada.cuando), const Duration(seconds: 20));
      expect(seSaludaEnLaTele(llegada, miTele: 2, ahora: otraHora), isTrue);
    });
  });

  group('las dos teles, a la vez', () {
    test('Juli ingresa a PÉREZ y Caro a ACOSTA en el mismo segundo: cada tele saluda '
        'al suyo, sin esperar a la otra', () {
      final bienvenidas = <String, BienvenidaDeLaNoche>{};
      final tele1 = _tele(1, bienvenidas);
      final tele2 = _tele(2, bienvenidas);
      // La primera lectura va en silencio (quién ya estaba).
      tele1.leyo([_fila('perez', adentro: false), _fila('acosta', adentro: false)], ahora: _ahora);
      tele2.leyo([_fila('perez', adentro: false), _fila('acosta', adentro: false)], ahora: _ahora);

      bienvenidas['perez'] = _b(1);
      bienvenidas['acosta'] = _b(2);
      final lectura = [_fila('perez'), _fila('acosta')];
      tele1.leyo(lectura, ahora: _ahora);
      tele2.leyo(lectura, ahora: _ahora);

      final en1 = tele1.siguiente(_ahora);
      final en2 = tele2.siguiente(_ahora);
      expect(en1!.personas.map((i) => i.id), ['perez']);
      expect(en2!.personas.map((i) => i.id), ['acosta']);
      // Y las dos tienen a los dos en la lista de los que llegaron.
      expect(tele1.ingresados.map((i) => i.id), containsAll(['perez', 'acosta']));
      expect(tele2.ingresados.map((i) => i.id), containsAll(['perez', 'acosta']));
      expect(tele1.cola, isEmpty);
      expect(tele2.cola, isEmpty);
    });

    test('tres familias seguidas de Juli van en fila en la Tele 1; la Tele 2 sigue '
        'con lo suyo', () {
      final bienvenidas = <String, BienvenidaDeLaNoche>{};
      final tele1 = _tele(1, bienvenidas);
      final tele2 = _tele(2, bienvenidas);
      final antes = [for (final id in ['a', 'b', 'c', 'd']) _fila(id, adentro: false)];
      tele1.leyo(antes, ahora: _ahora);
      tele2.leyo(antes, ahora: _ahora);
      for (final id in ['a', 'b', 'c']) {
        bienvenidas[id] = _b(1);
      }
      bienvenidas['d'] = _b(2);
      final despues = [for (final id in ['a', 'b', 'c', 'd']) _fila(id)];
      tele1.leyo(despues, ahora: _ahora);
      tele2.leyo(despues, ahora: _ahora);

      expect(tele1.cola.map((i) => i.id), ['a', 'b', 'c']);
      expect(tele2.cola.map((i) => i.id), ['d']);
    });

    test('al conectarse, la lista entera que llega a la Tele 2 no se saluda', () {
      final bienvenidas = <String, BienvenidaDeLaNoche>{
        // Marcados hace rato en la Tele 1, mientras la Tele 2 estaba apagada.
        'a': _b(2, hace: const Duration(minutes: 20)),
        'b': _b(2, hace: const Duration(minutes: 5)),
      };
      final tele2 = _tele(2, bienvenidas);
      tele2.leyo(const [], ahora: _ahora);
      tele2.leyo([_fila('a'), _fila('b'), _fila('c')], ahora: _ahora);
      expect(tele2.cola, isEmpty);
      expect(tele2.ingresados, hasLength(3));
    });

    test('sin filtro (Recepción en la PC), se saluda a todos, como siempre', () {
      final pc = IngresosTotem();
      pc.leyo(const [], ahora: _ahora);
      pc.leyo([_fila('a'), _fila('b')], ahora: _ahora);
      expect(pc.cola.map((i) => i.id), ['a', 'b']);
    });
  });

  group('la fluidez', () {
    test('imágenes por segundo, con el tope de la pantalla', () {
      expect(Fluidez.porSegundoDe(const []), isNull);
      expect(
        Fluidez.porSegundoDe(List.filled(10, const Duration(microseconds: 16700))),
        closeTo(59.9, 0.2),
      );
      expect(
        Fluidez.porSegundoDe(List.filled(10, const Duration(milliseconds: 40))),
        closeTo(25, 0.1),
      );
      expect(Fluidez.porSegundoDe(List.filled(10, const Duration(milliseconds: 5))), 60);
    });

    test('lo que dice', () {
      expect(Fluidez.texto(null), 'Midiendo…');
      expect(Fluidez.texto(58), contains('anda suave'));
      expect(Fluidez.texto(42), contains('se puede notar'));
      expect(Fluidez.texto(20), contains('fondo quieto'));
    });
  });
}
