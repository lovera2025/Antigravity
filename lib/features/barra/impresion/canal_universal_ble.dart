import 'dart:async';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

import 'canal_ble.dart';

/// El Bluetooth de verdad, con la misma API en Android y en Windows.
class CanalUniversalBle implements CanalBle {
  static const _esperaConectar = Duration(seconds: 15);

  @override
  Future<void> pedirPermisos() => UniversalBle.requestPermissions();

  @override
  Future<List<DispositivoBle>> emparejados() async {
    final lista = await UniversalBle.getSystemDevices();
    return [for (final d in lista) _dispositivo(d, emparejado: true)];
  }

  @override
  Stream<DispositivoBle> buscar() {
    late final StreamController<DispositivoBle> salida;
    StreamSubscription<BleDevice>? sub;
    salida = StreamController<DispositivoBle>(
      onListen: () {
        sub = UniversalBle.scanStream.listen(
          (d) => salida.add(_dispositivo(d)),
          onError: salida.addError,
        );
        UniversalBle.startScan().catchError(salida.addError);
      },
      onCancel: () async {
        await sub?.cancel();
        await dejarDeBuscar();
      },
    );
    return salida.stream;
  }

  @override
  Future<void> dejarDeBuscar() => UniversalBle.stopScan();

  @override
  Future<void> conectar(String id) =>
      UniversalBle.connect(id, timeout: _esperaConectar);

  @override
  Future<void> desconectar(String id) => UniversalBle.disconnect(id);

  @override
  Future<bool> estaConectado(String id) async =>
      await UniversalBle.getConnectionState(id) == BleConnectionState.connected;

  @override
  Future<List<CaracteristicaBle>> caracteristicas(String id) async {
    final servicios = await UniversalBle.discoverServices(id);
    return [
      for (final s in servicios)
        for (final c in s.characteristics)
          CaracteristicaBle(
            servicio: s.uuid,
            uuid: c.uuid,
            escribe: c.properties.contains(CharacteristicProperty.write),
            escribeSinRespuesta: c.properties.contains(
              CharacteristicProperty.writeWithoutResponse,
            ),
            avisa: c.properties.contains(CharacteristicProperty.notify),
            indica: c.properties.contains(CharacteristicProperty.indicate),
          ),
    ];
  }

  static const _esperaSuscribir = Duration(seconds: 3);

  @override
  Stream<Uint8List> escuchar(String id, CaracteristicaBle c) {
    late final StreamController<Uint8List> salida;
    StreamSubscription<Uint8List>? sub;
    salida = StreamController<Uint8List>(
      onListen: () async {
        sub = UniversalBle.characteristicValueStream(id, c.uuid).listen(
          salida.add,
          onError: salida.addError,
        );
        try {
          if (c.avisa) {
            await UniversalBle.subscribeNotifications(
              id,
              c.servicio,
              c.uuid,
              timeout: _esperaSuscribir,
            );
          } else {
            await UniversalBle.subscribeIndications(
              id,
              c.servicio,
              c.uuid,
              timeout: _esperaSuscribir,
            );
          }
        } catch (e) {
          if (!salida.isClosed) salida.addError(e);
        }
      },
      onCancel: () async {
        await sub?.cancel();
        try {
          await UniversalBle.unsubscribe(
            id,
            c.servicio,
            c.uuid,
            timeout: _esperaSuscribir,
          );
        } catch (_) {
          // Ya desconectada, o no llegó a suscribirse: no hay nada que soltar.
        }
      },
    );
    return salida.stream;
  }

  @override
  Future<int> pedirMtu(String id, int mtu) => UniversalBle.requestMtu(id, mtu);

  @override
  Future<void> escribir(String id, CaracteristicaBle c, Uint8List bytes) =>
      UniversalBle.write(
        id,
        c.servicio,
        c.uuid,
        bytes,
        withoutResponse: c.escribeSinRespuesta,
      );

  DispositivoBle _dispositivo(BleDevice d, {bool emparejado = false}) {
    final nombre = (d.name ?? d.rawName ?? '').trim();
    return DispositivoBle(
      id: d.deviceId,
      nombre: nombre.isEmpty ? 'Sin nombre' : nombre,
      emparejado: emparejado,
    );
  }
}
