import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/barra/impresion/canal_ble.dart';
import 'package:arguello_events/features/barra/impresion/impresora_bluetooth.dart';
import 'package:arguello_events/features/barra/impresion/tabla_850.dart';
import 'package:arguello_events/features/barra/impresion/ticket_esc_pos.dart';

class _BundleVacio extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => Future.error(StateError('no está: $key'));
}

/// Los tres caminos de escritura que trae la TP-POS58, más lo que no sirve para imprimir.
const _tpPos58 = [
  CaracteristicaBle(
    servicio: '00001800-0000-1000-8000-00805f9b34fb',
    uuid: '00002a00-0000-1000-8000-00805f9b34fb',
    escribe: true,
  ),
  CaracteristicaBle(
    servicio: '0000ff00-0000-1000-8000-00805f9b34fb',
    uuid: '0000ff02-0000-1000-8000-00805f9b34fb',
    escribeSinRespuesta: true,
  ),
  CaracteristicaBle(
    servicio: 'e7810a71-73ae-499d-8c15-faa9aef0c3f2',
    uuid: 'bef8d6c9-9c21-4c9e-b632-bd58c1009f9f',
    escribe: true,
  ),
  CaracteristicaBle(
    servicio: '49535343-fe7d-4ae5-8fa9-9fafd205e455',
    uuid: '49535343-8841-43f4-a8d4-ecbe34729bb3',
    escribe: true,
    escribeSinRespuesta: true,
  ),
  CaracteristicaBle(
    servicio: '49535343-fe7d-4ae5-8fa9-9fafd205e455',
    uuid: '49535343-1e4d-4bd9-ba61-23c647249616',
  ),
];

class _CanalEnMemoria implements CanalBle {
  List<CaracteristicaBle> lista = _tpPos58;
  int? mtu = 185;

  /// En qué escrituras se corta, contando desde 0 todas las que se intentaron.
  final cortarEn = <int>{};
  int _intentos = 0;

  /// Apagada: no se deja conectar.
  bool apagada = false;
  int conexiones = 0;
  final conectados = <String>[];
  final escrito = <Uint8List>[];

  @override
  Future<void> pedirPermisos() async {}
  @override
  Future<List<DispositivoBle>> emparejados() async => const [];
  @override
  Stream<DispositivoBle> buscar() => const Stream.empty();
  @override
  Future<void> dejarDeBuscar() async {}
  @override
  Future<void> conectar(String id) async {
    if (apagada) throw StateError('no contesta');
    conexiones++;
    conectados.add(id);
  }

  @override
  Future<void> desconectar(String id) async => conectados.remove(id);
  @override
  Future<bool> estaConectado(String id) async => conectados.contains(id);
  @override
  Future<List<CaracteristicaBle>> caracteristicas(String id) async => lista;
  @override
  Future<int> pedirMtu(String id, int m) async {
    final valor = mtu;
    if (valor == null) throw StateError('no deja pedirlo');
    return valor;
  }

