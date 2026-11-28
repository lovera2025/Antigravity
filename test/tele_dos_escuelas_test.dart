import 'package:arguello_events/models/como_lo_nombran.dart';
import 'dart:io';

import 'package:arguello_events/features/recepcion/central/central_puerta.dart';
import 'package:arguello_events/features/recepcion/central/pedidos_de_la_puerta.dart';
import 'package:arguello_events/features/recepcion/services/puerta_del_evento.dart';
import 'package:arguello_events/features/tele/busqueda_de_la_tele.dart';
import 'package:arguello_events/features/totem/services/tiempos_a_mano.dart';
import 'package:arguello_events/models/invitado.dart';
import 'package:arguello_events/models/silla_puerta.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/celular_de_prueba.dart';

/// **La Tele 1 atiende las dos escuelas de la noche** (25-nov-2026): cada tele
/// con su escuela, cada celular con la de su tele, y cambiar de escuela sin
/// reiniciar nada ni volver a escanear. Todo por la red de esta PC, como en el
/// salón; la base, en memoria.
const _a = 'e0000000-0000-4000-8000-00000000000a';
const _b = 'e0000000-0000-4000-8000-00000000000b';
const _codigo = '4821';

/// La base de la tele, con las dos escuelas.
class _Base implements PuertaDeEstaPc {
  final filas = <String, Invitado>{};

  // Cómo lo nombran (v85): esta prueba no lo usa.
  @override
  Future<ComoLoNombran?> nombresDe(String contratoId) async => null;

  @override
  Future<void> guardarNombres(ComoLoNombran fila) async {}
  final ingresos = <(String evento, String id)>[];
  void Function()? alCambiar;

  void poner(String evento, String id, String nombre, {bool adentro = false}) =>
      filas[id] = Invitado(
        id: id,
        eventoId: evento,
        nombreCompleto: nombre,
        dni: '',
        estadoIngreso: adentro ? EstadoIngreso.ingresado : EstadoIngreso.pendiente,
        updatedAt: adentro ? DateTime.utc(2026, 12, 4, 23) : null,
      );

  PuertaDelEvento lista(String evento) =>
      PuertaDelEvento.particular([for (final f in filas.values) if (f.eventoId == evento) f]);

  @override
  Future<Invitado?> fila(String id) async => filas[id];

  @override
  Future<void> ingresar(String eventoId, PersonaPuerta persona, {required bool saludar}) async {
    ingresos.add((eventoId, persona.id));
    poner(eventoId, persona.id, persona.nombre, adentro: true);
    alCambiar?.call();
  }

  @override
  Future<void> deshacer(String id) async {
    final f = filas[id]!;
    poner(f.eventoId, id, f.nombreCompleto);
    alCambiar?.call();
  }

  @override
  Future<List<SillaPuerta>> sillasDelEvento(String eventoId) async => const [];

  @override
  Future<void> sumarSilla({
    required String eventoId,
    required String contratoId,
    required int mesa,
    required String vale,
    required String anotadoPor,
    String? nota,
  }) async {}

  @override
  Future<void> quitarSilla(String sillaId, {required String por, required String motivo}) async {}

  @override
  Future<void> ponerTiempos(String eventoId, TiemposAMano t, {int? tele}) async {}
}

