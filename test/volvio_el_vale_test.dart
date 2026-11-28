import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/barra/cuentas/cierre_de_barra.dart';
import 'package:arguello_events/features/barra/cuentas/cuenta_barra.dart';
import 'package:arguello_events/features/barra/cuentas/cuenta_del_proveedor.dart';
import 'package:arguello_events/features/barra/cuentas/stock_de_la_barra.dart';
import 'package:arguello_events/features/barra/cuentas/stock_por_barra.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/impresion/modelo_ticket.dart';
import 'package:arguello_events/features/barra/impresion/ticket_esc_pos.dart';
import 'package:arguello_events/features/barra/widgets/anular_venta_dialog.dart';

/// **"¿Volvió el vale?"** al anular una venta de la barra (28-nov-2026, decidido por el
/// usuario con el ejemplo de 2 Speed): si quien anula tiene el vale en la mano, la
/// bebida no salió y el stock vuelve (lo de siempre); si el vale ya se entregó, la plata
/// se anula igual pero **el stock no vuelve**, y GANANCIA lo cuenta como perdido (al
/// proveedor se le paga igual). Una venta de solo sillas de la noche no pregunta.
const _evento = 'e0000000-0000-4000-8000-000000000001';
const _speed = 'p0000000-0000-4000-8000-000000000002';
const _cerveza = 'p0000000-0000-4000-8000-000000000001';
const _silla = 'p0000000-0000-4000-8000-000000000005';
const _fernet = 'p0000000-0000-4000-8000-000000000006';
const _botella = 'p0000000-0000-4000-8000-000000000007';
const _b1 = 'Barra 1';

