// La pantalla del plano de la fiesta (`PlanoEventoScreen`) montada de verdad,
// con la base y la nube reemplazadas por cosas en memoria, puestas por los
// mismos providers que usa la app. Es la misma idea que
// `test/plano_evento_screen_test.dart`, armada para que la usen otras pruebas:
// la de punta a punta del sorteo (tildar en el cartel, SORTEAR y mirar el
// plano) y la de la mesa adicional "a confirmar".
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/core/services/sync_engine.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/common/providers/user_role_provider.dart';
import 'package:arguello_events/features/common/utils/subir_ya.dart';
import 'package:arguello_events/features/eventos/repositories/contratos_repository.dart';
import 'package:arguello_events/features/eventos/repositories/entradas_entregas_repository.dart';
import 'package:arguello_events/features/eventos/repositories/entradas_retiro_repository.dart';
import 'package:arguello_events/features/eventos/repositories/sillas_reparto_repository.dart';
import 'package:arguello_events/features/eventos/repositories/sorteos_mesas_repository.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/plano_evento_screen.dart';
import 'package:arguello_events/features/plano/repositories/mesas_movimientos_repository.dart';
import 'package:arguello_events/features/plano/repositories/planos_evento_repository.dart';
import 'package:arguello_events/features/plano/repositories/predios_repository.dart';
import 'package:arguello_events/features/plano/widgets/vista_plano.dart';
import 'package:arguello_events/features/recepcion/services/puerta_al_dia.dart';
import 'package:arguello_events/main.dart' show supabaseProvider;
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/entradas_retiro.dart';
import 'package:arguello_events/models/entrega_entradas.dart';
import 'package:arguello_events/models/evento.dart';
import 'package:arguello_events/models/movimiento_mesas.dart';
import 'package:arguello_events/models/plano_evento.dart';
import 'package:arguello_events/models/predio.dart';
import 'package:arguello_events/models/sillas_reparto.dart';
import 'package:arguello_events/models/sorteo_mesas_registro.dart';

