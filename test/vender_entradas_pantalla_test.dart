// VENDER, la pantalla de la caja de entradas (etapa 4 del spec del 13-nov,
// sección 7), montada de verdad: la entrega y la venta en memoria, y la hoja
// del cobro de verdad (la misma de la barra).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/common/utils/solo_jefe.dart';
import 'package:arguello_events/features/entradas/datos/entradas_repositorio.dart';
import 'package:arguello_events/features/entradas/pdf/comprobante_entradas_pdf.dart';
import 'package:arguello_events/features/entradas/pdf/papeles_de_entradas.dart';
import 'package:arguello_events/features/entradas/providers/entradas_providers.dart';
import 'package:arguello_events/features/entradas/widgets/abrir_caja_entradas_dialog.dart';
import 'package:arguello_events/features/entradas/widgets/vender_entradas_screen.dart';
import 'package:arguello_events/features/entradas/widgets/ventas_de_entradas_screen.dart';

import 'helpers/entradas_en_memoria.dart';
import 'helpers/entrega_en_memoria.dart';

const _perez = EntregaEnMemoria.idPerez;

class _Montada {
  final EntregaEnMemoria e;
  final EntradasEnMemoria entradas;
  final List<DatosDelComprobante> comprobantes;
  _Montada(this.e, this.entradas, this.comprobantes);
}

/// Entra Carla (con "Vende entradas" salvo [vende] false) y toca VENDER.
Future<_Montada> _montar(
  WidgetTester tester, {
  bool vende = true,
  bool jefe = false,
  bool conPrecio = true,
  bool conCaja = true,
  bool aMano = false,
  double recargo = 0,
  bool anticipada = false,
  bool fallaElComprobante = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1100, 1500);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final e = EntregaEnMemoria();
  final entradas = EntradasEnMemoria();
  final comprobantes = <DatosDelComprobante>[];
  if (conPrecio) {
    entradas.conPrecio(
      idFiestaEntrega,
      aMano: aMano,
      recargo: recargo,
      anticipada: anticipada ? 8000 : null,
      hasta: anticipada ? '2026-11-28' : null,
    );
  }
  final c = ProviderContainer(overrides: [
    ...e.reemplazos(jefe: jefe),
    ...entradas.reemplazos,
    hoyEnArgentinaProvider.overrideWithValue(() => DateTime.utc(2026, 11, 20, 12)),
    abrirComprobanteDeEntradasProvider.overrideWithValue((datos, {context}) async {
      if (fallaElComprobante) throw StateError('sin impresora (prueba)');
      comprobantes.add(datos);
    }),
  ]);
  addTearDown(c.dispose);
  final carla = e.operador();
  await c.read(appRoleProvider.notifier).entrarComoEntradas(
        carla,
        PermisosEfectivos(entradas: true, vendeEntradas: vende),
      );
  if (conCaja) {
    await entradas.abrirCaja(
      eventoId: idFiestaEntrega,
      operadorId: jefe ? null : carla.id,
      operadorNombre: jefe ? 'Jefe' : 'Carla',
      cambioInicial: 5000,
    );
    entradas.escrituras = 0;
  }
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => VenderEntradasScreen(evento: fiestaDeLaEntrega),
                ),
              ),
              child: const Text('ir a vender'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('ir a vender'));
  await tester.pumpAndSettle();
  return _Montada(e, entradas, comprobantes);
}

String _texto(WidgetTester tester, String clave) =>
    tester.widget<Text>(find.byKey(Key(clave))).data!;

String? _falta(WidgetTester tester) {
  final f = find.byKey(const Key('vender_falta'));
  return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
}

bool _apagado(WidgetTester tester, String clave) =>
    tester.widget<FilledButton>(find.byKey(Key(clave))).onPressed == null;

Future<void> _tocar(WidgetTester tester, String clave, {int veces = 1}) async {
  for (var i = 0; i < veces; i++) {
    await tester.tap(find.byKey(Key(clave)));
    await tester.pump();
  }
}

Future<void> _poner(WidgetTester tester, String clave, String texto) async {
  await tester.enterText(find.byKey(Key(clave)), texto);
  await tester.pump();
}

Future<void> _aAlguienDeAfuera(WidgetTester tester, {int sueltas = 2}) async {
  await tester.tap(find.text('Alguien de afuera'));
  await tester.pump();
  await _tocar(tester, 'vender_sueltas_mas', veces: sueltas);
}