void main() {
  final ahora = DateTime.utc(2026, 12, 5, 2); // viernes 4, 23 hs de Argentina

  final numeros = <String, int>{};
  VentaBarra vender(CajaBarra c, List<(String, String, int)> lleva, {double precio = 4000}) {
    final r = [
      for (final (id, nombre, n) in lleva)
        RenglonVenta(productoId: id, nombre: nombre, precio: precio, cantidad: n),
    ];
    final n = (numeros[c.id] ?? 0) + 1;
    numeros[c.id] = n;
    return VentaBarra.nueva(
      cajaBarraId: c.id,
      eventoId: c.eventoId,
      numero: n,
      renglones: r,
      medio: MedioBarra.efectivo,
      efectivo: CuentaBarra(r).total,
      deviceId: 'tablet-${c.numeroCaja}',
      ahora: ahora,
    );
  }

  CajaBarra caja() => CajaBarra.abrir(eventoId: _evento, numeroCaja: 1, sede: _b1, ahora: ahora);

  AnulacionBarra anular(VentaBarra v, {required bool volvio}) =>
      AnulacionBarra.de(v, motivo: 'Se equivocó', valeVolvio: volvio, hechoPor: 'Romi', ahora: ahora);

  group('la respuesta va en el motivo', () {
    test('con el vale de vuelta el motivo queda como se escribió', () {
      final c = caja();
      final a = anular(vender(c, [(_speed, 'Speed', 2)]), volvio: true);
      expect(a.motivo, 'Se equivocó');
      expect(a.valeVolvio, isTrue);
      expect(a.motivoParaMostrar, 'Se equivocó');
    });

    test('sin el vale, la marca va al final y la pantalla muestra solo lo escrito', () {
      final c = caja();
      final a = anular(vender(c, [(_speed, 'Speed', 2)]), volvio: false);
      expect(a.motivo, 'Se equivocó ${AnulacionBarra.marcaValeNoVolvio}');
      expect(a.valeVolvio, isFalse);
      expect(a.motivoParaMostrar, 'Se equivocó');
    });

    test('lo anulado antes de esta versión (sin marca) cuenta como que el vale volvió', () {
      final viejo = AnulacionBarra.fromMap({
        'id': 'a1',
        'venta_id': 'v1',
        'caja_barra_id': 'c1',
        'evento_id': _evento,
        'motivo': 'se cobró dos veces',
        'created_at': '2026-11-20T02:00:00.000Z',
        'updated_at': '2026-11-20T02:00:00.000Z',
      });
      expect(viejo.valeVolvio, isTrue);
      expect(viejo.motivoParaMostrar, 'se cobró dos veces');
    });

    test('la marca sola no es un motivo', () {
      final v = vender(caja(), [(_speed, 'Speed', 1)]);
      expect(() => AnulacionBarra.de(v, motivo: '  ', valeVolvio: false, ahora: ahora), throwsArgumentError);
      expect(
        () => AnulacionBarra.de(v, motivo: AnulacionBarra.marcaValeNoVolvio, valeVolvio: false, ahora: ahora),
        throwsArgumentError,
      );
    });

    test('si alguien tipea la marca y dice que el vale volvió, vale lo que contestó', () {
      final v = vender(caja(), [(_speed, 'Speed', 1)]);
      final a = AnulacionBarra.de(v,
          motivo: 'raro ${AnulacionBarra.marcaValeNoVolvio}', valeVolvio: true, ahora: ahora);
      expect(a.valeVolvio, isTrue);
      expect(a.motivo, 'raro');
    });

    test('viaja entera por la red y por la nube (toMap / fromMap)', () {
      final a = anular(vender(caja(), [(_speed, 'Speed', 1)]), volvio: false);
      final b = AnulacionBarra.fromMap(a.toMap());
      expect(b.valeVolvio, isFalse);
      expect(b.motivoParaMostrar, 'Se equivocó');
      expect(b.id, a.id);
    });

    test('una venta de solo sillas de la noche no pregunta; con un trago, sí', () {
      final c = caja();
      expect(AnulacionBarra.preguntaPorElVale(vender(c, [(_silla, 'Silla extra', 2)])), isFalse);
      expect(AnulacionBarra.preguntaPorElVale(vender(c, [(_silla, 'Silla suelta', 1)])), isFalse);
      expect(AnulacionBarra.preguntaPorElVale(vender(c, [(_silla, 'Silla extra', 1), (_speed, 'Speed', 1)])),
          isTrue);
      expect(AnulacionBarra.preguntaPorElVale(vender(c, [(_speed, 'Speed', 1)])), isTrue);
    });
  });

  group('el stock', () {
    PrecioBarra precio(String p, int stock) =>
        PrecioBarra.para(eventoId: _evento, productoId: p, precio: 4000, stockInicial: stock, ahora: ahora);

    test('el stock general: vuelve solo con el vale', () {
      final c = caja();
      final conVale = vender(c, [(_speed, 'Speed', 2)]);
      final sinVale = vender(c, [(_speed, 'Speed', 3)]);
      final vendida = vender(c, [(_speed, 'Speed', 1)]);
      final s = StockDeLaBarra.de(
        eventoId: _evento,
        precios: [precio(_speed, 24)],
        ventas: [conVale, sinVale, vendida],
        anulaciones: [anular(conVale, volvio: true), anular(sinVale, volvio: false)],
      );
      expect(s[_speed]!.vendido, 4, reason: 'la vendida (1) y la anulada sin el vale (3)');
      expect(s[_speed]!.queda, 20);
    });

    test('el stock por barra: vuelve solo con el vale, también en el depósito', () {
      final c = caja();
      final conVale = vender(c, [(_cerveza, 'Cerveza', 5)]);
      final sinVale = vender(c, [(_cerveza, 'Cerveza', 2)]);
      final s = StockPorBarra.de(
        eventoId: _evento,
        precios: [precio(_cerveza, 100)],
        repartos: [
          StockEnLaBarra.para(eventoId: _evento, productoId: _cerveza, barra: _b1, arranque: 60, ahora: ahora),
        ],
        movimientos: const [],
        ventas: [conVale, sinVale],
        cajas: [c],
        anulaciones: [anular(conVale, volvio: true), anular(sinVale, volvio: false)],
      );
      expect(s.en(_b1, _cerveza)!.vendido, 2);
      expect(s.en(_b1, _cerveza)!.queda, 58);
      expect(s.en(kDeposito, _cerveza)!.queda, 40, reason: 'vender no toca el depósito');
    });

    test('un conteo después de la anulada sin el vale no la vuelve a sumar', () {
      final c = caja();
      final sinVale = vender(c, [(_cerveza, 'Cerveza', 2)]);
      final anulacion = anular(sinVale, volvio: false);
      StockPorBarra stock(List<MovimientoDeStock> movs) => StockPorBarra.de(
            eventoId: _evento,
            precios: [precio(_cerveza, 100)],
            repartos: [
              StockEnLaBarra.para(eventoId: _evento, productoId: _cerveza, barra: _b1, arranque: 60, ahora: ahora),
            ],
            movimientos: movs,
            ventas: [sinVale],
            cajas: [c],
            anulaciones: [anulacion],
          );
      final visto = stock(const []);
      expect(visto.en(_b1, _cerveza)!.queda, 58);
      final conteo = MovimientoDeStock.conteo(
        eventoId: _evento,
        productoId: _cerveza,
        lugar: _b1,
        contadas: 58,
        foto: visto.fotoDe(_b1, _cerveza),
        ajuste: visto.ajustePara(_b1, _cerveza, 58),
        ahora: ahora.add(const Duration(minutes: 10)),
      ).conEquipo('celular-nico');
      expect(stock([conteo]).en(_b1, _cerveza)!.queda, 58, reason: 'contó lo que había: 58');
    });

    test('la plata no cambia: toda anulada deja de contar, con o sin el vale', () {
      final c = caja();
      final conVale = vender(c, [(_speed, 'Speed', 2)]);
      final sinVale = vender(c, [(_speed, 'Speed', 3)]);
      final vendida = vender(c, [(_speed, 'Speed', 1)]);
      final cierre = CierreDeBarra.deLaFiesta(
        [conVale, sinVale, vendida],
        [anular(conVale, volvio: true), anular(sinVale, volvio: false)],
      );
      expect(cierre.porProducto.single.unidades, 1);
      expect(ventasAnuladas([anular(conVale, volvio: true), anular(sinVale, volvio: false)]),
          {conVale.id, sinVale.id});
      expect(ventasAnuladasConElVale([anular(conVale, volvio: true), anular(sinVale, volvio: false)]),
          {conVale.id});
    });
  });

  group('GANANCIA', () {
    test('lo entregado sin el vale es perdido: se le debe al proveedor, no se vendió', () {
      final c = caja();
      final buena = vender(c, [(_speed, 'Speed', 2)], precio: 5000);
      final sinVale = vender(c, [(_speed, 'Speed', 3)], precio: 5000);
      final conVale = vender(c, [(_speed, 'Speed', 4)], precio: 5000);
      final p = CuentaDelProveedor.de([
        FiestaParaLaGanancia(
          eventoId: _evento,
          nombre: 'TÉCNICA',
          fecha: DateTime(2026, 12, 4),
          cajas: [c],
          ventas: [buena, sinVale, conVale],
          anulaciones: [anular(sinVale, volvio: false), anular(conVale, volvio: true)],
          precios: [PrecioBarra.para(eventoId: _evento, productoId: _speed, precio: 5000, stockInicial: 24, ahora: ahora)],
          repartos: [
            StockEnLaBarra.para(eventoId: _evento, productoId: _speed, barra: _b1, arranque: 24, ahora: ahora),
          ],
          listas: {_speed: 1500},
        ),
      ]).productos.single;
      expect(p.vendidas, 2);
      expect(p.perdidas, 3);
      expect(p.seVendio, 1000000, reason: r'2 x $5.000');
      expect(p.leDebo, 750000, reason: r'(2 + 3) x $1.500');
      expect(p.ganancia, 250000);
      expect(p.quedaron, 19, reason: '24 − 2 vendidas − 3 entregadas');
    });

    test('sin reparto, lo que quedó también descuenta lo entregado sin el vale', () {
      final c = caja();
      final sinVale = vender(c, [(_speed, 'Speed', 3)], precio: 5000);
      final p = CuentaDelProveedor.de([
        FiestaParaLaGanancia(
          eventoId: _evento,
          nombre: 'TÉCNICA',
          fecha: DateTime(2026, 12, 4),
          cajas: [c],
          ventas: [sinVale],
          anulaciones: [anular(sinVale, volvio: false)],
          precios: [PrecioBarra.para(eventoId: _evento, productoId: _speed, precio: 5000, stockInicial: 24, ahora: ahora)],
          listas: {_speed: 1500},
        ),
      ]).productos.single;
      expect(p.vendidas, 0);
      expect(p.perdidas, 3);
      expect(p.quedaron, 21);
    });

    test('un trago con receta entregado sin el vale: lo que lleva se le debe igual', () {
      final c = caja();
      final sinVale = vender(c, [(_fernet, 'Fernet con coca', 2)], precio: 6000);
      final cuenta = CuentaDelProveedor.de([
        FiestaParaLaGanancia(
          eventoId: _evento,
          nombre: 'TÉCNICA',
          fecha: DateTime(2026, 12, 4),
          cajas: [c],
          ventas: [sinVale],
          anulaciones: [anular(sinVale, volvio: false)],
          precios: [PrecioBarra.para(eventoId: _evento, productoId: _fernet, precio: 6000, ahora: ahora)],
          recetas: [
            RecetaBarra.para(
              eventoId: _evento,
              productoId: _fernet,
              ingredienteId: _botella,
              cantidad: 200,
              unidad: UnidadDeReceta.cc,
              ahora: ahora,
            ),
          ],
          listas: {_botella: 9000},
          contenidos: {_botella: 750},
        ),
      ]);
      final fernet = cuenta.productos.singleWhere((p) => p.productoId == _fernet);
      expect(fernet.vendidas, 0);
      expect(fernet.perdidas, 2);
      expect(fernet.seVendio, 0);
      expect(fernet.leDebo, 480000, reason: r'400 cc de una botella de $9.000 que trae 750');
      expect(cuenta.paraElProveedor.singleWhere((u) => u.productoId == _botella).cc, 400);
      expect(cuenta.leDebo, cuenta.paraElProveedor.fold<int>(0, (s, u) => s + u.leDebo));
    });
  });

  group('el papel', () {
    test('el ticket anulado dice el motivo sin la marca y que el vale no volvió', () {
      final c = caja();
      final v = vender(c, [(_speed, 'Speed', 2)]);
      final lineas = ModeloTicket.deVenta(
        v,
        caja: c,
        fiesta: 'TÉCNICA',
        anulacion: anular(v, volvio: false),
      );
      // Los renglones del papel parten el texto largo: se juntan con un espacio.
      final texto = [for (final l in lineas) if (l is TextoTicket) l.texto.trim()].join(' ');
      expect(texto, contains('Motivo: Se equivocó'));
      expect(texto, isNot(contains('[el vale')), reason: 'la marca no se imprime');
      expect(texto, contains('El vale no volvió'));
    });
  });

  group('la ventana', () {
    Future<AnulacionPedida?> abrir(WidgetTester tester, {required bool pregunta, Future<void> Function()? hacer}) async {
      AnulacionPedida? respuesta;
      var cerro = false;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              respuesta = await pedirAnulacion(
                context,
                titulo: 'Anular la N° 0003',
                explicacion: 'Deja de contar en la caja.',
                preguntaPorElVale: pregunta,
              );
              cerro = true;
            },
            child: const Text('abrir'),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await hacer?.call();
      await tester.pumpAndSettle();
      expect(cerro, isTrue, reason: 'la ventana se tiene que haber cerrado');
      return respuesta;
    }

    FilledButton boton(WidgetTester tester) => tester.widget(find.byKey(const Key('motivo_anular')));

    testWidgets('no anula sin contestar si volvió el vale, aunque haya motivo', (tester) async {
      final r = await abrir(tester, pregunta: true, hacer: () async {
        expect(find.text('¿Volvió el vale?'), findsOneWidget);
        await tester.enterText(find.byKey(const Key('motivo_texto')), 'Se equivocó de bebida');
        await tester.pump();
        expect(boton(tester).onPressed, isNull, reason: 'ninguna respuesta viene marcada');
        expect(find.text('Falta decir si volvió el vale.'), findsOneWidget);
        await tester.tap(find.byKey(const Key('anular_vale_no_volvio')));
        await tester.pump();
        expect(find.byKey(const Key('anular_que_pasa')), findsOneWidget);
        expect(boton(tester).onPressed, isNotNull);
        await tester.tap(find.byKey(const Key('motivo_anular')));
      });
      expect(r, (motivo: 'Se equivocó de bebida', valeVolvio: false));
    });

    testWidgets('con SÍ, LO TENGO el vale volvió', (tester) async {
      final r = await abrir(tester, pregunta: true, hacer: () async {
        await tester.tap(find.byKey(const Key('anular_vale_volvio')));
        await tester.pump();
        expect(boton(tester).onPressed, isNull, reason: 'falta el motivo');
        await tester.enterText(find.byKey(const Key('motivo_texto')), 'Se cobró dos veces');
        await tester.pump();
        await tester.tap(find.byKey(const Key('motivo_anular')));
      });
      expect(r, (motivo: 'Se cobró dos veces', valeVolvio: true));
    });

    testWidgets('una venta de solo sillas no pregunta por el vale', (tester) async {
      final r = await abrir(tester, pregunta: false, hacer: () async {
        expect(find.text('¿Volvió el vale?'), findsNothing);
        await tester.enterText(find.byKey(const Key('motivo_texto')), 'No vino');
        await tester.pump();
        await tester.tap(find.byKey(const Key('motivo_anular')));
      });
      expect(r, (motivo: 'No vino', valeVolvio: true));
    });

    testWidgets('CANCELAR no anula', (tester) async {
      final r = await abrir(tester, pregunta: true, hacer: () async {
        await tester.tap(find.text('CANCELAR'));
      });
      expect(r, isNull);
    });
  });

  test('ninguna cuenta del stock usa la lista de anuladas de la plata', () {
    // Las del stock (`StockDeLaBarra`, `StockPorBarra`) usan solo las anuladas con el
    // vale de vuelta (`ventasAnuladasConElVale`): la anulada sin el vale sigue
    // descontando. Si una vuelve a `ventasAnuladas(`, el stock volvería sin el vale.
    for (final ruta in [
      'lib/features/barra/cuentas/stock_de_la_barra.dart',
      'lib/features/barra/cuentas/stock_por_barra.dart',
      'lib/features/barra/cuentas/stock_para_vender.dart',
    ]) {
      final codigo = File(ruta)
          .readAsStringSync()
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(codigo, isNot(contains('ventasAnuladas(')), reason: ruta);
    }
    // Y nadie arma a mano la lista de anuladas para el stock.
    for (final f in Directory('lib/features/barra').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final ruta = f.path.replaceAll('\\', '/');
      if (ruta.endsWith('cuentas/cierre_de_barra.dart')) continue;
      final codigo = f.readAsStringSync();
      expect(RegExp(r'for \(final a in anulaciones\) a\.ventaId\}').hasMatch(codigo), isFalse, reason: ruta);
    }
  });
}
