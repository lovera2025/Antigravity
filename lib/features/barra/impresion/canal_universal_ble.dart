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
          ),
    ];
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
