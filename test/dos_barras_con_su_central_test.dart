// Una central por barra (25-nov-2026): dos notebooks, cada una con su central, y las
// tablets de cada barra, todo de verdad (servidores, búsqueda por UDP y clientes) por la
// red de esta PC. Cada barra "contesta" en su puerto; "juntar las redes" es que la otra
// pregunte también ahí. Sin base, sin nube y sin router.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/core/utils/uuid_utils.dart';
import 'package:arguello_events/features/barra/central/barra_con_la_red.dart';
import 'package:arguello_events/features/barra/central/buscar_central.dart';
import 'package:arguello_events/features/barra/central/central_barra.dart';
import 'package:arguello_events/features/barra/central/cliente_de_la_central.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';

import 'helpers/barra_en_memoria.dart';

const _fiesta = 'e0000000-0000-4000-8000-000000000001';

Future<void> hasta(bool Function() listo, {String? que, int segundos = 8}) async {
  final limite = DateTime.now().add(Duration(seconds: segundos));
  while (!listo()) {
    if (DateTime.now().isAfter(limite)) fail('no pasó: ${que ?? 'lo esperado'}');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// Dos puertos UDP libres y distintos **fuera del rango que Windows reparte solo**
/// (49152 en adelante): si no, el socket de búsqueda de una central podía quedarse con el
/// puerto de la otra antes de que esa lo abriera, y la tablet no la oía.
Future<(int, int)> dosPuertosLibres() async {
  final azar = Random();
  final libres = <int>[];
  while (libres.length < 2) {
    final p = 20000 + azar.nextInt(20000);
    if (libres.contains(p)) continue;
    try {
      final s = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, p);
      s.close();
      libres.add(p);
    } catch (_) {}
  }
  return (libres[0], libres[1]);
}

/// Una notebook: su barra en memoria, su central y lo que contesta a la búsqueda.
class _Notebook {
  _Notebook(this.equipo, this.barraDelSalon, this.puertoBusqueda, {this.ahora})
      : barra = BarraEnMemoria()..equipo = equipo {
    barra.reloj = () => DateTime.now().toUtc();
  }

  final String equipo;
  final String barraDelSalon;
  final int puertoBusqueda;
  final BarraEnMemoria barra;

  /// La hora de la notebook (null: la de esta PC).
  final DateTime Function()? ahora;

  /// A qué puertos pregunta su enganche: con la otra red "junta", también al de la otra.
  final preguntaA = <int>[];
  CentralBarra? central;
  RespondeBusqueda? responde;

  Future<void> prender() async {
    preguntaA
      ..clear()
      ..add(puertoBusqueda);
    final c = CentralBarra(eventoId: _fiesta, barra: barra, barraDelSalon: barraDelSalon, ahora: ahora);
    final puerto = await c.arrancar(desde: 0, en: InternetAddress.loopbackIPv4);
    final r = RespondeBusqueda(eventoId: _fiesta, puertoCentral: puerto, barra: barraDelSalon, equipo: equipo);
    await r.escuchar(puerto: puertoBusqueda, en: InternetAddress.loopbackIPv4);
    c.engancharConOtras(
      equipo: equipo,
      buscador: BuscaCentral(
        eventoId: _fiesta,
        cada: const Duration(milliseconds: 100),
        puertos: preguntaA,
        destinos: () async => [InternetAddress.loopbackIPv4],
      ),
      latido: const Duration(milliseconds: 100),
      silencioMaximo: const Duration(seconds: 2),
      pausa: const Duration(milliseconds: 50),
    );
    central = c;
    responde = r;
  }

  /// Se apaga (o se reinicia la notebook): la base queda.
  Future<void> apagar() async {
    responde?.cerrar();
    responde = null;
    await central?.cerrar();
    central = null;
  }

  bool enganchada() => central?.otras.any((o) => o.conectada) ?? false;
}

/// Una tablet de una barra: su barra en memoria, la barra con la red y su cliente.
class _Tablet {
  _Tablet(this.equipo, String nombre, {required String barraDeLaCaja, required List<int> pregunta, Duration espera = const Duration(seconds: 10)})
      : barra = BarraEnMemoria()..equipo = equipo {
    barra.reloj = () => DateTime.now().toUtc();
    cliente = ClienteDeLaCentral(
      eventoId: _fiesta,
      equipo: equipo,
      nombreCaja: nombre,
      barra: barra,
      barraDeLaCaja: barraDeLaCaja,
      eleccion: EleccionDeCentral.deLaCaja(barra: barraDeLaCaja, esperaPorSuBarra: espera),
      buscador: BuscaCentral(
        eventoId: _fiesta,
        cada: const Duration(milliseconds: 100),
        puertos: pregunta,
        destinos: () async => [InternetAddress.loopbackIPv4],
      ),
      latido: const Duration(milliseconds: 100),
      silencioMaximo: const Duration(seconds: 2),
      pausa: const Duration(milliseconds: 50),
    );
    aviso.salida = cliente.mandar;
    caja = BarraConLaRed(caja: barra, jefe: barra, red: barra, aviso: aviso);
  }

  final String equipo;
  final BarraEnMemoria barra;
  final aviso = AvisoALaRed();
  late final ClienteDeLaCentral cliente;
  late final BarraConLaRed caja;

  Future<CajaBarra> abrir(int numero, String sede) => caja.abrirCaja(
        eventoId: _fiesta,
        operadorId: UuidUtils.generate(),
        operadorNombre: 'Cajera $numero',
        numeroCaja: numero,
        sede: sede,
      );

  Future<VentaBarra> vender(CajaBarra c) => caja.vender(
        caja: c,
        renglones: const [RenglonVenta(productoId: 'p', nombre: 'Cerveza lata', precio: 3500, cantidad: 1)],
        medio: MedioBarra.efectivo,
        efectivo: 3500,
        quien: 'Cajera',
      );

  bool tiene(VentaBarra v) => barra.ventasGuardadas.any((x) => x.id == v.id);
}

bool _tiene(BarraEnMemoria b, VentaBarra v) => b.ventasGuardadas.any((x) => x.id == v.id);

void main() {
  late _Notebook barra1, barra2;
  final tablets = <_Tablet>[];

  setUp(() async {
    // "a-..." < "b-...": de las dos, la de la Barra 1 es la que se engancha.
    final (p1, p2) = await dosPuertosLibres();
    barra1 = _Notebook('a-notebook', 'Barra 1', p1);
    barra2 = _Notebook('b-notebook', 'Barra 2', p2);
    await barra1.prender();
    await barra2.prender();
  });

  tearDown(() async {
    for (final t in tablets) {
      t.cliente.dispose();
    }
    tablets.clear();
    await barra1.apagar();
    await barra2.apagar();
  });

  _Tablet tablet(String equipo, String nombre, String barra, List<int> pregunta, {Duration? espera}) {
    final t = _Tablet(equipo, nombre,
        barraDeLaCaja: barra, pregunta: pregunta, espera: espera ?? const Duration(seconds: 10));
    tablets.add(t);
    t.cliente.arrancar();
    return t;
  }

  /// Las dos redes "se ven": cada enganche pregunta también en el puerto de la otra.
  void juntar() {
    barra1.preguntaA.add(barra2.puertoBusqueda);
    barra2.preguntaA.add(barra1.puertoBusqueda);
  }

  /// Se cortan: cada una pregunta solo en el suyo, y el enganche se vuelve a buscar.
  void separar() {
    barra1.preguntaA.remove(barra2.puertoBusqueda);
    barra2.preguntaA.remove(barra1.puertoBusqueda);
    barra1.central!.volverABuscarLaOtra();
    barra2.central!.volverABuscarLaOtra();
  }

  test('separadas cada una trabaja sola; juntas se pasan todo, sin repetir nada, y al cortar siguen', () async {
    final a = tablet('tablet-a', 'Caja 1 · Marta', 'Barra 1', [barra1.puertoBusqueda]);
    final b = tablet('tablet-b', 'Caja 2 · Sofía', 'Barra 2', [barra2.puertoBusqueda]);
    await hasta(() => a.cliente.conectada && b.cliente.conectada, que: 'cada tablet con la central de su barra');
    expect(a.cliente.donde!.barra, 'Barra 1');
    expect(b.cliente.donde!.barra, 'Barra 2');

    // 1. Islas: cada una vende y su central lo tiene; la otra no.
    final cajaA = await a.abrir(1, 'Barra 1');
    final cajaB = await b.abrir(2, 'Barra 2');
    final va1 = await a.vender(cajaA);
    final vb1 = await b.vender(cajaB);
    await hasta(() => _tiene(barra1.barra, va1) && _tiene(barra2.barra, vb1), que: 'cada central con lo suyo');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(_tiene(barra1.barra, vb1), isFalse, reason: 'sin verse, la Barra 1 no sabe de la 2');
    expect(_tiene(barra2.barra, va1), isFalse);
    expect(barra1.enganchada() || barra2.enganchada(), isFalse);

    // 2. Se juntan las redes: se enganchan solas y se pasan todo.
    juntar();
    await hasta(() => barra1.enganchada() && barra2.enganchada(), que: 'las dos centrales enganchadas');
    await hasta(() => _tiene(barra1.barra, vb1) && _tiene(barra2.barra, va1), que: 'cada una con lo de la otra');
    await hasta(() => a.tiene(vb1) && b.tiene(va1), que: 'y las tablets de cada barra también');
    expect(barra2.central!.cajas.where((c) => c.esCentral), hasLength(1),
        reason: 'un solo enganche: la Barra 1 se conectó a la 2, y no al revés también');
    expect(barra1.central!.otras.single.barra, 'Barra 2');

    // 3. Enganchadas, lo nuevo cruza en el momento, en las dos direcciones.
    final va2 = await a.vender(cajaA);
    final vb2 = await b.vender(cajaB);
    await hasta(() => b.tiene(va2) && a.tiene(vb2), que: 'lo nuevo, de una barra a la otra');

    // Nada repetido: cada venta una vez en cada equipo, y lo de otro no se sube de nuevo.
    for (final e in [barra1.barra, barra2.barra, a.barra, b.barra]) {
      final ids = [for (final v in e.ventasGuardadas) v.id];
      expect(ids.toSet().length, ids.length, reason: '${e.equipo}: sin repetidas');
      expect(ids.toSet(), {va1.id, va2.id, vb1.id, vb2.id}, reason: e.equipo);
    }
    expect(barra1.barra.sinSubir, isEmpty, reason: 'la notebook no sube lo de las tablets');
    expect(barra2.barra.sinSubir, isEmpty);
    expect(a.barra.sinSubir, {va1.id, va2.id}, reason: 'cada tablet sube solo lo suyo');
    expect(b.barra.sinSubir, {vb1.id, vb2.id});

    // 4. Se cortan otra vez: cada una sigue sola; al volver a verse se juntan.
    separar();
    await hasta(() => !barra1.enganchada(), que: 'se cortó el enganche');
    final va3 = await a.vender(cajaA);
    final vb3 = await b.vender(cajaB);
    await hasta(() => _tiene(barra1.barra, va3) && _tiene(barra2.barra, vb3), que: 'cada una sigue vendiendo');
    juntar();
    await hasta(() => b.tiene(va3) && a.tiene(vb3), que: 'al volver a verse, lo de la noche cortada cruza');
    for (final e in [barra1.barra, barra2.barra, a.barra, b.barra]) {
      expect(e.ventasGuardadas, hasLength(6), reason: e.equipo);
    }
  });

  test('muchas preguntas seguidas por la red: ninguna se pierde (el socket no espera)', () async {
    final recibe = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final manda = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    var llegaron = 0;
    recibe.listen((e) {
      if (e == RawSocketEvent.read && recibe.receive() != null) llegaron++;
    });
    // Todas a la vez, sin esperar entre una y otra: así salen las preguntas a cada
    // dirección de la red y las respuestas a cada tablet.
    await Future.wait([
      for (var i = 0; i < 40; i++)
        mandarDatagrama(manda, [i], InternetAddress.loopbackIPv4, recibe.port),
    ]);
    await hasta(() => llegaron == 40, que: 'llegaron las 40 (llegaron $llegaron)', segundos: 3);
    recibe.close();
    manda.close();
  });

  // La revisión independiente del 26-nov: el enganche y una caja de la misma notebook
  // usaban el mismo id, y la otra central los echaba por turno sin fin.
  test('una caja con el id de la notebook conectada a la otra central no choca con el enganche', () async {
    final caja = tablet('a-notebook', 'Encargada · Romi', 'Barra 2', [barra2.puertoBusqueda]);
    await hasta(() => caja.cliente.conectada, que: 'la caja de la notebook A, en la central B');
    var contar = false;
    var cayo = 0;
    caja.cliente.addListener(() {
      if (contar && !caja.cliente.conectada) cayo++;
    });
    juntar();
    await hasta(() => barra1.enganchada(), que: 'A enganchada con B');
    contar = true;
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(cayo, 0, reason: 'B no echa a la caja por el enganche');
    expect(barra1.enganchada(), isTrue);
    expect(caja.cliente.conectada, isTrue);
  });

  test('la tablet sabe si su hora está corrida contra la de la notebook', () async {
    final (p, _) = await dosPuertosLibres();
    final adelantada = _Notebook('c-notebook', 'Barra 1', p,
        ahora: () => DateTime.now().add(const Duration(minutes: 75)));
    await adelantada.prender();
    addTearDown(adelantada.apagar);
    final atrasada = tablet('tablet-c', 'Caja 3', 'Barra 1', [p]);
    final bien = tablet('tablet-a', 'Caja 1', 'Barra 1', [barra1.puertoBusqueda]);
    await hasta(() => atrasada.cliente.relojCorrido != null, que: 'la tablet ve la hora de la notebook');
    expect(atrasada.cliente.relojCorrido, inInclusiveRange(74, 75), reason: 'atrasada una hora y cuarto');
    await hasta(() => bien.cliente.conectada, que: 'la otra conectada');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(bien.cliente.relojCorrido, isNull, reason: 'con la misma hora no hay nada que avisar');
  });

  test('el OK de la encargada cruza de una barra a la otra', () async {
    juntar();
    await hasta(() => barra1.enganchada(), que: 'enganchadas');
    final cajera = tablet('tablet-b', 'Caja 2 · Sofía', 'Barra 2', [barra2.puertoBusqueda]);
    final encargada = tablet('tablet-e', 'Encargada · Romi', 'Barra 1', [barra1.puertoBusqueda]);
    await hasta(() => cajera.cliente.conectada && encargada.cliente.conectada, que: 'conectadas');
    final caja = await cajera.abrir(2, 'Barra 2');
    final pedido = await cajera.caja.anotarPasoDelCierre(PasoDelCierre.pedir(
      caja: caja,
      efectivoContado: 0,
      hechoPor: 'Sofía',
      ahora: DateTime.now(),
    ));
    await hasta(() => encargada.barra.pasosGuardados.any((p) => p.id == pedido.id),
        que: 'el pedido de la Barra 2 le llega a la encargada en la Barra 1');
    final ok = await encargada.caja.anotarPasoDelCierre(PasoDelCierre.responder(
      pedido: pedido,
      tipo: TipoPasoDelCierre.ok,
      hechoPor: 'Romi',
      ahora: DateTime.now(),
    ));
    await hasta(() => cajera.barra.pasosGuardados.any((p) => p.id == ok.id), que: 'y su OK vuelve');
  });

  test('la tablet se engancha a la de su barra; si su notebook no aparece, a la otra', () async {
    juntar();
    final ambas = [barra1.puertoBusqueda, barra2.puertoBusqueda];
    final deLa2 = tablet('tablet-b', 'Caja 2', 'Barra 2', ambas, espera: const Duration(milliseconds: 600));
    await hasta(() => deLa2.cliente.conectada, que: 'conectada');
    expect(deLa2.cliente.donde!.barra, 'Barra 2', reason: 'la de su barra, aunque conteste también la otra');

    // Se apaga la notebook de la Barra 2: la tablet termina en la de la Barra 1, que tiene todo.
    await barra2.apagar();
    await hasta(() => deLa2.cliente.conectada && deLa2.cliente.donde?.barra == 'Barra 1',
        que: 'la tablet se pasa a la otra central', segundos: 12);
    final caja = await deLa2.abrir(2, 'Barra 2');
    final v = await deLa2.vender(caja);
    await hasta(() => _tiene(barra1.barra, v), que: 'lo que vende llega igual');
  });

  test('se reinicia la notebook: la central vuelve con otra dirección y las tablets la encuentran solas', () async {
    final a = tablet('tablet-a', 'Caja 1 · Marta', 'Barra 1', [barra1.puertoBusqueda]);
    await hasta(() => a.cliente.conectada, que: 'conectada');
    final caja = await a.abrir(1, 'Barra 1');
    final antes = await a.vender(caja);
    await hasta(() => _tiene(barra1.barra, antes), que: 'llegó');

    await barra1.apagar();
    await hasta(() => !a.cliente.conectada, que: 'sin central');
    final sinCentral = await a.vender(caja);
    expect(a.cliente.porMandar, 1, reason: 'lo vendido sin central queda para mandar');

    await barra1.prender();
    await hasta(() => a.cliente.conectada, que: 'la encontró de nuevo', segundos: 12);
    await hasta(() => _tiene(barra1.barra, sinCentral), que: 'y le mandó lo de mientras');
    expect(barra1.barra.ventasGuardadas.where((v) => v.id == antes.id), hasLength(1), reason: 'nada repetido');
  });
}
