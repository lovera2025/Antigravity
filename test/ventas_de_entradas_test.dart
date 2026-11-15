// VENTAS, el historial de la venta de entradas (etapa 5 del spec del 13-nov,
// sección 8), montada de verdad con la entrega y la venta en memoria: quién ve
// qué, "Pago verificado" y ANULAR solo del jefe, reimprimir y el historial.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/common/utils/solo_jefe.dart';
import 'package:arguello_events/features/entradas/datos/entradas_repositorio.dart';
import 'package:arguello_events/features/entradas/pdf/comprobante_entradas_pdf.dart';
import 'package:arguello_events/features/entradas/pdf/historial_entradas_pdf.dart';
import 'package:arguello_events/features/entradas/pdf/papeles_de_entradas.dart';
import 'package:arguello_events/features/entradas/widgets/ventas_de_entradas_screen.dart';

import 'helpers/entradas_en_memoria.dart';
import 'helpers/entrega_en_memoria.dart';

class _Montada {
  final EntradasEnMemoria entradas;
  final List<DatosDelComprobante> comprobantes;
  final List<DatosDelHistorial> historiales;
  final CajaEntradas carla;
  final VentaEntradas v1, v2, v3;
  _Montada(this.entradas, this.comprobantes, this.historiales, this.carla,
      this.v1, this.v2, this.v3);
}

Future<VentaEntradas> _vender(
  EntradasEnMemoria entradas,
  CajaEntradas caja,
  String comprador, {
  int sueltas = 2,
  MedioBarra medio = MedioBarra.efectivo,
  String? numeros,
  String? familia,
}) =>
    entradas.vender(
      caja: caja,
      contratoAlumnoId: familia,
      compradorNombre: comprador,
      renglones: [
        RenglonEntradas.suelta(nombre: 'Entrada', precioLista: 10000, cantidad: sueltas),
      ],
      medio: medio,
      efectivo: medio == MedioBarra.efectivo ? 10000.0 * sueltas : 0,
      transferencia: medio == MedioBarra.transferencia ? 10000.0 * sueltas : 0,
      numeros: numeros,
      quien: caja.operadorNombre!,
    );

/// Dos cajas: la de Carla (dos ventas) y la de Maxi (una). [jefe]: mira el
/// jefe en modo jefe; si no, Carla, con su caja.
Future<_Montada> _montar(
  WidgetTester tester, {
  bool jefe = false,
  bool conVentas = true,
  Size tamano = const Size(1200, 1300),
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final e = EntregaEnMemoria();
  final entradas = EntradasEnMemoria()..conPrecio(idFiestaEntrega);
  final comprobantes = <DatosDelComprobante>[];
  final historiales = <DatosDelHistorial>[];
  final c = ProviderContainer(overrides: [
    ...e.reemplazos(jefe: jefe),
    ...entradas.reemplazos,
    abrirComprobanteDeEntradasProvider
        .overrideWithValue((datos, {context}) async => comprobantes.add(datos)),
    abrirHistorialDeEntradasProvider
        .overrideWithValue((datos, {context}) async => historiales.add(datos)),
  ]);
  addTearDown(c.dispose);
  final operadora = e.operador();
  await c.read(appRoleProvider.notifier).entrarComoEntradas(
        operadora,
        const PermisosEfectivos(entradas: true, vendeEntradas: true),
      );
  final carla = await entradas.abrirCaja(
    eventoId: idFiestaEntrega,
    operadorId: operadora.id,
    operadorNombre: 'Carla',
  );
  final maxi = await entradas.abrirCaja(
    eventoId: idFiestaEntrega,
    operadorId: 'maxi',
    operadorNombre: 'Maxi',
  );
  late VentaEntradas v1, v2, v3;
  if (conVentas) {
    v1 = await _vender(entradas, carla, 'PEREZ MARTA',
        numeros: '2000-2001', familia: EntregaEnMemoria.idPerez);
    v2 = await _vender(entradas, carla, 'RUIZ MARTA',
        sueltas: 4, medio: MedioBarra.transferencia);
    v3 = await _vender(entradas, maxi, 'SOSA DIEGO', sueltas: 1, numeros: '2001');
  }
  entradas.escrituras = 0;
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      home: VentasDeEntradasScreen(evento: fiestaDeLaEntrega, caja: carla),
    ),
  ));
  await tester.pumpAndSettle();
  return conVentas
      ? _Montada(entradas, comprobantes, historiales, carla, v1, v2, v3)
      : _Montada(entradas, comprobantes, historiales, carla,
          _nada, _nada, _nada);
}

