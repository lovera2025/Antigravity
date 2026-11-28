import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:arguello_events/features/barra/central/barra_con_la_red.dart';
import 'package:arguello_events/features/barra/central/buscar_central.dart';
import 'package:arguello_events/features/barra/central/central_barra.dart';
import 'package:arguello_events/features/barra/central/cliente_de_la_central.dart';
import 'package:arguello_events/features/barra/central/llave_de_la_barra.dart';
import 'package:arguello_events/features/barra/cuentas/pedido_de_cierre.dart';
import 'package:arguello_events/features/barra/cuentas/reglas_de_la_barra.dart';
import 'package:arguello_events/features/barra/datos/aviso_al_anotar.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/pagina/catalogo_de_la_pagina.dart';
import 'package:arguello_events/features/barra/pagina/cliente_de_la_pagina.dart';
import 'package:arguello_events/features/recepcion/central/cliente_central.dart' show GuardadoDelCelular;

import 'helpers/barra_en_memoria.dart';

/// **La página del iPhone de la encargada y del repositor** (28-nov-2026), de punta a
/// punta: la central de verdad en esta PC (loopback), la página con su cliente de verdad
/// y una tablet de cajera, cada una con su barra. Sin base, sin nube y sin router.
const _fiesta = 'e0000000-0000-4000-8000-000000000001';
const _otraFiesta = 'e0000000-0000-4000-8000-000000000002';

/// El navegador del iPhone (lo que guarda la página entre una vez y otra).
class _Navegador implements GuardadoDelCelular {
  _Navegador({this.demora = Duration.zero});

  final datos = <String, String>{};

  /// Lo que tarda en guardar (Safari no guarda al instante).
  final Duration demora;

  @override
  Future<String?> leer(String clave) async => datos[clave];

  @override
  Future<void> guardar(String clave, String? valor) async {
    if (demora > Duration.zero) await Future<void>.delayed(demora);
    if (valor == null) {
      datos.remove(clave);
    } else {
      datos[clave] = valor;
    }
  }
}

