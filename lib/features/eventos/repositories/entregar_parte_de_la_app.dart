import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/local_database.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/instalacion_id.dart';
import '../../../core/utils/ar_time.dart';
import '../../../models/contrato_alumno.dart';
import '../../../models/entradas_retiro.dart';
import '../../../models/entrega_entradas.dart';
import '../../common/utils/subir_ya.dart';
import '../services/entregar_parte.dart';
import 'contratos_repository.dart';
import 'entradas_entregas_repository.dart';
import 'entradas_retiro_repository.dart';

/// [EntregarParte] con la base del equipo y la nube de verdad.
///
/// No decide nada: lee, guarda (los renglones y la fila de `entradas_retiro`,
/// en una sola transacción) y sube. **Es el único lugar que escribe
/// `entradas_entregas`** (`test/entregar_parte_test.dart` lo vigila).
class _PuertosDeLaApp implements PuertosDeLaEntrega {
  final Ref _ref;

  _PuertosDeLaApp(this._ref);

  ContratosRepository get _contratos => _ref.read(contratosRepositoryProvider);
  EntradasRetiroRepository get _retiros =>
      _ref.read(entradasRetiroRepositoryProvider);
  EntradasEntregasRepository get _entregas =>
      _ref.read(entradasEntregasRepositoryProvider);

  @override
  bool get hayInternet =>
      _ref.read(connectivityServiceProvider).currentStatus !=
      AppConnectivity.offline;

  @override
  Future<LoDeLaNube> deLaNube(String contratoAlumnoId) async {
    final retiro = await _retiros.traerDeLaNube(contratoAlumnoId);
    final renglones = await _entregas.traerDeLaNube(contratoAlumnoId);
    return LoDeLaNube(retiro: retiro, renglones: renglones);
  }

  @override
  Future<LoDeLaFiesta> leer(String eventoId) async {
    final alumnos = await _contratos.getByEvento(eventoId);
    final ids = [for (final a in alumnos) a.id];
    final retiros = await _retiros.obtenerPorContratoIds(ids);
    final porAlumno = await _entregas.deContratos(ids);
    return LoDeLaFiesta(
      alumnos: alumnos,
      retiros: retiros,
      renglones: [for (final l in porAlumno.values) ...l],
    );
  }

  @override
  Future<CuentaDelAlumno> cuentaDe(ContratoAlumno alumno) async {
    final pagos = await _contratos.getPagosForContratoIds([alumno.id]);
    final mora = await _contratos.sumMoraCobradaHistorialPorContratos([alumno.id]);
    return CuentaDelAlumno(
      pagos: pagos,
      moraCobradaHistorial: mora[alumno.id] ?? 0,
    );
  }

  @override
  Future<void> guardar(
    List<EntregaEntradas> renglones, {
    EntradasRetiro? retiro,
  }) async {
    final db = await LocalDatabase.instance;
    await db.transaction((txn) async {
      await _entregas.agregarEn(txn, renglones);
      if (retiro != null) await _retiros.guardarEn(txn, retiro);
    });
  }

  @override
  Future<bool> subir({
    required List<String> renglones,
    String? retiro,
    required DateTime desde,
  }) async {
    // Arriba ya, no en el próximo ciclo: mientras no sube, el otro equipo no la
    // ve y podría entregarle de nuevo a la misma familia.
    try {
      final subida = _ref.read(subidaInmediataProvider);
      if (renglones.isNotEmpty) {
        await subida.subir(
          tabla: EntradasEntregasRepository.tabla,
          registroId: renglones.last,
          desde: desde,
        );
      } else if (retiro != null) {
        await subida.subir(
          tabla: 'entradas_retiro',
          registroId: retiro,
          desde: desde,
        );
      }
      return !await subida.queda({
        EntradasEntregasRepository.tabla: renglones,
        if (retiro != null) 'entradas_retiro': [retiro],
      });
    } catch (e) {
      debugPrint('La entrega quedó guardada; sube con la cola: $e');
      return false;
    }
  }

  @override
  Future<String?> equipo() async {
    try {
      return await InstalacionId.inicializar();
    } catch (_) {
      return InstalacionId.valor;
    }
  }

  @override
  DateTime ahora() => ArTime.nowUtc();
}

/// El único camino para guardar una entrega por partes: la entrega de ENTRADAS
/// y el bloque GRATIS de VENDER lo usan.
final entregarParteProvider = Provider<EntregarParte>(
  (ref) => EntregarParte(_PuertosDeLaApp(ref)),
);