/// Relleno para el caso sin ventas: no se usa.
final _nada = VentaEntradas.nueva(
  cajaEntradasId: 'x',
  eventoId: 'x',
  numero: 1,
  compradorNombre: 'NADIE NADIE',
  renglones: [
    RenglonEntradas.suelta(nombre: 'Entrada', precioLista: 1, cantidad: 1),
  ],
  medio: MedioBarra.efectivo,
  efectivo: 1,
  ahora: DateTime.utc(2026),
);

String _texto(WidgetTester tester, String clave) =>
    tester.widget<Text>(find.byKey(Key(clave))).data!;

Future<void> _tocar(WidgetTester tester, String clave) async {
  await tester.ensureVisible(find.byKey(Key(clave)));
  await tester.tap(find.byKey(Key(clave)));
  await tester.pumpAndSettle();
}

void main() {
  group('quién ve qué', () {
    testWidgets('quien vende ve solo las de su caja, con "Pago verificado" y ANULAR '
        'apagados y el motivo', (tester) async {
      final m = await _montar(tester);
      expect(_texto(tester, 'ventas_alcance'), 'PUERTO VIEJO · La caja de Carla');
      expect(find.byKey(Key('venta_${m.v1.id}')), findsOneWidget);
      expect(find.byKey(Key('venta_${m.v2.id}')), findsOneWidget);
      expect(find.byKey(Key('venta_${m.v3.id}')), findsNothing,
          reason: 'la de Maxi es de otra caja');
      // Sin sumas de plata: cuenta su caja a ciegas (revisión del 14-nov).
      expect(_texto(tester, 'ventas_totales'),
          '2 ventas · 6 entradas · pago verificado: 0 de 2');

      final tilde = tester.widget<Checkbox>(find.byKey(Key('verificar_${m.v1.id}')));
      expect(tilde.onChanged, isNull);
      final anular = tester.widget<TextButton>(find.byKey(Key('anular_${m.v1.id}')));
      expect(anular.onPressed, isNull);
      expect(_texto(tester, 'ventas_motivo'), contains(kSoloEnModoJefe));
      // Reimprimir sí puede.
      final reimprimir =
          tester.widget<TextButton>(find.byKey(Key('reimprimir_${m.v1.id}')));
      expect(reimprimir.onPressed, isNotNull);
      // Tocar lo apagado no escribe nada.
      await tester.tap(find.byKey(Key('verificar_${m.v1.id}')), warnIfMissed: false);
      await tester.tap(find.byKey(Key('anular_${m.v1.id}')), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(m.entradas.escrituras, 0);
    });

    testWidgets('el jefe ve todas las de la fiesta, de la más nueva a la más vieja',
        (tester) async {
      final m = await _montar(tester, jefe: true);
      expect(_texto(tester, 'ventas_alcance'), 'PUERTO VIEJO · Todas las cajas');
      for (final v in [m.v1, m.v2, m.v3]) {
        expect(find.byKey(Key('venta_${v.id}')), findsOneWidget);
      }
      expect(_texto(tester, 'ventas_totales'),
          r'3 ventas · 7 entradas · $ 70.000 · pago verificado: 0 de 3');
      expect(find.byKey(const Key('ventas_motivo')), findsNothing);
      final arriba = tester.getTopLeft(find.byKey(Key('venta_${m.v3.id}'))).dy;
      final abajo = tester.getTopLeft(find.byKey(Key('venta_${m.v1.id}'))).dy;
      expect(arriba, lessThan(abajo));
    });

    testWidgets('el número que quedó en dos ventas se avisa arriba, también a quien '
        'mira solo su caja', (tester) async {
      await _montar(tester);
      expect(
        find.text('El 2001 está en dos ventas (PEREZ MARTA y SOSA DIEGO): revisar.'),
        findsOneWidget,
      );
    });

    testWidgets('sin ventas lo dice', (tester) async {
      await _montar(tester, conVentas: false);
      expect(_texto(tester, 'ventas_vacio'), 'Todavía no hay ventas.');
    });
  });

  group('Pago verificado, solo el jefe', () {
    testWidgets('lo tilda y queda quién; destildar actualiza la misma fila',
        (tester) async {
      final m = await _montar(tester, jefe: true);
      await _tocar(tester, 'verificar_${m.v1.id}');
      final fila = m.entradas.listaVerificaciones.single;
      expect(fila.ventaId, m.v1.id);
      expect(fila.verificado, isTrue);
      expect(fila.hechoPor, isNotEmpty);
      expect(tester.widget<Checkbox>(find.byKey(Key('verificar_${m.v1.id}'))).value,
          isTrue);
      expect(_texto(tester, 'ventas_totales'), contains('pago verificado: 1 de 3'));

      await _tocar(tester, 'verificar_${m.v1.id}');
      expect(m.entradas.listaVerificaciones.single.verificado, isFalse);
      expect(_texto(tester, 'ventas_totales'), contains('pago verificado: 0 de 3'));
      // La venta no se tocó.
      expect(m.entradas.listaVentas.first.toMap(), m.v1.toMap());
    });

    testWidgets('el filtro: verificadas y sin verificar', (tester) async {
      final m = await _montar(tester, jefe: true);
      await _tocar(tester, 'verificar_${m.v1.id}');
      await tester.tap(find.text('Verificadas'));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('venta_${m.v1.id}')), findsOneWidget);
      expect(find.byKey(Key('venta_${m.v2.id}')), findsNothing);
      await tester.tap(find.text('Sin verificar'));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('venta_${m.v1.id}')), findsNothing);
      expect(find.byKey(Key('venta_${m.v2.id}')), findsOneWidget);
      expect(find.byKey(Key('venta_${m.v3.id}')), findsOneWidget);
    });
  });

  group('ANULAR, solo el jefe', () {
    testWidgets('pide el motivo y si devolvieron las entradas; la venta queda en la '
        'lista, tachada, con todo', (tester) async {
      final m = await _montar(tester, jefe: true);
      await _tocar(tester, 'anular_${m.v1.id}');
      expect(find.text('Anular la venta N° 0001'), findsOneWidget);
      expect(find.textContaining('(2000 al 2001)'), findsOneWidget,
          reason: 'los números, a la vista');

      await _tocar(tester, 'anular_confirmar');
      expect(_texto(tester, 'anular_problema'), 'Escribí por qué se anula.');
      await tester.enterText(find.byKey(const Key('anular_motivo')), 'se equivocó');
      await tester.pump();
      await _tocar(tester, 'anular_confirmar');
      expect(_texto(tester, 'anular_problema'),
          'Decí si devolvieron las entradas y las pulseras.');
      expect(m.entradas.listaAnulaciones, isEmpty);

      await _tocar(tester, 'anular_devolvieron_no');
      await _tocar(tester, 'anular_confirmar');

      final a = m.entradas.listaAnulaciones.single;
      expect(a.ventaId, m.v1.id);
      expect(a.motivo, 'se equivocó');
      expect(a.devueltas, isFalse);
      expect(a.hechoPor, isNotEmpty);
      // La venta sigue, sin tocar, y en la lista.
      expect(m.entradas.listaVentas.first.toMap(), m.v1.toMap());
      expect(find.byKey(Key('venta_${m.v1.id}')), findsOneWidget);
      expect(_texto(tester, 'anulada_${m.v1.id}'), contains('se equivocó'));
      expect(_texto(tester, 'anulada_${m.v1.id}'),
          contains('NO devolvieron las entradas: esos números quedan anulados'));
      // Ya no se verifica ni se vuelve a anular.
      expect(find.byKey(Key('verificar_${m.v1.id}')), findsNothing);
      expect(find.byKey(Key('anular_${m.v1.id}')), findsNothing);
      expect(_texto(tester, 'ventas_totales'),
          r'2 ventas · 5 entradas · $ 50.000 · 1 anulada · pago verificado: 0 de 2');
    });

    testWidgets('con las entradas devueltas lo dice así', (tester) async {
      final m = await _montar(tester, jefe: true);
      await _tocar(tester, 'anular_${m.v2.id}');
      await tester.enterText(find.byKey(const Key('anular_motivo')), 'pagó dos veces');
      await tester.pump();
      await _tocar(tester, 'anular_devolvieron_si');
      await _tocar(tester, 'anular_confirmar');
      expect(m.entradas.listaAnulaciones.single.devueltas, isTrue);
      expect(_texto(tester, 'anulada_${m.v2.id}'),
          contains('devolvieron las entradas y pulseras'));
    });

    testWidgets('volver del cartel no anula nada', (tester) async {
      final m = await _montar(tester, jefe: true);
      await _tocar(tester, 'anular_${m.v1.id}');
      await tester.enterText(find.byKey(const Key('anular_motivo')), 'me arrepentí');
      await _tocar(tester, 'anular_volver');
      expect(m.entradas.listaAnulaciones, isEmpty);
      expect(m.entradas.escrituras, 0);
      expect(find.byKey(Key('anular_${m.v1.id}')), findsOneWidget);
    });
  });

  group('los papeles', () {
    testWidgets('REIMPRIMIR abre el comprobante como COPIA, con la familia; anulada, '
        'lo lleva cruzado', (tester) async {
      final m = await _montar(tester, jefe: true);
      await _tocar(tester, 'reimprimir_${m.v1.id}');
      final c = m.comprobantes.single;
      expect(c.venta.id, m.v1.id);
      expect(c.copia, isTrue);
      expect(c.alumno, 'PÉREZ, JUAN');
      expect(c.mesa, '12-13');
      expect(c.anulacion, isNull);

      await _tocar(tester, 'anular_${m.v1.id}');
      await tester.enterText(find.byKey(const Key('anular_motivo')), 'se equivocó');
      await tester.pump();
      await _tocar(tester, 'anular_devolvieron_si');
      await _tocar(tester, 'anular_confirmar');
      await _tocar(tester, 'reimprimir_${m.v1.id}');
      expect(m.comprobantes.last.anulacion?.motivo, 'se equivocó');
    });

    testWidgets('IMPRIMIR HISTORIAL arma el papel con lo que se está mirando',
        (tester) async {
      final m = await _montar(tester);
      await _tocar(tester, 'ventas_imprimir');
      final h = m.historiales.single;
      expect(h.alcance, 'La caja de Carla');
      expect(h.conPlata, isFalse, reason: 'quien vende cuenta a ciegas');
      expect(h.fiesta, 'PUERTO VIEJO');
      expect(h.historial.ventas, hasLength(2));
      expect(h.historial.repetidos, hasLength(1));
    });

    testWidgets('el del jefe trae todas las cajas', (tester) async {
      final m = await _montar(tester, jefe: true);
      await _tocar(tester, 'ventas_imprimir');
      expect(m.historiales.single.alcance, 'Todas las cajas');
      expect(m.historiales.single.conPlata, isTrue);
      expect(m.historiales.single.historial.ventas, hasLength(3));
    });

    // En un celular, con el texto IMPRIMIR HISTORIAL el título se cortaba
    // ("Ventas de e…"): va el ícono, que deja lugar, y hace lo mismo. Que el
    // título entra entero se mira en la muestra, con la letra de la app (la de
    // las pruebas es mucho más ancha).
    testWidgets('en un celular es un ícono chico, nada se desborda, y abre el papel',
        (tester) async {
      final m = await _montar(tester, jefe: true, tamano: const Size(390, 1250));
      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byKey(const Key('ventas_imprimir')),
          matching: find.byIcon(Icons.print_outlined),
        ),
        findsOneWidget,
      );
      expect(find.text('IMPRIMIR HISTORIAL'), findsNothing);
      expect(tester.getSize(find.byKey(const Key('ventas_imprimir'))).width,
          lessThanOrEqualTo(48));
      await _tocar(tester, 'ventas_imprimir');
      expect(m.historiales.single.alcance, 'Todas las cajas');
    });
  });
}