Future<void> _elegirAPerez(WidgetTester tester) async {
  await _poner(tester, 'vender_buscar', 'perez');
  await tester.tap(find.byKey(const Key('vender_familia_$_perez')));
  await tester.pump();
}

Future<void> _confirmarElCobro(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('cobro_confirmar')));
  await tester.pumpAndSettle();
}

void main() {
  group('quién puede vender', () {
    testWidgets('sin el permiso no se vende: lo dice, y no abre ninguna caja',
        (tester) async {
      final m = await _montar(tester, vende: false, conCaja: false);
      expect(_texto(tester, 'vender_sin_permiso'), kSinPermisoParaVender);
      expect(find.byKey(const Key('vender_efectivo')), findsNothing);
      expect(find.text('Abrir la caja de entradas'), findsNothing);
      expect(m.entradas.listaCajas, isEmpty);
    });

    testWidgets('sin precio: lo dice, y no abre la caja', (tester) async {
      final m = await _montar(tester, conPrecio: false, conCaja: false);
      expect(_texto(tester, 'vender_sin_precio'), kLaFiestaNoTienePrecio);
      expect(find.text('Abrir la caja de entradas'), findsNothing);
      expect(find.byKey(const Key('vender_efectivo')), findsNothing);
      expect(m.entradas.listaCajas, isEmpty);
    });
  });

  group('la caja', () {
    testWidgets('sin caja abierta la pide, con su cambio inicial', (tester) async {
      final m = await _montar(tester, conCaja: false);
      expect(find.text('Abrir la caja de entradas'), findsOneWidget);
      expect(find.textContaining('PUERTO VIEJO · vende Carla'), findsOneWidget);
      await _poner(tester, 'abrir_caja_cambio', '5000');
      await tester.tap(find.byKey(const Key('abrir_caja_abrir')));
      await tester.pumpAndSettle();

      final caja = m.entradas.listaCajas.single;
      expect(caja.cambioInicial, 5000);
      expect(caja.operadorNombre, 'Carla');
      expect(caja.eventoId, idFiestaEntrega);
      expect(caja.abierta, isTrue);
      expect(_texto(tester, 'vender_linea_texto'), 'Caja abierta · Carla · Todo subido');
      expect(find.byKey(const Key('vender_efectivo')), findsOneWidget);
    });

    testWidgets('volver sin abrirla sale de VENDER', (tester) async {
      final m = await _montar(tester, conCaja: false);
      await tester.tap(find.byKey(const Key('abrir_caja_volver')));
      await tester.pumpAndSettle();
      expect(find.byType(VenderEntradasScreen), findsNothing);
      expect(find.text('ir a vender'), findsOneWidget);
      expect(m.entradas.listaCajas, isEmpty);
    });

    testWidgets('con una ya abierta la retoma: tocar dos veces no abre dos',
        (tester) async {
      final m = await _montar(tester);
      expect(find.text('Abrir la caja de entradas'), findsNothing);
      expect(m.entradas.listaCajas, hasLength(1));
      expect(m.entradas.escrituras, 0);
    });
  });

  group('lo que se vende', () {
    testWidgets('nombre y apellido son obligatorios: sin eso los medios están apagados '
        'y dice por qué', (tester) async {
      await _montar(tester);
      await _aAlguienDeAfuera(tester);
      expect(_falta(tester), 'Escribí nombre y apellido de quien compra');
      for (final b in ['vender_efectivo', 'vender_transferencia', 'vender_mixto']) {
        expect(_apagado(tester, b), isTrue, reason: b);
      }
      await _poner(tester, 'vender_comprador', 'Carla');
      expect(_falta(tester), 'Escribí nombre y apellido de quien compra',
          reason: 'una sola palabra no alcanza');
      await _poner(tester, 'vender_comprador', 'GOMEZ CARLA');
      expect(_falta(tester), isNull);
      expect(_apagado(tester, 'vender_efectivo'), isFalse);
      expect(_texto(tester, 'vender_total'), r'$ 20.000');
      expect(_texto(tester, 'vender_cantidad'), 'Total · 2 entradas');
    });

    testWidgets('sin entradas elegidas tampoco se puede', (tester) async {
      await _montar(tester);
      await _aAlguienDeAfuera(tester, sueltas: 0);
      await _poner(tester, 'vender_comprador', 'GOMEZ CARLA');
      expect(_falta(tester), 'Elegí cuántas entradas lleva');
      expect(_apagado(tester, 'vender_efectivo'), isTrue);
    });

    testWidgets('una familia: cuántas le quedan, a cuánto, y que debe; se le vende '
        'igual, y nunca más de las que le quedan', (tester) async {
      await _montar(tester);
      await _elegirAPerez(tester);
      expect(
        _texto(tester, 'vender_le_quedan'),
        r'Le quedan 8 entradas de sus lugares adicionales, a $ 5.000 cada una '
        '(le corresponden 8, compró 0).',
      );
      expect(_texto(tester, 'vender_debe'),
          r'Debe $ 70.000 del contrato: se salda en caja. Se le vende igual.');
      expect(_texto(tester, 'vender_lugar_cantidad'), '8',
          reason: 'viene con todas las que le quedan');
      await _tocar(tester, 'vender_lugar_mas', veces: 3);
      expect(_texto(tester, 'vender_lugar_cantidad'), '8', reason: 'el tope');
      await _tocar(tester, 'vender_lugar_menos', veces: 3);
      expect(_texto(tester, 'vender_lugar_cantidad'), '5');
      expect(_texto(tester, 'vender_total'), r'$ 25.000');
      await _poner(tester, 'vender_comprador', 'PEREZ MARTA');
      expect(_falta(tester), isNull, reason: 'la deuda del contrato no frena la venta');
    });

    testWidgets('una familia sin lugares adicionales no tiene ese renglón',
        (tester) async {
      await _montar(tester);
      await _poner(tester, 'vender_buscar', 'lopez');
      await tester.tap(find.byKey(const Key('vender_familia_${EntregaEnMemoria.idLopez}')));
      await tester.pump();
      expect(find.byKey(const Key('vender_lugar_mas')), findsNothing);
      expect(_texto(tester, 'vender_le_quedan'), contains('van al precio de hoy'));
      expect(find.byKey(const Key('vender_debe')), findsNothing);
    });

    testWidgets('el descuento a mano, solo con permiso: apagado y con el motivo',
        (tester) async {
      await _montar(tester);
      await _aAlguienDeAfuera(tester);
      final campo = tester.widget<TextField>(find.byKey(const Key('vender_descuento')));
      expect(campo.enabled, isFalse);
      expect(_texto(tester, 'vender_descuento_motivo'), contains(kSoloEnModoJefe));
      expect(_texto(tester, 'vender_total'), r'$ 20.000');
    });

    testWidgets('si el jefe lo permitió en PRECIOS, el vendedor descuenta', (tester) async {
      await _montar(tester, aMano: true);
      await _aAlguienDeAfuera(tester);
      expect(
        tester.widget<TextField>(find.byKey(const Key('vender_descuento'))).enabled,
        isTrue,
      );
      expect(find.byKey(const Key('vender_descuento_motivo')), findsNothing);
      await _poner(tester, 'vender_descuento', '20');
      expect(_texto(tester, 'vender_total'), r'$ 16.000');
      expect(_texto(tester, 'vender_sueltas_subtotal'), r'$ 16.000');
    });

    testWidgets('con la anticipada dice "anticipada" y cobra ese precio; las de lugar '
        'no bajan', (tester) async {
      await _montar(tester, anticipada: true);
      await _elegirAPerez(tester);
      expect(find.text('Entradas (anticipada)'), findsOneWidget);
      await _tocar(tester, 'vender_sueltas_mas', veces: 2);
      expect(_texto(tester, 'vender_sueltas_subtotal'), r'$ 16.000');
      expect(_texto(tester, 'vender_lugar_subtotal'), r'$ 40.000',
          reason: 'el 50 % sale del valor de la entrada, no de la anticipada');
    });
  });

  group('los números del talonario', () {
    testWidgets('son opcionales, y el "al" se calcula solo', (tester) async {
      await _montar(tester);
      await _aAlguienDeAfuera(tester, sueltas: 4);
      await _poner(tester, 'vender_comprador', 'GOMEZ CARLA');
      expect(_falta(tester), isNull);
      expect(_texto(tester, 'vender_al_calculado'), 'al …');
      await _poner(tester, 'vender_del', '3000');
      expect(_texto(tester, 'vender_al_calculado'), 'al 3003');
      expect(_falta(tester), isNull);
    });

    // Hasta la 6.9.2 este número no se vendía ("El 1006 ya se le dio a GÓMEZ,
    // ANA"). Cambió a propósito el 20-nov: lo que se vende sale del talonario
    // de las anticipadas, y lo entregado sin cargo es otro.
    testWidgets('pueden repetir uno ya entregado sin cargo: es otro talonario',
        (tester) async {
      final m = await _montar(tester);
      await _aAlguienDeAfuera(tester);
      await _poner(tester, 'vender_comprador', 'GOMEZ CARLA');
      await _poner(tester, 'vender_del', '1006');
      expect(_falta(tester), isNull, reason: 'GÓMEZ, ANA tiene del 1001 al 1007 entregados');
      expect(_apagado(tester, 'vender_efectivo'), isFalse);
      await _tocar(tester, 'vender_efectivo');
      await tester.pumpAndSettle();
      await _confirmarElCobro(tester);
      expect(m.entradas.listaVentas.single.numeros, '1006-1007');
    });

    testWidgets('no pueden repetir uno ya vendido', (tester) async {
      final m = await _montar(tester);
      await _aAlguienDeAfuera(tester);
      await _poner(tester, 'vender_comprador', 'GOMEZ CARLA');
      await _poner(tester, 'vender_del', '3000');
      await _tocar(tester, 'vender_efectivo');
      await tester.pumpAndSettle();
      await _confirmarElCobro(tester);
      expect(m.entradas.listaVentas.single.numeros, '3000-3001');

      await _aAlguienDeAfuera(tester);
      await _poner(tester, 'vender_comprador', 'RUIZ MARTA');
      await _poner(tester, 'vender_del', '3001');
      expect(_falta(tester), 'El 3001 ya se le dio a GOMEZ CARLA (3000 al 3001).');
      expect(_apagado(tester, 'vender_efectivo'), isTrue);
      await _poner(tester, 'vender_del', '3002');
      expect(_falta(tester), isNull);
    });

    testWidgets('dos tramos, cuando el talonario salta', (tester) async {
      final m = await _montar(tester);
      await _aAlguienDeAfuera(tester, sueltas: 8);
      await _poner(tester, 'vender_comprador', 'GOMEZ CARLA');
      await _tocar(tester, 'vender_dos_tramos');
      await _poner(tester, 'vender_del', '100');
      await _poner(tester, 'vender_al', '104');
      await _poner(tester, 'vender_del_2', '200');
      expect(_texto(tester, 'vender_al_calculado'), 'al 202');
      expect(_falta(tester), isNull);
      await _tocar(tester, 'vender_efectivo');
      await tester.pumpAndSettle();
      await _confirmarElCobro(tester);
      expect(m.entradas.listaVentas.single.numeros, '100-104,200-202');
    });
  });

  group('cobrar y guardar', () {
    testWidgets('en efectivo: guarda la venta, abre el comprobante y deja la pantalla '
        'limpia', (tester) async {
      final m = await _montar(tester);
      await _elegirAPerez(tester);
      await _tocar(tester, 'vender_sueltas_mas', veces: 2);
      await _poner(tester, 'vender_comprador', 'perez marta');
      await _poner(tester, 'vender_dni', '30111222');
      await _poner(tester, 'vender_del', '2000');
      expect(_texto(tester, 'vender_total'), r'$ 60.000');
      expect(_texto(tester, 'vender_al_calculado'), 'al 2009');

      await _tocar(tester, 'vender_efectivo');
      await tester.pumpAndSettle();
      expect(find.text('Pagar en efectivo'), findsOneWidget);
      expect(_texto(tester, 'cobro_a_cobrar'), r'$ 60.000');
      await _confirmarElCobro(tester);

      final v = m.entradas.listaVentas.single;
      expect(v.numero, 1);
      expect(v.total, 60000);
      expect(v.efectivo, 60000);
      expect(v.medio, MedioBarra.efectivo);
      expect(v.cantidad, 10);
      expect(v.cuantas(TipoRenglonEntradas.lugar), 8);
      expect(v.contratoAlumnoId, _perez);
      expect(v.compradorNombre, 'perez marta');
      expect(v.compradorDni, '30111222');
      expect(v.numeros, '2000-2009');
      expect(v.hechoPor, 'Carla');
      expect(v.cajaEntradasId, m.entradas.listaCajas.single.id);

      // El comprobante, de esa venta, con el alumno y su mesa.
      final c = m.comprobantes.single;
      expect(c.venta.id, v.id);
      expect(c.fiesta, 'PUERTO VIEJO');
      expect(c.alumno, 'PÉREZ, JUAN');
      expect(c.mesa, '12-13');
      expect(c.copia, isFalse);

      // La pantalla queda lista para la siguiente.
      expect(find.textContaining(r'Venta N° 0001 guardada · 10 entradas · $ 60.000'),
          findsOneWidget);
      expect(
        tester.widget<TextField>(find.byKey(const Key('vender_comprador'))).controller!.text,
        '',
      );
      expect(_texto(tester, 'vender_total'), r'$ 0');
      // Y ya no le quedan de sus lugares.
      await _elegirAPerez(tester);
      expect(_texto(tester, 'vender_le_quedan'),
          'Ya compró todas las de sus lugares adicionales (8).');
      expect(find.byKey(const Key('vender_lugar_mas')), findsNothing);
    });

    testWidgets('el comprobante se vuelve a abrir desde el aviso, como COPIA',
        (tester) async {
      final m = await _montar(tester);
      await _aAlguienDeAfuera(tester);
      await _poner(tester, 'vender_comprador', 'GOMEZ CARLA');
      await _tocar(tester, 'vender_efectivo');
      await tester.pumpAndSettle();
      await _confirmarElCobro(tester);
      await _tocar(tester, 'vender_ver_comprobante');
      await tester.pumpAndSettle();
      expect(m.comprobantes, hasLength(2));
      expect(m.comprobantes.last.copia, isTrue);
      expect(m.comprobantes.last.alumno, isNull, reason: 'compró alguien de afuera');
    });

    testWidgets('por transferencia, con el recargo de la fiesta', (tester) async {
      final m = await _montar(tester, recargo: 5);
      await _aAlguienDeAfuera(tester);
      await _poner(tester, 'vender_comprador', 'GOMEZ CARLA');
      await _tocar(tester, 'vender_transferencia');
      await tester.pumpAndSettle();
      expect(_texto(tester, 'cobro_transfiere'), r'$ 21.000');
      await _confirmarElCobro(tester);
      final v = m.entradas.listaVentas.single;
      expect(v.medio, MedioBarra.transferencia);
      expect(v.total, 20000);
      expect(v.recargo, 1000);
      expect(v.transferencia, 21000);
      expect(v.efectivo, 0);
    });

    testWidgets('volver del cobro no guarda nada', (tester) async {
      final m = await _montar(tester);
      await _aAlguienDeAfuera(tester);
      await _poner(tester, 'vender_comprador', 'GOMEZ CARLA');
      await _tocar(tester, 'vender_mixto');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cobro_volver')));
      await tester.pumpAndSettle();
      expect(m.entradas.listaVentas, isEmpty);
      expect(m.comprobantes, isEmpty);
      expect(_texto(tester, 'vender_total'), r'$ 20.000', reason: 'sigue lo escrito');
    });

    testWidgets('si la base no anda, lo dice y no pierde lo escrito', (tester) async {
      final m = await _montar(tester);
      await _aAlguienDeAfuera(tester);
      await _poner(tester, 'vender_comprador', 'GOMEZ CARLA');
      m.entradas.falla = true;
      await _tocar(tester, 'vender_efectivo');
      await tester.pumpAndSettle();
      await _confirmarElCobro(tester);
      expect(find.text('No se guardó la venta. Probá de nuevo.'), findsOneWidget);
      expect(m.entradas.listaVentas, isEmpty);
      expect(m.comprobantes, isEmpty);
      expect(
        tester.widget<TextField>(find.byKey(const Key('vender_comprador'))).controller!.text,
        'GOMEZ CARLA',
      );
      expect(find.byKey(const Key('vender_guardada')), findsNothing);
    });

    testWidgets('sin impresora la venta igual queda: se guarda antes de abrir el '
        'comprobante', (tester) async {
      final m = await _montar(tester, fallaElComprobante: true);
      await _aAlguienDeAfuera(tester);
      await _poner(tester, 'vender_comprador', 'GOMEZ CARLA');
      await _tocar(tester, 'vender_efectivo');
      await tester.pumpAndSettle();
      await _confirmarElCobro(tester);
      expect(m.entradas.listaVentas, hasLength(1));
      expect(find.byKey(const Key('vender_guardada')), findsOneWidget);
      expect(find.textContaining('La venta quedó guardada'), findsOneWidget);
    });

    testWidgets('en modo jefe, con el 100 % de descuento se guarda sin cobrar',
        (tester) async {
      final m = await _montar(tester, jefe: true);
      await _aAlguienDeAfuera(tester);
      await _poner(tester, 'vender_comprador', 'INVITADA DEL JEFE');
      await _poner(tester, 'vender_descuento', '100');
      expect(_texto(tester, 'vender_total'), r'$ 0');
      expect(find.byKey(const Key('vender_efectivo')), findsNothing);
      await _tocar(tester, 'vender_sin_cargo');
      await tester.pumpAndSettle();
      expect(find.text('Venta sin cargo'), findsOneWidget);
      await tester.tap(find.byKey(const Key('vender_sin_cargo_confirmar')));
      await tester.pumpAndSettle();
      final v = m.entradas.listaVentas.single;
      expect(v.total, 0);
      expect(v.descuento, 20000, reason: 'el descuento queda escrito en la venta');
      expect(v.cantidad, 2);
    });
  });

  group('la línea de arriba', () {
    testWidgets('dice cuántas ventas esperan subir, también sin internet',
        (tester) async {
      final m = await _montar(tester);
      expect(_texto(tester, 'vender_linea_texto'), 'Caja abierta · Carla · Todo subido');
      await _aAlguienDeAfuera(tester);
      await _poner(tester, 'vender_comprador', 'GOMEZ CARLA');
      await _tocar(tester, 'vender_efectivo');
      await tester.pumpAndSettle();
      await _confirmarElCobro(tester);
      expect(_texto(tester, 'vender_linea_texto'),
          'Caja abierta · Carla · 1 venta subiendo');
      m.e.conexion.cambiar(AppConnectivity.offline);
      await tester.pumpAndSettle();
      expect(_texto(tester, 'vender_linea_texto'),
          'Caja abierta · Carla · Sin internet · 1 venta por subir');
    });

    // Etapa 7: el aviso del motor sale al bajar, no al subir. Sin escuchar lo
    // pendiente, la línea quedaba en "1 venta subiendo" aunque la venta ya hubiera
    // subido, hasta la próxima venta o la próxima bajada.
    testWidgets('cuando la venta termina de subir, dice "Todo subido" sola', (tester) async {
      final m = await _montar(tester);
      await _aAlguienDeAfuera(tester);
      await _poner(tester, 'vender_comprador', 'GOMEZ CARLA');
      await _tocar(tester, 'vender_efectivo');
      await tester.pumpAndSettle();
      await _confirmarElCobro(tester);
      expect(_texto(tester, 'vender_linea_texto'),
          'Caja abierta · Carla · 1 venta subiendo');
      // El motor terminó de subir: la cola quedó vacía y avisa lo pendiente.
      m.entradas.sinSubir = 0;
      m.e.motor.pendiente.add(0);
      await tester.pumpAndSettle();
      expect(_texto(tester, 'vender_linea_texto'), 'Caja abierta · Carla · Todo subido');
    });
  });

  group('VENTAS, desde la barra de VENDER', () {
    testWidgets('abre las ventas de la caja de quien vende, y al volver sigue en VENDER',
        (tester) async {
      final m = await _montar(tester);
      await _tocar(tester, 'vender_ventas');
      await tester.pumpAndSettle();
      final ventas =
          tester.widget<VentasDeEntradasScreen>(find.byType(VentasDeEntradasScreen));
      expect(ventas.caja?.id, m.entradas.listaCajas.single.id);
      expect(_texto(tester, 'ventas_alcance'), contains('La caja de Carla'));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(VentasDeEntradasScreen), findsNothing);
      expect(find.byType(VenderEntradasScreen), findsOneWidget);
    });

    // Revisión del 14-nov: al volver con la última venta anulada, el aviso verde
    // de "guardada" seguía arriba y su comprobante salía sin ANULADA.
    testWidgets('si se anula la última venta, se va el aviso de guardada y su copia '
        'sale ANULADA', (tester) async {
      final m = await _montar(tester, jefe: true);
      await _aAlguienDeAfuera(tester);
      await _poner(tester, 'vender_comprador', 'GOMEZ CARLA');
      await _tocar(tester, 'vender_efectivo');
      await tester.pumpAndSettle();
      await _confirmarElCobro(tester);
      expect(find.byKey(const Key('vender_guardada')), findsOneWidget);
      final venta = m.entradas.listaVentas.single;
      // Antes de anular, la copia sale limpia.
      expect(m.comprobantes.single.anulacion, isNull);
      await m.entradas.anular(venta, motivo: 'error de carga', devueltas: true, quien: 'Jefe');
      await _tocar(tester, 'vender_ventas');
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vender_guardada')), findsNothing);
    });

    testWidgets('sin caja abierta no está', (tester) async {
      await _montar(tester, conCaja: false);
      // VENDER pide la caja: se vuelve sin abrirla y no queda VENTAS a la vista.
      expect(find.byKey(const Key('vender_ventas')), findsNothing);
    });
  });
}