/// No se usa para nada: los reemplazos heredan de clases que lo piden.
SupabaseClient supabaseDePrueba() => SupabaseClient(
      'http://localhost:1',
      'anon-de-test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );

/// El plano de la fiesta, en esta PC y en la nube.
class PlanosEnMemoria extends PlanosEventoRepository {
  PlanosEnMemoria(super.supabase, {this.aca}) : nube = aca;

  PlanoEvento? aca;
  PlanoEvento? nube;
  bool sinRed = false;
  final guardados = <PlanoEvento>[];

  @override
  Future<PlanoEvento?> obtener(String eventoId) async => aca;

  @override
  Future<List<ConfigPlano>> configsDeLasFiestas() async => [
        if (aca != null) aca!.config,
      ];

  @override
  Future<void> guardar(PlanoEvento plano) async {
    guardados.add(plano);
    aca = plano;
    if (!sinRed) nube = plano;
  }

  @override
  Future<PlanoEvento?> traerDeLaNube(String eventoId) async {
    if (sinRed) throw Exception('sin red');
    if (nube != null) aca = nube;
    return nube;
  }
}

/// Las familias de la fiesta, sus mesas y sus pagos.
class ContratosDelPlano extends ContratosRepository {
  ContratosDelPlano(
    super.supabase,
    super.connectivity,
    this.alumnos,
    this._planos,
  );

  List<ContratoAlumno> alumnos;
  final PlanosEnMemoria _planos;

  /// Los pagos de cada familia, como están en la base de la PC.
  Map<String, List<Map<String, dynamic>>> pagos = {};

  final asignaciones = <Map<String, String?>>[];
  final movimientos = <MovimientoMesas>[];

  /// Lo que se guardó de cada contrato con [actualizarContrato] (el contrato
  /// entero, como quedó), y lo que se mandó cada vez.
  final actualizados = <ContratoAlumno>[];
  final mandado = <Map<String, dynamic>>[];

  /// Los contratos a los que se les rehízo la cuenta y las mesas adicionales
  /// (lo que hace Editar alumno después de guardar la ficha).
  final recalculados = <String>[];
  final reconciliados = <String>[];

  /// Guardar la ficha falla (para probar que se dice).
  bool fallaAlActualizar = false;

  /// Cuántas familias tienen en la nube otra mesa que todavía no bajó. Null:
  /// no se pudo consultar (sin conexión).
  int? deOtraPc = 0;

  @override
  Future<ContratoAlumno?> getContratoById(String id) async =>
      alumnos.where((a) => a.id == id).firstOrNull;

  @override
  Future<void> actualizarContrato(
    String id,
    Map<String, dynamic> updates,
  ) async {
    if (fallaAlActualizar) throw Exception('no se pudo guardar la ficha');
    mandado.add(updates);
    alumnos = [
      for (final a in alumnos)
        a.id == id ? ContratoAlumno.fromJson({...a.toJson(), ...updates}) : a,
    ];
    actualizados.add(alumnos.firstWhere((a) => a.id == id));
  }

  @override
  Future<void> recalcularProgresoContrato(
    String contratoId, {
    bool revisarNube = true,
  }) async =>
      recalculados.add(contratoId);

  @override
  Future<void> reconciliarMesasEstadoContrato(String contratoId) async =>
      reconciliados.add(contratoId);

  @override
  Future<List<ContratoAlumno>> getByEvento(String eventoId) async =>
      List.of(alumnos);

  @override
  Future<int?> mesasDeOtraPcSinBajar(String eventoId) async => deOtraPc;

  @override
  Future<List<Map<String, dynamic>>> getPagosForContratoIds(
    List<String> contratoIds,
  ) async =>
      [
        for (final id in contratoIds)
          for (final p in pagos[id] ?? const <Map<String, dynamic>>[])
            {...p, 'contrato_alumno_id': id},
      ];

  @override
  Future<void> asignarNumerosMesa(
    Map<String, String?> numeroPorContrato, {
    SorteoMesasRegistro? registro,
    MovimientoMesas? movimiento,
    PlanoEvento? plano,
  }) async {
    asignaciones.add(numeroPorContrato);
    alumnos = [
      for (final a in alumnos)
        numeroPorContrato.containsKey(a.id)
            ? a.copyWith(numeroMesa: numeroPorContrato[a.id] ?? '')
            : a,
    ];
    if (movimiento != null) movimientos.add(movimiento);
    if (plano != null) await _planos.guardar(plano);
  }
}

class _Movimientos extends MesasMovimientosRepository {
  _Movimientos(this._contratos);
  final ContratosDelPlano _contratos;

  @override
  Future<List<MovimientoMesas>> delEvento(String eventoId) async =>
      List.of(_contratos.movimientos);
}

class _Sillas extends SillasRepartoRepository {
  @override
  Future<Map<String, SillasReparto>> obtenerPorContratoIds(
    List<String> ids,
  ) async =>
      const {};
}

class _Entradas extends EntradasRetiroRepository {
  _Entradas(super.supabase);

  @override
  Future<Map<String, EntradasRetiro>> obtenerPorContratoIds(
    List<String> ids,
  ) async =>
      const {};
}

/// La entrega por partes: nadie retiró nada.
class _Partes extends EntradasEntregasRepository {
  _Partes() : super(null, abrir: () => throw StateError('la prueba no abre la base'));

  @override
  Future<Map<String, List<EntregaEntradas>>> deContratos(List<String> ids) async =>
      const {};
}

class _Sorteos extends SorteosMesasRepository {
  @override
  Future<List<SorteoMesasRegistro>> delEvento(String eventoId) async =>
      const [];
}

class ConexionDePrueba extends ConnectivityService {
  AppConnectivity estado = AppConnectivity.online;

  @override
  AppConnectivity get currentStatus => estado;
}

class _Motor implements SyncEngine {
  final bajo = StreamController<Set<String>>.broadcast();

  /// Si se puede bajar de la nube, y lo que la bajada deja en la base de
  /// esta PC (un pago que hizo recién la otra).
  bool hayNube = true;
  void Function()? alBajar;
  int bajadas = 0;

  @override
  Stream<Set<String>> get cambiosBajadosStream => bajo.stream;

  @override
  Future<bool> bajarParaLosLugares() async {
    if (!hayNube) return false;
    bajadas++;
    alBajar?.call();
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _Subida implements SubidaInmediata {
  @override
  Future<bool> subir({
    required String tabla,
    required String registroId,
    required DateTime desde,
  }) async =>
      true;

  @override
  Future<bool> queda(Map<String, Iterable<String>> registros) async => false;
}

class _Predios extends PrediosRepository {
  _Predios(super.supabase);

  @override
  Future<List<Predio>> todos() async => const [];

  @override
  Future<List<Predio>> traerDeLaNube() async => const [];
}

class _Puerta implements PuertaAlDia {
  final alDia = <String>[];

  @override
  Future<PuertaAlDiaResultado> trasElSalon(String eventoId) async {
    alDia.add(eventoId);
    return const PuertaAlDiaResultado(personas: 0, sacadas: 0, sinSorteo: false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// Todo lo que rodea a la pantalla del plano en una prueba.
class MundoDelPlano {
  MundoDelPlano(
    SupabaseClient supabase, {
    PlanoEvento? plano,
    required List<ContratoAlumno> alumnos,
  })  : planos = PlanosEnMemoria(supabase, aca: plano),
        conexion = ConexionDePrueba() {
    contratos = ContratosDelPlano(supabase, conexion, alumnos, planos);
  }

  final PlanosEnMemoria planos;
  final ConexionDePrueba conexion;
  late final ContratosDelPlano contratos;
  final _motor = _Motor();
  final puerta = _Puerta();

  /// Lo que devolvió la pantalla del plano al cerrarse (por ejemplo, a quién
  /// cobrarle), y si ya se cerró.
  Object? alCerrar;
  bool cerrada = false;

  /// Bajó algo de la otra PC: ya está en la base de esta.
  void bajo(Set<String> tablas) => _motor.bajo.add(tablas);

  /// Sin internet: ni la nube contesta ni se puede bajar nada.
  void sinInternet() {
    conexion.estado = AppConnectivity.offline;
    planos.sinRed = true;
    contratos.deOtraPc = null;
    _motor.hayNube = false;
  }

  /// La nube contesta por las mesas y el plano, pero bajar lo último falla.
  void sinBajada() => _motor.hayNube = false;

  /// Lo que deja en la base de esta PC la bajada de antes de guardar.
  set alBajar(void Function() f) => _motor.alBajar = f;

  int get bajadas => _motor.bajadas;
}

/// Deja pasar lo que la pantalla tiene pendiente: lecturas, guardados, y un
/// cartel que se abre o termina de cerrarse.
Future<void> asentar(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

/// Monta la pantalla del plano de [evento], con [plano] y [alumnos] en
/// memoria.
Future<MundoDelPlano> montarPlanoDeLaFiesta(
  WidgetTester tester, {
  required Evento evento,
  required PlanoEvento plano,
  required List<ContratoAlumno> alumnos,
  Map<String, List<Map<String, dynamic>>> pagos = const {},
  bool esJefe = true,
  Size tamanio = const Size(1400, 900),
}) async {
  final supabase = supabaseDePrueba();
  final mundo = MundoDelPlano(supabase, plano: plano, alumnos: alumnos);
  mundo.contratos.pagos = {...pagos};
  tester.view.physicalSize = tamanio;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(mundo._motor.bajo.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        supabaseProvider.overrideWithValue(supabase),
        connectivityServiceProvider.overrideWithValue(mundo.conexion),
        syncEngineProvider.overrideWithValue(mundo._motor),
        subidaInmediataProvider.overrideWithValue(_Subida()),
        puertaAlDiaProvider.overrideWithValue(mundo.puerta),
        contratosRepositoryProvider.overrideWithValue(mundo.contratos),
        planosEventoRepositoryProvider.overrideWithValue(mundo.planos),
        prediosRepositoryProvider.overrideWithValue(_Predios(supabase)),
        mesasMovimientosRepositoryProvider
            .overrideWithValue(_Movimientos(mundo.contratos)),
        sillasRepartoRepositoryProvider.overrideWithValue(_Sillas()),
        entradasRetiroRepositoryProvider
            .overrideWithValue(_Entradas(supabase)),
        // Sin este reemplazo el plano iría a leer la base de la PC: quién ya
        // retiró una parte de la entrega.
        entradasEntregasRepositoryProvider.overrideWithValue(_Partes()),
        sorteosMesasRepositoryProvider.overrideWithValue(_Sorteos()),
        esRolJefeProvider.overrideWithValue(esJefe),
        userRoleProvider.overrideWith(
          (ref) async => const UserRoleState(nombre: 'Prueba', isLoading: false),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: FuentesPlano.linea, useMaterial3: true),
        home: Navigator(
          // Una pantalla debajo: la del plano se puede cerrar y devolver algo.
          onGenerateInitialRoutes: (navegador, _) => [
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('La fiesta')),
            ),
            MaterialPageRoute<Object?>(
              builder: (_) => PlanoEventoScreen(evento: evento),
            )..popped.then((v) {
                mundo.alCerrar = v;
                mundo.cerrada = true;
              }),
          ],
        ),
      ),
    ),
  );
  await asentar(tester);
  expect(tester.takeException(), isNull);
  return mundo;
}

/// Lo que se dibuja en el plano: quién está en cada mesa (mesa → ids).
Map<int, List<String>> ocupantesDibujados(WidgetTester tester) {
  final vista = tester.widget<VistaPlano>(find.byType(VistaPlano));
  return {
    for (final m in vista.armado.mesas)
      m.numero: [
        for (final o in vista.estado.info(m.numero).ocupantes) o.id,
      ],
  };
}