Future<void> hasta(bool Function() listo, {String? que, Duration limite = const Duration(seconds: 6)}) async {
  final fin = DateTime.now().add(limite);
  while (!listo()) {
    if (DateTime.now().isAfter(fin)) fail('no pasó: ${que ?? 'lo esperado'}');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late _QuienQueCuenta personas;
  late _NotebookQuePuedeFallar notebook;
  late CentralBarra central;
  late int puerto;
  late Directory carpeta;
  final subidas = <String>[];
  final aCerrar = <ChangeNotifierLike>[];
  final mensajesDeLaPagina = <String>[];

  late ProductoBarra speed;
  late CajaBarra cajaDeMarta;

  Future<void> prenderCentral({int desde = 0}) async {
    central = CentralBarra(
      eventoId: _fiesta,
      barra: notebook,
      quienEsQuien: personas,
      barraDelSalon: 'Barra 1',
      paginaDeLaBarra: carpeta,
      fiestaParaLaPagina: () async =>
          fiestaParaLaPagina(fiestaDePrueba(_fiesta, 'TÉCNICA PINAROLI', DateTime(2026, 12, 4, 22))),
      catalogoParaLaPagina: () => catalogoParaLaPagina(notebook, _fiesta),
      alGuardarDeLaPagina: (tabla, id) => subidas.add('$tabla $id'),
    );
    puerto = await central.arrancar(desde: desde, en: InternetAddress.loopbackIPv4);
  }

  setUp(() async {
    subidas.clear();
    mensajesDeLaPagina.clear();
    personas = _QuienQueCuenta();
    personas.persona('op-marta', 'Marta', pin: '1111', rol: RolEnLaBarra.cajera);
    personas.persona('op-romi', 'Romi', pin: '7777', rol: RolEnLaBarra.encargada);
    personas.persona('op-nico', 'Nico', pin: '5555', rol: RolEnLaBarra.repositor);
    notebook = _NotebookQuePuedeFallar()..equipo = 'notebook';
    notebook.reloj = () => DateTime.now().toUtc();
    speed = notebook.producto('Speed', categoria: 'Energizantes');
    notebook.precio(_fiesta, speed, 4000, stock: 48);
    await notebook.guardarCosto(
        CostoBarra.para(eventoId: _fiesta, productoId: speed.id, precioLista: 1234.56, ahora: DateTime.now()),
        quien: 'Jefe');
    cajaDeMarta = await notebook.abrirCaja(
        eventoId: _fiesta, operadorId: 'op-marta', operadorNombre: 'Marta', numeroCaja: 1);
    await notebook.vender(
      caja: cajaDeMarta,
      renglones: [RenglonVenta(productoId: speed.id, nombre: 'Speed', precio: 4000, cantidad: 2)],
      medio: MedioBarra.efectivo,
      efectivo: 8000,
      quien: 'Marta',
    );
    notebook.subioTodo();
    carpeta = Directory.systemTemp.createTempSync('barra_pagina');
    File('${carpeta.path}${Platform.pathSeparator}index.html').writeAsStringSync('<html>la pagina</html>');
    File('${carpeta.path}${Platform.pathSeparator}main.dart.js').writeAsStringSync('// js');
    await prenderCentral();
  });

  tearDown(() async {
    for (final c in aCerrar) {
      c.dispose();
    }
    aCerrar.clear();
    await central.cerrar();
    try {
      carpeta.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// La página en un iPhone: su navegador y su cliente. Lo que recibe se anota en
  /// [mensajesDeLaPagina] (para mirar que nunca llegue el precio de lista).
  ClienteDeLaPagina iphone({_Navegador? navegador, WebSocketChannel Function(Uri)? abrir, int? por}) {
    final c = ClienteDeLaPagina(
      servidor: Uri.parse('http://127.0.0.1:${por ?? puerto}/'),
      guardado: navegador ?? _Navegador(),
      abrir: abrir ?? IOWebSocketChannel.connect,
      escucharTodo: mensajesDeLaPagina.add,
      latido: const Duration(milliseconds: 100),
      silencioMaximo: const Duration(seconds: 2),
      esperaDeRespuesta: const Duration(seconds: 3),
      pausas: const [Duration(milliseconds: 50)],
    );
    aCerrar.add(ChangeNotifierLike(c.dispose));
    return c;
  }

  Future<ClienteDeLaPagina> entrar(String pin, {_Navegador? navegador}) async {
    final c = iphone(navegador: navegador);
    await c.iniciar();
    c.entrar(pin);
    await hasta(() => c.estado != EstadoDeLaPagina.entrando, que: 'que conteste la notebook');
    return c;
  }

  Future<ClienteDeLaCentral> tabletDeMarta(BarraEnMemoria barra) async {
    final cliente = ClienteDeLaCentral(
      credencial: () async => CredencialDeLaBarra.operador('op-marta', '1111'),
      eventoId: _fiesta,
      equipo: 'tablet-marta',
      nombreCaja: 'Caja 1 · Marta',
      barra: barra,
      aMano: DondeEstaLaCentral('127.0.0.1', puerto),
      latido: const Duration(milliseconds: 100),
      silencioMaximo: const Duration(seconds: 2),
      pausa: const Duration(milliseconds: 50),
    );
    aCerrar.add(ChangeNotifierLike(cliente.dispose));
    cliente.arrancar();
    await hasta(() => cliente.conectada, que: 'la tablet de Marta conectada');
    return cliente;
  }

  group('la notebook sirve la página', () {
    Future<(int, String, String?)> pedir(String camino) async {
      final http = HttpClient();
      try {
        final r = await (await http.getUrl(Uri.parse('http://127.0.0.1:$puerto$camino'))).close();
        return (r.statusCode, await r.transform(utf8.decoder).join(), r.headers.contentType?.mimeType);
      } finally {
        http.close();
      }
    }

    test('la página y sus archivos, y nada fuera de su carpeta', () async {
      final (codigo, cuerpo, tipo) = await pedir('/');
      expect(codigo, 200);
      expect(cuerpo, contains('la pagina'));
      expect(tipo, 'text/html');
      expect((await pedir('/main.dart.js')).$1, 200);
      expect((await pedir('/main.dart.js')).$3, 'application/javascript');
      expect((await pedir('/no_esta.js')).$1, 404);
      expect((await pedir('/../secreto.txt')).$1, 404);
      expect((await pedir('/%2e%2e/secreto.txt')).$1, 404);
    });

    test('sin la carpeta de la página, nada (la central sigue para las tablets)', () async {
      await central.cerrar();
      central = CentralBarra(eventoId: _fiesta, barra: notebook, quienEsQuien: personas);
      puerto = await central.arrancar(desde: 0, en: InternetAddress.loopbackIPv4);
      expect((await pedir('/')).$1, 404);
    });
  });

  group('entra solo con el PIN', () {
    test('la encargada entra, ve la fiesta y todo lo de la noche, con el catálogo', () async {
      final c = await entrar('7777');
      expect(c.estado, EstadoDeLaPagina.conectada);
      expect(c.quien?.nombre, 'Romi');
      expect(c.quien?.rol, RolEnLaBarra.encargada);
      expect(c.quien?.operadorId, 'op-romi');
      expect(c.fiesta, 'TÉCNICA PINAROLI');
      expect(c.barraDelSalon, 'Barra 1');
      await hasta(() => c.evento != null, que: 'la fiesta');
      expect(c.evento!.containsKey('pin_operador'), isFalse);
      final ventas = await c.barra.ventas(_fiesta);
      expect(ventas.single.renglones.single.cantidad, 2);
      expect((await c.barra.precios(_fiesta)).single.stockInicial, 48);
      expect((await c.barra.productos()).single.nombre, 'Speed');
      expect((await c.barra.cajas(_fiesta)).single.id, cajaDeMarta.id);
    });

    test('el repositor entra con el suyo', () async {
      final c = await entrar('5555');
      expect(c.quien?.rol, RolEnLaBarra.repositor);
      expect(c.quien?.nombre, 'Nico');
    });

    test('el jefe entra con el PIN maestro de la notebook', () async {
      final c = await entrar('2026');
      expect(c.quien?.rol, RolEnLaBarra.jefe);
      expect(c.quien?.nombre, 'Jefe');
    });

    test('la cajera no entra con el suyo, ni un PIN equivocado', () async {
      final cajera = await entrar('1111');
      expect(cajera.estado, EstadoDeLaPagina.pidePin);
      expect(cajera.problema, contains('no es de una encargada'));
      final mal = await entrar('9999');
      expect(mal.estado, EstadoDeLaPagina.pidePin);
      expect(mal.quien, isNull);
    });

    test('cinco PIN equivocados en un minuto: frena', () async {
      for (var i = 0; i < kIntentosDeLaPagina; i++) {
        await entrar('900$i');
      }
      final otra = await entrar('7777');
      expect(otra.estado, EstadoDeLaPagina.pidePin, reason: 'ni con el PIN bueno, hasta que pase el minuto');
      expect(otra.problema, contains('Demasiados intentos'));
    });

    test('la página no es una caja: no suma en las cajas conectadas', () async {
      final c = await entrar('7777');
      expect(c.conectada, isTrue);
      expect(central.conectadas, 0);
      expect(central.cajas, isEmpty);
      expect(central.paginas.single.nombre, 'Romi');
      expect(central.paginas.single.conectada, isTrue);
    });

    test('el PIN no viaja, y el precio de lista nunca llega a la página', () async {
      final c = await entrar('7777');
      await hasta(() => c.evento != null);
      final todo = mensajesDeLaPagina.join('\n');
      expect(todo, isNot(contains('7777')));
      expect(todo, isNot(contains('barra_costos')));
      expect(todo, isNot(contains('precio_lista')));
      expect(todo, isNot(contains('1234.56')));
      expect(await c.barra.costos(_fiesta), isEmpty);
    });

    test('la página va con la hora de la notebook', () async {
      final c = await entrar('7777');
      expect(c.ahora().difference(DateTime.now()).inSeconds.abs(), lessThan(3));
    });
  });

  test('una notebook de afuera no se hace pasar por la central', () async {
    // Una "central" que contesta "adelante" sin saber el PIN: la página no le cree.
    final falsa = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    falsa.listen((pedido) async {
      final ws = await WebSocketTransformer.upgrade(pedido);
      ws.add(jsonEncode({'t': 'reto', 'n': '0123456789abcdef0123456789abcdef', 'evento': _fiesta}));
      ws.listen((_) => ws.add(jsonEncode({
            't': 'adelante',
            'rol': 'encargada',
            'nombre': 'Romi',
            'quien': 'operador',
            'ficha': 'abc',
            'prueba': 'cualquier cosa',
          })));
    });
    final c = ClienteDeLaPagina(
      servidor: Uri.parse('http://127.0.0.1:${falsa.port}/'),
      guardado: _Navegador(),
      abrir: IOWebSocketChannel.connect,
    );
    aCerrar.add(ChangeNotifierLike(c.dispose));
    await c.iniciar();
    c.entrar('7777');
    await hasta(() => c.estado == EstadoDeLaPagina.pidePin, que: 'que no le crea');
    expect(c.quien, isNull);
    expect(c.problema, contains('No es la notebook'));
    await falsa.close(force: true);
  });

  group('la ficha de la noche', () {
    test('si se cierra Safari, vuelve a entrar sola, sin el PIN', () async {
      final navegador = _Navegador();
      final primera = await entrar('7777', navegador: navegador);
      expect(primera.conectada, isTrue);
      expect(navegador.datos.values.join(), isNot(contains('7777')), reason: 'no se guarda el PIN');
      primera.dispose();
      aCerrar.removeLast();
      final segunda = iphone(navegador: navegador);
      await segunda.iniciar();
      await hasta(() => segunda.conectada, que: 'que entre sola');
      expect(segunda.quien?.nombre, 'Romi');
    });

    test('la ficha copiada en otro teléfono no sirve', () async {
      final navegador = _Navegador();
      await entrar('7777', navegador: navegador);
      final otro = _Navegador()..datos.addAll({
          for (final e in navegador.datos.entries)
            if (!e.key.endsWith('equipo')) e.key: e.value,
        });
      final ladron = iphone(navegador: otro);
      await ladron.iniciar();
      await hasta(() => ladron.estado == EstadoDeLaPagina.pidePin, que: 'que pida el PIN');
      expect(ladron.quien, isNull);
    });

    test('si la notebook se reinició, pide el PIN de nuevo', () async {
      final navegador = _Navegador();
      final c = await entrar('7777', navegador: navegador);
      final viejo = puerto;
      await central.cerrar();
      await hasta(() => c.estado == EstadoDeLaPagina.sinConexion, que: 'sin conexión');
      await prenderCentral(desde: viejo);
      expect(puerto, viejo);
      await hasta(() => c.estado == EstadoDeLaPagina.pidePin, que: 'que pida el PIN');
      expect(c.problema, contains('se reinició'));
    });

    test('se corta el wifi y vuelve: se reconecta sola, sin el PIN', () async {
      WebSocketChannel? ultimo;
      final c = iphone(abrir: (uri) => ultimo = IOWebSocketChannel.connect(uri));
      await c.iniciar();
      c.entrar('7777');
      await hasta(() => c.conectada);
      await ultimo!.sink.close();
      await hasta(() => c.estado == EstadoDeLaPagina.sinConexion, que: 'que se dé cuenta');
      await hasta(() => c.conectada, que: 'que vuelva sola');
      expect(c.quien?.nombre, 'Romi');
    });
  });

  group('lo que anota la página', () {
    test('anular sin el vale: llega a la tablet, queda en la cola de la notebook y se sube', () async {
      final tablet = BarraEnMemoria()..equipo = 'tablet-marta';
      await tabletDeMarta(tablet);
      final c = await entrar('7777');
      final venta = (await c.barra.ventas(_fiesta)).single;
      final a = await c.barra.anular(venta, motivo: 'se la tomó', quien: 'Romi', valeVolvio: false);
      expect(a.deviceId, c.equipo, reason: 'a nombre del teléfono');
      expect(notebook.anulacionesGuardadas.single.valeVolvio, isFalse);
      expect(notebook.otrosSinSubir, contains(a.id), reason: 'la sube la notebook');
      expect(subidas, ['barra_anulaciones ${a.id}']);
      await hasta(() => tablet.anulacionesGuardadas.isNotEmpty, que: 'la anulación en la tablet');
      expect(tablet.anulacionesGuardadas.single.hechoPor, 'Romi');
      expect((await c.barra.anulaciones(_fiesta)).single.id, a.id);
      final otra = await c.barra.anular(venta, motivo: 'otra vez', quien: 'Romi');
      expect(otra.id, a.id, reason: 'anular dos veces deja una sola');
    });

    test('el OK del cierre: la cajera pide, la encargada acepta desde el iPhone y le llega', () async {
      final tablet = BarraEnMemoria()..equipo = 'tablet-marta';
      final cliente = await tabletDeMarta(tablet);
      final aviso = AvisoALaRed()..salida = cliente.mandar;
      final caja = BarraConLaRed(caja: tablet, jefe: tablet, red: tablet, aviso: aviso);
      // Una caja vive en un solo equipo: la de esta prueba la abre la tablet.
      final suya = await caja.abrirCaja(eventoId: _fiesta, operadorId: 'op-marta', operadorNombre: 'Marta', numeroCaja: 2);
      await hasta(() => notebook.cajasGuardadas.any((c) => c.id == suya.id), que: 'la caja en la notebook');
      final pedido = await caja.anotarPasoDelCierre(PasoDelCierre.pedir(
        caja: suya,
        efectivoContado: 8000,
        hechoPor: 'Marta',
        ahora: DateTime.now(),
      ));
      final c = await entrar('7777');
      await hasta(() => notebook.pasosGuardados.isNotEmpty, que: 'el pedido en la notebook');
      final pasos = await c.barra.pasosDelCierre(_fiesta);
      expect(pasos.single.id, pedido.id, reason: 'la página ve el pedido');
      await c.barra.anotarPasoDelCierre(PasoDelCierre.responder(
        pedido: pasos.single,
        tipo: TipoPasoDelCierre.ok,
        hechoPor: 'Romi',
        ahora: c.ahora(),
      ));
      await hasta(() => tablet.pasosGuardados.length == 2, que: 'el OK en la tablet de la cajera');
      expect(PedidoDeCierre.de(pedido.cajaBarraId, tablet.pasosGuardados).aceptado, isTrue);
    });

    test('sacar efectivo desde el iPhone: le llega a la tablet de la caja', () async {
      final tablet = BarraEnMemoria()..equipo = 'tablet-marta';
      await tabletDeMarta(tablet);
      final c = await entrar('7777');
      final m = await c.barra.anotarMovimientoDeCaja(
        MovimientoDeCaja.nuevo(
          eventoId: _fiesta,
          cajaBarraId: cajaDeMarta.id,
          tipo: TipoMovimientoDeCaja.retiro,
          monto: 5000,
          motivo: 'para el cambio de la otra',
          ahora: c.ahora(),
        ),
        quien: 'Romi',
      );
      expect(notebook.movimientosDeCajaGuardados.single.id, m.id);
      await hasta(() => tablet.movimientosDeCajaGuardados.isNotEmpty, que: 'el retiro en la tablet');
    });

    test('el repositor repone desde el iPhone; anular no le toca', () async {
      final tablet = BarraEnMemoria()..equipo = 'tablet-marta';
      await tabletDeMarta(tablet);
      final c = await entrar('5555');
      final repuesto = await c.barra.anotarMovimientoDeStock(
        MovimientoDeStock.reposicion(
          eventoId: _fiesta,
          productoId: speed.id,
          barra: 'Barra 1',
          cantidad: 24,
          hechoPor: 'Nico',
          ahora: c.ahora(),
        ),
        quien: 'Nico',
      );
      await hasta(() => tablet.movimientosGuardados.any((m) => m.id == repuesto.id), que: 'lo repuesto en la tablet');
      final venta = (await c.barra.ventas(_fiesta)).single;
      await expectLater(
        c.barra.anular(venta, motivo: 'no', quien: 'Nico'),
        throwsA(isA<LaNotebookNoLoGuardo>()),
      );
      expect(notebook.anulacionesGuardadas, isEmpty);
      expect(central.rechazos.last.nombre, 'Página');
    });

    test('no se anota algo de otro teléfono, de otra fiesta, ni una venta', () async {
      final c = await entrar('7777');
      final venta = (await c.barra.ventas(_fiesta)).single;
      final ajena = AnulacionBarra.de(venta, motivo: 'x', hechoPor: 'Romi', deviceId: 'otro', ahora: c.ahora());
      await expectLater(c.escribir('barra_anulaciones', ajena.toMap()), throwsA(isA<LaNotebookNoLoGuardo>()));
      final deOtra = {...AnulacionBarra.de(venta, motivo: 'x', deviceId: c.equipo, ahora: c.ahora()).toMap(),
        'evento_id': _otraFiesta};
      await expectLater(c.escribir('barra_anulaciones', deOtra), throwsA(isA<LaNotebookNoLoGuardo>()));
      await expectLater(c.escribir('barra_ventas', venta.toMap()), throwsA(isA<LaNotebookNoLoGuardo>()));
      expect(notebook.anulacionesGuardadas, isEmpty);
      expect(notebook.deLaPagina, 0);
    });

    test('el catálogo, los precios y el reparto no se cambian desde la página', () async {
      final c = await entrar('2026');
      expect(() => c.barra.guardarPrecio(PrecioBarra.para(eventoId: _fiesta, productoId: speed.id, precio: 1, ahora: DateTime.now()), quien: 'Jefe'),
          throwsUnsupportedError);
      expect(() => c.barra.guardarCosto(CostoBarra.para(eventoId: _fiesta, productoId: speed.id, ahora: DateTime.now()), quien: 'Jefe'),
          throwsUnsupportedError);
    });

    test('sin conexión no se anota nada', () async {
      final c = await entrar('7777');
      final venta = (await c.barra.ventas(_fiesta)).single;
      await central.cerrar();
      await hasta(() => c.estado == EstadoDeLaPagina.sinConexion);
      await expectLater(
        c.barra.anular(venta, motivo: 'x', quien: 'Romi'),
        throwsA(isA<SinConexionConLaNotebook>()),
      );
      expect(await c.barra.anulaciones(_fiesta), isEmpty, reason: 'nada quedó "hecho" sin estarlo');
      await prenderCentral();
    });

    test('lo que vende una tablet le llega a la página al toque', () async {
      final tablet = BarraEnMemoria()..equipo = 'tablet-marta';
      final cliente = await tabletDeMarta(tablet);
      final c = await entrar('7777');
      var cambios = 0;
      final escucha = c.cambios.listen((_) => cambios++);
      final aviso = AvisoALaRed()..salida = cliente.mandar;
      final caja = BarraConLaRed(caja: tablet, jefe: tablet, red: tablet, aviso: aviso);
      final suya = await caja.abrirCaja(eventoId: _fiesta, operadorId: 'op-marta', operadorNombre: 'Marta', numeroCaja: 2);
      await caja.vender(
        caja: suya,
        renglones: [RenglonVenta(productoId: speed.id, nombre: 'Speed', precio: 4000, cantidad: 1)],
        medio: MedioBarra.efectivo,
        efectivo: 4000,
        quien: 'Marta',
      );
      await hasta(() => notebook.ventasGuardadas.length == 2, que: 'la venta en la notebook');
      await hasta(() => cambios > 1, que: 'la venta en la página');
      expect((await c.barra.ventas(_fiesta)).length, 2);
      await escucha.cancel();
    });
  });

  // ── La tercera revisión (28-nov-2026): lo mandado sin respuesta, el PIN, SALIR ──

  Future<MovimientoDeCaja> retiro(ClienteDeLaPagina c, {double monto = 5000}) => c.barra.anotarMovimientoDeCaja(
        MovimientoDeCaja.nuevo(
          eventoId: _fiesta,
          cajaBarraId: cajaDeMarta.id,
          tipo: TipoMovimientoDeCaja.retiro,
          monto: monto,
          motivo: 'para el cambio de la otra',
          ahora: c.ahora(),
        ),
        quien: 'Romi',
      );

  /// El iPhone de Romi, entrando a la notebook por [puente].
  Future<ClienteDeLaPagina> romiPor(_Puente puente, {_Navegador? navegador}) async {
    final c = iphone(por: puente.puerto, navegador: navegador);
    await c.iniciar();
    c.entrar('7777');
    await hasta(() => c.conectada, que: 'Romi conectada');
    return c;
  }

  Future<_Puente> unPuente() async {
    final p = _Puente(puerto);
    await p.abrir();
    addTearDown(p.cerrar);
    return p;
  }

  bool esRespuesta(String m) => m.contains('"t":"respuesta"');

  group('lo mandado sin respuesta no se anota dos veces', () {
    test('se corta justo después de mandar un retiro: queda por confirmar, se reenvía con el mismo número y queda '
        'una sola vez', () async {
      final tablet = BarraEnMemoria()..equipo = 'tablet-marta';
      await tabletDeMarta(tablet);
      final puente = await unPuente();
      final c = await romiPor(puente);
      puente.pierdeDeLaNotebook = esRespuesta;
      final r = _Resultado(retiro(c));
      await hasta(() => notebook.movimientosDeCajaGuardados.isNotEmpty, que: 'que la notebook lo anote');
      expect(c.porConfirmar, 1);
      puente.pierdeDeLaNotebook = (_) => false;
      await puente.cortar();
      await hasta(() => r.listo, que: 'que la pantalla se entere');
      expect(r.error, isA<QuedaPorConfirmar>(), reason: 'no "probá de nuevo"');
      expect(textoDelError(r.error!, 'No se pudo. Probá de nuevo.'), contains('No lo repitas'));
      await hasta(() => c.conectada && c.porConfirmar == 0, que: 'que vuelva sola y se confirme');
      expect(notebook.movimientosDeCajaGuardados, hasLength(1), reason: 'una sola vez');
      expect(subidas.where((s) => s.startsWith('barra_caja_movimientos')), hasLength(1));
      expect((await c.barra.movimientosDeCaja(_fiesta)).single.monto, 5000, reason: 'la página lo muestra');
      await hasta(() => tablet.movimientosDeCajaGuardados.isNotEmpty, que: 'el retiro en la tablet');
      expect(tablet.movimientosDeCajaGuardados, hasLength(1));
      expect(c.noSeAnotaron, isEmpty);
    });

    test('si nunca le llegó a la notebook, al volver se anota, una vez', () async {
      final puente = await unPuente();
      final c = await romiPor(puente);
      puente.pierdeDelTelefono = (m) => m.contains('"t":"escribe"');
      final r = _Resultado(retiro(c));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(notebook.movimientosDeCajaGuardados, isEmpty);
      puente.pierdeDelTelefono = (_) => false;
      await puente.cortar();
      await hasta(() => r.listo);
      expect(r.error, isA<QuedaPorConfirmar>());
      await hasta(() => c.conectada && c.porConfirmar == 0, que: 'que se confirme al volver');
      expect(notebook.movimientosDeCajaGuardados, hasLength(1));
      expect(await c.barra.movimientosDeCaja(_fiesta), hasLength(1));
    });

    test('la respuesta que llega tarde también lo confirma', () async {
      final puente = await unPuente();
      final c = await romiPor(puente);
      puente.retiene = esRespuesta;
      await expectLater(retiro(c), throwsA(isA<QuedaPorConfirmar>()));
      expect(c.porConfirmar, 1);
      expect(await c.barra.movimientosDeCaja(_fiesta), isEmpty, reason: 'nada "hecho" sin respuesta');
      puente.retiene = (_) => false;
      puente.retenidos.forEach(puente.alTelefono);
      await hasta(() => c.porConfirmar == 0, que: 'que la respuesta tardía lo confirme');
      expect(await c.barra.movimientosDeCaja(_fiesta), hasLength(1));
      expect(notebook.movimientosDeCajaGuardados, hasLength(1));
    });

    test('lo por confirmar que al final la notebook no guarda: la franja lo dice hasta que lo lean', () async {
      final puente = await unPuente();
      final c = await romiPor(puente);
      puente.retiene = esRespuesta;
      await expectLater(retiro(c), throwsA(isA<QuedaPorConfirmar>()));
      final pedido = (jsonDecode(puente.retenidos.single) as Map)['pedido'];
      puente.alTelefono(jsonEncode({'t': 'respuesta', 'pedido': pedido, 'ok': false, 'motivo': 'La caja ya se cerró'}));
      await hasta(() => c.noSeAnotaron.isNotEmpty, que: 'que lo avise');
      expect(c.noSeAnotaron.single, 'Un retiro o cambio de caja no se anotó: La caja ya se cerró');
      expect(c.porConfirmar, 0);
      expect(await c.barra.movimientosDeCaja(_fiesta), isEmpty);
      c.olvidarLoQueNoSeAnoto();
      expect(c.noSeAnotaron, isEmpty);
    });

    test('la respuesta trae la fila como quedó: si la venta ya la anuló la notebook, vale la de la notebook', () async {
      final puente = await unPuente();
      final c = await romiPor(puente);
      final venta = (await c.barra.ventas(_fiesta)).single;
      // La página todavía no se enteró de la anulación del jefe.
      puente.pierdeDeLaNotebook = (m) => m.contains('"t":"filas"');
      final delJefe = await notebook.anular(venta, motivo: 'la anuló el jefe', quien: 'Jefe');
      final a = await c.barra.anular(venta, motivo: 'otra cosa', quien: 'Romi', valeVolvio: false);
      expect(a.id, delJefe.id);
      expect(a.hechoPor, 'Jefe', reason: 'la del iPhone no pisa la de la notebook');
      expect(a.deviceId, 'notebook');
      expect(a.valeVolvio, isTrue);
      expect((await c.barra.anulaciones(_fiesta)).single.hechoPor, 'Jefe');
      expect(notebook.anulacionesGuardadas, hasLength(1));
    });
  });

  group('el PIN, de a uno por dirección', () {
    test('muchos PIN equivocados a la vez desde el iPhone: se prueban de a uno y a los cinco frena', () async {
      personas.demora = const Duration(milliseconds: 80);
      final todos = [for (var i = 0; i < 10; i++) iphone()];
      for (final c in todos) {
        await c.iniciar();
      }
      for (var i = 0; i < todos.length; i++) {
        todos[i].entrar('90${i.toString().padLeft(2, '0')}');
      }
      await hasta(() => todos.every((c) => c.estado == EstadoDeLaPagina.pidePin),
          que: 'que todos vuelvan a pedir el PIN', limite: const Duration(seconds: 10));
      expect(personas.pruebasDeLaPagina, kIntentosDeLaPagina, reason: 'los demás ni se probaron');
      expect(todos.where((c) => (c.problema ?? '').contains('Demasiados intentos')),
          hasLength(todos.length - kIntentosDeLaPagina));
      expect(todos.every((c) => c.quien == null), isTrue);
    });

    test('las tablets también: muchos PIN equivocados a la vez se prueban de a uno, y frena', () async {
      personas.demora = const Duration(milliseconds: 80);
      final malas = [
        for (var i = 0; i < 8; i++)
          ClienteDeLaCentral(
            credencial: () async => CredencialDeLaBarra.operador('op-marta', '0000'),
            eventoId: _fiesta,
            equipo: 'tablet-mala-$i',
            nombreCaja: 'Caja $i',
            barra: BarraEnMemoria()..equipo = 'tablet-mala-$i',
            aMano: DondeEstaLaCentral('127.0.0.1', puerto),
            latido: const Duration(milliseconds: 100),
            silencioMaximo: const Duration(seconds: 2),
            pausa: const Duration(milliseconds: 50),
          ),
      ];
      for (final m in malas) {
        aCerrar.add(ChangeNotifierLike(m.dispose));
        m.arrancar();
      }
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(personas.pruebasDeLaCaja, kIntentosDeLaPagina, reason: 'de a uno: los demás se cerraron sin probar');
      expect(malas.any((m) => m.conectada), isFalse);
      expect(notebook.cajasGuardadas, hasLength(1), reason: 'nada de lo que mandaron se guardó');
    });
  });

  group('la ficha deja de valer', () {
    test('SALIR: la ficha de esa noche ya no entra, ni copiada', () async {
      final navegador = _Navegador();
      final c = await entrar('7777', navegador: navegador);
      final antes = Map.of(navegador.datos);
      await c.salir();
      expect(c.estado, EstadoDeLaPagina.pidePin);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final otra = iphone(navegador: _Navegador()..datos.addAll(antes));
      await otra.iniciar();
      await hasta(() => otra.estado == EstadoDeLaPagina.pidePin, que: 'que pida el PIN');
      expect(otra.quien, isNull);
    });

    test('le sacan el permiso a mitad de la noche: al volver pide el PIN, lo dice, y lo por confirmar se avisa',
        () async {
      final navegador = _Navegador();
      final puente = await unPuente();
      final c = await romiPor(puente, navegador: navegador);
      puente.pierdeDelTelefono = (m) => m.contains('"t":"escribe"');
      final r = _Resultado(retiro(c));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      personas.persona('op-romi', 'Romi', pin: '7777', rol: RolEnLaBarra.cajera);
      puente.pierdeDelTelefono = (_) => false;
      await puente.cortar();
      await hasta(() => c.estado == EstadoDeLaPagina.pidePin, que: 'que pida el PIN');
      expect(r.error, isA<QuedaPorConfirmar>());
      expect(c.problema, contains('Ya no tenés permiso'));
      expect(c.quien, isNull);
      expect(navegador.datos.containsKey('barra_pagina_ficha'), isFalse, reason: 'la ficha se borró');
      expect(c.porConfirmar, 0, reason: 'no se reenvía con otro que entre');
      expect(c.noSeAnotaron.single, contains('te sacaron el permiso'));
      expect(notebook.movimientosDeCajaGuardados, isEmpty);
    });

    test('si falla leer la fiesta después del PIN bueno, no dice "PIN no reconocido": vuelve sola', () async {
      notebook.fallarAlLeer = 1;
      // Safari tarda en guardar la ficha: el corte llega mientras tanto.
      final c = iphone(navegador: _Navegador(demora: const Duration(milliseconds: 300)));
      await c.iniciar();
      c.entrar('7777');
      await hasta(() => c.conectada && c.evento != null, que: 'que entre sola con su ficha');
      expect(c.problema, isNull);
      expect(c.quien?.nombre, 'Romi');
      // Lo de la noche llega después del catálogo: se espera, no se da por llegado.
      final fin = DateTime.now().add(const Duration(seconds: 6));
      while ((await c.barra.ventas(_fiesta)).isEmpty) {
        if (DateTime.now().isAfter(fin)) fail('no llegaron las ventas de la noche');
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(await c.barra.ventas(_fiesta), hasLength(1));
    });
  });
}

/// Para cerrar en el tearDown lo que tiene `dispose`.
class ChangeNotifierLike {
  ChangeNotifierLike(this.dispose);
  final void Function() dispose;
}

/// Quién es quién, contando cuántos PIN se probaron (y tardando lo que se le diga, para
/// que muchos intentos a la vez se pisen si no van de a uno).
class _QuienQueCuenta extends QuienEsQuienEnMemoria {
  var pruebasDeLaPagina = 0;
  var pruebasDeLaCaja = 0;
  Duration demora = Duration.zero;

  @override
  Future<List<PersonaDeLaBarra>> paraLaPagina() async {
    pruebasDeLaPagina++;
    if (demora > Duration.zero) await Future<void>.delayed(demora);
    return super.paraLaPagina();
  }

  @override
  Future<PersonaDeLaBarra?> operador(String id) async {
    pruebasDeLaCaja++;
    if (demora > Duration.zero) await Future<void>.delayed(demora);
    return super.operador(id);
  }
}

/// La notebook, que puede fallar al leer la fiesta las veces que se le diga.
class _NotebookQuePuedeFallar extends BarraEnMemoria {
  var fallarAlLeer = 0;

  @override
  Future<Map<String, List<Map<String, Object?>>>> filasDeLaFiesta(String eventoId) async {
    if (fallarAlLeer > 0) {
      fallarAlLeer--;
      throw StateError('la base no contesta');
    }
    return super.filasDeLaFiesta(eventoId);
  }
}

/// **Un router de mentira entre el iPhone y la notebook**: pasa todo, salvo lo que se le
/// diga que pierda o retenga, y corta cuando se le pide. Así se prueba lo que pasa cuando
/// se bloquea el iPhone o se corta el wifi justo en el peor momento.
class _Puente {
  _Puente(this.haciaPuerto);
  final int haciaPuerto;
  late HttpServer _servidor;
  int get puerto => _servidor.port;

  bool Function(String deLaNotebook) pierdeDeLaNotebook = (_) => false;
  bool Function(String delTelefono) pierdeDelTelefono = (_) => false;
  bool Function(String deLaNotebook) retiene = (_) => false;
  final retenidos = <String>[];
  final _pares = <(WebSocket, WebSocket)>[];

  Future<void> abrir() async {
    _servidor = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _servidor.listen((pedido) async {
      final telefono = await WebSocketTransformer.upgrade(pedido);
      final WebSocket notebook;
      try {
        notebook = await WebSocket.connect('ws://127.0.0.1:$haciaPuerto${pedido.uri}');
      } catch (_) {
        await telefono.close();
        return;
      }
      _pares.add((telefono, notebook));
      notebook.listen(
        (m) {
          if (m is String && pierdeDeLaNotebook(m)) return;
          if (m is String && retiene(m)) {
            retenidos.add(m);
            return;
          }
          telefono.add(m);
        },
        onDone: () => telefono.close(_codigo(notebook.closeCode), notebook.closeReason),
      );
      telefono.listen(
        (m) {
          if (m is String && pierdeDelTelefono(m)) return;
          notebook.add(m);
        },
        onDone: () => notebook.close(),
      );
    });
  }

  static int? _codigo(int? c) => c == null || c == 1005 || c == 1006 ? null : c;

  /// Le manda al teléfono [mensaje] como si viniera de la notebook.
  void alTelefono(String mensaje) {
    for (final (telefono, _) in _pares) {
      telefono.add(mensaje);
    }
  }

  /// Se corta el wifi: se cierran las conexiones de ahora (las que vengan después pasan).
  Future<void> cortar() async {
    final pares = [..._pares];
    _pares.clear();
    for (final (telefono, notebook) in pares) {
      await telefono.close();
      await notebook.close();
    }
  }

  Future<void> cerrar() async {
    await cortar();
    await _servidor.close(force: true);
  }
}

/// Lo que pasó con un futuro que se deja correr: el valor o el error, cuando llegue.
class _Resultado<T> {
  _Resultado(Future<T> f) {
    f.then((v) {
      valor = v;
      listo = true;
    }, onError: (Object e) {
      error = e;
      listo = true;
    });
  }
  T? valor;
  Object? error;
  var listo = false;
}
