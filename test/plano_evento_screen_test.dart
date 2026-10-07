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

ArmadoSalon _armado({int mesas = 40}) => ArmarAMedida.armar(
      OpcionesAMedida(playon: PlayonReal.costaSurubi, cantidad: mesas),
    ).armado;

PlanoEvento _plano({ConfigPlano config = ConfigPlano.vacia, int mesas = 40}) =>
    PlanoEvento.nuevo(
      eventoId: _eventoId,
      armado: _armado(mesas: mesas),
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

  /// Para frenar un guardado por la mitad y mirar la pantalla mientras tanto.
  Completer<void>? freno;

  /// La base no deja guardar.
  bool falla = false;

  @override
  Future<PlanoEvento?> obtener(String eventoId) async => aca;

  @override
  Future<void> guardar(PlanoEvento plano) async {
    await freno?.future;
    if (falla) throw Exception('SqliteException(5): database is locked');
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

  /// Cuántas veces se leyeron las familias: cada recarga de la pantalla las
  /// lee una vez.
  int lecturas = 0;

  @override
  Future<List<ContratoAlumno>> getByEvento(String eventoId) async {
    lecturas++;
    return List.of(alumnos);
  }

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

/// Deja pasar lo que la pantalla tiene pendiente: lecturas, guardados, y un
/// cartel que se abre o termina de cerrarse.
Future<void> _asentar(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 30));
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

/// Toca GUARDAR (u otro botón) y espera a que la pantalla termine.
Future<void> _guardar(WidgetTester tester, String clave) async {
  await _tocar(tester, clave);
  await _asentar(tester);
}

/// Toca un botón del cartel de arriba, por su texto.
Future<void> _contestar(WidgetTester tester, String texto) async {
  await tester.tap(find.text(texto).last);
  await _asentar(tester);
}

/// Lo último que dijo la pantalla: el aviso al lado de los botones del pie.
String _dicho(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const Key('aviso_del_pie_texto')))
    .data!;

/// La flecha de volver, y lo que tarda la pantalla en irse.
Future<void> _volver(WidgetTester tester) async {
  await tester.pageBack();
  await _asentar(tester);
  await tester.pump(const Duration(milliseconds: 500));
}

bool _sigueAbierto(WidgetTester tester) =>
    find.byType(PlanoEventoScreen).evaluate().isNotEmpty;

