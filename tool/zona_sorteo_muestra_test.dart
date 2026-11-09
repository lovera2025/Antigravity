// Muestras de "las mesas de más van lejos" (6.5.0): el cartel del sorteo con una
// familia de 5 mesas tildada sola, y la ventana para elegir la zona en el plano.
//
//   flutter test tool/zona_sorteo_muestra_test.dart --dart-define=salida=<carpeta>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/pago_para_sorteo.dart';
import 'package:arguello_events/features/eventos/widgets/sorteo_mesas_dialog.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');

ContratoAlumno _familia(String id, String nombre,
        {int extras = 0, List<int>? mesas}) =>
    ContratoAlumno(
      id: id,
      eventoId: 'e',
      nombreAlumno: nombre,
      cantidadAcompanantes: 0,
      montoTotalPactado: 1,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      numeroMesa:
          mesas == null ? null : MesasExtraUtils.formatearAsignacionMesas(mesas),
      cursoDivision: '5° A',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final carpeta = _salida.isNotEmpty
      ? _salida
      : Directory.systemTemp.createTempSync('zona_sorteo').path;

  setUpAll(() async {
    await cargarFuentesPlano();
    final iconos = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconos.load();
  });

  final alumnos = [
    _familia('rios', 'RÍOS, MATEO', extras: 4),
    _familia('sosa', 'SOSA, PILAR', extras: 3),
    _familia('luna', 'LUNA, TOMÁS', extras: 2),
    _familia('gomez', 'GÓMEZ, ANA', extras: 2, mesas: [10, 11]),
    for (var i = 1; i <= 9; i++) _familia('a$i', 'FAMILIA$i, ALUMNO', mesas: [i]),
    for (var i = 12; i <= 30; i++) _familia('b$i', 'FAMILIA$i, ALUMNO', mesas: [i]),
  ];
  final pagos = {
    for (final a in alumnos) a.id: const PagoAlumno(base: 1, mesas: 1),
  };
  final plano = PlanoEvento.nuevo(
    eventoId: 'e',
    armado: ArmadosPredefinidos.normal2aPagina3(),
    estilo: EstiloPlano.gala,
    modo: ModoSorteo.entera,
    ahora: DateTime.utc(2026, 11, 9),
  );

  Future<void> sacar(
    WidgetTester tester,
    String archivo,
    Size tam,
    Future<void> Function() tocar,
  ) async {
    final clave = GlobalKey();
    tester.view.physicalSize = tam * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepaintBoundary(
      key: clave,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: FuentesPlano.linea, useMaterial3: true),
        home: Scaffold(
          body: SorteoMesasDialog(
            tituloInstitucion: 'ESCUELA NORMAL',
            alumnos: alumnos,
            avisos: const [],
            pagos: pagos,
            plano: plano,
          ),
        ),
      ),
    ));
    await tester.pump();
    await tocar();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final boundary =
          clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final imagen = await boundary.toImage(pixelRatio: 2);
      final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
      final f = File('$carpeta${Platform.pathSeparator}$archivo')
        ..writeAsBytesSync(datos!.buffer.asUint8List());
      // ignore: avoid_print
      print('── PNG en: ${f.path}');
    });
  }

  testWidgets('el cartel, con las de más tildadas', (tester) async {
    await sacar(tester, '1_cartel.png', const Size(900, 1500), () async {
      await tester.ensureVisible(find.byKey(const Key('aviso_mas_de_tres')));
    });
  });

  testWidgets('elegir la zona en el plano', (tester) async {
    await sacar(tester, '2_elegir_zona.png', const Size(1366, 900), () async {
      await tester.ensureVisible(find.byKey(const Key('distancia_lejos_rios')));
      await tester.tap(find.byKey(const Key('distancia_lejos_rios')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Donde yo elija').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('elegir_zona_rios')));
      await tester.tap(find.byKey(const Key('elegir_zona_rios')));
      await tester.pumpAndSettle();
      for (final n in [60, 66, 67]) {
        // Toca la mesa como un clic: por el callback del plano.
        final vista = find.byKey(const ValueKey('zona_plano'));
        (tester.widget(vista) as dynamic).onTapMesa(n);
      }
    });
  });
}
