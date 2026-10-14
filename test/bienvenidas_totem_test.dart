import 'package:arguello_events/features/totem/services/bienvenidas_totem.dart';
import 'package:arguello_events/models/invitado.dart';
import 'package:flutter_test/flutter_test.dart';

/// A quién saluda el tótem (`bienvenidas_totem.dart`).
///
/// Lo que se cuida: que nadie reciba una bienvenida atrasada después de un
/// corte, y que nadie la reciba dos veces.
Invitado _inv(String id, {bool adentro = true}) => Invitado(
      id: id,
      eventoId: 'evento',
      nombreCompleto: 'INVITADO $id',
      dni: '',
      estadoIngreso:
          adentro ? EstadoIngreso.ingresado : EstadoIngreso.pendiente,
    );

List<String> _ids(Iterable<Invitado> lista) => [for (final i in lista) i.id];

void main() {
  group('si la lectura va en silencio', () {
    test('la primera siempre', () {
      expect(lecturaEnSilencio(primera: true), isTrue);
      expect(
        lecturaEnSilencio(primera: true, corte: const Duration(seconds: 3)),
        isTrue,
      );
    });

    test('sin corte, no', () {
      expect(lecturaEnSilencio(primera: false), isFalse);
    });

    test('un corte corto no se come ningún saludo', () {
      expect(
        lecturaEnSilencio(primera: false, corte: const Duration(seconds: 5)),
        isFalse,
      );
      expect(
        lecturaEnSilencio(primera: false, corte: const Duration(seconds: 59)),
        isFalse,
      );
    });

    test('un corte de un minuto o más, sí', () {
      expect(
        lecturaEnSilencio(primera: false, corte: kCorteLargoTotem),
        isTrue,
      );
      expect(
        lecturaEnSilencio(primera: false, corte: const Duration(minutes: 12)),
        isTrue,
      );
    });
  });

  group('la espera entre reintentos', () {
    test('crece de 2 a 32 segundos y ahí se queda', () {
      expect(
        [for (var n = 0; n < 7; n++) esperaDeReintento(n).inSeconds],
        [2, 4, 8, 16, 32, 32, 32],
      );
    });

    test('no se da vuelta después de horas sin internet', () {
      // Con el desplazamiento sin tope, a los 32 intentos en la web (y a los 62
      // en el escritorio) la cuenta daba la vuelta y reintentaba cada 2 s.
      for (final n in [31, 32, 33, 62, 63, 64, 500, 100000]) {
        expect(esperaDeReintento(n).inSeconds, 32, reason: 'intento $n');
      }
      expect(esperaDeReintento(-3).inSeconds, 2);
    });
  });

  group('una lectura de la nube', () {
    test('la primera pone en la lista a los que ya entraron, sin saludar', () {
      final r = resolverLectura(
        lectura: [_inv('a'), _inv('b', adentro: false), _inv('c')],
        vistos: {},
        delPuente: {},
        enSilencio: true,
      );
      expect(r.saludar, isEmpty);
      expect(_ids(r.sinSaludo), ['a', 'c']);
      expect(r.sacar, isEmpty);
    });

    test('un ingreso nuevo lleva bienvenida', () {
      final r = resolverLectura(
        lectura: [_inv('a'), _inv('b'), _inv('c', adentro: false)],
        vistos: {'a'},
        delPuente: {},
        enSilencio: false,
      );
      expect(_ids(r.saludar), ['b']);
      expect(r.sinSaludo, isEmpty);
      expect(r.sacar, isEmpty);
    });

    test('después de un corte largo, los que entraron van a la lista callados',
        () {
      final r = resolverLectura(
        lectura: [_inv('a'), _inv('b'), _inv('c'), _inv('d')],
        vistos: {'a'},
        delPuente: {},
        enSilencio: true,
      );
      expect(r.saludar, isEmpty);
      expect(_ids(r.sinSaludo), ['b', 'c', 'd']);
      // Al que ya estaba no se lo toca: la lista no se rearma.
      expect(r.sacar, isEmpty);
    });

    test('nadie se saluda dos veces', () {
      final lectura = [_inv('a'), _inv('b')];
      final primera = resolverLectura(
        lectura: lectura,
        vistos: {},
        delPuente: {},
        enSilencio: false,
      );
      expect(_ids(primera.saludar), ['a', 'b']);
      final segunda = resolverLectura(
        lectura: lectura,
        vistos: {'a', 'b'},
        delPuente: {},
        enSilencio: false,
      );
      expect(segunda.saludar, isEmpty);
      expect(segunda.sinSaludo, isEmpty);
    });

    test('el que está en pantalla o en la cola no se vuelve a encolar', () {
      final r = resolverLectura(
        lectura: [_inv('a'), _inv('b')],
        vistos: {},
        delPuente: {},
        enCurso: {'a'},
        enSilencio: false,
      );
      expect(_ids(r.saludar), ['b']);
      expect(_ids(r.sinSaludo), ['a']);
    });

    test('una fila repetida en la lectura cuenta una sola vez', () {
      final r = resolverLectura(
        lectura: [_inv('a'), _inv('a')],
        vistos: {},
        delPuente: {},
        enSilencio: false,
      );
      expect(_ids(r.saludar), ['a']);
    });

    test('si se deshace un ingreso, sale de la lista', () {
      final r = resolverLectura(
        lectura: [_inv('a'), _inv('b', adentro: false)],
        vistos: {'a', 'b'},
        delPuente: {},
        enSilencio: false,
      );
      expect(r.sacar, {'b'});
    });

    test('deshacer y volver a marcar saluda de nuevo', () {
      final deshecho = resolverLectura(
        lectura: [_inv('a', adentro: false)],
        vistos: {'a'},
        delPuente: {},
        enSilencio: false,
      );
      expect(deshecho.sacar, {'a'});
      final otraVez = resolverLectura(
        lectura: [_inv('a')],
        vistos: {},
        delPuente: {},
        enSilencio: false,
      );
      expect(_ids(otraVez.saludar), ['a']);
    });

    test('vaciar la lista saca a todos', () {
      final r = resolverLectura(
        lectura: const [],
        vistos: {'a', 'b', 'c'},
        delPuente: {},
        enSilencio: false,
      );
      expect(r.sacar, {'a', 'b', 'c'});
    });
  });

  group('lo que avisó esta PC por el puente', () {
    // El caso real: se corta internet, la PC de Recepción sigue marcando y el
    // tótem saluda por el puente. Vuelve internet y el tótem lee la nube antes
    // de que la PC haya subido esos ingresos.
    test('una lectura atrasada de la nube no lo saca de la lista', () {
      final r = resolverLectura(
        lectura: [_inv('a'), _inv('b', adentro: false)],
        vistos: {'a', 'b'},
        delPuente: {'b'},
        enSilencio: true,
      );
      expect(r.sacar, isEmpty, reason: 'b lo marcó esta PC: la nube va atrás');
      expect(r.confirmados, isEmpty);
    });

    test('cuando sube a la nube no se lo saluda de nuevo', () {
      // Primero la lectura atrasada…
      final atrasada = resolverLectura(
        lectura: [_inv('b', adentro: false)],
        vistos: {'b'},
        delPuente: {'b'},
        enSilencio: true,
      );
      final vistos = {'b'}..removeAll(atrasada.sacar);
      // …y después la que ya trae el ingreso.
      final alDia = resolverLectura(
        lectura: [_inv('b')],
        vistos: vistos,
        delPuente: {'b'},
        enSilencio: false,
      );
      expect(alDia.saludar, isEmpty);
      expect(alDia.sinSaludo, isEmpty);
      expect(alDia.confirmados, {'b'});
    });

    test('una vez confirmado, si otra PC lo deshace sí sale', () {
      final r = resolverLectura(
        lectura: [_inv('b', adentro: false)],
        vistos: {'b'},
        delPuente: {},
        enSilencio: false,
      );
      expect(r.sacar, {'b'});
    });

    test('la protección es solo para los del puente', () {
      final r = resolverLectura(
        lectura: [_inv('a', adentro: false), _inv('b', adentro: false)],
        vistos: {'a', 'b'},
        delPuente: {'b'},
        enSilencio: false,
      );
      expect(r.sacar, {'a'});
    });
  });

  // Lo mismo, pero de corrido: lo que la pantalla le va contando a
  // `IngresosTotem` a lo largo de la noche.
  group('una noche en el tótem', () {
    final t0 = DateTime(2026, 12, 12, 22);
    DateTime en(int segundos) => t0.add(Duration(seconds: segundos));

    /// Saca de la cola a los que les toca la bienvenida, como hace la
    /// pantalla, y devuelve sus ids.
    List<String> saludados(IngresosTotem sala) {
      final ids = _ids(sala.cola);
      sala.cola.clear();
      return ids;
    }

    test('al abrir, los que ya entraron aparecen sin bienvenida', () {
      final sala = IngresosTotem();
      sala.leyo([_inv('a'), _inv('b'), _inv('c', adentro: false)], ahora: t0);
      expect(sala.cola, isEmpty);
      expect(_ids(sala.ingresados), ['b', 'a']);
      expect(sala.conectado, isTrue);
    });

    test('el que entra después se saluda una vez, por donde llegue primero',
        () {
      final sala = IngresosTotem()..leyo([_inv('a')], ahora: t0);

      // Llega el aviso y enseguida la nube con lo mismo.
      expect(sala.aviso(_inv('b')), isTrue);
      expect(saludados(sala), ['b']);
      sala.leyo([_inv('a'), _inv('b')], ahora: en(1));
      expect(sala.cola, isEmpty);

      // Otro llega solo por la nube.
      sala.leyo([_inv('a'), _inv('b'), _inv('c')], ahora: en(5));
      expect(saludados(sala), ['c']);
      expect(_ids(sala.ingresados), ['c', 'b', 'a']);

      // Y el aviso repetido no hace nada.
      expect(sala.aviso(_inv('c')), isFalse);
      expect(sala.cola, isEmpty);
    });

    test('el que se está saludando no se encola de nuevo', () {
      final sala = IngresosTotem()..leyo(const [], ahora: t0);
      sala.aviso(_inv('a'), ahora: en(0));
      expect(_ids(sala.siguiente(en(0))!.personas), ['a']);
      // Una lectura vieja lo saca, y la siguiente lo trae: sigue en pantalla.
      sala.leyo([_inv('a', adentro: false)], ahora: en(1));
      sala.leyo([_inv('a')], ahora: en(2));
      expect(sala.cola, isEmpty);
      expect(_ids(sala.enPantalla!.personas), ['a'], reason: 'una sola vez');
      expect(_ids(sala.ingresados), ['a'], reason: 'vuelve a la lista');
      // Terminó su bienvenida: la lectura siguiente no lo saluda otra vez.
      sala.termino();
      sala.leyo([_inv('a')], ahora: en(70));
      expect(sala.cola, isEmpty);
    });

    test('el que espera en la cola tampoco se saluda dos veces', () {
      final sala = IngresosTotem()..leyo(const [], ahora: t0);
      sala.aviso(_inv('a'), ahora: en(0));
      sala.aviso(_inv('b'), ahora: en(0));
      // `a` pasa a la pantalla y `b` espera. Llega una lectura vieja.
      sala.siguiente(en(0));
      sala.leyo(
        [_inv('a', adentro: false), _inv('b', adentro: false)],
        ahora: en(1),
      );
      sala.leyo([_inv('a'), _inv('b')], ahora: en(2));
      expect(_ids(sala.cola), ['b'], reason: 'b sigue esperando, una vez');
      expect(saludados(sala), ['b']);
      sala.leyo([_inv('a'), _inv('b')], ahora: en(70));
      expect(sala.cola, isEmpty);
    });

    test('se corta internet un rato largo: nadie se saluda tarde ni dos veces',
        () {
      final sala = IngresosTotem()..leyo([_inv('a')], ahora: t0);

      // Se corta. El tótem intenta leer varias veces y no puede.
      sala.noPudoLeer(en(10));
      sala.noPudoLeer(en(12));
      sala.noPudoLeer(en(40));
      expect(sala.conectado, isFalse);

      // Recepción sigue marcando en esta PC: llega por el puente y se saluda.
      sala.aviso(_inv('b'), porElPuente: true);
      sala.aviso(_inv('c'), porElPuente: true);
      expect(saludados(sala), ['b', 'c']);

      // Vuelve internet a los cinco minutos. La nube todavía no tiene a b ni a
      // c (esta PC no los subió), y sí a d y e, que entraron por la otra PC.
      sala.leyo(
        [
          _inv('a'),
          _inv('b', adentro: false),
          _inv('c', adentro: false),
          _inv('d'),
          _inv('e'),
        ],
        ahora: en(310),
      );
      expect(sala.conectado, isTrue);
      expect(sala.cola, isEmpty, reason: 'd y e entraron hace rato');
      expect(_ids(sala.ingresados), ['e', 'd', 'c', 'b', 'a'],
          reason: 'b y c siguen en la lista; d y e se suman arriba');

      // Esta PC sube lo suyo y la nube ya trae a todos.
      final todos = [_inv('a'), _inv('b'), _inv('c'), _inv('d'), _inv('e')];
      sala.leyo(todos, ahora: en(315));
      expect(sala.cola, isEmpty, reason: 'b y c ya se saludaron');
      expect(_ids(sala.ingresados), ['e', 'd', 'c', 'b', 'a']);

      // Y la noche sigue normal.
      sala.leyo([...todos, _inv('f')], ahora: en(330));
      expect(saludados(sala), ['f']);
    });

    test('un corte corto no se come el saludo del que entró por la otra PC',
        () {
      final sala = IngresosTotem()..leyo([_inv('a')], ahora: t0);
      sala.noPudoLeer(en(10));
      sala.leyo([_inv('a'), _inv('b')], ahora: en(18));
      expect(saludados(sala), ['b']);
    });

    test('el corte se cuenta desde el primer fallo, no desde el último', () {
      final sala = IngresosTotem()..leyo([_inv('a')], ahora: t0);
      sala.noPudoLeer(en(10));
      sala.noPudoLeer(en(100)); // el último intento fallido fue hace 5 s
      sala.leyo([_inv('a'), _inv('b')], ahora: en(105));
      expect(sala.cola, isEmpty);
      expect(_ids(sala.ingresados), ['b', 'a']);
    });

    test('pasado el corte, el silencio se termina', () {
      final sala = IngresosTotem()..leyo(const [], ahora: t0);
      sala.noPudoLeer(en(10));
      sala.leyo([_inv('a')], ahora: en(200));
      expect(sala.cola, isEmpty);
      sala.leyo([_inv('a'), _inv('b')], ahora: en(201));
      expect(saludados(sala), ['b']);
    });

    test('deshacer un ingreso por el puente lo saca aunque no haya subido',
        () {
      final sala = IngresosTotem()..leyo(const [], ahora: t0);
      sala.noPudoLeer(en(5));
      sala.aviso(_inv('a'), porElPuente: true);
      expect(saludados(sala), ['a']);
      sala.baja('a');
      expect(sala.ingresados, isEmpty);
      // Si lo marcan de nuevo, se lo saluda de nuevo.
      expect(sala.aviso(_inv('a'), porElPuente: true), isTrue);
      expect(saludados(sala), ['a']);
    });

    test('vaciar la lista no deja a nadie protegido', () {
      final sala = IngresosTotem()..leyo(const [], ahora: t0);
      sala.aviso(_inv('a'), porElPuente: true);
      sala.vaciar();
      expect(sala.ingresados, isEmpty);
      expect(sala.cola, isEmpty);
      sala.leyo([_inv('a', adentro: false)], ahora: en(3));
      expect(sala.ingresados, isEmpty);
    });

    test('al cambiar de fiesta o volver de estar escondido, arranca callado',
        () {
      final sala = IngresosTotem()..leyo([_inv('a')], ahora: t0);
      sala.aviso(_inv('b'), porElPuente: true);
      sala.pausar();
      expect(sala.cola, isEmpty, reason: 'escondido, nadie espera saludo');

      sala.reiniciar();
      expect(sala.ingresados, isEmpty);
      expect(sala.conectado, isTrue);
      sala.leyo([_inv('x'), _inv('y')], ahora: en(600));
      expect(sala.cola, isEmpty);
      expect(_ids(sala.ingresados), ['y', 'x']);
    });
  });

  // Sección 5 de la 6.0.0: el tótem que abre sin internet toma de la base de
  // la PC quién ya entró, en vez de arrancar con la lista vacía.
  group('abierto sin internet: lo que tiene la PC', () {
    final t0 = DateTime(2026, 12, 12, 23);
    DateTime en(int segundos) => t0.add(Duration(seconds: segundos));

    IngresosTotem sinInternet() => IngresosTotem()..noPudoLeer(t0);

    test('los que ya entraron aparecen sin bienvenida', () {
      final sala = sinInternet();
      expect(sala.leyoDeLaPc([_inv('a'), _inv('b'), _inv('c', adentro: false)]),
          isTrue);
      expect(sala.cola, isEmpty);
      expect(_ids(sala.ingresados), ['b', 'a']);
      expect(sala.conectado, isFalse, reason: 'sigue sin poder leer la nube');
      expect(sala.leyoDeLaNube, isFalse);
    });

    test('una vez que leyó la nube, lo de la PC no se usa más', () {
      final sala = IngresosTotem()..leyo([_inv('a')], ahora: t0);
      sala.noPudoLeer(en(10));
      expect(sala.leyoDeLaPc([_inv('a'), _inv('z')]), isFalse);
      expect(_ids(sala.ingresados), ['a'], reason: 'z no aparece');
    });

    test('pedirla de nuevo no cambia nada', () {
      final sala = sinInternet()..leyoDeLaPc([_inv('a'), _inv('b')]);
      sala.leyoDeLaPc([_inv('a'), _inv('b')]);
      expect(_ids(sala.ingresados), ['b', 'a']);
      expect(sala.cola, isEmpty);
    });

    test('lo que marca después esta PC se saluda por el puente, una vez', () {
      final sala = sinInternet()..leyoDeLaPc([_inv('a')]);
      expect(sala.aviso(_inv('a'), porElPuente: true), isFalse,
          reason: 'ya estaba adentro');
      expect(sala.aviso(_inv('b'), porElPuente: true), isTrue);
      expect(_ids(sala.cola), ['b']);
    });

    test('vuelve internet: la primera lectura de la nube va en silencio', () {
      final sala = sinInternet()..leyoDeLaPc([_inv('a')]);
      // La otra PC marcó a d y e mientras tanto; esta PC no los tenía.
      sala.leyo([_inv('a'), _inv('d'), _inv('e')], ahora: en(20));
      expect(sala.cola, isEmpty, reason: 'nadie se saluda tarde');
      expect(_ids(sala.ingresados), ['e', 'd', 'a']);
      expect(sala.conectado, isTrue);
      expect(sala.leyoDeLaNube, isTrue);
    });

    test('lo marcado sin internet no se pierde ni se saluda dos veces', () {
      // b lo marcó esta PC sin internet, antes de abrir el tótem.
      final sala = sinInternet()
        ..leyoDeLaPc([_inv('a'), _inv('b')], sinSubir: {'b'});
      // Vuelve internet: la nube todavía no tiene a b.
      sala.leyo([_inv('a'), _inv('b', adentro: false)], ahora: en(30));
      expect(_ids(sala.ingresados), ['b', 'a'], reason: 'b sigue adentro');
      // Esta PC sube a b, y la nube ya lo trae.
      sala.leyo([_inv('a'), _inv('b')], ahora: en(35));
      expect(sala.cola, isEmpty, reason: 'b no se saluda de nuevo');
      // Y, ya confirmado, si otra PC lo deshace, sale.
      sala.leyo([_inv('a'), _inv('b', adentro: false)], ahora: en(40));
      expect(_ids(sala.ingresados), ['a']);
    });

    test('lo que ya había subido sí sigue a la nube', () {
      // a había subido; mientras esta PC estuvo sin internet, otra deshizo su
      // ingreso.
      final sala = sinInternet()..leyoDeLaPc([_inv('a'), _inv('b')], sinSubir: {'b'});
      sala.leyo([_inv('a', adentro: false), _inv('b', adentro: false)],
          ahora: en(30));
      expect(_ids(sala.ingresados), ['b'], reason: 'b no subió todavía');
    });

    test('un deshacer sin subir no frena el saludo si otra PC lo marca', () {
      // c tiene un cambio sin subir, pero es un deshacer: no está adentro.
      final sala = sinInternet()
        ..leyoDeLaPc([_inv('a'), _inv('c', adentro: false)], sinSubir: {'c'});
      sala.leyo([_inv('a')], ahora: en(30));
      sala.leyo([_inv('a'), _inv('c')], ahora: en(35));
      expect(_ids(sala.cola), ['c'],
          reason: 'si lo vuelven a marcar en otra PC, se lo saluda');
    });

    test('al cambiar de fiesta o volver de estar escondido, se puede pedir de nuevo',
        () {
      final sala = sinInternet()..leyo([_inv('a')], ahora: en(1));
      sala.reiniciar();
      sala.noPudoLeer(en(60));
      expect(sala.leyoDeLaPc([_inv('x')]), isTrue);
      expect(_ids(sala.ingresados), ['x']);
    });
  });

  // La cola que se acorta (pedido del usuario el 14-oct): 7 s si nadie
  // espera, 3 s si hay gente esperando.
  group('cuánto dura una bienvenida', () {
    final t0 = DateTime(2026, 12, 12, 22);
    DateTime en(int ms) => t0.add(Duration(milliseconds: ms));

    test('7 s si nadie espera, 3 s si hay cola', () {
      expect(finDeBienvenida(empezo: t0, hayCola: false), en(7000));
      expect(finDeBienvenida(empezo: t0, hayCola: true), en(3000));
    });

    test('el que se suma a la tarjeta le da 3 s más, como mínimo', () {
      // Se suma a los 6 s, sin cola: la tarjeta sigue hasta los 9.
      expect(
        finDeBienvenida(empezo: t0, hayCola: false, seSumo: en(6000)),
        en(9000),
      );
      // Se suma a los 2 s: los 7 s de siempre alcanzan.
      expect(
        finDeBienvenida(empezo: t0, hayCola: false, seSumo: en(2000)),
        en(7000),
      );
      // Con cola, igual se lo deja leer.
      expect(
        finDeBienvenida(empezo: t0, hayCola: true, seSumo: en(2500)),
        en(5500),
      );
    });

    test('llega alguien a los 2 s: la que está se va a los 3', () {
      final sala = IngresosTotem()..leyo(const [], ahora: t0);
      sala.aviso(_inv('a'), ahora: en(0));
      sala.siguiente(en(0));
      expect(sala.fin, en(7000), reason: 'sola, 7 s');
      sala.aviso(_inv('b'), ahora: en(2000));
      expect(sala.fin, en(3000));
      expect(sala.enCamino, 1);
    });

    test('llega alguien a los 5 s: la que está se va enseguida', () {
      final sala = IngresosTotem()..leyo(const [], ahora: t0);
      sala.aviso(_inv('a'), ahora: en(0));
      sala.siguiente(en(0));
      sala.aviso(_inv('b'), ahora: en(5000));
      // Ya pasó: la pantalla la termina en el momento.
      expect(sala.fin!.isBefore(en(5000)), isTrue);
    });

    test('la que entra con gente esperando dura 3 s; la última, 7', () {
      final sala = IngresosTotem()..leyo(const [], ahora: t0);
      for (final id in ['a', 'b', 'c']) {
        sala.aviso(_inv(id), ahora: en(0));
      }
      expect(_ids(sala.siguiente(en(0))!.personas), ['a']);
      expect(sala.fin, en(3000));
      expect(sala.enCamino, 2);
      sala.termino();
      sala.siguiente(en(4000));
      expect(sala.fin, en(7000), reason: 'b: todavía espera c');
      sala.termino();
      sala.siguiente(en(8000));
      expect(sala.fin, en(15000), reason: 'c: nadie espera');
      expect(sala.enCamino, 0);
    });

    test('sin nadie en pantalla no hay fin', () {
      final sala = IngresosTotem()..leyo(const [], ahora: t0);
      expect(sala.fin, isNull);
      expect(sala.siguiente(t0), isNull);
    });
  });

  // En un masivo, el alumno y sus acompañantes se saludan juntos. De qué
  // familia es cada uno lo dice la ficha del evento.
  group('la familia junta', () {
    final t0 = DateTime(2026, 12, 12, 22);
    DateTime en(int ms) => t0.add(Duration(milliseconds: ms));

    /// "perez" y "perez-1", "perez-2"... son la familia de "perez".
    String familia(Invitado i) => i.id.split('-').first;

    IngresosTotem sala() => IngresosTotem()
      ..familiaDe = familia
      ..leyo(const [], ahora: t0);

    test('los que esperan juntos se saludan en una sola tarjeta', () {
      final s = sala();
      s.aviso(_inv('garcia'), ahora: en(0));
      s.aviso(_inv('perez'), ahora: en(0));
      s.aviso(_inv('acosta'), ahora: en(0));
      s.aviso(_inv('perez-1'), ahora: en(0));
      s.aviso(_inv('perez-2'), ahora: en(0));
      expect(_ids(s.siguiente(en(0))!.personas), ['garcia']);
      s.termino();
      final b = s.siguiente(en(4000))!;
      expect(b.familia, 'perez');
      expect(_ids(b.personas), ['perez', 'perez-1', 'perez-2']);
      expect(_ids(s.cola), ['acosta'], reason: 'los de otra familia, después');
    });

    test('el que se marca mientras está la tarjeta, se suma a ella', () {
      final s = sala();
      s.aviso(_inv('perez'), ahora: en(0));
      s.siguiente(en(0));
      expect(s.aviso(_inv('perez-1'), ahora: en(1500)), isTrue);
      expect(s.aviso(_inv('perez-2'), ahora: en(3000)), isTrue);
      expect(_ids(s.enPantalla!.personas), ['perez', 'perez-1', 'perez-2']);
      expect(s.cola, isEmpty);
      expect(s.fin, en(7000), reason: 'los 3 s del último entran en los 7');
      expect(_ids(s.ingresados), ['perez-2', 'perez-1', 'perez']);
    });

    test('si se suma tarde, la tarjeta se queda 3 s más', () {
      final s = sala();
      s.aviso(_inv('perez'), ahora: en(0));
      s.siguiente(en(0));
      s.aviso(_inv('perez-1'), ahora: en(6500));
      expect(s.fin, en(9500));
    });

    test('mientras la tarjeta se va, el de la familia espera la suya', () {
      final s = sala();
      s.aviso(_inv('perez'), ahora: en(0));
      s.siguiente(en(0));
      s.termino();
      s.aviso(_inv('perez-1'), ahora: en(7200));
      expect(_ids(s.cola), ['perez-1']);
    });

    test('lo que trae la nube también se suma a la tarjeta de su familia', () {
      final s = sala();
      s.aviso(_inv('perez'), porElPuente: true, ahora: en(0));
      s.siguiente(en(0));
      // La otra PC marcó a la acompañante; llega por la relectura.
      s.leyo([_inv('perez'), _inv('perez-1'), _inv('garcia')], ahora: en(2000));
      expect(_ids(s.enPantalla!.personas), ['perez', 'perez-1']);
      expect(_ids(s.cola), ['garcia']);
      expect(s.fin, en(5000), reason: 'hay cola, y la que se sumó se lee 3 s');
    });

    test('un particular: cada uno su tarjeta', () {
      final s = IngresosTotem()..leyo(const [], ahora: t0);
      s.aviso(_inv('perez'), ahora: en(0));
      s.aviso(_inv('perez-1'), ahora: en(0));
      expect(_ids(s.siguiente(en(0))!.personas), ['perez']);
      expect(_ids(s.cola), ['perez-1']);
    });

    test('sacar al único de la tarjeta la saca de la pantalla', () {
      final s = sala();
      s.aviso(_inv('perez'), ahora: en(0));
      s.aviso(_inv('perez-1'), ahora: en(0));
      s.siguiente(en(0));
      s.baja('perez-1');
      expect(_ids(s.enPantalla!.personas), ['perez']);
      s.baja('perez');
      expect(s.enPantalla, isNull);
    });

    test('vaciar, pausar o cambiar de fiesta no deja a nadie en pantalla', () {
      for (final corte in <void Function(IngresosTotem)>[
        (s) => s.vaciar(),
        (s) => s.pausar(),
        (s) => s.reiniciar(),
      ]) {
        final s = sala();
        s.aviso(_inv('perez'), ahora: en(0));
        s.siguiente(en(0));
        corte(s);
        expect(s.enPantalla, isNull);
        expect(s.fin, isNull);
      }
    });

    test('una noche: cuatro familias de golpe y una que se completa', () {
      final s = sala();
      // Recepción marca rápido: Acosta (2), Benítez, Fernández, García y la
      // acompañante de Benítez.
      for (final (ms, id) in [
        (0, 'acosta'),
        (300, 'acosta-1'),
        (600, 'benitez'),
        (900, 'fernandez'),
        (1200, 'garcia'),
        (1800, 'benitez-1'),
      ]) {
        s.aviso(_inv(id), ahora: en(ms));
        if (s.enPantalla == null) s.siguiente(en(ms));
      }
      // Acosta salió sola y su acompañante se sumó a los 300 ms.
      expect(_ids(s.enPantalla!.personas), ['acosta', 'acosta-1']);
      expect(s.enCamino, 4);
      expect(s.fin, en(3300), reason: 'hay cola: 3 s desde que se sumó María');

      final tarjetas = <List<String>>[];
      var ahora = 3300;
      while (s.enPantalla != null) {
        tarjetas.add(_ids(s.enPantalla!.personas));
        final fin = s.fin!;
        ahora = fin.difference(t0).inMilliseconds + 1200; // se va y 0,3 s
        s.termino();
        s.siguiente(en(ahora));
      }
      expect(tarjetas, [
        ['acosta', 'acosta-1'],
        ['benitez', 'benitez-1'],
        ['fernandez'],
        ['garcia'],
      ]);
      // Con 7 s fijos eran seis tarjetas y unos 50 s; así, cuatro y unos 21.
      expect(ahora, lessThan(25000));
    });
  });
}
