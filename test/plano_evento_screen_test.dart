// La pantalla del plano entera, con sus providers, sin base ni red.
//
// `plano_evento_cuerpo_test` prueba lo que se ve y se toca; las cuentas de cada
// guardado tienen sus propios tests. Acá se prueba lo que va en el medio y que
// hasta ahora no tenía ninguno: la pantalla que, al tocar GUARDAR, relee la
// nube, vuelve a hacer la cuenta sobre eso, guarda o frena, y lo dice.
//
// Se monta `PlanoEventoScreen` de verdad. En lugar de la base y la nube lleva
// reemplazos en memoria, puestos por los mismos providers que usa la app: así
// un test puede decir "la otra PC cambió el plano", "no hay conexión" o "no hay
// modo jefe", y mirar qué se guardó.
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
import 'package:arguello_events/features/eventos/repositories/entradas_retiro_repository.dart';
import 'package:arguello_events/features/eventos/repositories/sillas_reparto_repository.dart';
import 'package:arguello_events/features/eventos/repositories/sorteos_mesas_repository.dart';
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/plano/dibujo/pintor_plano.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/plano_evento_screen.dart';
import 'package:arguello_events/features/plano/repositories/mesas_movimientos_repository.dart';
import 'package:arguello_events/features/plano/repositories/planos_evento_repository.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/widgets/vista_plano.dart';
import 'package:arguello_events/main.dart' show supabaseProvider;
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/entradas_retiro.dart';
import 'package:arguello_events/models/evento.dart';
import 'package:arguello_events/models/movimiento_mesas.dart';
import 'package:arguello_events/models/plano_evento.dart';
import 'package:arguello_events/models/sillas_reparto.dart';
import 'package:arguello_events/models/sorteo_mesas_registro.dart';

const _eventoId = 'e0000000-0000-4000-8000-000000000001';
final _ahora = DateTime.utc(2026, 10, 7, 15);

ContratoAlumno _alumno(
  String id,
  String nombre, {
  int extras = 0,
  int sillas = 0,
  List<int> mesas = const [],
  String division = '5° A',
}) =>
    ContratoAlumno(
      id: id,
      eventoId: _eventoId,
      nombreAlumno: nombre,
      cantidadAcompanantes: 3,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      sillasExtraCantidad: sillas,
      sillasExtraPrecioTotal: 8000.0 * sillas,
      numeroMesa:
          mesas.isEmpty ? null : MesasExtraUtils.formatearAsignacionMesas(mesas),
      cursoDivision: division,
    );

/// Una escuela chica ya sorteada: dos familias con mesa y una sin.
List<ContratoAlumno> _sorteada() => [
      _alumno('gomez', 'GÓMEZ, SOFÍA', extras: 1, sillas: 3, mesas: [8, 9]),
      _alumno('sosa', 'SOSA, LUZ', mesas: [20], division: '5° B'),
      _alumno('vega', 'VEGA, ANA', extras: 1, division: '5° B'),
    ];

/// La misma escuela antes del sorteo: nadie tiene mesa.
List<ContratoAlumno> _sinSortear() => [
      _alumno('gomez', 'GÓMEZ, SOFÍA', extras: 1, sillas: 3),
      _alumno('sosa', 'SOSA, LUZ', division: '5° B'),
      _alumno('vega', 'VEGA, ANA', extras: 1, division: '5° B'),
    ];

ArmadoSalon _armado() => ArmarAMedida.armar(
      const OpcionesAMedida(playon: PlayonReal.costaSurubi, cantidad: 40),
    ).armado;

PlanoEvento _plano({ConfigPlano config = ConfigPlano.vacia}) =>
    PlanoEvento.nuevo(
      eventoId: _eventoId,
      armado: _armado(),
      estilo: EstiloPlano.arquitecto,
      modo: ModoSorteo.entera,
      ahora: _ahora,
    ).copyWith(config: config, ahora: _ahora);