Future<void> _hasta(bool Function() listo) async {
  final limite = DateTime.now().add(const Duration(seconds: 5));
  while (!listo()) {
    if (DateTime.now().isAfter(limite)) throw StateError('no pasó');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late _Base base;
  late CentralPuerta central;
  late int puerto;
  final abiertos = <CelularDePrueba>[];
  final pedidasParaLaTele1 = <(String, String?)>[];
  final giros = <String>[];
  final avisos = <String?>[];

  Future<CelularDePrueba> celular(String nombre, {int? tele}) async {
    final c = await CelularDePrueba.conectar(
      puerto,
      codigo: _codigo,
      id: 'cel-$nombre',
      nombre: nombre,
      tele: tele,
    );
    abiertos.add(c);
    return c;
  }

  Future<CelularDePrueba> tele2(String evento) async {
    final t = await CelularDePrueba.conectarTele(puerto, evento: evento);
    abiertos.add(t);
    return t;
  }

  /// Como la app (`CentralDeLaPuerta`): a cada escuela que se atiende se le
  /// pasa su lista y su nombre, y la base avisa los cambios.
  void avisar() {
    for (final e in central.atiende) {
      central
        ..ponerPuerta(base.lista(e), de: e)
        ..ponerFilas([for (final f in base.filas.values) if (f.eventoId == e) f], de: e);
    }
  }

  setUp(() async {
    base = _Base()
      ..poner(_a, 'a1', 'CEIBO, JUAN')
      ..poner(_a, 'a2', 'HORNERO, LUCÍA')
      ..poner(_b, 'b1', 'ZORZAL, ANA')
      ..poner(_b, 'b2', 'TALA, PABLO');
    pedidasParaLaTele1.clear();
    giros.clear();
    avisos.clear();
    central = CentralPuerta(eventoId: _a, codigo: _codigo, pc: base, esTele: true)
      ..ponerEscuelasParaElegir(const [
        EscuelaParaElegir(_a, 'ESCUELA A'),
        EscuelaParaElegir(_b, 'ESCUELA B'),
      ])
      ..ponerTitulo('ESCUELA A');
    central
      ..alAtender = (e) {
        central.ponerTitulo(e == _a ? 'ESCUELA A' : 'ESCUELA B', de: e);
        avisar();
      }
      ..alCambiarTele1 = ((e, por) {
        pedidasParaLaTele1.add((e, por));
      })
      ..alGirarTele1 = giros.add
      ..alCambiarLasEscuelas = avisos.add;
    puerto = await central.arrancar(desde: 0, en: InternetAddress.loopbackIPv4);
    base.alCambiar = avisar;
    avisar();
  });

  tearDown(() async {
    for (final c in abiertos) {
      try {
        await c.ws.close();
      } catch (_) {}
    }
    abiertos.clear();
    await central.cerrar();
  });

  group('cada tele con su escuela', () {
    test('la Tele 2 con la escuela B: la Tele 1 atiende las dos, y la Tele 2 copia las dos',
        () async {
      final t = await tele2(_b);
      await t.espera('central');
      expect(central.atiende, [_a, _b]);
      expect(central.escuelaDeTele(2), _b);
      // Copia lo de las dos: si la Tele 1 se apaga, tiene todo.
      final ids = <String>{};
      while (!ids.containsAll(['a1', 'a2', 'b1', 'b2'])) {
        final f = await t.espera('filas');
        ids.addAll([for (final x in f['filas'] as List) x['id'] as String]);
      }
    });

    test('cada celular ve la escuela de su tele y marca en esa', () async {
      final t = await tele2(_b);
      await t.espera('central');
      final juli = await celular('Juli', tele: 1);
      final caro = await celular('Caro', tele: 2);
      final pj = await juli.espera('puerta');
      final pc = await caro.espera('puerta', cumple: (m) => m['evento'] == _b);
      expect(pj['evento'], _a);
      expect(pc['titulo'], 'ESCUELA B');
      expect((await caro.pedirYEsperar('x', QuePide.ingresar, 'b1'))['hizo'], 'ingresar');
      expect(base.ingresos.last, (_b, 'b1'));
      // La marca es de la escuela B, con la tele de Caro.
      expect(central.marcasDe(_b)!.bienvenida('b1')!.tele, 2);
      expect(central.marcasDe(_a)!.bienvenida('b1'), isNull);
      // Lo de la escuela A no le llega a Caro.
      expect((await juli.pedirYEsperar('y', QuePide.ingresar, 'a1'))['hizo'], 'ingresar');
      expect(base.ingresos.last, (_a, 'a1'));
    });

    test('un pedido que quedó sin mandar va a su escuela, aunque la tele haya cambiado',
        () async {
      final juli = await celular('Juli', tele: 1);
      await juli.espera('puerta');
      // Tocado mirando la escuela B (la Tele 1 la tenía antes).
      central.atender(_b);
      final r = await juli.pedirYEsperar('z', QuePide.ingresar, 'b2', evento: _b);
      expect(r['hizo'], 'ingresar');
      expect(base.ingresos.last, (_b, 'b2'));
    });

    test('"Las dos" va solo con la misma escuela en las dos teles', () async {
      final t = await tele2(_b);
      await t.espera('central');
      final juli = await celular('Juli', tele: 1);
      await juli.espera('puerta');
      juli.elegirTele(kLasDosTeles);
      final aviso = await juli.espera('aviso');
      expect(aviso['texto'], contains('misma escuela'));
      expect((await juli.espera('tu_tele'))['n'], 1);
      final teles = await juli.espera('teles', cumple: (m) => m['lasDos'] == false);
      expect(teles['lasDos'], isFalse);
    });
  });

  group('cambiar la escuela de una tele, sin desconectar a nadie', () {
    test('la Tele 1 pasa a la B: sus celulares pasan solos, con aviso y el mismo código',
        () async {
      final juli = await celular('Juli', tele: 1);
      await juli.espera('puerta');
      central.cambiarEscuelaDeTele(1, _b, yaCambio: true);
      final p = await juli.espera('puerta', cumple: (m) => m['evento'] == _b);
      expect(p['titulo'], 'ESCUELA B');
      expect((await juli.espera('aviso'))['texto'], 'La Tele 1 pasó a ESCUELA B');
      expect(central.codigo, _codigo);
      expect(central.eventoId, _b);
      // Sigue conectado: marca en la B.
      expect((await juli.pedirYEsperar('q', QuePide.ingresar, 'b1'))['hizo'], 'ingresar');
    });

    test('desde el celular, sin PIN: la Tele 1 la cambia la tele, y dice quién', () async {
      final caro = await celular('Caro', tele: 1);
      await caro.espera('puerta');
      caro.mandar({'t': 'escuela', 'tele': 1, 'evento': _b});
      await caro.espera('aviso');
      expect(pedidasParaLaTele1, [(_b, 'Caro')]);
      expect(avisos.last, 'Caro pasó la Tele 1 a ESCUELA B');
    });

    test('desde el celular para la Tele 2: se lo pide a la Tele 2', () async {
      final t = await tele2(_a);
      await t.espera('central');
      final caro = await celular('Caro', tele: 2);
      await caro.espera('puerta');
      caro.mandar({'t': 'escuela', 'tele': 2, 'evento': _b});
      final pedido = await t.espera('escuela');
      expect(pedido['evento'], _b);
      expect(pedido['por'], 'Caro');
      expect((await caro.espera('puerta', cumple: (m) => m['evento'] == _b))['titulo'], 'ESCUELA B');
    });

    test('la Tele 2 cambió con su control: sus celulares pasan, y no se le vuelve a pedir',
        () async {
      final t = await tele2(_a);
      await t.espera('central');
      final caro = await celular('Caro', tele: 2);
      await caro.espera('puerta');
      // Lo que llegó antes del cambio no cuenta: un "escuelas" de antes que ya
      // nombraba a B cortaba la espera de abajo antes de tiempo.
      t.darPorMiradoLoQueLlego();
      t.mandar({'t': 'escuela', 'evento': _b});
      await caro.espera('puerta', cumple: (m) => m['evento'] == _b);
      expect((await caro.espera('aviso'))['texto'], 'La Tele 2 pasó a ESCUELA B');
      await t.espera('escuelas', cumple: (m) => (m['escuelas'] as List).contains(_b));
      // Una ida y vuelta por el mismo cable: la central atiende los mensajes de la
      // tele en orden, así que si le hubiera pedido la escuela, ese pedido ya llegó
      // antes que este "hola". (Esperar solo "escuelas" no alcanzaba: sale uno antes
      // del pedido, y la rotura R6 pasaba a veces.)
      t.darPorMiradoLoQueLlego();
      t.mandar({'t': 'hola'});
      await t.espera('hola');
      expect(t.cuantos('escuela'), 0);
    });

    test('la otra tele tenía la misma: a sus celulares, MANTENER · CAMBIAR; vale el primero',
        () async {
      final t = await tele2(_a);
      await t.espera('central');
      final caro = await celular('Caro', tele: 2);
      final mili = await celular('Mili', tele: 2);
      final juli = await celular('Juli', tele: 1);
      await juli.espera('puerta');
      await caro.espera('puerta');
      await mili.espera('puerta');
      central.cambiarEscuelaDeTele(1, _b, yaCambio: true);
      final p = await caro.espera('pregunta');
      expect(p['texto'], 'La Tele 1 cambió a ESCUELA B');
      final id = p['id'];
      await mili.espera('pregunta');
      expect(juli.cuantos('pregunta'), 0, reason: 'la Tele 1 ya cambió');
      caro.mandar({'t': 'contesta', 'id': id, 'cambiar': true});
      mili.mandar({'t': 'contesta', 'id': id, 'cambiar': false});
      // CAMBIAR: la Tele 2 pasa a la B.
      expect((await t.espera('escuela'))['evento'], _b);
      final cerrada = await mili.espera('pregunta_cerrada', cumple: (m) => m['texto'] != null);
      expect(cerrada['texto'], 'Caro eligió CAMBIAR.');
      expect(central.escuelaDeTele(2), _b);
    });

    test('MANTENER: la otra tele sigue con la suya', () async {
      final t = await tele2(_a);
      await t.espera('central');
      final caro = await celular('Caro', tele: 2);
      await caro.espera('puerta');
      central.cambiarEscuelaDeTele(1, _b, yaCambio: true);
      final p = await caro.espera('pregunta');
      caro.mandar({'t': 'contesta', 'id': p['id'], 'cambiar': false});
      await caro.espera('pregunta_cerrada');
      expect(central.escuelaDeTele(2), _a);
      expect(t.cuantos('escuela'), 0);
    });

    test('GIRAR desde el celular: la Tele 1 la gira la tele; la 2, se lo pide', () async {
      final t = await tele2(_a);
      await t.espera('central');
      final caro = await celular('Caro', tele: 2);
      await caro.espera('puerta');
      caro.mandar({'t': 'girar', 'tele': 1, 'como': 'vertical'});
      caro.mandar({'t': 'girar', 'tele': 2, 'como': 'dar_vuelta'});
      expect((await t.espera('girar'))['como'], 'dar_vuelta');
      expect(giros, ['vertical']);
      caro.mandar({'t': 'girar', 'tele': 1, 'como': 'de costado'});
      await caro.pedirYEsperar('h', QuePide.ingresar, 'a1');
      expect(giros, ['vertical'], reason: 'un giro raro no se hace');
    });
  });

  group('lo que encontró la revisión del 26-nov', () {
    const ajena = 'e0000000-0000-4000-8000-0000000000ee';

    test('una escuela que no es de esta tele: no cambia, y el celular que la pidió se entera',
        () async {
      expect(central.cambiarEscuelaDeTele(1, ajena), isFalse);
      expect(central.eventoId, _a);
      expect(central.atiende, [_a]);
      final juli = await celular('Juli', tele: 1);
      await juli.espera('puerta');
      juli.mandar({'t': 'escuela', 'tele': 1, 'evento': ajena});
      expect((await juli.espera('aviso'))['texto'], 'Esa escuela no está en esta tele.');
      expect(pedidasParaLaTele1, isEmpty);
      expect(central.eventoId, _a);
    });

    test('la Tele 2 desconectada no cambia de escuela: no se enteraría, y al volver la '
        'central la volvería atrás', () async {
      final t = await tele2(_a);
      await t.espera('central');
      await t.ws.close();
      await _hasta(() => !central.teles.single.conectada);
      expect(central.cambiarEscuelaDeTele(2, _b), isFalse);
      expect(central.escuelaDeTele(2), _a);
      final caro = await celular('Caro', tele: 2);
      await caro.espera('puerta');
      caro.mandar({'t': 'escuela', 'tele': 2, 'evento': _b});
      expect((await caro.espera('aviso'))['texto'], contains('no está conectada'));
      // Ella misma sí: vuelve con la suya.
      expect(central.cambiarEscuelaDeTele(2, _b, yaCambio: true), isTrue);
    });

    test('la escuela que ninguna tele muestra se suelta, y se vuelve a atender si hace falta',
        () async {
      final soltadas = <String>[];
      central.alSoltar = soltadas.add;
      central.cambiarEscuelaDeTele(1, _b, yaCambio: true);
      expect(central.atiende, [_b]);
      expect(soltadas, [_a]);
      // Vuelve a la A: se atiende de nuevo, con su lista.
      final juli = await celular('Juli', tele: 1);
      await juli.espera('puerta', cumple: (m) => m['evento'] == _b);
      central.cambiarEscuelaDeTele(1, _a, yaCambio: true);
      expect(central.atiende, [_a]);
      await juli.espera('puerta', cumple: (m) => m['evento'] == _a);
    });

    test('su tele pasa a una escuela todavía sin lista: al celular le llega "esperando" y '
        'un salón vacío, los dos con la escuela', () async {
      final juli = await celular('Juli', tele: 1);
      await juli.espera('puerta');
      central.alAtender = (_) {};
      central.cambiarEscuelaDeTele(1, _b, yaCambio: true);
      expect((await juli.espera('esperando'))['evento'], _b);
      final salon = await juli.espera('salon', cumple: (m) => m['evento'] == _b);
      expect(salon['armado'], isNull);
    });

    test('la Tele 2 desconectada se queda con su escuela: no se suelta', () async {
      final t = await tele2(_b);
      await t.espera('central');
      await t.ws.close();
      await _hasta(() => !central.teles.single.conectada);
      central.cambiarEscuelaDeTele(1, _b, yaCambio: true);
      central.cambiarEscuelaDeTele(1, _a, yaCambio: true);
      expect(central.atiende, containsAll([_a, _b]));
    });

    test('la Tele 1 vuelve a cambiar: la pregunta de antes se cierra y su respuesta ya '
        'no cambia nada', () async {
      final t = await tele2(_a);
      await t.espera('central');
      final caro = await celular('Caro', tele: 2);
      await caro.espera('puerta');
      central.cambiarEscuelaDeTele(1, _b, yaCambio: true);
      final p = await caro.espera('pregunta');
      central.cambiarEscuelaDeTele(1, _a, yaCambio: true);
      final cerrada = await caro.espera('pregunta_cerrada');
      expect(cerrada['id'], p['id']);
      expect(cerrada['texto'], contains('volvió a cambiar'));
      caro.mandar({'t': 'contesta', 'id': p['id'], 'cambiar': true});
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(central.escuelaDeTele(2), _a);
      expect(t.cuantos('escuela'), 0);
    });

    test('"Pasar a principal" con la Tele 1 apagada: esta tele atiende también la escuela '
        'de aquella, y sus celulares (QR de "la otra escuela") marcan en ella', () async {
      central.atenderSinTele(_b);
      expect(central.atiende, [_a, _b]);
      expect(central.escuelaDeTele(2), _b);
      final caro = await celular('Caro', tele: 2);
      final p = await caro.espera('puerta');
      expect(p['evento'], _b);
      await caro.pedirYEsperar('b', QuePide.ingresar, 'b1', evento: _b);
      expect(base.ingresos.last, (_b, 'b1'));
      final juli = await celular('Juli', tele: 1);
      expect((await juli.espera('puerta'))['evento'], _a);
      // Una escuela que no es suya, no.
      central.atenderSinTele(ajena);
      expect(central.atiende, [_a, _b]);
    });
  });

  group('la notebook, como siempre', () {
    test('sin tele no atiende otra escuela ni cambia de escuela', () async {
      await central.cerrar();
      // Aunque alguien le pase las escuelas que vienen.
      central = CentralPuerta(eventoId: _a, codigo: _codigo, pc: base)
        ..ponerEscuelasParaElegir(const [EscuelaParaElegir(_b, 'ESCUELA B')]);
      puerto = await central.arrancar(desde: 0, en: InternetAddress.loopbackIPv4);
      central.atender(_b);
      central.cambiarEscuelaDeTele(1, _b);
      expect(central.atiende, [_a]);
      expect(central.eventoId, _a);
      central.ponerPuerta(base.lista(_a));
      final juli = await celular('Juli');
      await juli.espera('puerta');
      // Un pedido con otra escuela va a la de la notebook, como siempre.
      await juli.pedirYEsperar('n', QuePide.ingresar, 'a1', evento: _b);
      expect(base.ingresos.last, (_a, 'a1'));
    });
  });

  group('la Tele 1 contesta a la Tele 2 de cualquier escuela', () {
    test('con la escuela que le preguntaron, solo si es suya, y sin decir cuáles atiende '
        '(revisión del 26-nov)', () {
      final r = RespondeLaTele1(puertoCentral: 8787, conoce: (id) => id == _a || id == _b);
      expect(r.respuesta({'t': 'buscar', 'evento': _b}), {
        't': 'central',
        'evento': _b,
        'puerto': 8787,
        'tele': true,
      });
      expect(r.respuesta({'t': 'buscar', 'evento': 'f9999999-0000-4000-8000-000000000009'}), isNull,
          reason: 'una escuela que no es de esta tele: no contesta');
      expect(r.respuesta({'t': 'buscar', 'evento': 'raro'}), isNull);
      expect(r.respuesta({'t': 'otra'}), isNull);
    });
  });
}
