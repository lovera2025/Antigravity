// Muestras del cierre de una caja de barra (etapa 6), sin base ni nube, para mirarlo:
//
//   flutter test tool/barra_cierre_muestra_test.dart --dart-define=salida=C:\carpeta
//
// Salen:
//   • Cierre_1_contar_tablet.png: el paso de contar, a ciegas (ninguna plata de la caja);
//   • Cierre_2_cierre_tablet.png: después de cerrar, en una tablet acostada: la diferencia y
//     los botones a la izquierda, el papel a la derecha;
//   • Cierre_3_cierre_celular.png: lo mismo en un celular, uno debajo del otro;
//   • Cierre_4_papel_entero.png: el papel completo, con el historial, como en la pantalla;
//   • Cierre_caja2.pdf: el PDF de 58 mm que se guarda, una sola hoja larga.
//
// Una noche inventada: 30 ventas, una anulada, sillas extra y $ 500 de diferencia.

// ignore_for_file: avoid_print, invalid_use_of_visible_for_testing_member

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/barra/cuentas/cierre_de_barra.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/estilos/disenio_barra.dart';
import 'package:arguello_events/features/barra/impresion/modelo_ticket.dart';
import 'package:arguello_events/features/barra/impresion/papel_en_pantalla.dart';
import 'package:arguello_events/features/barra/impresion/papel_pdf.dart';
import 'package:arguello_events/features/barra/widgets/cerrar_caja_barra_screen.dart';
import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/common/services/pdf_service.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';