/// El cartel que hay que cerrar: su título y su texto.
(String, String) _cartel(WidgetTester tester) {
  final cartel = tester.widget<AlertDialog>(find.byType(AlertDialog).last);
  return ((cartel.title! as Text).data!, (cartel.content! as Text).data!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Tocar un botón tapado (por un cartel, por el aviso de abajo) es un
    // error del test, no un aviso: si no, el caso pasaría sin haber tocado
    // nada.
    WidgetController.hitTestWarningShouldBeFatal = true;
    // No se usa para nada: los reemplazos heredan de clases que lo piden.
    _supabase = SupabaseClient(
      'http://localhost:1',
      'anon-de-test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });

  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

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

  // Los tres guardados de Personalizar pasan por el mismo camino: releer la
  // nube y las familias, volver a hacer la cuenta sobre eso, y recién ahí
  // guardar. Si lo que hay ya no es lo que se veía, no se guarda.
  group('Personalizar: Medidas', () {
    Future<_Mundo> corregir(WidgetTester tester) async {
      final mundo = await _abrir(tester);
      await _personalizar(tester, 'medidas');
      await tester.enterText(find.byKey(const Key('medida_lugar')), '2,4');
      await tester.pump();
      return mundo;
    }

    testWidgets('corregir y GUARDAR las guarda, y lo dice', (tester) async {
      final mundo = await corregir(tester);
      await _guardar(tester, 'guardar_medidas');
      expect(mundo.guardado.config.medidas.lugarMesaM, 2.4);
      // Solo cambia la medida: el salón y lo demás del plano quedan igual.
      expect(mundo.guardado.armado.mesas.length, 40);
      expect(mundo.planos.guardados, hasLength(1));
      expect(_dicho(tester), 'Medidas guardadas.');
      expect(mundo.subida.pedidas, ['planos_evento']);
      // Sigue en Medidas, con lo guardado a la vista.
      expect(find.byKey(const Key('panel_medidas')), findsOneWidget);
      expect(_vista(tester).lugares!.lugarMesaM, 2.4);
    });

    testWidgets('si la otra PC las cambió mientras se corregían, no se guarda',
        (tester) async {
      final mundo = await corregir(tester);
      mundo.planos.nube = _plano(
        config: const ConfigPlano(medidas: MedidasPlano(lugarMesaM: 2.2)),
      );
      await _guardar(tester, 'guardar_medidas');
      expect(mundo.planos.guardados, isEmpty);
      expect(_cartel(tester).$1, 'No se puede');
      await _contestar(tester, 'ENTENDIDO');
      // Quedan a la vista las de la otra PC.
      expect(_vista(tester).lugares!.lugarMesaM, 2.2);
    });
  });

  group('Personalizar: Colores y textos', () {
    Future<_Mundo> elegir(WidgetTester tester) async {
      final mundo = await _abrir(tester);
      await _personalizar(tester, 'colores');
      await _tocar(tester, 'color_5A_5');
      await tester.enterText(
        find.byKey(const Key('texto_titulo')),
        'Promo 2026',
      );
      await tester.pump();
      return mundo;
    }

    testWidgets('elegir un color y un título y GUARDAR los guarda',
        (tester) async {
      final mundo = await elegir(tester);
      await _guardar(tester, 'guardar_colores');
      expect(mundo.guardado.config.colores, {'5A': 5});
      expect(mundo.guardado.config.titulo, 'Promo 2026');
      expect(mundo.planos.guardados, hasLength(1));
      expect(_dicho(tester), 'Colores y textos guardados.');
      expect(find.byKey(const Key('panel_colores')), findsOneWidget);
    });

    testWidgets('si la otra PC cambió los colores mientras tanto, no se guarda',
        (tester) async {
      final mundo = await elegir(tester);
      mundo.planos.nube = _plano(
        config: const ConfigPlano(colores: {'5B': 2}),
      );
      await _guardar(tester, 'guardar_colores');
      expect(mundo.planos.guardados, isEmpty);
      expect(_cartel(tester).$1, 'No se puede');
      await _contestar(tester, 'ENTENDIDO');
    });
  });

  group('Personalizar: Acomodar', () {
    Future<_Mundo> agregarUna(
      WidgetTester tester, {
      List<ContratoAlumno>? alumnos,
    }) async {
      final mundo = await _abrir(tester, alumnos: alumnos);
      await _personalizar(tester, 'acomodar');
      await _tocar(tester, 'acomodar_agregar');
      expect(_vista(tester).armado.existe(41), isTrue);
      return mundo;
    }

    testWidgets('agregar una mesa y GUARDAR guarda el salón nuevo',
        (tester) async {
      final mundo = await agregarUna(tester, alumnos: _sinSortear());
      await _guardar(tester, 'guardar_acomodo');
      expect(mundo.guardado.armado.mesas.length, 41);
      expect(mundo.planos.guardados, hasLength(1));
      expect(_dicho(tester), 'El salón quedó guardado.');
      // Las mesas no se tocan desde acá: solo el plano.
      expect(mundo.contratos.asignaciones, isEmpty);
    });

    testWidgets('con la escuela ya sorteada, dice cómo darle mesa al que falta',
        (tester) async {
      final mundo = await agregarUna(tester);
      await _guardar(tester, 'guardar_acomodo');
      expect(mundo.guardado.armado.mesas.length, 41);
      expect(
        _dicho(tester),
        'El salón quedó guardado. Para darle mesa a quien todavía no tiene, '
        'tocá SORTEO en la fiesta: los que ya tienen no se mueven.',
      );
    });

    testWidgets('si la otra PC acomodó el salón mientras tanto, no se guarda',
        (tester) async {
      final mundo = await agregarUna(tester);
      mundo.planos.nube = _plano(mesas: 42);
      await _guardar(tester, 'guardar_acomodo');
      expect(mundo.planos.guardados, isEmpty);
      expect(_cartel(tester).$1, 'No se puede');
      await _contestar(tester, 'ENTENDIDO');
    });

    testWidgets('si la otra PC sorteó mientras se acomodaba, no se guarda',
        (tester) async {
      final mundo = await agregarUna(tester, alumnos: _sinSortear());
      // Bajó el sorteo de la otra PC, y la pantalla todavía no lo mostró.
      mundo.contratos.alumnos = _sorteada();
      await _guardar(tester, 'guardar_acomodo');
      expect(mundo.planos.guardados, isEmpty);
      expect(_cartel(tester).$1, 'No se puede');
      await _contestar(tester, 'ENTENDIDO');
    });
  });

  group('antes de guardar', () {
    Future<_Mundo> conAlgoParaGuardar(WidgetTester tester) async {
      final mundo = await _abrir(tester);
      await _personalizar(tester, 'medidas');
      await tester.enterText(find.byKey(const Key('medida_lugar')), '2,4');
      await tester.pump();
      return mundo;
    }

    testWidgets('si la otra PC cambió mesas que todavía no bajaron, espera',
        (tester) async {
      final mundo = await conAlgoParaGuardar(tester);
      mundo.contratos.distintasEnLaOtraPc = 2;
      await _guardar(tester, 'guardar_medidas');
      expect(mundo.planos.guardados, isEmpty);
      expect(_cartel(tester), (
        'Todavía no',
        'La otra PC cambió mesas de 2 familias y todavía no llegaron acá. '
            'Esperá unos segundos y probá de nuevo.',
      ));
      await _contestar(tester, 'ENTENDIDO');

      // Cuando llegaron, se guarda.
      mundo.contratos.distintasEnLaOtraPc = 0;
      await _guardar(tester, 'guardar_medidas');
      expect(mundo.guardado.config.medidas.lugarMesaM, 2.4);
    });

    testWidgets('sin conexión pregunta: con CANCELAR no guarda, con SEGUIR sí',
        (tester) async {
      final mundo = await conAlgoParaGuardar(tester);
      mundo.planos.sinRed = true;
      mundo.conexion.estado = AppConnectivity.offline;
      mundo.contratos.distintasEnLaOtraPc = null;
      mundo.subida.sube = false;

      await _guardar(tester, 'guardar_medidas');
      expect(_cartel(tester).$1, 'Sin conexión');
      await _contestar(tester, 'CANCELAR');
      expect(mundo.planos.guardados, isEmpty);

      await _guardar(tester, 'guardar_medidas');
      expect(_cartel(tester).$1, 'Sin conexión');
      await _contestar(tester, 'SEGUIR');
      expect(mundo.guardado.config.medidas.lugarMesaM, 2.4);
      expect(
        _dicho(tester),
        'Medidas guardadas. Quedó en esta PC; sube cuando vuelva la conexión.',
      );
    });

    testWidgets('con conexión pero sin poder leer el plano de la nube, '
        'también pregunta', (tester) async {
      final mundo = await conAlgoParaGuardar(tester);
      mundo.planos.sinRed = true;
      await _guardar(tester, 'guardar_medidas');
      expect(_cartel(tester).$1, 'Sin conexión');
      await _contestar(tester, 'CANCELAR');
      expect(mundo.planos.guardados, isEmpty);
    });

    testWidgets('si guardó y no pudo subir, dice que quedó en esta PC',
        (tester) async {
      final mundo = await conAlgoParaGuardar(tester);
      mundo.subida.sube = false;
      await _guardar(tester, 'guardar_medidas');
      expect(mundo.planos.guardados, hasLength(1));
      expect(
        _dicho(tester),
        'Medidas guardadas. Quedó en esta PC; sube cuando vuelva la conexión.',
      );
    });
  });

  // Fijar y dejar libre cambian el plano; cambiar y mudar cambian los números
  // de mesa de las familias, con su renglón en el Historial.
  group('las mesas y las familias', () {
    testWidgets('dejar libre una mesa la guarda con su motivo', (tester) async {
      final mundo = await _abrir(tester, alumnos: _sinSortear());
      await _personalizar(tester);
      await _tocarMesa(tester, 30);
      await _guardar(tester, 'accion_dejar_libre');
      await tester.enterText(find.byKey(const Key('motivo')), 'Columna');
      await tester.pump();
      await _guardar(tester, 'confirmar');

      expect(mundo.guardado.config.libres.keys, [30]);
      expect(mundo.guardado.config.libres[30]!.motivo, 'Columna');
      expect(mundo.guardado.config.libres[30]!.por, isNotEmpty);
      expect(_dicho(tester), 'La mesa 30 quedó libre.');
      expect(mundo.contratos.asignaciones, isEmpty);
    });

    testWidgets('fijar una mesa para una familia la guarda con su motivo',
        (tester) async {
      final mundo = await _abrir(tester, alumnos: _sinSortear());
      await _personalizar(tester);
      await _tocarMesa(tester, 30);
      await _guardar(tester, 'accion_fijar_en_mesa');
      await _tocar(tester, 'familia_sosa');
      await tester.enterText(
        find.byKey(const Key('motivo')),
        'Cerca del ingreso',
      );
      await tester.pump();
      await _guardar(tester, 'confirmar');

      expect(mundo.guardado.config.fijadas.keys, [30]);
      expect(mundo.guardado.config.fijadas[30]!.alumnoId, 'sosa');
      expect(mundo.guardado.config.fijadas[30]!.motivo, 'Cerca del ingreso');
      expect(_dicho(tester), 'Quedó fijada la 30 para SOSA.');
    });

    /// SOSA, que está en la 20, pasa a la 30: hasta el cartel de confirmar.
    Future<_Mundo> mudarASosa(WidgetTester tester) async {
      final mundo = await _abrir(tester);
      await _personalizar(tester);
      await _tocarMesa(tester, 20);
      await _tocar(tester, 'accion_mover');
      await _tocarMesa(tester, 30);
      await _asentar(tester);
      await tester.enterText(
        find.byKey(const Key('motivo')),
        'Pedido de la familia',
      );
      await tester.pump();
      return mundo;
    }

    testWidgets('mudar una familia guarda los números y el renglón, juntos',
        (tester) async {
      final mundo = await mudarASosa(tester);
      await _guardar(tester, 'confirmar');

      final cambio = mundo.contratos.asignaciones.single;
      expect(cambio.numeros, {'sosa': '30'});
      expect(cambio.movimiento!.tipo, TipoMovimientoMesas.mover);
      expect(cambio.movimiento!.antes, {'sosa': '20'});
      expect(cambio.movimiento!.despues, {'sosa': '30'});
      expect(cambio.movimiento!.motivo, 'Pedido de la familia');
      expect(cambio.movimiento!.eventoId, _eventoId);
      expect(_dicho(tester), 'SOSA pasó a la 30.');
      expect(mundo.subida.pedidas, ['mesas_movimientos']);
    });

    testWidgets('DESHACER, recién hecho el cambio, lo vuelve atrás con otro '
        'renglón', (tester) async {
      final mundo = await mudarASosa(tester);
      await _guardar(tester, 'confirmar');
      final hecho = mundo.contratos.asignaciones.single.movimiento!;

      await _guardar(tester, 'aviso_del_pie_accion');
      expect(
        tester.widget<AlertDialog>(find.byType(AlertDialog)).title,
        isA<Text>().having((t) => t.data, 'título', 'Deshacer el cambio'),
      );
      // No pide el motivo de nuevo: queda el del cambio que se deshace.
      expect(find.byKey(const Key('motivo')), findsNothing);
      await _guardar(tester, 'confirmar');

      expect(mundo.contratos.asignaciones, hasLength(2));
      final vuelta = mundo.contratos.asignaciones.last;
      expect(vuelta.numeros, {'sosa': '20'});
      expect(vuelta.movimiento!.tipo, TipoMovimientoMesas.deshacer);
      expect(vuelta.movimiento!.deshaceId, hecho.id);
      expect(vuelta.movimiento!.motivo, 'Pedido de la familia');
      expect(_dicho(tester), 'El cambio se deshizo.');
    });

    testWidgets('desde el Historial también se deshace', (tester) async {
      final mundo = await mudarASosa(tester);
      await _guardar(tester, 'confirmar');
      final hecho = mundo.contratos.asignaciones.single.movimiento!;
      await _tocar(tester, 'salir_personalizar');

      // Con el aviso todavía a la vista: va al lado de los botones, no encima.
      expect(find.byKey(const Key('aviso_del_pie')), findsOneWidget);
      await _guardar(tester, 'historial');
      await _guardar(tester, 'deshacer_${hecho.id}');
      await _guardar(tester, 'confirmar');
      expect(mundo.contratos.asignaciones.last.numeros, {'sosa': '20'});
    });

    testWidgets('si las mesas de esa familia cambiaron mientras se confirmaba, '
        'no se guarda nada', (tester) async {
      final mundo = await mudarASosa(tester);
      // La otra PC la pasó a la 21, y ya bajó.
      mundo.contratos.alumnos = [
        for (final a in mundo.contratos.alumnos)
          a.id == 'sosa' ? a.copyWith(numeroMesa: '21') : a,
      ];
      await _guardar(tester, 'confirmar');
      expect(mundo.contratos.asignaciones, isEmpty);
      expect(_cartel(tester).$1, 'Las mesas cambiaron recién');
      await _contestar(tester, 'ENTENDIDO');
    });

    testWidgets('si la otra PC cambió mesas que todavía no bajaron, espera',
        (tester) async {
      final mundo = await mudarASosa(tester);
      mundo.contratos.distintasEnLaOtraPc = 1;
      await _guardar(tester, 'confirmar');
      expect(mundo.contratos.asignaciones, isEmpty);
      expect(_cartel(tester), (
        'Todavía no',
        'La otra PC cambió mesas de 1 familia y todavía no llegaron acá. '
            'Esperá unos segundos y probá de nuevo.',
      ));
      await _contestar(tester, 'ENTENDIDO');
    });

    testWidgets('sin conexión pregunta antes de mudar, y CANCELAR no guarda',
        (tester) async {
      final mundo = await mudarASosa(tester);
      mundo.contratos.distintasEnLaOtraPc = null;
      mundo.planos.sinRed = true;
      await _guardar(tester, 'confirmar');
      expect(_cartel(tester).$1, 'Sin conexión');
      await _contestar(tester, 'CANCELAR');
      expect(mundo.contratos.asignaciones, isEmpty);
    });

    testWidgets('sin modo jefe el Historial se lee, y no deja deshacer',
        (tester) async {
      final cambio = MovimientoMesas(
        id: 'm0000000-0000-4000-8000-000000000001',
        eventoId: _eventoId,
        tipo: TipoMovimientoMesas.mover,
        antes: const {'sosa': '12'},
        despues: const {'sosa': '20'},
        motivo: 'Pedido de la familia',
        hechoPor: 'Jefe',
        createdAt: _ahora,
      );
      final mundo = await _abrir(
        tester,
        esJefe: false,
        antes: (m) => m.contratos.movimientos.add(cambio),
      );
      await _guardar(tester, 'historial');
      expect(find.text('Historial de las mesas'), findsOneWidget);
      expect(find.text('Motivo: Pedido de la familia'), findsOneWidget);
      expect(find.byKey(Key('deshacer_${cambio.id}')), findsNothing);
      expect(
        find.text('Deshacer un cambio: solo en modo jefe.'),
        findsOneWidget,
      );
      await _contestar(tester, 'CERRAR');
      expect(mundo.contratos.asignaciones, isEmpty);
    });
  });

  group('la flecha de volver', () {
    testWidgets('sin nada pendiente, sale sin preguntar', (tester) async {
      await _abrir(tester);
      await _volver(tester);
      expect(_sigueAbierto(tester), isFalse);
      expect(find.text('La fiesta'), findsOneWidget);
    });

    testWidgets('con algo sin guardar pregunta: SEGUIR ACÁ no pierde nada, '
        'SALIR SIN GUARDAR sale', (tester) async {
      final mundo = await _abrir(tester);
      await _personalizar(tester, 'acomodar');
      await _tocar(tester, 'acomodar_agregar');

      await _volver(tester);
      expect(find.text('Hay cambios sin guardar'), findsOneWidget);
      await _guardar(tester, 'seguir_aca');
      expect(_sigueAbierto(tester), isTrue);
      // Lo acomodado sigue ahí.
      expect(find.byKey(const Key('panel_acomodar')), findsOneWidget);
      expect(_vista(tester).armado.existe(41), isTrue);

      await _volver(tester);
      await _guardar(tester, 'salir_sin_guardar');
      await tester.pump(const Duration(milliseconds: 500));
      expect(_sigueAbierto(tester), isFalse);
      expect(mundo.planos.guardados, isEmpty);
    });

    testWidgets('mientras se guarda no se sale', (tester) async {
      final mundo = await _abrir(tester);
      await _personalizar(tester, 'medidas');
      await tester.enterText(find.byKey(const Key('medida_lugar')), '2,4');
      await tester.pump();
      mundo.planos.freno = Completer<void>();
      await _guardar(tester, 'guardar_medidas');
      expect(mundo.planos.guardados, isEmpty);

      await _volver(tester);
      expect(_sigueAbierto(tester), isTrue);
      expect(find.byType(AlertDialog), findsNothing);

      mundo.planos.freno!.complete();
      await _asentar(tester);
      expect(mundo.planos.guardados, hasLength(1));
      expect(_dicho(tester), 'Medidas guardadas.');
    });
  });

  group('lo que baja de la otra PC', () {
    testWidgets('con la pantalla abierta, se actualiza sola', (tester) async {
      final mundo = await _abrir(tester);
      expect(find.text('Promo 2026'), findsNothing);
      final antes = mundo.contratos.lecturas;

      // Lo que la bajada dejó en la base de esta PC.
      mundo.planos.aca = _plano(config: const ConfigPlano(titulo: 'Promo 2026'));
      mundo.motor.bajo.add({'planos_evento'});
      await _asentar(tester);
      expect(find.text('Promo 2026'), findsOneWidget);
      expect(mundo.contratos.lecturas, antes + 1);
      expect(mundo.planos.guardados, isEmpty);
    });

    testWidgets('si baja algo que no es del salón, no recarga', (tester) async {
      final mundo = await _abrir(tester);
      final antes = mundo.contratos.lecturas;
      mundo.motor.bajo.add({'pagos_contrato_alumno', 'egresos'});
      await _asentar(tester);
      expect(mundo.contratos.lecturas, antes);
    });

    testWidgets('si baja mientras se guarda, se relee al terminar',
        (tester) async {
      final mundo = await _abrir(tester);
      await _personalizar(tester, 'medidas');
      await tester.enterText(find.byKey(const Key('medida_lugar')), '2,4');
      await tester.pump();
      mundo.planos.freno = Completer<void>();
      await _guardar(tester, 'guardar_medidas');

      // Guardando: lo que baja espera.
      final antes = mundo.contratos.lecturas;
      mundo.motor.bajo.add({'contratos_alumnos'});
      await _asentar(tester);
      expect(mundo.contratos.lecturas, antes);

      // Al terminar se lee dos veces: lo recién guardado, y lo que bajó.
      mundo.planos.freno!.complete();
      await _asentar(tester);
      expect(mundo.contratos.lecturas, antes + 2);
    });
  });

  // Lo que la pantalla dice después de un cambio va al lado de los botones del
  // pie. Antes iba en el aviso de abajo de siempre, que quedaba varios segundos
  // encima de ESTILO Y ARMADO, PERSONALIZAR, IMPRIMIR e HISTORIAL: tocarlos en
  // ese rato no hacía nada.
  group('el aviso de lo que pasó', () {
    Future<_Mundo> guardarMedidas(
      WidgetTester tester, {
      void Function(_Mundo mundo)? antes,
    }) async {
      final mundo = await _abrir(tester);
      await _personalizar(tester, 'medidas');
      await tester.enterText(find.byKey(const Key('medida_lugar')), '2,4');
      await tester.pump();
      antes?.call(mundo);
      await _guardar(tester, 'guardar_medidas');
      return mundo;
    }

    testWidgets('va al lado de los botones del pie, y no los tapa',
        (tester) async {
      await guardarMedidas(tester);
      expect(_dicho(tester), 'Medidas guardadas.');
      expect(find.byType(SnackBar), findsNothing);
      // Está en el mismo renglón que los botones, a su derecha.
      final aviso = tester.getRect(find.byKey(const Key('aviso_del_pie')));
      final historial = tester.getRect(find.byKey(const Key('historial')));
      expect(aviso.left, greaterThanOrEqualTo(historial.right));
      expect(aviso.center.dy, closeTo(historial.center.dy, 12));
      // Y los botones se pueden tocar ya: en este archivo, tocar algo tapado
      // es un error.
      await _guardar(tester, 'historial');
      expect(find.text('Historial de las mesas'), findsOneWidget);
      await _contestar(tester, 'CERRAR');
    });

    testWidgets('se va solo', (tester) async {
      await guardarMedidas(tester);
      expect(find.byKey(const Key('aviso_del_pie')), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(find.byKey(const Key('aviso_del_pie')), findsNothing);
    });

    testWidgets('si no se pudo guardar lo dice en palabras, sin el error crudo',
        (tester) async {
      final mundo = await guardarMedidas(tester, antes: (m) => m.planos.falla = true);
      expect(mundo.planos.guardados, isEmpty);
      expect(
        _dicho(tester),
        'No se pudo guardar. Tocá Actualizar para ver cómo quedó y probá de '
        'nuevo.',
      );
      // El error tal cual vino queda para quien lo busque, al pasar el mouse.
      final pista = tester.widget<Tooltip>(
        find.ancestor(
          of: find.byKey(const Key('aviso_del_pie_texto')),
          matching: find.byType(Tooltip),
        ),
      );
      expect(pista.message, contains('database is locked'));
      // Y la pantalla queda libre para probar de nuevo.
      mundo.planos.falla = false;
      await _guardar(tester, 'guardar_medidas');
      expect(mundo.planos.guardados, hasLength(1));
      expect(_dicho(tester), 'Medidas guardadas.');
    });

    testWidgets('en una fiesta sin plano no hay pie: va en el aviso de abajo',
        (tester) async {
      final mundo = await _abrir(
        tester,
        conPlano: false,
        alumnos: _sinSortear(),
        antes: (m) => m.planos.falla = true,
      );
      await _guardar(tester, 'listo');
      expect(mundo.planos.guardados, isEmpty);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.text('No se pudo guardar el plano. Tocá Actualizar para ver cómo '
            'quedó y probá de nuevo.'),
        findsOneWidget,
      );
    });
  });
}
