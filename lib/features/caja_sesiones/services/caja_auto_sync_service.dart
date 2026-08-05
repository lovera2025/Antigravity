import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/sync_engine.dart';
import '../providers/app_role_provider.dart';
import '../repositories/sesiones_caja_repository.dart';

class CajaAutoSyncService {
  final AppRoleState _role;
  final SesionesCajaRepository _sesiones;
  final SyncEngine _syncEngine;

  const CajaAutoSyncService(this._role, this._sesiones, this._syncEngine);

  Future<bool> _pullConReintentos() async {
    for (var intento = 0; intento < 3; intento++) {
      final ok = await _syncEngine.pullOperationalUpdates();
      if (ok) return true;
      final ocupado =
          _syncEngine.status == SyncStatus.syncing ||
          _syncEngine.status == SyncStatus.wakingUp ||
          _syncEngine.status == SyncStatus.probing;
      if (!ocupado) return false;
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
    return false;
  }

  Future<bool> refreshBeforePayment() => _pullConReintentos();

  /// Antes de abrir caja: sin datos frescos no hay forma de saber si el mismo
  /// operador la tiene abierta en otra PC. Devuelve `false` si no se pudo
  /// verificar — en ese caso **no se bloquea**, solo se informa.
  Future<bool> refreshBeforeOpen() => _pullConReintentos();

  /// Sube únicamente entradas de cola tocadas desde [startedAt].
  ///
  /// Caja auto-sincroniza todas sus mutaciones permitidas. El jefe solo lo
  /// hace para un cobro masivo mientras exista una caja operativa abierta.
  Future<void> afterMassiveMutation({
    required DateTime startedAt,
    required bool isPayment,
  }) async {
    if (_role.esCaja && _role.tieneSesionCaja) {
      await _sesiones.flushBestEffort(createdSince: startedAt);
      return;
    }
    if (!_role.esJefe || !isPayment) return;
    final abiertas = await _sesiones.sesionesAbiertas();
    if (abiertas.isEmpty) return;
    await _sesiones.flushBestEffort(createdSince: startedAt);
  }
}

final cajaAutoSyncServiceProvider = Provider<CajaAutoSyncService>((ref) {
  return CajaAutoSyncService(
    ref.watch(appRoleProvider),
    ref.watch(sesionesCajaRepositoryProvider),
    ref.watch(syncEngineProvider),
  );
});
