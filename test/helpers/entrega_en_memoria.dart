// La entrega de entradas (`RetiroEntradasScreen`) sin base ni nube: los alumnos, sus
// pagos y las entregas en memoria, y "la otra PC" que cobra y avisa como el pulso.
// Lo usan `test/retiro_entradas_screen_test.dart` y la ventana de prueba
// `tool/entradas_prueba.dart`, puestos por los mismos providers que usa la app.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/core/services/sync_engine.dart';
import 'package:arguello_events/features/caja_sesiones/models/operador_caja.dart';
import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/common/providers/user_role_provider.dart';
import 'package:arguello_events/features/common/utils/subir_ya.dart';
import 'package:arguello_events/features/eventos/repositories/contratos_repository.dart';
import 'package:arguello_events/features/eventos/repositories/entradas_entregas_repository.dart';
import 'package:arguello_events/features/eventos/repositories/entradas_retiro_repository.dart';
import 'package:arguello_events/features/eventos/repositories/entregar_parte_de_la_app.dart';
import 'package:arguello_events/features/eventos/repositories/sorteos_mesas_repository.dart';
import 'package:arguello_events/features/eventos/services/entrega_por_partes.dart';
import 'package:arguello_events/features/eventos/services/entregar_parte.dart';
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/retiro_entradas.dart';
import 'package:arguello_events/main.dart' show supabaseProvider;
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/entradas_retiro.dart';
import 'package:arguello_events/models/entrega_entradas.dart';
import 'package:arguello_events/models/evento.dart';
import 'package:arguello_events/models/sorteo_mesas_registro.dart';

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

/// Los renglones de la entrega por partes (`entradas_entregas`), en memoria.
/// **Sin este reemplazo, la entrega iría a leer la base de la PC.** Se escribe
/// solo por [EntregarParte] (los [PuertosEnMemoria]): `agregar` no se usa.
class PartesEnMemoria extends EntradasEntregasRepository {
  PartesEnMemoria()
      : super(null, abrir: () => throw StateError('la prueba no abre la base'));

  final renglones = <EntregaEntradas>[];

  List<EntregaEntradas> de(String alumnoId) => [
        for (final r in renglones)
          if (r.contratoAlumnoId == alumnoId) r,
      ]..sort(EntregaEntradas.enOrden);

  @override
  Future<Map<String, List<EntregaEntradas>>> deContratos(List<String> ids) async =>
      EntregaEntradas.porAlumno([
        for (final r in renglones)
          if (ids.contains(r.contratoAlumnoId)) r,
      ]);

  @override
  Future<List<EntregaEntradas>> delEvento(String eventoId) async => [
        for (final r in renglones)
          if (r.eventoId == eventoId) r,
      ]..sort(EntregaEntradas.enOrden);

  @override
  Future<List<EntregaEntradas>> traerDeLaNube(String contratoAlumnoId) async =>
      de(contratoAlumnoId);
}

/// [EntregarParte] con lo de [EntregaEnMemoria]: los alumnos y sus pagos, las
/// filas de `entradas_retiro` y los renglones, todo en memoria. "La nube" es lo
/// mismo que tiene este equipo (no hay otro más nuevo), y sin conexión
/// ([EntregaEnMemoria.conexion]) no se la puede mirar.
class PuertosEnMemoria implements PuertosDeLaEntrega {
  PuertosEnMemoria(this.e, {bool Function(String tabla)? alSubir})
      : _alSubir = alSubir;

  final EntregaEnMemoria e;
  final bool Function(String tabla)? _alSubir;

  @override
  bool get hayInternet => e.conexion.currentStatus != AppConnectivity.offline;

  @override
  Future<LoDeLaNube> deLaNube(String contratoAlumnoId) async {
    if (!hayInternet) throw StateError('sin internet');
    if (e.nubeQueNoContesta > 0) {
      e.nubeQueNoContesta--;
      throw StateError('la nube no contesta');
    }
    return LoDeLaNube(
      retiro: e.entregas.filas[contratoAlumnoId],
      renglones: e.partes.de(contratoAlumnoId),
    );
  }

