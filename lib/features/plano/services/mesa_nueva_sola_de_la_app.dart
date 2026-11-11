import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/local_database.dart';
import '../../../core/utils/ar_time.dart';
import '../../../core/utils/uuid_utils.dart';
import '../../../models/contrato_alumno.dart';
import '../../../models/plano_evento.dart';
import '../../../models/sorteo_mesas_registro.dart';
import '../../common/utils/subir_ya.dart';
import '../../eventos/repositories/contratos_repository.dart';
import '../../eventos/repositories/sorteos_mesas_repository.dart';
import '../../recepcion/services/puerta_al_dia.dart';
import '../repositories/planos_evento_repository.dart';
import 'mesa_nueva_sola.dart';

/// [MesaNuevaSola] con la base y la nube de verdad.
///
/// **Es el único lugar, fuera de las dos pantallas del salón, que guarda
/// números de mesa y el plano, y no pregunta por el modo jefe** (lo pidió el
/// usuario el 10-nov-2026; `test/solo_modo_jefe_test.dart` lo nombra). Por eso
/// no decide nada: todo lo que decide está en [MesaNuevaSola], y acá solo se
/// lee y se guarda por los mismos caminos del botón SORTEO
/// (`asignarNumerosMesa`, en una sola transacción, y la subida en el momento).
class _PuertosDeLaApp implements PuertosDeLaMesaNueva {
  final Ref _ref;

  _PuertosDeLaApp(this._ref);

  ContratosRepository get _contratos => _ref.read(contratosRepositoryProvider);
  PlanosEventoRepository get _planos =>
      _ref.read(planosEventoRepositoryProvider);

  @override
  Future<List<ContratoAlumno>> alumnos(String eventoId) =>
      _contratos.getByEvento(eventoId);

  @override
  Future<Map<String, List<Map<String, dynamic>>>> pagos(
    List<ContratoAlumno> alumnos,
  ) async {
    final r = <String, List<Map<String, dynamic>>>{};
    final filas = await _contratos.getPagosForContratoIds([
      for (final a in alumnos) a.id,
    ]);
    for (final p in filas) {
      final id = p['contrato_alumno_id'] as String?;
      if (id != null) r.putIfAbsent(id, () => []).add(p);
    }
    return r;
  }

  @override
  Future<List<SorteoMesasRegistro>> registros(String eventoId) =>
      _ref.read(sorteosMesasRepositoryProvider).delEvento(eventoId);

  @override
  Future<PlanoEvento?> planoDeEstaPc(String eventoId) =>
      _planos.obtener(eventoId);

  @override
  Future<int?> mesasDeOtraPcSinBajar(String eventoId) =>
      _contratos.mesasDeOtraPcSinBajar(eventoId);

  @override
  Future<PlanoEvento?> planoDeLaNube(String eventoId) =>
      _planos.traerDeLaNube(eventoId);

  @override
  Future<void> guardar({
    required Map<String, String> numeros,
    required SorteoMesasRegistro registro,
    PlanoEvento? plano,
  }) async {
    final desde = DateTime.now().toUtc();
    await _contratos.asignarNumerosMesa(
      numeros,
      registro: registro,
      plano: plano,
    );
    // Cuanto antes llega a la nube, antes lo ve la otra PC: es lo que achica
    // el momento en que dos PCs pueden darle el mismo número a dos familias.
    // Si no sube ahora, sube con la cola de siempre.
    try {
      await _ref.read(subidaInmediataProvider).subir(
            tabla: 'sorteos_mesas',
            registroId: registro.id,
            desde: desde,
          );
    } catch (e) {
      debugPrint('La mesa nueva quedó guardada; sube con la cola: $e');
    }
  }

  @override
  Future<void> puertaAlDia(String eventoId, Iterable<String> alumnos) =>
      _ref.read(puertaAlDiaProvider).trasLosAlumnos(eventoId, alumnos);

  @override
  DateTime ahora() => ArTime.nowUtc();

  @override
  String nuevoId() => UuidUtils.generate();
}

final mesaNuevaSolaProvider = Provider<MesaNuevaSola>(
  (ref) => MesaNuevaSola(_PuertosDeLaApp(ref)),
);

