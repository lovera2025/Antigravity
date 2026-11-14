// El historial de ventas de entradas (VENTAS, sección 8 del spec del 13-nov):
// cada venta con su anulación y su "Pago verificado", el filtro, los totales y
// los números repetidos. Sin pantalla; y el PDF, medido y leído.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

import 'package:arguello_events/features/entradas/cuentas/historial_de_entradas.dart';
import 'package:arguello_events/features/entradas/datos/entradas_repositorio.dart';
import 'package:arguello_events/features/entradas/pdf/historial_entradas_pdf.dart';
import 'package:arguello_events/models/entradas_retiro.dart';

import 'helpers/entradas_en_memoria.dart';
import 'helpers/leer_pdf.dart';

const _fiesta = 'e0000000-0000-4000-8000-000000000001';

/// Dos cajas (Carla y Maxi) con cuatro ventas: una verificada, una anulada.
class _Noche {
  final entradas = EntradasEnMemoria();
  late CajaEntradas carla, maxi;
  late VentaEntradas v1, v2, v3, v4;

  Future<VentaEntradas> _vender(
    CajaEntradas caja,
    String comprador, {
    int sueltas = 2,
    MedioBarra medio = MedioBarra.efectivo,
    String? numeros,
  }) =>
      entradas.vender(
        caja: caja,
        compradorNombre: comprador,
        renglones: [
          RenglonEntradas.suelta(
              nombre: 'Entrada', precioLista: 10000, cantidad: sueltas),
        ],
        medio: medio,
        efectivo: medio == MedioBarra.efectivo ? 10000.0 * sueltas : 0,
        transferencia: medio == MedioBarra.transferencia ? 10000.0 * sueltas : 0,
        numeros: numeros,
        quien: caja.operadorNombre!,
      );

  Future<void> armar() async {
    carla = await entradas.abrirCaja(
        eventoId: _fiesta, operadorId: 'carla', operadorNombre: 'Carla');
    maxi = await entradas.abrirCaja(
        eventoId: _fiesta, operadorId: 'maxi', operadorNombre: 'Maxi');
    v1 = await _vender(carla, 'PEREZ, ANA', numeros: '100-101');
    v2 = await _vender(carla, 'RUIZ, MARTA',
        sueltas: 4, medio: MedioBarra.transferencia, numeros: '200-203');
    v3 = await _vender(maxi, 'SOSA, DIEGO', sueltas: 1);
    v4 = await _vender(maxi, 'LEDESMA, JUAN', numeros: '203-204');
    await entradas.verificar(v1, verificado: true, quien: 'Jefe');
    await entradas.anular(v3,
        motivo: 'se equivoco de persona', devueltas: true, quien: 'Jefe');
  }

  Future<HistorialDeEntradas> historial({String? caja}) async =>
      HistorialDeEntradas.de(
        cajas: await entradas.cajas(_fiesta),
        ventas: await entradas.ventas(_fiesta),
        anulaciones: await entradas.anulaciones(_fiesta),
        verificaciones: await entradas.verificaciones(_fiesta),
        soloDeLaCaja: caja,
      );
}

