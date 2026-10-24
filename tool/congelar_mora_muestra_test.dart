// Arnés manual: Congelar la mora (6.2.1) con el ejemplo de PÉREZ, JUAN (datos
// inventados, no abre la base). Saca:
//   Congelar_1_congelar.png        — sin nada congelado, el copo abre "Congelar";
//   Congelar_2_mora_congelada.png  — 10 días después, "Mora congelada" con
//                                    Mantener y Recalcular;
//   Congelar_3_aviso.png           — el aviso celeste, en una celda como la de
//                                    ESTADO DE DEUDA.
//
//   flutter test tool/congelar_mora_muestra_test.dart --dart-define=salida=<carpeta>

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mora_congelada.dart';
import 'package:arguello_events/features/eventos/widgets/congelar_mora_dialog.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');
const _id = 'c0000000-0000-4000-8000-0000000000aa';

final _perez = ContratoAlumno(
  id: _id,
  eventoId: 'e0000000-0000-4000-8000-000000000001',
  nombreAlumno: 'PÉREZ, JUAN',
  cantidadAcompanantes: 0,
  montoTotalPactado: 270000,
  saldoDeudor: 180000,
  cuotasPagadas: 3,
  totalCuotas: 9,
  createdAt: DateTime.utc(2026, 3, 30, 3),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final carpeta = _salida.isNotEmpty ? _salida : Directory.systemTemp.createTempSync('congelar').path;

  Future<void> sacar(WidgetTester tester, String archivo, Widget hijo, {Size tam = const Size(520, 620)}) async {
    await cargarFuentesPlano();
    final iconos = FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconos.load();
    Directory(carpeta).createSync(recursive: true);
    final clave = GlobalKey();
    tester.view.physicalSize = tam * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: RepaintBoundary(
          key: clave,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: FuentesPlano.linea, useMaterial3: true),
            home: Scaffold(backgroundColor: const Color(0xFF6B6B6B), body: Center(child: hijo)),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final b = clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 2);
      final datos = await img.toByteData(format: ui.ImageByteFormat.png);
      final f = File('$carpeta${Platform.pathSeparator}$archivo')..writeAsBytesSync(datos!.buffer.asUint8List());
      print('── PNG en: ${f.path}');
    });
  }

  tearDown(MoraCongelada.vaciar);

  testWidgets('Congelar: sin nada congelado (23/10)', (tester) async {
    await sacar(
      tester,
      'Congelar_1_congelar.png',
      CongelarMoraDialog(contrato: _perez, moraCobradaHistorial: 0, hoy: DateTime(2026, 10, 23)),
    );
  });

  testWidgets('Mora congelada: 10 días después (2/11)', (tester) async {
    MoraCongelada.poner(_id, MoraCongelada.nada.congelar(cuotas: {4, 5}, dia: DateTime(2026, 10, 23)));
    await sacar(
      tester,
      'Congelar_2_mora_congelada.png',
      CongelarMoraDialog(contrato: _perez, moraCobradaHistorial: 0, hoy: DateTime(2026, 11, 2)),
    );
  });

  testWidgets('el aviso celeste en ESTADO DE DEUDA', (tester) async {
    MoraCongelada.poner(_id, MoraCongelada.nada.congelar(cuotas: {4, 5}, dia: DateTime(2026, 10, 23)));
    await sacar(
      tester,
      'Congelar_3_aviso.png',
      Container(
        width: 360,
        padding: const EdgeInsets.all(14),
        color: Colors.white,
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFE67E22)),
              SizedBox(width: 6),
              Text('EN MORA', style: TextStyle(color: Color(0xFFE67E22), fontWeight: FontWeight.w700, fontSize: 12)),
            ]),
            Text('Saldo: \$180.000,00', style: TextStyle(color: Color(0xFFE67E22), fontSize: 11, fontWeight: FontWeight.w600)),
            Text('(3/9 cuotas)', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
            AvisoMoraCongelada(contratoId: _id, tamano: 10),
            SizedBox(height: 2),
            Text('Mora pendiente: \$51.600,00', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFE65100))),
          ],
        ),
      ),
      tam: const Size(420, 160),
    );
  });
}