  @override
  Future<LoDeLaFiesta> leer(String eventoId) async => LoDeLaFiesta(
        alumnos: [
          for (final a in e.contratos.alumnos)
            if (a.eventoId == eventoId) a,
        ],
        retiros: Map.of(e.entregas.filas),
        renglones: List.of(e.partes.renglones),
      );

  @override
  Future<CuentaDelAlumno> cuentaDe(ContratoAlumno alumno) async => CuentaDelAlumno(
        pagos: [
          for (final p in e.contratos.pagos)
            if (p['contrato_alumno_id'] == alumno.id) p,
        ],
        moraCobradaHistorial: 0,
      );

  @override
  Future<void> guardar(List<EntregaEntradas> renglones, {EntradasRetiro? retiro}) async {
    for (final r in renglones) {
      if (e.partes.renglones.any((x) => x.id == r.id)) continue;
      e.partes.renglones.add(r);
    }
    if (retiro != null) {
      e.entregas.filas[retiro.contratoAlumnoId] = retiro;
      e.filasEscritas++;
    }
  }

  @override
  Future<bool> subir({
    required List<String> renglones,
    String? retiro,
    required DateTime desde,
  }) async {
    final alSubir = _alSubir;
    if (alSubir == null) return hayInternet;
    var subio = true;
    if (renglones.isNotEmpty) subio = alSubir(EntradasEntregasRepository.tabla) && subio;
    if (retiro != null) subio = alSubir('entradas_retiro') && subio;
    return subio;
  }

  @override
  Future<String?> equipo() async => 'equipo-de-prueba';

  @override
  DateTime ahora() => e.ahora();
}

/// El registro de sorteos, en memoria: vacío salvo lo que la prueba le ponga.
/// De acá sale lo que cada familia tenía al sorteo (`fotoDeLosLugaresProvider`):
/// **sin este reemplazo, la entrega y VENDER irían a leer la base de la PC.**
class SorteosEnMemoria extends SorteosMesasRepository {
  final registros = <SorteoMesasRegistro>[];

  @override
  Future<List<SorteoMesasRegistro>> delEvento(String eventoId) async =>
      [for (final r in registros) if (r.eventoId == eventoId) r];
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

  /// Los renglones de la entrega por partes (pulseras y generales).
  final partes = PartesEnMemoria();

  /// Cuántas veces se escribió una fila completa de `entradas_retiro`.
  int filasEscritas = 0;

  /// Cuántas de las próximas consultas a la nube no contestan, con internet
  /// (la nube caída, o la tablet recién reconectada).
  int nubeQueNoContesta = 0;

  /// La hora de la entrega: avanza un minuto cada vez que se pide, desde el
  /// 20-nov-2026 a las 10 (después de la entrega de GÓMEZ, del 7-nov).
  DateTime _hora = DateTime.utc(2026, 11, 20, 13);
  DateTime ahora() => _hora = _hora.add(const Duration(minutes: 1));

  /// Los renglones de [alumnoId], del más viejo al más nuevo.
  List<EntregaEntradas> renglonesDe(String alumnoId) => partes.de(alumnoId);

  /// Cómo está la entrega de [alumnoId], por parte.
  EstadoDeLaEntrega estadoDe(String alumnoId) {
    final a = contratos.alumnos.firstWhere((x) => x.id == alumnoId);
    return EstadoDeLaEntrega.deAlumno(
      a,
      retiro: entregas.filas[alumnoId],
      renglones: partes.de(alumnoId),
    );
  }

