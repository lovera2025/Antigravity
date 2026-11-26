// Muestras de "el descuento es para lo que la familia tenía al sorteo"
// (17-nov-2026), sin base ni nube, para mirarlas:
//
//   flutter test tool/lugares_al_sorteo_muestra_test.dart --dart-define=salida=C:\carpeta
//
// Salen, con el tema claro de la app:
//   • Lugares_1_entradas_recordatorio.png: ENTRADAS de una fiesta sorteada
//     antes de la regla, en modo jefe, con el recordatorio arriba;
//   • Lugares_2_precios_sin_revisar.png: PRECIOS de esa fiesta, con el aviso y
//     REVISAR LA LISTA;
//   • Lugares_3_lista.png: la lista, con lo que vino después tildado y lo de
//     revisar sin tildar, cada uno con su porqué;
//   • Lugares_4_lista_sin_internet.png: lo que dice si no hay internet;
//   • Lugares_5_precios_aceptada.png: PRECIOS con la lista ya aceptada;
//   • Lugares_6_precios_sin_sorteo.png: PRECIOS de una fiesta sin sortear.
//
// Los nombres son inventados.

// ignore_for_file: avoid_print, invalid_use_of_visible_for_testing_member

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/entradas/widgets/precios_de_entradas_dialog.dart';
import 'package:arguello_events/features/eventos/retiro_entradas_screen.dart';
import 'package:arguello_events/features/eventos/services/lugares_al_sorteo.dart';
import 'package:arguello_events/features/eventos/widgets/lugares_al_sorteo_dialog.dart';
import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/sorteo_mesas_registro.dart';

import '../test/helpers/entradas_en_memoria.dart';
import '../test/helpers/entrega_en_memoria.dart';
import '../test/helpers/revision_en_memoria.dart';
import '../test/helpers/tema_de_la_app.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');

// 12/11/2026 21:40 en Argentina.
final _sorteoEl = DateTime.utc(2026, 11, 13, 0, 40);

ContratoAlumno _alumno(
  String id,
  String nombre, {
  int extras = 0,
  int sillas = 0,
  String? mesa,
  DateTime? creado,
}) =>
    ContratoAlumno(
      id: id,
      eventoId: idFiestaEntrega,
      nombreAlumno: nombre,
      cantidadAcompanantes: 0,
      montoTotalPactado: 300000 + 70000.0 * extras + 8000.0 * sillas,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      sillasExtraCantidad: sillas,
      sillasExtraPrecioTotal: 8000.0 * sillas,
      numeroMesa: mesa,
      createdAt: creado ?? DateTime.utc(2026, 3, 1),
    );

SorteoMesasRegistro _renglon(
  String id,
  Map<String, String> resultado, {
  int horas = 0,
  Map<String, String>? antes,
  Map<String, String>? lugares,
  bool auto = false,
}) =>
    SorteoMesasRegistro(
      id: id,
      eventoId: idFiestaEntrega,
      tipo: TipoRegistroSorteo.sorteo,
      resultado: resultado,
      antes: antes,
      lugares: lugares,
      automatico: auto,
      hechoPor: auto ? null : 'Jefe',
      createdAt: _sorteoEl.add(Duration(hours: horas)),
    );