void main() {
  late _Noche n;

  setUp(() async {
    n = _Noche();
    await n.armar();
  });

  group('el historial', () {
    test('el jefe ve todas las de la fiesta, de la más nueva a la más vieja', () async {
      final h = await n.historial();
      expect([for (final v in h.ventas) v.venta.compradorNombre],
          ['LEDESMA, JUAN', 'SOSA, DIEGO', 'RUIZ, MARTA', 'PEREZ, ANA']);
      expect(h.ventas.last.caja?.operadorNombre, 'Carla');
      expect(h.ventas.first.vendio, 'Maxi');
    });

    test('quien vende ve solo las de su caja, con sus cuentas', () async {
      final h = await n.historial(caja: n.carla.id);
      expect([for (final v in h.ventas) v.venta.compradorNombre],
          ['RUIZ, MARTA', 'PEREZ, ANA']);
      expect(h.totales.ventas, 2);
      expect(h.totales.efectivo, 20000);
      expect(h.totales.transferencia, 40000);
      expect(h.totales.anuladas, 0, reason: 'la anulada es de la otra caja');
    });

    test('cada venta sabe si está anulada y si tiene el pago verificado', () async {
      final h = await n.historial();
      final por = {for (final v in h.ventas) v.venta.compradorNombre: v};
      expect(por['PEREZ, ANA']!.verificada, isTrue);
      expect(por['RUIZ, MARTA']!.verificada, isFalse);
      expect(por['SOSA, DIEGO']!.anulada, isTrue);
      expect(por['SOSA, DIEGO']!.anulacion!.motivo, 'se equivoco de persona');
      expect(h.verificadas, 1);
      expect(h.sinVerificar, 2, reason: 'la anulada no espera verificación');
    });

    test('destildar deja la venta sin verificar; una anulada no cuenta como verificada',
        () async {
      await n.entradas.verificar(n.v1, verificado: false, quien: 'Jefe');
      await n.entradas.verificar(n.v3, verificado: true, quien: 'Jefe');
      final h = await n.historial();
      expect(h.verificadas, 0);
      expect(h.sinVerificar, 3);
      expect(n.entradas.listaVerificaciones, hasLength(2),
          reason: 'tildar y destildar actualiza la misma fila: no se borra');
    });

    test('el filtro: todas, verificadas y sin verificar', () async {
      final h = await n.historial();
      List<String> con(FiltroDeVentas f) =>
          [for (final v in h.con(f)) v.venta.compradorNombre];
      expect(con(FiltroDeVentas.todas), hasLength(4));
      expect(con(FiltroDeVentas.verificadas), ['PEREZ, ANA']);
      expect(con(FiltroDeVentas.sinVerificar), ['LEDESMA, JUAN', 'RUIZ, MARTA']);
    });

    test('los totales de la fiesta no cuentan la anulada', () async {
      final t = (await n.historial()).totales;
      expect(t.ventas, 3);
      expect(t.anuladas, 1);
      expect(t.entradas, 8);
      expect(t.efectivo, 40000);
      expect(t.transferencia, 40000);
      expect(t.total, 80000);
    });

    test('los números repetidos se buscan en toda la fiesta, aunque se mire una caja',
        () async {
      // El 203 está en la venta de Carla y en la de Maxi.
      final deCarla = await n.historial(caja: n.carla.id);
      expect([for (final r in deCarla.repetidos) r.texto],
          ['El 203 está en dos ventas (RUIZ, MARTA y LEDESMA, JUAN): revisar.']);
      final deTodos = await n.historial();
      expect(deTodos.repetidos, hasLength(1));
    });

    test('también avisa el número que está en una venta y en una entrega', () async {
      final h = HistorialDeEntradas.de(
        cajas: await n.entradas.cajas(_fiesta),
        ventas: [n.v1],
        anulaciones: const [],
        entregados: const {
          'ALUMNO, UNO': [TramoTalonario(95, 100)],
        },
      );
      expect(h.repetidos.single.texto,
          'El 100 está en una venta (PEREZ, ANA) y en una entrega (ALUMNO, UNO): revisar.');
    });

    test('sin ventas da todo en cero', () {
      final h = HistorialDeEntradas.de(
        cajas: const [],
        ventas: const [],
        anulaciones: const [],
      );
      expect(h.ventas, isEmpty);
      expect(h.totales.ventas, 0);
      expect(h.repetidos, isEmpty);
    });
  });

  group('el historial impreso', () {
    Future<Uint8List> pdf(HistorialDeEntradas h) => HistorialEntradasPdf.armar(
          DatosDelHistorial(
            historial: h,
            fiesta: 'INSTITUTO SAN LORENZO',
            fechaFiesta: DateTime(2026, 12, 4),
            alcance: 'Todas las cajas',
            emitido: DateTime.utc(2026, 11, 21, 13),
          ),
        );

    test('es A4, y nada se sale de la hoja', () async {
      final bytes = await pdf(await n.historial());
      expect(paginasDelPdf(bytes), 1);
      final hoja = HistorialEntradasPdf.hoja;
      expect(hoja.width, closeTo(PdfPageFormat.a4.width, 0.01));
      for (final p in palabrasDelPdf(bytes)) {
        expect(p.x, greaterThanOrEqualTo(hoja.marginLeft - 0.5),
            reason: '"${p.texto}" empieza antes del margen');
        expect(p.x + p.ancho, lessThanOrEqualTo(hoja.width - hoja.marginRight + 0.5),
            reason: '"${p.texto}" termina fuera de la hoja');
      }
    });

    test('trae todas las ventas, las anuladas con su motivo, y los totales', () async {
      final palabras = {
        for (final p in palabrasDelPdf(await pdf(await n.historial()))) p.texto,
      };
      for (final esperada in [
        'INSTITUTO', 'HISTORIAL', 'ENTRADAS', '04/12/2026',
        'PEREZ,', 'RUIZ,', 'SOSA,', 'LEDESMA,',
        'Carla', 'Maxi', 'Efectivo', 'Transferencia',
        'Anulada', 'ANULADAS', 'equivoco', 'devolvieron',
        '80.000', 'verificado', 'revisar.',
      ]) {
        expect(palabras, contains(esperada), reason: 'falta "$esperada"');
      }
    });

    test('con muchas ventas se parte en hojas, sin perder ninguna', () async {
      for (var i = 0; i < 90; i++) {
        await n._vender(n.carla, 'COMPRADOR NUMERO$i', sueltas: 1);
      }
      final bytes = await pdf(await n.historial());
      expect(paginasDelPdf(bytes), greaterThan(1));
      final palabras = {for (final p in palabrasDelPdf(bytes)) p.texto};
      expect(palabras, contains('NUMERO0'));
      expect(palabras, contains('NUMERO89'));
      expect(palabras, contains('Hoja'));
    });

    test('sin ventas lo dice', () async {
      final vacio = HistorialDeEntradas.de(
        cajas: const [],
        ventas: const [],
        anulaciones: const [],
      );
      final palabras = {for (final p in palabrasDelPdf(await pdf(vacio))) p.texto};
      expect(palabras, contains('ventas.'));
    });
  });
}