/// Mira un evento con [sola] y deja escrito lo que pasó. **En la web no hace
/// nada**: ahí no hay base en el equipo, y la mesa la da una PC cuando abre.
///
/// [agregaron]: las familias que acaban de agregar una mesa en Editar alumno
/// (`MesaNuevaSola.agregoUnaMesa`).
Future<ResultadoMesaNueva> mirarMesaNueva(
  MesaNuevaSola sola,
  String eventoId, {
  Set<String> agregaron = const {},
}) async {
  if (kIsWeb) return ResultadoMesaNueva.nada;
  final r = await sola.revisar(eventoId, agregaron: agregaron);
  if (r.estado == EstadoMesaNueva.dio ||
      r.estado == EstadoMesaNueva.fallo ||
      (agregaron.isNotEmpty && r.aviso != null)) {
    await VigiaDeLaMesaNueva.anotar(r);
  }
  return r;
}

/// Cuándo se mira si a alguien le toca una mesa sola, además de justo después
/// de cobrarle: **al abrir el programa** y **cuando baja algo de otra PC**. Es
/// para lo que se cobró sin internet, en otra PC o con una versión anterior, y
/// para arreglar una mesa que dos PCs le dieron a dos familias.
///
/// No tiene reloj propio (el sync en reposo, 6.3.3): se dispara con algo que
/// pasó, espera un rato y mira **primero la base de esta PC, sin pedirle nada a
/// la nube**. Casi siempre no hay nada que hacer y ahí termina.
///
/// La espera es distinta en cada PC (al azar entre 20 y 60 s): si las tres
/// abren a la misma hora, no miran todas en el mismo segundo.
class VigiaDeLaMesaNueva {
  final Ref _ref;
  final _azar = Random();
  Timer? _espera;
  bool _mirando = false;

  VigiaDeLaMesaNueva(this._ref);

  /// Las tablas que, si bajan, pueden haber dejado a alguien esperando mesa.
  static const tablas = {
    'pagos_contrato_alumno',
    'contratos_alumnos',
    'planos_evento',
    'sorteos_mesas',
  };

  /// Terminó la primera bajada del día.
  void alArrancar() => _programar();

  /// Bajó algo nuevo de la nube.
  void alBajar(Set<String> bajaron) {
    if (bajaron.any(tablas.contains)) _programar();
  }

  void _programar() {
    if (!kMesaNuevaSolaHabilitada || kIsWeb) return;
    _espera?.cancel();
    _espera = Timer(
      Duration(seconds: 20 + _azar.nextInt(41)),
      () => unawaited(revisarTodo()),
    );
  }

  /// Mira todas las fiestas con plano de esta PC. **Nunca lanza.**
  Future<List<ResultadoMesaNueva>> revisarTodo() async {
    if (_mirando) return const [];
    _mirando = true;
    final dieron = <ResultadoMesaNueva>[];
    try {
      final sola = _ref.read(mesaNuevaSolaProvider);
      final eventos =
          await _ref.read(planosEventoRepositoryProvider).eventosConPlano();
      for (final id in eventos) {
        final r = await mirarMesaNueva(sola, id);
        if (r.estado == EstadoMesaNueva.dio ||
            r.estado == EstadoMesaNueva.fallo) {
          dieron.add(r);
        }
      }
    } catch (e) {
      debugPrint('La mesa nueva sola: no se pudo mirar ($e)');
    } finally {
      _mirando = false;
    }
    return dieron;
  }

  void cerrar() => _espera?.cancel();

  static const archivo = 'mesa_nueva_sola.txt';

  /// Deja escrito, junto a la base, a quién se le dio una mesa sola y cuándo
  /// (como `revision_mora.txt`): si alguien pregunta de dónde salió la 102,
  /// está ahí, además de en el registro de sorteos.
  static Future<void> anotar(ResultadoMesaNueva r) async {
    final aviso = r.aviso;
    final texto = [
      ?aviso,
      if (r.error != null) 'Lo que falló: ${r.error}',
    ].join(' ');
    if (texto.isEmpty) return;
    try {
      final base = File(await LocalDatabase.dbPath);
      final destino =
          File('${base.parent.path}${Platform.pathSeparator}$archivo');
      final a = ArTime.nowAr();
      String dos(int n) => n.toString().padLeft(2, '0');
      await destino.writeAsString(
        '${dos(a.day)}/${dos(a.month)}/${a.year} '
        '${dos(a.hour)}:${dos(a.minute)} · $texto\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (e) {
      debugPrint('La mesa nueva sola: no se pudo anotar ($e)');
    }
  }
}

final vigiaDeLaMesaNuevaProvider = Provider<VigiaDeLaMesaNueva>((ref) {
  final vigia = VigiaDeLaMesaNueva(ref);
  ref.onDispose(vigia.cerrar);
  return vigia;
});
