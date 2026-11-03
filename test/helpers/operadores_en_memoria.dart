// Los operadores, sus permisos y sus cajas, sin base ni red. Lo usan
// `test/operadores_screen_test.dart`, `test/entrada_operador_test.dart` y la ventana
// de prueba `tool/operadores_prueba.dart`, puestos por los mismos providers que usa
// la app.
import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/features/caja_sesiones/models/operador_caja.dart';
import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/models/sesion_caja.dart';
import 'package:arguello_events/features/caja_sesiones/repositories/operadores_caja_repository.dart';
import 'package:arguello_events/features/caja_sesiones/repositories/permisos_operador_repository.dart';
import 'package:arguello_events/features/caja_sesiones/repositories/sesiones_caja_repository.dart';
import 'package:arguello_events/features/caja_sesiones/services/caja_auto_sync_service.dart';

OperadorCaja operadorDePrueba(String id, String nombre, String pin) => OperadorCaja(
      id: id,
      nombre: nombre,
      pin: pin,
      activo: true,
      createdAt: DateTime.utc(2026, 5),
      updatedAt: DateTime.utc(2026, 5),
    );

class OperadoresEnMemoria implements OperadoresCajaRepository {
  final List<OperadorCaja> lista;
  final eliminados = <String>[];

  OperadoresEnMemoria(this.lista);

  @override
  Future<List<OperadorCaja>> listar({
    bool soloActivos = false,
    bool incluirModoJefe = false,
  }) async =>
      List.of(lista);

  @override
  Future<OperadorCaja?> findByPin(String pin) async {
    for (final o in lista) {
      if (o.pin == pin.trim()) return o;
    }
    return null;
  }

  @override
  Future<OperadorCaja> crear({required String nombre, required String pin}) async {
    final n = (lista.length + 1).toString().padLeft(12, '0');
    final op = operadorDePrueba('a0000000-0000-4000-8000-$n', nombre, pin);
    lista.add(op);
    return op;
  }

  @override
  Future<OperadorCaja> actualizar(OperadorCaja op) async {
    lista[lista.indexWhere((o) => o.id == op.id)] = op;
    return op;
  }

  @override
  Future<void> eliminar(String id) async {
    eliminados.add(id);
    lista.removeWhere((o) => o.id == id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Hace la misma cuenta que la base: si no cambió nada, no escribe.
class PermisosEnMemoria extends PermisosOperadorRepository {
  final filas = <String, PermisosOperador>{};
  final guardados = <String>[];

  void poner(String operadorId, PermisosEfectivos p) {
    filas[operadorId] = PermisosOperador.para(
      operadorId: operadorId,
      permisos: p,
      ahora: DateTime.utc(2026, 11, 3),
    );
  }

  @override
  Future<PermisosEfectivos> de(String operadorId) async =>
      PermisosEfectivos.de(filas[operadorId]);

  @override
  Future<Map<String, PermisosOperador>> todas() async => Map.of(filas);

  @override
  Future<List<CambioDePermiso>> guardar({
    required String operadorId,
    required PermisosEfectivos permisos,
    required String quien,
    DateTime? ahora,
  }) async {
    final cambios = CambioDePermiso.entre(
      operadorId: operadorId,
      antes: PermisosEfectivos.de(filas[operadorId]),
      despues: permisos,
      hechoPor: quien,
      ahora: DateTime.utc(2026, 11, 3),
    );
    if (cambios.isEmpty) return const [];
    guardados.add(quien);
    poner(operadorId, permisos);
    return cambios;
  }
}

class SesionesEnMemoria implements SesionesCajaRepository {
  final abiertas = <String, SesionCaja>{};

  @override
  Future<SesionCaja?> sesionAbiertaDeOperador(String operadorId) async =>
      abiertas[operadorId];

  @override
  Future<List<SesionCaja>> sesionesAbiertasDeOperador(String operadorId) async => [
        if (abiertas[operadorId] != null) abiertas[operadorId]!,
      ];

  @override
  Future<SesionCaja?> getById(String id) async {
    for (final s in abiertas.values) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  Future<SesionCaja> abrir({
    required String operadorId,
    required double cambioInicial,
    required String etiqueta,
    String? notaApertura,
    String? deviceId,
  }) async {
    final ahora = DateTime.utc(2026, 11, 3, 12);
    return abiertas[operadorId] = SesionCaja(
      id: 'b0000000-0000-4000-8000-${operadorId.substring(24)}',
      operadorId: operadorId,
      abiertaAt: ahora,
      cambioInicial: cambioInicial,
      etiqueta: etiqueta,
      deviceId: deviceId,
      createdAt: ahora,
      updatedAt: ahora,
    );
  }

  @override
  Future<List<SesionCaja>> cerrarSesionesVencidasDeOperador(
    String operadorId, {
    required String notaCierre,
  }) async =>
      const [];

  @override
  Future<List<SesionCaja>> cerrarSesionJefeVencida() async => const [];

  @override
  Future<List<SesionCaja>> consolidarSesionesDuplicadas(String operadorId) async =>
      const [];

  @override
  Future<void> heartbeat(String sesionId) async {}

  @override
  Future<void> flushBestEffort({DateTime? createdSince}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// La bajada de la nube: [alBajar] es lo que trae, y [bajadas] cuenta los pedidos.
class SubidaEnMemoria implements CajaAutoSyncService {
  void Function()? alBajar;
  var bajadas = 0;

  @override
  Future<bool> refreshBeforeOpen() async {
    bajadas++;
    alBajar?.call();
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ConexionFija extends ConnectivityService {
  AppConnectivity estado;

  ConexionFija([this.estado = AppConnectivity.online]);

  @override
  AppConnectivity get currentStatus => estado;
}

/// Todo junto, listo para un `ProviderScope`.
class OperadoresEnPrueba {
  final operadores = OperadoresEnMemoria([]);
  final permisos = PermisosEnMemoria();
  final sesiones = SesionesEnMemoria();
  final subida = SubidaEnMemoria();
  final conexion = ConexionFija();

  List<Override> get reemplazos => [
        operadoresCajaRepositoryProvider.overrideWithValue(operadores),
        permisosOperadorRepositoryProvider.overrideWithValue(permisos),
        sesionesCajaRepositoryProvider.overrideWithValue(sesiones),
        cajaAutoSyncServiceProvider.overrideWithValue(subida),
        connectivityServiceProvider.overrideWithValue(conexion),
      ];
}
