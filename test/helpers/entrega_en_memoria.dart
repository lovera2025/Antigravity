// La entrega de entradas (`RetiroEntradasScreen`) sin base ni nube: los alumnos, sus
// pagos y las entregas en memoria, y "la otra PC" que cobra y avisa como el pulso.
// Lo usan `test/retiro_entradas_screen_test.dart` y la ventana de prueba
// `tool/entradas_prueba.dart`, puestos por los mismos providers que usa la app.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/core/services/sync_engine.dart';
import 'package:arguello_events/features/caja_sesiones/models/operador_caja.dart';
import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/common/providers/user_role_provider.dart';
import 'package:arguello_events/features/common/utils/subir_ya.dart';
import 'package:arguello_events/features/eventos/repositories/contratos_repository.dart';
import 'package:arguello_events/features/eventos/repositories/entradas_retiro_repository.dart';
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/retiro_entradas.dart';
import 'package:arguello_events/main.dart' show supabaseProvider;
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/entradas_retiro.dart';
import 'package:arguello_events/models/evento.dart';

import 'barra_en_memoria.dart' show fiestaDePrueba;
import 'operadores_en_memoria.dart';
import 'puerta_en_memoria.dart' show ConexionApagada, MotorDePrueba;

const idFiestaEntrega = 'e0000000-0000-4000-8000-000000000001';

final Evento fiestaDeLaEntrega =
    fiestaDePrueba(idFiestaEntrega, 'PUERTO VIEJO', DateTime(2026, 12, 4));

/// Un alumno con la base de $300.000 en 9 cuotas pagas, [extras] mesas
/// adicionales de $70.000 en una cuota y lo que deba de eso ([saldo]).
ContratoAlumno alumnoDeLaEntrega({
  required String id,
  required String nombre,
  List<int> mesas = const [12],
  int extras = 0,
  double saldo = 0,
  String division = '5° A',
}) {
  final mesaExtra = 70000.0 * extras;
  return ContratoAlumno(
    id: id,
    eventoId: idFiestaEntrega,
    nombreAlumno: nombre,
    cantidadAcompanantes: 0,
    montoTotalPactado: 300000 + mesaExtra,
    saldoDeudor: saldo,
    totalCuotas: 9,
    cuotasPagadas: 9,
    mesaExtraPrecio: mesaExtra,
    mesaExtraCantidad: extras,
    mesaExtraCuotas: 1,
    mesaExtraCuotasPagadas: extras > 0 && saldo == 0 ? 1 : 0,
    numeroMesa: MesasExtraUtils.formatearAsignacionMesas(mesas),
    cursoDivision: division,
    createdAt: DateTime(2026, 2, 1),
  );
}

Map<String, dynamic> pagoDeLaEntrega(String alumnoId, double monto, String concepto) => {
      'contrato_alumno_id': alumnoId,
      'monto': monto,
      'monto_gross': monto,
      'concepto': concepto,
      'anulado': 0,
      'fecha_pago': '2026-08-10',
    };

/// Los alumnos y sus pagos, en memoria.
class ContratosDeLaEntrega extends ContratosRepository {
  ContratosDeLaEntrega(SupabaseClient supabase) : super(supabase, ConexionApagada());

  final alumnos = <ContratoAlumno>[];
  final pagos = <Map<String, dynamic>>[];

  @override
  Future<List<ContratoAlumno>> getByEvento(String eventoId) async =>
      [for (final a in alumnos) if (a.eventoId == eventoId) a];

  @override
  Future<List<Map<String, dynamic>>> getPagosForContratoIds(List<String> contratoIds) async =>
      [for (final p in pagos) if (contratoIds.contains(p['contrato_alumno_id'])) p];

  @override
  Future<Map<String, double>> sumMoraCobradaHistorialPorContratos(List<String> contratoIds) async =>
      const {};
}

/// Las entregas, en memoria. La nube no tiene nada más nuevo.
class EntregasEnMemoria extends EntradasRetiroRepository {
  EntregasEnMemoria(super.supabase);

  final filas = <String, EntradasRetiro>{};

  @override
  Future<Map<String, EntradasRetiro>> obtenerPorContratoIds(List<String> ids) async => {
        for (final id in ids)
          if (filas[id] != null) id: filas[id]!,
      };

  @override
  Future<void> guardar(EntradasRetiro retiro) async => filas[retiro.contratoAlumnoId] = retiro;

  @override
  Future<EntradasRetiro?> traerDeLaNube(String contratoAlumnoId) async => null;
}