/// Una fiesta sorteada el 12/11 sin anotar los lugares, con un caso de cada
/// huella.
RevisionEnMemoria _fiestaDeMuestra() => RevisionEnMemoria(
      alumnosDeLaFiesta: [
        // El programa le dio sola la 151 dos días después, sin ningún pago.
        _alumno('a', 'ACOSTA, VALENTINA', extras: 1, mesa: '12, 151'),
        // Se cargó después del sorteo, con adicional y sillas.
        _alumno(
          'b',
          'BENÍTEZ, JOAQUÍN',
          extras: 1,
          sillas: 2,
          mesa: '152, 153',
          creado: _sorteoEl.add(const Duration(hours: 70)),
        ),
        // Sillas sin ninguna huella.
        _alumno('c', 'CASTRO, MÍA', sillas: 2, mesa: '14'),
        // Adicional sin número, con el primer pago después del sorteo.
        _alumno('d', 'DOMÍNGUEZ, BRUNO', extras: 1, mesa: '20'),
        // "Los que faltaban" le dio la 80.
        _alumno('e', 'VIRARO, CAMILA', extras: 1, mesa: '22, 80'),
        // Ya la tenía en el sorteo: no figura.
        _alumno('f', 'FERREYRA, LUCAS', extras: 1, mesa: '30, 31'),
        _alumno('g', 'GÓMEZ, SOFÍA', mesa: '32'),
      ],
      registrosDeLaFiesta: [
        _renglon(
          'sorteo',
          const {'a': '12', 'c': '14', 'd': '20', 'e': '22', 'f': '30, 31', 'g': '32'},
          antes: const {},
        ),
        _renglon(
          'faltaban',
          const {'e': '22, 80'},
          horas: 44,
          antes: const {'e': '22'},
        ),
        _renglon(
          'auto',
          const {'a': '12, 151'},
          horas: 50,
          antes: const {'a': '12'},
          auto: true,
        ),
        _renglon(
          'nuevo',
          const {'b': '152, 153'},
          horas: 72,
          antes: const {},
        ),
      ],
      pagos: {
        'd': [
          {
            'concepto': 'Mesa Extra 1',
            'monto': 70000.0,
            'monto_gross': 70000.0,
            'anulado': 0,
            'created_at':
                _sorteoEl.add(const Duration(hours: 90)).toIso8601String(),
          },
        ],
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final carpeta = _salida.isNotEmpty
      ? _salida
      : Directory.systemTemp.createTempSync('lugares_al_sorteo_muestra').path;
  Directory(carpeta).createSync(recursive: true);

  Future<void> letras() async {
    SharedPreferences.setMockInitialValues({});
    await cargarFuentesPlano();
    final iconos = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconos.load();
  }

  Future<void> guardar(WidgetTester tester, GlobalKey clave, String nombre) async {
    await tester.runAsync(() async {
      final boundary =
          clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final imagen = await boundary.toImage(pixelRatio: 1);
      final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
      final archivo = File('$carpeta${Platform.pathSeparator}$nombre')
        ..writeAsBytesSync(datos!.buffer.asUint8List());
      print('── PNG en: ${archivo.path}');
    });
  }

  Future<void> pasar(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<(GlobalKey, EntregaEnMemoria)> montar(
    WidgetTester tester, {
    required Widget pantalla,
    required Size tamano,
    List<Override> extra = const [],
    void Function(EntregaEnMemoria)? preparar,
  }) async {
    await letras();
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final e = EntregaEnMemoria();
    preparar?.call(e);
    final entradas = EntradasEnMemoria()..conPrecio(idFiestaEntrega);
    final c = ProviderContainer(overrides: [
      ...e.reemplazos(jefe: true),
      ...entradas.reemplazos,
      ...extra,
    ]);
    addTearDown(c.dispose);
    final clave = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: clave,
      child: UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: temaClaroDeLaApp(),
          home: pantalla,
        ),
      ),
    ));
    await pasar(tester);
    return (clave, e);
  }

  final sinAnotar = LugaresAlSorteo.vigente([_renglon('s', const {'a': '12'})]);
  final anotados = LugaresAlSorteo.vigente([
    _renglon('s', const {'a': '12'}, lugares: const {}),
  ]);

  testWidgets('ENTRADAS con el recordatorio', (tester) async {
    final (clave, _) = await montar(
      tester,
      tamano: const Size(1300, 620),
      preparar: (e) => e.sorteos.registros.add(
        _renglon(
          'sorteo',
          const {
            EntregaEnMemoria.idPerez: '12',
            EntregaEnMemoria.idLopez: '14',
            EntregaEnMemoria.idGomez: '15',
          },
          antes: const {},
        ),
      ),
      pantalla: RetiroEntradasScreen(
        evento: fiestaDeLaEntrega,
        onCobrar: (_) async {},
        onEditarAlumno: (_) async {},
      ),
    );
    expect(find.byKey(const Key('entradas_falta_revisar_lugares')), findsOneWidget);
    await guardar(tester, clave, 'Lugares_1_entradas_recordatorio.png');
  });

  for (final (nombre, foto, conBoton) in [
    ('Lugares_2_precios_sin_revisar.png', sinAnotar, true),
    ('Lugares_5_precios_aceptada.png', anotados, false),
    ('Lugares_6_precios_sin_sorteo.png', FotoDeLosLugares.sinSorteo, false),
  ]) {
    testWidgets('PRECIOS · $nombre', (tester) async {
      final (clave, _) = await montar(
        tester,
        tamano: const Size(900, 900),
        pantalla: Scaffold(
          body: PreciosDeEntradasDialog(
            eventoId: idFiestaEntrega,
            fiesta: 'PUERTO VIEJO',
            quien: 'Jefe',
            lugares: foto,
            revisarLugares: conBoton ? (_) async => null : null,
          ),
        ),
      );
      await guardar(tester, clave, nombre);
    });
  }

  testWidgets('la lista, y lo que dice sin internet', (tester) async {
    final m = _fiestaDeMuestra();
    final (clave, _) = await montar(
      tester,
      tamano: const Size(900, 1000),
      extra: [m.reemplazo],
      pantalla: const Scaffold(
        body: RevisionDeLugaresDialog(
          eventoId: idFiestaEntrega,
          fiesta: 'PUERTO VIEJO',
        ),
      ),
    );
    expect(find.text('Se agregaron después del sorteo'), findsOneWidget);
    expect(find.text('Para revisar'), findsOneWidget);
    await guardar(tester, clave, 'Lugares_3_lista.png');

    m.hayInternet = false;
    await tester.tap(find.byKey(const Key('revision_aceptar')));
    await pasar(tester);
    expect(find.byKey(const Key('revision_problema')), findsOneWidget);
    await guardar(tester, clave, 'Lugares_4_lista_sin_internet.png');
  });
}