  /// Otro equipo le entregó [parte] a [alumnoId] a las [hora]: su renglón, con lo
  /// que le corresponde, y sin tocar la fila de `entradas_retiro`.
  EntregaEntradas entregadaEnOtroEquipo(
    String alumnoId,
    ParteEntrega parte,
    DateTime hora,
  ) {
    final a = contratos.alumnos.firstWhere((x) => x.id == alumnoId);
    final cuenta = RetiroEntradas.entradasDe(a);
    final r = EntregaEntradas.entrega(
      contratoAlumnoId: a.id,
      eventoId: a.eventoId,
      parte: parte,
      cantidad: parte == ParteEntrega.pulseras ? cuenta.vip : cuenta.generales,
      parentesco: ParentescoRetiro.madre,
      nombre: 'MADRE, UNA',
      escribioEnPlanilla: true,
      hechoPor: 'Sofi',
      deviceId: 'tablet-2',
      ahora: hora,
    );
    partes.renglones.add(r);
    return r;
  }

  /// El jefe anuló [parte] de [alumnoId] en otro equipo a las [hora], sin
  /// tocar la fila de `entradas_retiro` (no la tenía todavía).
  void anuladaEnOtroEquipo(
    String alumnoId,
    ParteEntrega parte,
    DateTime hora, {
    String motivo = 'eran de otro',
  }) {
    final a = contratos.alumnos.firstWhere((x) => x.id == alumnoId);
    final cuenta = RetiroEntradas.entradasDe(a);
    partes.renglones.add(EntregaEntradas.anulacion(
      contratoAlumnoId: a.id,
      eventoId: a.eventoId,
      parte: parte,
      cantidad: parte == ParteEntrega.pulseras ? cuenta.vip : cuenta.generales,
      motivo: motivo,
      hechoPor: 'Jefe',
      deviceId: 'pc-jefe',
      ahora: hora,
    ));
  }

  /// La entrega por partes en memoria. [alSubir] (la tabla que sube) dice si
  /// llegó a la nube; sin él, sube si hay conexión.
  List<Override> reemplazosDeLasPartes({bool Function(String tabla)? alSubir}) => [
        entradasEntregasRepositoryProvider.overrideWithValue(partes),
        entregarParteProvider.overrideWithValue(
          EntregarParte(PuertosEnMemoria(this, alSubir: alSubir)),
        ),
      ];

  /// El registro de sorteos de la fiesta: vacío (sin sorteo anotado, todo lo
  /// que se compra aparte va con descuento) salvo lo que la prueba agregue.
  final sorteos = SorteosEnMemoria();
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

  /// Un operador que entra con su PIN a Entradas (y Cobros si [cobros]; y con
  /// "Vende entradas" si [vende]).
  OperadorCaja operador({bool cobros = false, bool vende = false}) {
    final op = operadorDePrueba('a0000000-0000-4000-8000-000000000201', 'Carla', '4321');
    if (!operadores.operadores.lista.any((o) => o.id == op.id)) {
      operadores.operadores.lista.add(op);
    }
    operadores.permisos.poner(
      op.id,
      PermisosEfectivos(entradas: true, cobros: cobros, vendeEntradas: vende),
    );
    return op;
  }

  List<Override> reemplazos({bool? jefe}) => [
        ...operadores.reemplazos,
        supabaseProvider.overrideWithValue(supabase),
        contratosRepositoryProvider.overrideWithValue(contratos),
        entradasRetiroRepositoryProvider.overrideWithValue(entregas),
        // Sin estos dos la pantalla abre la base, y en `flutter test` se queda
        // esperando.
        ...reemplazosDeLasPartes(),
        sorteosMesasRepositoryProvider.overrideWithValue(sorteos),
        syncEngineProvider.overrideWithValue(motor),
        subidaInmediataProvider.overrideWithValue(SubidaDePrueba(motor)),
        userRoleProvider.overrideWith(
          (ref) async => const UserRoleState(isLoading: false),
        ),
        if (jefe != null) esRolJefeProvider.overrideWithValue(jefe),
      ];
}