/// Todo lo que se guarda "sube" al instante.
class SubidaDePrueba extends SubidaInmediata {
  SubidaDePrueba(super.motor);

  @override
  Future<bool> subir({
    required String tabla,
    required String registroId,
    required DateTime desde,
  }) async =>
      true;
}

/// La entrega de PUERTO VIEJO con tres familias:
/// - PÉREZ, JUAN debe su mesa adicional ($ 70.000);
/// - LÓPEZ, SOFÍA está al día y todavía no retiró;
/// - GÓMEZ, ANA ya retiró.
class EntregaEnMemoria {
  EntregaEnMemoria() {
    final perez = alumnoDeLaEntrega(
      id: idPerez,
      nombre: 'PÉREZ, JUAN',
      mesas: const [12, 13],
      extras: 1,
      saldo: 70000,
    );
    final lopez = alumnoDeLaEntrega(id: idLopez, nombre: 'LÓPEZ, SOFÍA', mesas: const [14]);
    final gomez = alumnoDeLaEntrega(id: idGomez, nombre: 'GÓMEZ, ANA', mesas: const [15]);
    contratos.alumnos.addAll([perez, lopez, gomez]);
    contratos.pagos.addAll([
      for (final a in [perez, lopez, gomez]) pagoDeLaEntrega(a.id, 300000, 'Cuota Base (9/9)'),
    ]);
    entregas.filas[idGomez] = RetiroEntradas.nuevaEntrega(
      alumno: gomez,
      entradas: RetiroEntradas.entradasDe(gomez),
      tramos: const [TramoTalonario(1001, 1007)],
      menores10: 0,
      parentesco: ParentescoRetiro.madre,
      nombre: 'Ana Gómez',
      quien: 'Jefe',
      ahora: DateTime.utc(2026, 11, 7, 18),
    );
  }

  static const idPerez = 'a0000000-0000-4000-8000-000000000101';
  static const idLopez = 'a0000000-0000-4000-8000-000000000102';
  static const idGomez = 'a0000000-0000-4000-8000-000000000103';

  /// Sin renovar la sesión sola: el reloj de la librería quedaría corriendo.
  final supabase = SupabaseClient('http://localhost:1', 'clave-de-prueba')..auth.stopAutoRefresh();
  late final contratos = ContratosDeLaEntrega(supabase);
  late final entregas = EntregasEnMemoria(supabase);
  final motor = MotorDePrueba();
  final operadores = OperadoresEnPrueba();

  /// La conexión de esta PC: `conexion.cambiar(AppConnectivity.offline)` la corta.
  ConexionFija get conexion => operadores.conexion;

  /// La otra PC cobra [monto] de la mesa adicional de [alumnoId]: el pago y la
  /// ficha cambian, y el aviso llega como el pulso.
  void cobrar(String alumnoId, double monto) {
    final i = contratos.alumnos.indexWhere((a) => a.id == alumnoId);
    final a = contratos.alumnos[i];
    final saldo = (a.saldoDeudor - monto).clamp(0, double.infinity).toDouble();
    contratos.alumnos[i] = a.copyWith(
      saldoDeudor: saldo,
      mesaExtraCuotasPagadas: saldo == 0 ? 1 : a.mesaExtraCuotasPagadas,
    );
    contratos.pagos.add(pagoDeLaEntrega(alumnoId, monto, 'Mesa Extra 1'));
    motor.bajo.add({'pagos_contrato_alumno', 'contratos_alumnos'});
  }

  /// Un operador que entra con su PIN a Entradas (y Cobros si [cobros]).
  OperadorCaja operador({bool cobros = false}) {
    final op = operadorDePrueba('a0000000-0000-4000-8000-000000000201', 'Carla', '4321');
    if (!operadores.operadores.lista.any((o) => o.id == op.id)) {
      operadores.operadores.lista.add(op);
    }
    operadores.permisos.poner(op.id, PermisosEfectivos(entradas: true, cobros: cobros));
    return op;
  }

  List<Override> reemplazos({bool? jefe}) => [
        ...operadores.reemplazos,
        supabaseProvider.overrideWithValue(supabase),
        contratosRepositoryProvider.overrideWithValue(contratos),
        entradasRetiroRepositoryProvider.overrideWithValue(entregas),
        syncEngineProvider.overrideWithValue(motor),
        subidaInmediataProvider.overrideWithValue(SubidaDePrueba(motor)),
        userRoleProvider.overrideWith(
          (ref) async => const UserRoleState(isLoading: false),
        ),
        if (jefe != null) esRolJefeProvider.overrideWithValue(jefe),
      ];
}