// ── Los reemplazos ──────────────────────────────────────────────────────────

/// El plano de la fiesta, en esta PC y en la nube.
class _Planos extends PlanosEventoRepository {
  _Planos(super.supabase, {this.aca}) : nube = aca;

  /// El que tiene esta PC.
  PlanoEvento? aca;

  /// El que tiene la nube. Cambiarlo es "la otra PC lo tocó".
  PlanoEvento? nube;

  /// Sin red: la nube no contesta, y lo guardado no llega.
  bool sinRed = false;

  final guardados = <PlanoEvento>[];

  @override
  Future<PlanoEvento?> obtener(String eventoId) async => aca;

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

typedef _Asignacion = ({
  Map<String, String?> numeros,
  MovimientoMesas? movimiento,
  PlanoEvento? plano,
});

/// Las familias de la fiesta y sus mesas.
class _Contratos extends ContratosRepository {
  _Contratos(super.supabase, super.connectivity, this.alumnos, this._planos);

  List<ContratoAlumno> alumnos;
  final _Planos _planos;

  /// Cuántas familias tienen en la nube otra mesa que todavía no bajó. Null:
  /// no se pudo consultar.
  int? distintasEnLaOtraPc = 0;

  final asignaciones = <_Asignacion>[];
  final movimientos = <MovimientoMesas>[];

  @override
  Future<List<ContratoAlumno>> getByEvento(String eventoId) async =>
      List.of(alumnos);

  @override
  Future<int?> mesasDeOtraPcSinBajar(String eventoId) async =>
      distintasEnLaOtraPc;

