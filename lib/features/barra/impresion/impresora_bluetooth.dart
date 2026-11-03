import 'dart:typed_data';

import 'canal_ble.dart';

/// Por dónde le escriben las impresoras térmicas, en orden de preferencia. Los tres
/// primeros son los que trae la TP-POS58.
const _preferidas = [
  // UART de ISSC/Microchip.
  '49535343-8841-43f4-a8d4-ecbe34729bb3',
  // El servicio FF00 de las impresoras chinas: FF02 es la escritura.
  '0000ff02-0000-1000-8000-00805f9b34fb',
  // El servicio E7810A71 de las térmicas portátiles.
  'bef8d6c9-9c21-4c9e-b632-bd58c1009f9f',
];

/// Los servicios que trae todo aparato Bluetooth y no son para imprimir: nombre,
/// batería, datos del fabricante.
const _deSistema = [
  '00001800-0000-1000-8000-00805f9b34fb',
  '00001801-0000-1000-8000-00805f9b34fb',
  '0000180a-0000-1000-8000-00805f9b34fb',
  '0000180f-0000-1000-8000-00805f9b34fb',
];

/// Por cuál característica se le manda el ticket: una conocida si está y, si no, la
/// primera de un servicio que no sea del sistema. Así anda con "lo que se detecte",
/// no solo con este modelo. Null si no hay por dónde escribirle.
CaracteristicaBle? elegirCaracteristica(Iterable<CaracteristicaBle> todas) {
  final utiles = [
    for (final c in todas)
      if ((c.escribe || c.escribeSinRespuesta) &&
          !_deSistema.contains(c.servicio.toLowerCase()))
        c,
  ];
  for (final uuid in _preferidas) {
    for (final c in utiles) {
      if (c.uuid.toLowerCase() == uuid) return c;
    }
  }
  return utiles.isEmpty ? null : utiles.first;
}

/// De a cuánto se manda, según lo negociado: tres bytes son del protocolo, y las
/// térmicas no aguantan trozos muy grandes. Sin saberlo, los 20 que anda siempre.
int tamanoDeTrozo(int? mtu) {
  if (mtu == null) return 20;
  final util = mtu - 3;
  if (util < 20) return 20;
  return util > 180 ? 180 : util;
}

/// Los bytes en trozos, en orden y sin perder ninguno.
List<Uint8List> partirEnTrozos(List<int> bytes, int tamano) {
  final datos = Uint8List.fromList(bytes);
  return [
    for (var i = 0; i < datos.length; i += tamano)
      Uint8List.sublistView(
        datos,
        i,
        i + tamano > datos.length ? datos.length : i + tamano,
      ),
  ];
}

/// Qué le pareció de impresora a este nombre, para ponerla primera en la lista.
bool pareceImpresora(String nombre) => RegExp(
      r'POS|PRINT|PT-?\d|MTP|RPP|TP-|TERMAL|THERMAL|58',
      caseSensitive: false,
    ).hasMatch(nombre);

enum ResultadoImpresion { impreso, noConectada, fallo }

/// La impresora de la barra: conectarse y mandarle bytes. Lo que dice el ticket lo
/// arma `TicketEscPos`; acá no se sabe qué se imprime.
class ImpresoraBluetooth {
  final CanalBle canal;

  /// Entre trozo y trozo: sin esto, a la impresora se le llena el búfer y pierde
  /// renglones sin avisar.
  final Duration pausa;

  String? _id;
  CaracteristicaBle? _caracteristica;
  int _tamano = tamanoDeTrozo(null);
  Future<void> _ultimo = Future<void>.value();

  ImpresoraBluetooth(
    this.canal, {
    this.pausa = const Duration(milliseconds: 20),
  });

  String? get conectadaA => _id;
  CaracteristicaBle? get caracteristica => _caracteristica;
  int get tamano => _tamano;

  /// Se conecta y busca por dónde escribirle. False si no tiene por dónde.
  Future<bool> conectar(String id) async {
    await canal.conectar(id);
    final elegida = elegirCaracteristica(await canal.caracteristicas(id));
    if (elegida == null) {
      await canal.desconectar(id);
      return false;
    }
    int? mtu;
    try {
      mtu = await canal.pedirMtu(id, 512);
    } catch (_) {
      // Windows lo negocia solo y puede no dejar pedirlo: se manda de a 20.
    }
    _id = id;
    _caracteristica = elegida;
    _tamano = tamanoDeTrozo(mtu);
    return true;
  }

  Future<void> desconectar() async {
    final id = _id;
    _id = null;
    _caracteristica = null;
    if (id != null) await canal.desconectar(id);
  }

  /// Manda [bytes] entero. **De a un ticket por vez:** dos a la vez saldrían
  /// mezclados en el papel. Nunca tira: dice cómo le fue.
  Future<ResultadoImpresion> imprimir(List<int> bytes) {
    final resultado = _ultimo.then((_) => _mandar(bytes));
    _ultimo = resultado.then<void>((_) {});
    return resultado;
  }

  Future<ResultadoImpresion> _mandar(List<int> bytes) async {
    final id = _id;
    final c = _caracteristica;
    if (id == null || c == null) return ResultadoImpresion.noConectada;
    try {
      for (final trozo in partirEnTrozos(bytes, _tamano)) {
        await canal.escribir(id, c, trozo);
        if (pausa > Duration.zero) await Future<void>.delayed(pausa);
      }
      return ResultadoImpresion.impreso;
    } catch (_) {
      return ResultadoImpresion.fallo;
    }
  }
}