  @override
  Future<void> escribir(String id, CaracteristicaBle c, Uint8List bytes) async {
    if (cortarEn.contains(_intentos++)) {
      conectados.remove(id);
      throw StateError('se cortó');
    }
    escrito.add(bytes);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('por dónde se le escribe', () {
    test('la TP-POS58: el UART de ISSC, que es el primero conocido', () {
      expect(
        elegirCaracteristica(_tpPos58)!.uuid,
        '49535343-8841-43f4-a8d4-ecbe34729bb3',
      );
    });

    test('otra impresora, con un servicio FF00', () {
      expect(
        elegirCaracteristica(_tpPos58.sublist(0, 3))!.uuid,
        '0000ff02-0000-1000-8000-00805f9b34fb',
      );
    });

    test('un modelo desconocido: la primera que escriba, sin tocar las del sistema', () {
      const rara = CaracteristicaBle(
        servicio: 'aaaaaaaa-0000-1000-8000-00805f9b34fb',
        uuid: 'bbbbbbbb-0000-1000-8000-00805f9b34fb',
        escribeSinRespuesta: true,
      );
      expect(elegirCaracteristica([_tpPos58.first, rara]), same(rara));
    });

    test('solo del sistema, o nada que escriba: no hay por dónde', () {
      expect(elegirCaracteristica([_tpPos58.first]), isNull);
      expect(elegirCaracteristica([_tpPos58.last]), isNull);
      expect(elegirCaracteristica(const []), isNull);
    });

    test('las mayúsculas del UUID no cambian nada', () {
      const mayus = CaracteristicaBle(
        servicio: '49535343-FE7D-4AE5-8FA9-9FAFD205E455',
        uuid: '49535343-8841-43F4-A8D4-ECBE34729BB3',
        escribe: true,
      );
      expect(elegirCaracteristica([_tpPos58[2], mayus]), same(mayus));
    });
  });

  group('los trozos', () {
    test('el tamaño sale del MTU, con piso y techo', () {
      expect(tamanoDeTrozo(null), 20);
      expect(tamanoDeTrozo(23), 20);
      expect(tamanoDeTrozo(10), 20);
      expect(tamanoDeTrozo(100), 97);
      expect(tamanoDeTrozo(512), 180);
    });

    test('parte en orden y no pierde ningún byte', () {
      final bytes = List<int>.generate(1000, (i) => i % 256);
      for (final tam in [20, 97, 180, 1000, 5000]) {
        final trozos = partirEnTrozos(bytes, tam);
        expect(trozos.expand((t) => t).toList(), bytes, reason: 'de a $tam');
        expect(trozos.every((t) => t.length <= tam), isTrue);
      }
      expect(partirEnTrozos(const [], 20), isEmpty);
    });
  });

  test('reconoce el nombre de una impresora', () {
    expect(pareceImpresora('TP-POS58'), isTrue);
    expect(pareceImpresora('Global PT-210'), isTrue);
    expect(pareceImpresora('GK-995W BT5.2-1'), isFalse);
    expect(pareceImpresora('Xinua-TB'), isFalse);
  });

  group('la impresora', () {
    late _CanalEnMemoria canal;
    late ImpresoraBluetooth impresora;

    setUp(() {
      canal = _CanalEnMemoria();
      impresora = ImpresoraBluetooth(canal, pausa: Duration.zero);
    });

    test('sin impresora elegida no toca el canal: lo dice', () async {
      expect(
        await impresora.imprimir([1, 2, 3]),
        ResultadoImpresion.sinImpresoraElegida,
      );
      expect(canal.escrito, isEmpty);
      expect(canal.conexiones, 0);
    });

    test('se conecta, elige por dónde y manda todo en trozos', () async {
      expect(await impresora.conectar('tp'), isTrue);
      expect(impresora.tamano, 180);
      final bytes = List<int>.generate(500, (i) => i % 256);
      expect(await impresora.imprimir(bytes), ResultadoImpresion.impreso);
      expect(canal.escrito.expand((t) => t).toList(), bytes);
      expect(canal.escrito, hasLength(3));
    });

    test('si no dejan pedir el MTU, se manda de a 20 igual', () async {
      canal.mtu = null;
      expect(await impresora.conectar('tp'), isTrue);
      expect(impresora.tamano, 20);
    });

    test('un aparato que no imprime no queda conectado', () async {
      canal.lista = [_tpPos58.first];
      expect(await impresora.conectar('auriculares'), isFalse);
      expect(canal.conectados, isEmpty);
      expect(impresora.conectadaA, isNull);
    });

    test('si se corta a la mitad, reconecta y manda el ticket entero una vez más', () async {
      await impresora.conectar('tp');
      canal.cortarEn.add(1);
      final bytes = List<int>.generate(500, (i) => i % 256);
      expect(await impresora.imprimir(bytes), ResultadoImpresion.impreso);
      expect(canal.conexiones, 2);
      // El primer trozo salió antes del corte; después, el ticket entero.
      expect(canal.escrito.skip(1).expand((t) => t).toList(), bytes);
    });

    test('si se vuelve a cortar lo dice, sin tirar, y el próximo ticket sale', () async {
      await impresora.conectar('tp');
      canal.cortarEn.addAll({1, 3});
      final bytes = List<int>.filled(500, 7);
      expect(await impresora.imprimir(bytes), ResultadoImpresion.fallo);
      canal
        ..cortarEn.clear()
        ..escrito.clear();
      expect(await impresora.imprimir(bytes), ResultadoImpresion.impreso);
      expect(canal.escrito.expand((t) => t).toList(), bytes);
    });

    test('si se desconectó entre un ticket y otro, se conecta sola antes', () async {
      await impresora.conectar('tp');
      canal.conectados.clear();
      expect(await impresora.imprimir([1, 2, 3]), ResultadoImpresion.impreso);
      expect(canal.conexiones, 2);
      expect(canal.escrito.expand((t) => t).toList(), [1, 2, 3]);
    });

    test('apagada: lo dice sin tirar y no escribe nada', () async {
      await impresora.conectar('tp');
      canal
        ..conectados.clear()
        ..apagada = true;
      expect(await impresora.imprimir([1, 2, 3]), ResultadoImpresion.noConectada);
      expect(canal.escrito, isEmpty);
      expect(await impresora.reconectar(), EstadoImpresora.noContesta);
      canal.apagada = false;
      expect(await impresora.imprimir([1, 2, 3]), ResultadoImpresion.impreso);
    });

    test('dos tickets a la vez no se mezclan', () async {
      await impresora.conectar('tp');
      final a = List<int>.filled(400, 1);
      final b = List<int>.filled(400, 2);
      await Future.wait([impresora.imprimir(a), impresora.imprimir(b)]);
      expect(canal.escrito.expand((t) => t).toList(), [...a, ...b]);
    });

    test('dos tickets a la vez con un corte en el primero tampoco', () async {
      await impresora.conectar('tp');
      canal.cortarEn.add(1);
      final a = List<int>.filled(400, 1);
      final b = List<int>.filled(400, 2);
      await Future.wait([impresora.imprimir(a), impresora.imprimir(b)]);
      expect(canal.escrito.skip(1).expand((t) => t).toList(), [...a, ...b]);
    });
  });

  group('la impresora de este equipo', () {
    late _CanalEnMemoria canal;
    const recordada = ImpresoraRecordada();

    ImpresoraBluetooth nueva() =>
        ImpresoraBluetooth(canal, pausa: Duration.zero, recordada: recordada);

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      canal = _CanalEnMemoria();
    });

    test('al conectarla queda guardada, con su nombre', () async {
      expect(await nueva().conectar('tp', nombre: 'TP-POS58'), isTrue);
      final guardada = await recordada.leer();
      expect(guardada?.id, 'tp');
      expect(guardada?.nombre, 'TP-POS58');
    });

    test('al volver a abrir, imprime sin elegirla de nuevo', () async {
      await nueva().conectar('tp', nombre: 'TP-POS58');
      canal.conectados.clear();
      final otra = nueva();
      expect((await otra.elegida())?.nombre, 'TP-POS58');
      expect(await otra.imprimir([9, 9]), ResultadoImpresion.impreso);
      expect(otra.conectadaA, 'tp');
    });

    test('reconectar sin nada elegido no toca el canal', () async {
      expect(await nueva().reconectar(), EstadoImpresora.sinElegir);
      expect(canal.conexiones, 0);
    });

    test('un aparato que no imprime no queda elegido', () async {
      canal.lista = [_tpPos58.first];
      expect(await nueva().conectar('auriculares', nombre: 'Auris'), isFalse);
      expect(await recordada.leer(), isNull);
    });

    test('olvidarla la saca del equipo y no imprime más', () async {
      final i = nueva();
      await i.conectar('tp', nombre: 'TP-POS58');
      await i.olvidar();
      expect(await recordada.leer(), isNull);
      expect(canal.conectados, isEmpty);
      expect(await i.imprimir([1]), ResultadoImpresion.sinImpresoraElegida);
      expect(
        await nueva().imprimir([1]),
        ResultadoImpresion.sinImpresoraElegida,
      );
      expect(canal.escrito, isEmpty);
    });

    test('elegir otra cambia la guardada y suelta la anterior', () async {
      final i = nueva();
      await i.conectar('tp', nombre: 'TP-POS58');
      await i.conectar('otra', nombre: 'PT-210');
      expect((await recordada.leer())?.id, 'otra');
      expect(canal.conectados, ['otra']);
    });

    test('reconectar sola no le borra el nombre', () async {
      await nueva().conectar('tp', nombre: 'TP-POS58');
      canal.conectados.clear();
      final otra = nueva();
      expect(await otra.reconectar(), EstadoImpresora.lista);
      expect((await recordada.leer())?.nombre, 'TP-POS58');
    });

    test('lo guardado roto es como no tener impresora', () async {
      SharedPreferences.setMockInitialValues({ImpresoraRecordada.claveId: ''});
      expect(await recordada.leer(), isNull);
      expect(await nueva().imprimir([1]), ResultadoImpresion.sinImpresoraElegida);
    });
  });

  group('el texto para el papel', () {
    test('con la tabla, los acentos quedan', () {
      expect(textoParaPapel('Café ñandú ¡Sí!', conAcentos: true), 'Café ñandú ¡Sí!');
    });

    test('sin tabla, se sacan', () {
      expect(textoParaPapel('Café ñandú ¡Sí! N°', conAcentos: false), 'Cafe nandu !Si! No');
    });

    test('lo que no se puede escribir no frena la venta', () {
      expect(textoParaPapel('Cerveza 🍺', conAcentos: true), 'Cerveza ?');
      expect(textoParaPapel('€ 10', conAcentos: false), '? 10');
      expect(textoParaPapel('€ 10 · Crème', conAcentos: true), '? 10 · Cr?me');
    });
  });

  group('la tabla 850, la que lee la TP-POS58', () {
    test('las letras del castellano van a su lugar de la 850', () {
      expect(tabla850.encode('áéíóúñ'), [0xA0, 0x82, 0xA1, 0xA2, 0xA3, 0xA4]);
      expect(tabla850.encode('ÁÉÍÓÚÑ'), [0xB5, 0x90, 0xD6, 0xE0, 0xE9, 0xA5]);
      expect(tabla850.encode('ü¿¡°'), [0x81, 0xA8, 0xAD, 0xF8]);
      expect(tabla850.encode(r'Caja 2 $ 1/2'), r'Caja 2 $ 1/2'.codeUnits);
    });

    test('lo que no está sale "?", sin tirar, y se lee de vuelta', () {
      expect(tabla850.encode('€'), [0x3F]);
      expect(tabla850.decode(tabla850.encode('¡Gracias! N° 17')), '¡Gracias! N° 17');
    });

    test('la letra suelta: entra o no entra', () {
      expect(entraEnLa850('ñ'), isTrue);
      expect(entraEnLa850('a'), isTrue);
      expect(entraEnLa850('è'), isFalse);
      expect(entraEnLa850('🍺'), isFalse);
    });
  });

  group('los renglones de un producto', () {
    test('lo que entra va en un renglón, con el importe al borde', () {
      final r = renglonesDe('2 x Cerveza lata', r'$ 7.000');
      expect(r, ['2 x Cerveza lata         \$ 7.000']);
      expect(r.single.length, letrasPorRenglon);
    });

    test('un nombre largo se parte por palabras y no pisa el importe', () {
      final r = renglonesDe(
        'Un nombre de producto muy largo que no entra',
        r'$ 123.000',
      );
      expect(r, [
        'Un nombre de producto  \$ 123.000',
        'muy largo que no entra',
      ]);
      expect(r.every((s) => s.length <= letrasPorRenglon), isTrue);
    });

    test('una palabra que no entra sola se corta', () {
      final r = renglonesDe('Supercalifragilisticoespialidoso', r'$ 1');
      expect(r.first, 'Supercalifragilisticoespiali \$ 1');
      expect(r.last, 'doso');
    });

    test('sin importe, el nombre usa el renglón entero', () {
      expect(renglonesDe('Efectivo', ''), ['Efectivo']);
      expect(renglonesDe('', ''), ['']);
    });

    test('en el ticket ningún renglón pasa las 32 letras', () async {
      final perfil = await CapabilityProfile.load();
      final s = bytesComoTexto(TicketEscPos(perfil).armar(const [
        RenglonTicket('1 x Champán Chandon Extra Brut del bueno', r'$ 45.000'),
      ]));
      expect(s, contains('1 x Champán Chandon     \$ 45.000'));
      expect(s, contains('Extra Brut del bueno'));
    });
  });

  group('los bytes del ticket', () {
    late CapabilityProfile perfil;
    setUpAll(() async => perfil = await CapabilityProfile.load());

    String armar(List<LineaTicket> l, {OpcionesEscPos? o, bool cortar = true}) =>
        bytesComoTexto(TicketEscPos(perfil, opciones: o ?? const OpcionesEscPos())
            .armar(l, cortar: cortar));

    test('empieza reiniciando la impresora y termina cortando', () {
      final s = armar(const [TextoTicket('hola')]);
      expect(s.startsWith('\x1B@'), isTrue);
      expect(s, contains('hola'));
      expect(s.endsWith('\x1DV\x00') || s.contains('\x1DV'), isTrue);
    });

    test('al final avanza lo justo y pide el corte, sin los 5 renglones en blanco del paquete', () {
      final bytes = TicketEscPos(perfil).armar(const [TextoTicket('hola')]);
      // ...el último renglón, un salto, avanzar 3 (ESC d 3) y cortar (GS V 0).
      expect(bytes.sublist(bytes.length - 7), [0x0A, 0x1B, 0x64, 3, 0x1D, 0x56, 0x30]);
      expect(bytes.sublist(bytes.length - 8, bytes.length - 7), isNot([0x0A]),
          reason: 'un solo salto después del texto');
      expect(OpcionesEscPos.deLaPrueba.avanceAlFinal, 3);
    });

    test('sin cortar, no corta: para encadenar papeles', () {
      expect(armar(const [TextoTicket('a')], cortar: false), isNot(contains('\x1DV')));
    });

    test('con acentos pide la tabla 850 y los manda en la 850', () {
      final bytes = TicketEscPos(perfil).armar(const [TextoTicket('Café')]);
      expect(bytesComoTexto(bytes), contains('\x1Bt\x02'));
      expect(bytesComoTexto(bytes), contains('Café'));
      final s = String.fromCharCodes(bytes);
      expect(s, contains('Caf\x82'), reason: 'la é de la 850, no la de Latin-1');
      expect(s, isNot(contains('Caf\xE9')));
    });

    test('sin acentos no pide tabla, y los saca', () {
      final s = armar(
        const [TextoTicket('Café')],
        o: const OpcionesEscPos(conAcentos: false),
      );
      expect(s, isNot(contains('\x1Bt')));
      expect(s, contains('Cafe'));
    });

    test('lo que usa la app es lo que dio el papel', () {
      expect(OpcionesEscPos.deLaPrueba.conAcentos, isTrue);
      expect(OpcionesEscPos.deLaPrueba.logo, LogoDelPapel.isotipo);
      expect(TicketEscPos(perfil).opciones, same(OpcionesEscPos.deLaPrueba));
    });

    test('el QR va nativo', () {
      expect(armar(const [QrTicket('je:barra:1')]), contains('\x1D(k'));
    });

    test('el ticket entero se arma, con un importe alineado a la derecha', () {
      final s = armar(ticketDePrueba());
      expect(s, contains('JUNIOR EVENTOS'));
      expect(s, contains(r'$ 16.000'));
      expect(s, contains('N° 0017'));
    });
  });

  group('el logo para el papel', () {
    Uint8List png(img.Image i) => Uint8List.fromList(img.encodePng(i));

    test('silueta: lo claro sobre transparente sale negro, y el resto blanco', () {
      final original = img.Image(width: 100, height: 100, numChannels: 4);
      img.fillRect(
        original,
        x1: 0, y1: 0, x2: 49, y2: 99,
        color: img.ColorRgba8(255, 255, 255, 255),
      );
      final s = LogoParaPapel.silueta(png(original), ancho: 40)!;
      expect(s.width, 40);
      expect(s.getPixel(5, 20).r, 0, reason: 'lo blanco opaco va en negro');
      expect(s.getPixel(35, 20).r, 255, reason: 'lo transparente queda papel');
    });

    test('umbral: lo oscuro sale negro, lo claro no', () {
      final original = img.Image(width: 100, height: 100);
      img.fill(original, color: img.ColorRgb8(255, 255, 255));
      img.fillRect(
        original,
        x1: 0, y1: 0, x2: 49, y2: 99,
        color: img.ColorRgb8(10, 10, 10),
      );
      final u = LogoParaPapel.umbral(png(original), ancho: 40)!;
      expect(u.getPixel(5, 20).r, 0);
      expect(u.getPixel(35, 20).r, 255);
    });

    test('una imagen rota no tira', () {
      expect(LogoParaPapel.silueta(Uint8List.fromList([1, 2, 3])), isNull);
      expect(LogoParaPapel.umbral(Uint8List.fromList([1, 2, 3])), isNull);
    });

    test('con logo, el ticket lleva la imagen', () async {
      final logo = img.Image(width: 40, height: 40);
      img.fill(logo, color: img.ColorRgb8(0, 0, 0));
      final armador = TicketEscPos(await CapabilityProfile.load());
      final sinLogo = armador.armar(const [TextoTicket('a')]);
      final conLogo = armador.armar([LogoTicket(logo), const TextoTicket('a')]);
      expect(conLogo.length, greaterThan(sinLogo.length + 100));
      expect(bytesComoTexto(conLogo), contains('\x1Dv0'), reason: 'raster');
    });

    test('los dos logos de la app se cargan y salen en blanco y negro', () async {
      for (final logo in LogoDelPapel.values) {
        final i = await logo.cargar(rootBundle);
        expect(i, isNotNull, reason: logo.asset);
        expect(i!.width, 240);
        final tonos = {for (final p in i) p.r.toInt()};
        expect(tonos.difference({0, 255}), isEmpty, reason: logo.asset);
        expect(tonos, contains(0), reason: '${logo.asset} no puede salir en blanco');
      }
    });

    test('un logo que no está deja el ticket sin logo, sin tirar', () async {
      expect(await LogoDelPapel.isotipo.cargar(_BundleVacio()), isNull);
    });
  });
}