import '../test/helpers/barra_en_memoria.dart';
import '../test/helpers/operadores_en_memoria.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');
const _marta = 'a0000000-0000-4000-8000-000000000001';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final carpeta = _salida.isNotEmpty ? _salida : Directory.systemTemp.createTempSync('cierre_muestra').path;
  Directory(carpeta).createSync(recursive: true);

  /// Una noche: 30 ventas en la caja 2, una anulada.
  Future<(BarraEnPrueba, OperadoresEnPrueba, CajaBarra)> noche() async {
    final operadores = OperadoresEnPrueba();
    operadores.operadores.lista.add(operadorDePrueba(_marta, 'Marta', '5555'));
    final prueba = BarraEnPrueba();
    final fiesta = fiestaDePrueba(BarraEnPrueba.id(1), 'PUERTO VIEJO', DateTime.now().add(const Duration(days: 5)));
    prueba.eventos.add(fiesta);
    final b = prueba.barra;
    final productos = [
      for (final (n, precio) in [
        ('Cerveza lata', 3500.0),
        ('Fernet con coca', 6000.0),
        ('Speed con vodka', 8000.0),
        ('Agua sin gas', 1000.0),
        ('Gaseosa', 2000.0),
        ('Silla extra', 8000.0),
      ])
        (b.producto(n), precio),
    ];
    for (final (p, precio) in productos) {
      b.precio(fiesta.id, p, precio);
    }
    var hora = DateTime.utc(2026, 12, 5, 1, 10); // 22:10 en Argentina
    b.reloj = () => hora;
    final abierta = await b.abrirCaja(eventoId: fiesta.id, operadorId: _marta, operadorNombre: 'Marta', numeroCaja: 2);
    final caja = await b.ponerCambio(abierta, 20000, quien: 'Marta');
    VentaBarra? anular;
    for (var i = 0; i < 30; i++) {
      hora = hora.add(Duration(minutes: 6 + i % 5));
      final (p, precio) = productos[i % productos.length];
      final n = 1 + i % 3;
      final total = precio * n;
      final transferencia = i % 4 == 1;
      final v = await b.vender(
        caja: caja,
        renglones: [RenglonVenta(productoId: p.id, nombre: p.nombre, precio: precio, cantidad: n)],
        medio: transferencia ? MedioBarra.transferencia : MedioBarra.efectivo,
        efectivo: transferencia ? 0 : total,
        transferencia: transferencia ? total : 0,
        quien: 'Marta',
      );
      if (i == 7) anular = v;
    }
    await b.anular(anular!, motivo: 'se cobró dos veces', quien: 'Marta');
    hora = hora.add(const Duration(minutes: 20));
    return (prueba, operadores, caja);
  }

  Future<void> guardar(WidgetTester tester, GlobalKey clave, String nombre) async {
    await tester.runAsync(() async {
      final boundary = clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final imagen = await boundary.toImage(pixelRatio: 1);
      final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
      final archivo = File('$carpeta${Platform.pathSeparator}$nombre')..writeAsBytesSync(datos!.buffer.asUint8List());
      print('── PNG en: ${archivo.path}');
    });
  }

  Future<void> letras() async {
    SharedPreferences.setMockInitialValues({});
    await cargarFuentesPlano();
    final iconos = FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconos.load();
  }

  for (final (nombre, tamano, numero) in [
    ('tablet', const Size(1280, 800), 2),
    ('celular', const Size(390, 844), 3),
  ]) {
    testWidgets('el cierre en $nombre', (tester) async {
      await letras();
      final (prueba, operadores, caja) = await noche();
      final clave = GlobalKey();
      tester.view.physicalSize = tamano;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final base = ThemeData(fontFamily: FuentesPlano.linea, useMaterial3: true);
      await tester.pumpWidget(RepaintBoundary(
        key: clave,
        child: ProviderScope(
          overrides: [...operadores.reemplazos, ...prueba.reemplazos],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: base,
            home: Theme(
              data: temaDeVender(DisenioBarra.nocheDorada, base: base),
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: TemaBarra.de(DisenioBarra.nocheDorada).fondo),
                child: CerrarCajaBarraScreen(caja: caja, fiesta: 'PUERTO VIEJO'),
              ),
            ),
          ),
        ),
      ));
      final c = ProviderScope.containerOf(tester.element(find.byType(CerrarCajaBarraScreen)));
      await c.read(appRoleProvider.notifier).entrarComoBarra(
            operadores.operadores.lista.single,
            const PermisosEfectivos(barra: true),
          );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('cierre_contado')), '');
      await tester.pumpAndSettle();
      final cuentas = CierreDeBarra.de(
        caja,
        await prueba.barra.ventasDeLaCaja(caja.id),
        await prueba.barra.anulacionesDeLaCaja(caja.id),
      );
      final contado = (cuentas.efectivoEsperado - 500).round();
      await tester.enterText(find.byKey(const Key('cierre_contado')), '$contado');
      await tester.pumpAndSettle();
      if (nombre == 'tablet') await guardar(tester, clave, 'Cierre_1_contar_tablet.png');
      await tester.tap(find.byKey(const Key('cierre_cerrar')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cierre_confirmar')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await guardar(tester, clave, 'Cierre_${numero}_cierre_$nombre.png');
    });
  }

  testWidgets('el papel entero y el PDF', (tester) async {
    await letras();
    final (prueba, _, caja) = await noche();
    final ventas = await prueba.barra.ventasDeLaCaja(caja.id);
    final anulaciones = await prueba.barra.anulacionesDeLaCaja(caja.id);
    final cuentas = CierreDeBarra.de(caja, ventas, anulaciones);
    final contado = cuentas.efectivoEsperado - 500;
    final cerrada = await prueba.barra.cerrarCaja(
      caja,
      efectivoContado: contado,
      diferencia: -500,
      nota: 'faltó un billete de 500',
      quien: 'Marta',
    );
    final lineas = ModeloTicket.deCierre(
      cerrada,
      cuentas,
      fiesta: 'PUERTO VIEJO',
      historial: ventas,
      anulaciones: anulaciones,
    );

    final clave = GlobalKey();
    tester.view.physicalSize = const Size(380, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: FuentesPlano.linea),
      home: Scaffold(
        backgroundColor: const Color(0xFF2B2B2B),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: RepaintBoundary(key: clave, child: PapelEnPantalla(lineas)),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await guardar(tester, clave, 'Cierre_4_papel_entero.png');

    await tester.runAsync(() async {
      final bytes = await PapelPdf.armar(
        lineas,
        titulo: 'Cierre de caja 2 - PUERTO VIEJO',
        fuentes: await PdfService.fuentesOutfit(),
      );
      final pdf = File('$carpeta${Platform.pathSeparator}Cierre_caja2.pdf')..writeAsBytesSync(bytes);
      print('── PDF en: ${pdf.path}');
    });
  });
}
