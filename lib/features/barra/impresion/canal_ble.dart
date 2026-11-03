import 'dart:typed_data';

/// Un aparato que se encontró por Bluetooth.
class DispositivoBle {
  final String id;
  final String nombre;

  /// Ya emparejado en este equipo: no hace falta que esté anunciándose.
  final bool emparejado;

  const DispositivoBle({
    required this.id,
    required this.nombre,
    this.emparejado = false,
  });
}

/// Por dónde se le puede escribir a un aparato.
class CaracteristicaBle {
  final String servicio;
  final String uuid;
  final bool escribe;
  final bool escribeSinRespuesta;

  const CaracteristicaBle({
    required this.servicio,
    required this.uuid,
    this.escribe = false,
    this.escribeSinRespuesta = false,
  });
}

/// Lo que la impresora necesita del Bluetooth. Detrás de esta interfaz está el
/// paquete de verdad (`CanalUniversalBle`) y, en los tests, uno en memoria: así todo
/// lo que decide se prueba sin la impresora, y si el paquete no sirviera en algún
/// equipo se cambia acá sin tocar lo demás.
abstract interface class CanalBle {
  Future<void> pedirPermisos();

  /// Los que ya están emparejados en este equipo.
  Future<List<DispositivoBle>> emparejados();

  /// Los que se van encontrando. Corre hasta [dejarDeBuscar].
  Stream<DispositivoBle> buscar();
  Future<void> dejarDeBuscar();

  Future<void> conectar(String id);
  Future<void> desconectar(String id);
  Future<bool> estaConectado(String id);

  Future<List<CaracteristicaBle>> caracteristicas(String id);

  /// El tamaño que quedó negociado. Puede tirar: no todos los equipos dejan pedirlo.
  Future<int> pedirMtu(String id, int mtu);

  Future<void> escribir(String id, CaracteristicaBle c, Uint8List bytes);
}