  @override
  Future<void> asignarNumerosMesa(
    Map<String, String?> numeroPorContrato, {
    SorteoMesasRegistro? registro,
    MovimientoMesas? movimiento,
    PlanoEvento? plano,
  }) async {
    asignaciones.add(
      (numeros: numeroPorContrato, movimiento: movimiento, plano: plano),
    );
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
  final _Contratos _contratos;

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

class _Sorteos extends SorteosMesasRepository {
  @override
  Future<List<SorteoMesasRegistro>> delEvento(String eventoId) async =>
      const [];
}

class _Conexion extends ConnectivityService {
  AppConnectivity estado = AppConnectivity.online;

  @override
  AppConnectivity get currentStatus => estado;
}

/// Del motor, la pantalla solo escucha el aviso de "bajó algo de la otra PC".
class _Motor implements SyncEngine {
  final bajo = StreamController<Set<String>>.broadcast();

  @override
  Stream<Set<String>> get cambiosBajadosStream => bajo.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// Si lo guardado llegó a la nube.
class _Subida implements SubidaInmediata {
  bool sube = true;
  final pedidas = <String>[];

  @override
  Future<bool> subir({
    required String tabla,
    required String registroId,
    required DateTime desde,
  }) async {
    pedidas.add(tabla);
    return sube;
  }

  @override
  Future<bool> queda(Map<String, Iterable<String>> registros) async => !sube;
}

/// Todo lo que rodea a la pantalla en un test.
class _Mundo {
  _Mundo(SupabaseClient supabase, {PlanoEvento? plano, required List<ContratoAlumno> alumnos})
      : planos = _Planos(supabase, aca: plano),
        conexion = _Conexion() {
    contratos = _Contratos(supabase, conexion, alumnos, planos);
  }

  final _Planos planos;
  final _Conexion conexion;
  late final _Contratos contratos;
  final motor = _Motor();
  final subida = _Subida();

  /// El último plano guardado.
  PlanoEvento get guardado => planos.guardados.last;
}

final _evento = Evento(
  id: _eventoId,
  clienteId: 'c0000000-0000-4000-8000-000000000001',
  tipo: 'Recepción',
  fechaEvento: DateTime(2026, 12, 12),
  estado: EstadoEvento.confirmado,
  modalidad: 'masivo',
);

late SupabaseClient _supabase;

/// Deja pasar lo que la pantalla tiene pendiente (lecturas, guardados).
Future<void> _asentar(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Abre la pantalla del plano de la fiesta.
Future<_Mundo> _abrir(
  WidgetTester tester, {
  bool esJefe = true,
  bool conPlano = true,
  ConfigPlano config = ConfigPlano.vacia,
  List<ContratoAlumno>? alumnos,
  void Function(_Mundo mundo)? antes,
}) async {
  final mundo = _Mundo(
    _supabase,
    plano: conPlano ? _plano(config: config) : null,
    alumnos: alumnos ?? _sorteada(),
  );
  antes?.call(mundo);
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(mundo.motor.bajo.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        supabaseProvider.overrideWithValue(_supabase),
        connectivityServiceProvider.overrideWithValue(mundo.conexion),
        syncEngineProvider.overrideWithValue(mundo.motor),
        subidaInmediataProvider.overrideWithValue(mundo.subida),
        contratosRepositoryProvider.overrideWithValue(mundo.contratos),
        planosEventoRepositoryProvider.overrideWithValue(mundo.planos),
        mesasMovimientosRepositoryProvider
            .overrideWithValue(_Movimientos(mundo.contratos)),
        sillasRepartoRepositoryProvider.overrideWithValue(_Sillas()),
        entradasRetiroRepositoryProvider
            .overrideWithValue(_Entradas(_supabase)),
        sorteosMesasRepositoryProvider.overrideWithValue(_Sorteos()),
        esRolJefeProvider.overrideWithValue(esJefe),
        userRoleProvider.overrideWith(
          (ref) async => const UserRoleState(nombre: 'Prueba', isLoading: false),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(fontFamily: FuentesPlano.linea, useMaterial3: true),
        home: Navigator(
          // Una pantalla debajo, para poder probar que la del plano se cierra.
          onGenerateInitialRoutes: (navegador, _) => [
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('La fiesta')),
            ),
            MaterialPageRoute<void>(
              builder: (_) => PlanoEventoScreen(evento: _evento),
            ),
          ],
        ),
      ),
    ),
  );
  await _asentar(tester);
  expect(tester.takeException(), isNull);
  return mundo;
}

bool _prendido(WidgetTester tester, String clave) =>
    tester.widget<ButtonStyleButton>(find.byKey(Key(clave))).enabled;

VistaPlano _vista(WidgetTester tester) =>
    tester.widget<VistaPlano>(find.byType(VistaPlano));

/// Toca una mesa del plano, en su lugar de la pantalla.
Future<void> _tocarMesa(WidgetTester tester, int numero) async {
  final vista = _vista(tester);
  final caja = tester.getRect(find.byType(VistaPlano));
  final m = vista.armado.mesa(numero)!;
  final punto = EncuadrePlano.de(vista.armado.hoja(m.hoja)!.caja, caja.size)
      .aPantalla(Offset(m.x, m.y));
  await tester.tapAt(caja.topLeft + punto);
  await tester.pump();
}

Future<void> _tocar(WidgetTester tester, String clave) async {
  await tester.ensureVisible(find.byKey(Key(clave)));
  await tester.pump();
  await tester.tap(find.byKey(Key(clave)));
  await tester.pump();
}

/// Prende Personalizar y abre una de sus pestañas.
Future<void> _personalizar(WidgetTester tester, [String? pestana]) async {
  await _tocar(tester, 'personalizar');
  if (pestana != null) await _tocar(tester, 'pestana_$pestana');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // No se usa para nada: los reemplazos heredan de clases que lo piden.
    _supabase = SupabaseClient(
      'http://localhost:1',
      'anon-de-test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });

  group('abrir el plano', () {
    testWidgets('en modo jefe se ve el salón, con todo para cambiarlo',
        (tester) async {
      final mundo = await _abrir(tester);
      expect(find.text('Plano del salón'), findsOneWidget);
      expect(_vista(tester).armado.mesas.length, 40);
      expect(_prendido(tester, 'estilo_y_armado'), isTrue);
      expect(_prendido(tester, 'personalizar'), isTrue);
      expect(_prendido(tester, 'imprimir'), isTrue);
      expect(_prendido(tester, 'historial'), isTrue);
      expect(find.byKey(const Key('motivo_solo_jefe')), findsNothing);
      // Abrir no guarda nada.
      expect(mundo.planos.guardados, isEmpty);
      expect(mundo.contratos.asignaciones, isEmpty);
    });

    testWidgets('sin modo jefe se ve igual, y lo que cambia el salón queda '
        'apagado', (tester) async {
      final mundo = await _abrir(tester, esJefe: false);
      expect(_vista(tester).armado.mesas.length, 40);
      expect(_prendido(tester, 'estilo_y_armado'), isFalse);
      expect(_prendido(tester, 'personalizar'), isFalse);
      expect(_prendido(tester, 'imprimir'), isTrue);
      expect(_prendido(tester, 'historial'), isTrue);
      expect(
        find.text('Armar y personalizar el plano: solo en modo jefe.'),
        findsOneWidget,
      );
      // Tocar una mesa muestra de quién es, sin ofrecer cambios.
      await _tocarMesa(tester, 8);
      expect(find.byKey(const Key('accion_mover')), findsNothing);
      await tester.tap(find.byKey(const Key('personalizar')),
          warnIfMissed: false);
      await tester.pump();
      expect(find.byKey(const Key('franja_personalizar')), findsNothing);
      expect(mundo.planos.guardados, isEmpty);
      expect(mundo.contratos.asignaciones, isEmpty);
    });

    testWidgets('lee primero el plano de la nube: si la otra PC lo cambió, '
        'se ve el de ella', (tester) async {
      final mundo = await _abrir(
        tester,
        antes: (m) => m.planos.nube =
            _plano(config: const ConfigPlano(titulo: 'Promo 2026')),
      );
      expect(find.text('Promo 2026'), findsOneWidget);
      expect(mundo.planos.guardados, isEmpty);
    });

    testWidgets('sin conexión abre igual, con el plano de esta PC',
        (tester) async {
      final mundo = await _abrir(
        tester,
        config: const ConfigPlano(titulo: 'El de esta PC'),
        antes: (m) {
          m.planos.sinRed = true;
          m.conexion.estado = AppConnectivity.offline;
        },
      );
      expect(find.text('El de esta PC'), findsOneWidget);
      expect(_vista(tester).armado.mesas.length, 40);
      expect(mundo.planos.guardados, isEmpty);
    });
  });

  group('una fiesta sin plano', () {
    testWidgets('en modo jefe se abren solos los tres pasos, y LISTO lo guarda',
        (tester) async {
      final mundo = await _abrir(
        tester,
        conPlano: false,
        alumnos: _sinSortear(),
      );
      expect(find.byKey(const Key('listo')), findsOneWidget);
      await _tocar(tester, 'listo');
      await _asentar(tester);

      final plano = mundo.guardado;
      expect(plano.tieneIdFijo, isTrue);
      expect(plano.eventoId, _eventoId);
      expect(plano.armadoONull, isNotNull);
      expect(find.text('Plano guardado.'), findsOneWidget);
      // Y ya se ve.
      expect(find.byType(VistaPlano), findsOneWidget);
    });

    testWidgets('sin modo jefe no se ofrece armarlo: dice quién lo arma',
        (tester) async {
      final mundo = await _abrir(
        tester,
        esJefe: false,
        conPlano: false,
        alumnos: _sinSortear(),
      );
      expect(find.byKey(const Key('listo')), findsNothing);
      expect(find.text('Esta fiesta todavía no tiene plano'), findsOneWidget);
      expect(find.text('Lo arma el jefe: solo en modo jefe.'), findsOneWidget);
      expect(_prendido(tester, 'armar_plano'), isFalse);
      expect(mundo.planos.guardados, isEmpty);
    });
  });
}
