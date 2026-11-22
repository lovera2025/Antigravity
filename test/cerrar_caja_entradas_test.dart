// Cerrar la caja de entradas (sección 9.1 del spec del 13-nov): CERRAR CAJA en
// VENDER, contar a ciegas, cerrar con la diferencia anotada, el papel del
// cierre (media A4, con la forma del recibo de las cuotas y sin la diferencia,
// desde el 22-nov-2026) y la nota. Montada de verdad, con la venta en memoria.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/common/services/pdf_service.dart';
import 'package:arguello_events/features/entradas/cuentas/cierre_de_entradas.dart';
import 'package:arguello_events/features/entradas/datos/entradas_repositorio.dart';
import 'package:arguello_events/features/entradas/pdf/cierre_caja_entradas_pdf.dart';
import 'package:arguello_events/features/entradas/pdf/papeles_de_entradas.dart';
import 'package:arguello_events/features/entradas/pdf/recibo_de_entradas_pdf.dart';
import 'package:arguello_events/features/entradas/providers/entradas_providers.dart';
import 'package:arguello_events/features/entradas/widgets/abrir_caja_entradas_dialog.dart';
import 'package:arguello_events/features/entradas/widgets/cerrar_caja_entradas_screen.dart';
import 'package:arguello_events/features/entradas/widgets/vender_entradas_screen.dart';

import 'helpers/entradas_en_memoria.dart';
import 'helpers/entrega_en_memoria.dart';
import 'helpers/leer_pdf.dart';

class _Montada {
  final EntregaEnMemoria e;
  final EntradasEnMemoria entradas;
  final CajaEntradas caja;
  final List<DatosDelCierreDeEntradas> papeles;
  final ProviderContainer c;
  _Montada(this.e, this.entradas, this.caja, this.papeles, this.c);

  CajaEntradas get guardada => entradas.listaCajas.single;
}

/// Una caja que tarda en cerrar hasta que la prueba la suelta ([freno]).
class _CierreQueTarda extends EntradasEnMemoria {
  final freno = Completer<void>();

  @override
  Future<CajaEntradas> cerrarCaja(
    CajaEntradas caja, {
    required double efectivoContado,
    required double diferencia,
    String? nota,
    required String quien,
  }) async {
    await freno.future;
    return super.cerrarCaja(
      caja,
      efectivoContado: efectivoContado,
      diferencia: diferencia,
      nota: nota,
      quien: quien,
    );
  }
}

/// La caja de Carla, con $ 5.000 de cambio y tres ventas: 2 en efectivo
/// ($ 20.000), 1 por transferencia ($ 10.000) y 1 en efectivo anulada
/// ($ 10.000). Tiene que haber $ 25.000 de efectivo.
Future<CajaEntradas> _unaNoche(EntradasEnMemoria entradas, String operadorId) async {
  final caja = await entradas.abrirCaja(
    eventoId: idFiestaEntrega,
    operadorId: operadorId,
    operadorNombre: 'Carla',
    cambioInicial: 5000,
  );
  RenglonEntradas sueltas(int n) =>
      RenglonEntradas.suelta(nombre: 'Entrada', precioLista: 10000, cantidad: n);
  await entradas.vender(
    caja: caja,
    compradorNombre: 'PEREZ, MARTA',
    renglones: [sueltas(2)],
    medio: MedioBarra.efectivo,
    efectivo: 20000,
    quien: 'Carla',
  );
  await entradas.vender(
    caja: caja,
    compradorNombre: 'GOMEZ, LUIS',
    renglones: [sueltas(1)],
    medio: MedioBarra.transferencia,
    transferencia: 10000,
    quien: 'Carla',
  );
  final sosa = await entradas.vender(
    caja: caja,
    compradorNombre: 'SOSA, DIEGO',
    renglones: [sueltas(1)],
    medio: MedioBarra.efectivo,
    efectivo: 10000,
    quien: 'Carla',
  );
  await entradas.anular(sosa, motivo: 'se cargó dos veces', devueltas: true, quien: 'Jefe');
  entradas.escrituras = 0;
  return caja;
}

/// Entra Carla con "Vende entradas" ([vende] false: sin el permiso). Con
/// [directo] se monta la pantalla de cerrar sola, con [caja]; si no, VENDER, y
/// se toca CERRAR CAJA.
Future<_Montada> _montar(
  WidgetTester tester, {
  bool vende = true,
  bool directo = false,
  CajaEntradas Function(CajaEntradas)? caja,
  EntradasEnMemoria? entradas,
  bool fallaElPapel = false,
  Completer<void>? papelQueTarda,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1100, 1300);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final e = EntregaEnMemoria();
  final memoria = (entradas ?? EntradasEnMemoria())..conPrecio(idFiestaEntrega);
  final papeles = <DatosDelCierreDeEntradas>[];
  final c = ProviderContainer(overrides: [
    ...e.reemplazos(jefe: false),
    ...memoria.reemplazos,
    abrirCierreDeEntradasProvider.overrideWithValue((datos, {context}) async {
      if (fallaElPapel) throw StateError('sin impresora (prueba)');
      if (papelQueTarda != null) await papelQueTarda.future;
      papeles.add(datos);
    }),
  ]);
  addTearDown(c.dispose);
  final carla = e.operador();
  await c.read(appRoleProvider.notifier).entrarComoEntradas(
        carla,
        PermisosEfectivos(entradas: true, vendeEntradas: vende),
      );
  var laCaja = await _unaNoche(memoria, carla.id);
  if (caja != null) {
    laCaja = caja(laCaja);
    memoria.listaCajas[0] = laCaja;
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
                  builder: (_) => directo
                      ? CerrarCajaEntradasScreen(caja: laCaja, evento: fiestaDeLaEntrega)
                      : VenderEntradasScreen(evento: fiestaDeLaEntrega),
                ),
              ),
              child: const Text('ir'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('ir'));
  await tester.pumpAndSettle();
  if (!directo) {
    await tester.tap(find.byKey(const Key('vender_cerrar')));
    await tester.pumpAndSettle();
  }
  return _Montada(e, memoria, laCaja, papeles, c);
}

String _texto(WidgetTester tester, String clave) =>
    tester.widget<Text>(find.byKey(Key(clave))).data!;

Future<void> _contar(WidgetTester tester, String monto) async {
  await tester.enterText(find.byKey(const Key('cierre_contado')), monto);
  await tester.pump();
  await tester.tap(find.byKey(const Key('cierre_cerrar')));
  await tester.pumpAndSettle();
}

void main() {
  // Para leer las letras de la app (Outfit) y el logo de los assets.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('contar a ciegas: antes de cerrar, la pantalla no muestra ninguna plata de la caja',
      () {
    final c = File('lib/features/entradas/widgets/cerrar_caja_entradas_screen.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    final i = c.indexOf('Widget _contar() {');
    expect(i, greaterThan(0));
    final contar = c.substring(i, c.indexOf('\n  }\n', i));
    for (final prohibido in [
      'efectivoEsperado',
      '_cuentas',
      'pesos(',
      '_ventas',
      'CierreDeEntradas',
      'efectivoContado',
    ]) {
      expect(contar, isNot(contains(prohibido)),
          reason: 'el paso de contar muestra $prohibido');
    }
  });

  group('CERRAR CAJA, desde VENDER', () {
    testWidgets('está al lado de VENTAS, y al contar no se ve ninguna plata', (tester) async {
      await _montar(tester);
      expect(find.byType(CerrarCajaEntradasScreen), findsOneWidget);
      expect(find.textContaining('Tenía que haber'), findsNothing);
      expect(find.textContaining('25.000'), findsNothing);
      expect(find.textContaining('20.000'), findsNothing);
      expect(find.byKey(const Key('cierre_resultado')), findsNothing);
      // Sin lo contado no se puede cerrar.
      final cerrar = tester.widget<ButtonStyleButton>(find.byKey(const Key('cierre_cerrar')));
      expect(cerrar.onPressed, isNull);
    });

    testWidgets('confirma viendo el número, cierra con la diferencia anotada y recién '
        'ahí muestra lo que tenía que haber; el papel, con su botón', (tester) async {
      final m = await _montar(tester);
      await tester.enterText(find.byKey(const Key('cierre_nota')), 'un billete roto');
      await _contar(tester, '24500');
      expect(_texto(tester, 'cierre_contado_grande'), r'$ 24.500');
      await tester.tap(find.byKey(const Key('cierre_confirmar')));
      await tester.pumpAndSettle();

      final caja = m.guardada;
      expect(caja.abierta, isFalse);
      expect(caja.efectivoContado, 24500);
      expect(caja.diferencia, -500);
      expect(caja.notaCierre, 'un billete roto');
      expect(_texto(tester, 'cierre_esperado'), r'$ 25.000');
      expect(_texto(tester, 'cierre_contaste'), r'$ 24.500');
      expect(_texto(tester, 'cierre_diferencia'), r'Faltan $ 500');
      expect(_texto(tester, 'cierre_vendidas'), '3 (3 sueltas y 0 de lugares)');
      expect(find.textContaining('Anuladas (no cuentan)'), findsOneWidget);
      // El papel no sale solo (22-nov-2026): IMPRIMIR EL CIERRE lo saca, con
      // la caja como quedó guardada.
      expect(m.papeles, isEmpty, reason: 'ningún papel se abre solo');
      expect(_texto(tester, 'cierre_aviso'), 'Caja cerrada.');
      await tester.tap(find.byKey(const Key('cierre_imprimir')));
      await tester.pumpAndSettle();
      expect(m.papeles.single.caja.diferencia, -500);
      expect(m.papeles.single.cuentas.efectivoEsperado, 25000);
      expect(m.papeles.single.fiesta, 'PUERTO VIEJO');

      // LISTO: se va el cierre y también VENDER.
      await tester.tap(find.byKey(const Key('cierre_listo')));
      await tester.pumpAndSettle();
      expect(find.byType(CerrarCajaEntradasScreen), findsNothing);
      expect(find.byType(VenderEntradasScreen), findsNothing);
      expect(find.text('ir'), findsOneWidget);
    });

    // Revisión del 15-nov: Atrás no sale mientras se cierra la caja ni mientras
    // sale el papel (la caja se cerraría igual sin que se vea el resultado);
    // cerrada, Atrás es LISTO (VENDER se va). Desde el 22-nov el papel sale
    // solo con IMPRIMIR EL CIERRE.
    testWidgets('Atrás espera a que se cierre la caja y a que salga el papel pedido; '
        'después es LISTO', (tester) async {
      final entradas = _CierreQueTarda();
      final papel = Completer<void>();
      final m = await _montar(tester, entradas: entradas, papelQueTarda: papel);
      await _contar(tester, '25000');
      await tester.tap(find.byKey(const Key('cierre_confirmar')));
      await tester.pumpAndSettle();

      // 1. Cerrando: Atrás no sale y la caja sigue abierta.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(CerrarCajaEntradasScreen), findsOneWidget);
      expect(m.guardada.abierta, isTrue);

      // 2. Cerrada; mientras sale el papel pedido, Atrás tampoco sale.
      entradas.freno.complete();
      await tester.pumpAndSettle();
      expect(m.guardada.abierta, isFalse);
      expect(find.byKey(const Key('cierre_resultado')), findsOneWidget);
      expect(m.papeles, isEmpty, reason: 'ningún papel se abre solo');
      await tester.tap(find.byKey(const Key('cierre_imprimir')));
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(CerrarCajaEntradasScreen), findsOneWidget);

      // 3. Salió el papel: Atrás es LISTO, y se van el cierre y VENDER.
      papel.complete();
      await tester.pumpAndSettle();
      expect(m.papeles, hasLength(1));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(CerrarCajaEntradasScreen), findsNothing);
      expect(find.byType(VenderEntradasScreen), findsNothing);
      expect(find.text('Abrir la caja de entradas'), findsNothing);
      expect(find.text('ir'), findsOneWidget);
    });

    // Mientras está abierto el cierre, VENDER (debajo) relee si baja algo: sin
    // caja abierta no tiene que pedir otra, o el cartel saldría encima.
    testWidgets('si baja algo con la caja ya cerrada, VENDER no pide abrir otra',
        (tester) async {
      final m = await _montar(tester);
      await _contar(tester, '25000');
      await tester.tap(find.byKey(const Key('cierre_confirmar')));
      await tester.pumpAndSettle();
      m.e.motor.bajo.add({'entradas_ventas'});
      await tester.pumpAndSettle();
      expect(find.text('Abrir la caja de entradas'), findsNothing);
      expect(find.byKey(const Key('cierre_diferencia')), findsOneWidget);
    });

    // Revisión del 15-nov: ENTRADAS del cierre de caja seguía mostrando
    // "abierta" una caja recién cerrada en la misma PC.
    testWidgets('al cerrar, ENTRADAS del cierre de caja se entera', (tester) async {
      final m = await _montar(tester);
      final mirando = m.c.listen(
        cajasDeEntradasDeLaFiestaProvider(idFiestaEntrega),
        (_, _) {},
      );
      addTearDown(mirando.close);
      await tester.runAsync(
          () => m.c.read(cajasDeEntradasDeLaFiestaProvider(idFiestaEntrega).future));
      expect(m.c.read(cajasDeEntradasDeLaFiestaProvider(idFiestaEntrega)).value!.abiertas, 1);
      await _contar(tester, '25000');
      await tester.tap(find.byKey(const Key('cierre_confirmar')));
      await tester.pumpAndSettle();
      final ahora = await tester.runAsync(
          () => m.c.read(cajasDeEntradasDeLaFiestaProvider(idFiestaEntrega).future));
      expect(ahora!.abiertas, 0);
      expect(ahora.cerradas, 1);
    });

    // 22-nov-2026: el papel es solo si se quiere. Si no se sacó, LISTO sale
    // igual, sin preguntar (se saca después en Cierre de caja → ENTRADAS).
    testWidgets('sin sacar el papel, LISTO sale sin preguntar', (tester) async {
      final m = await _montar(tester);
      await _contar(tester, '25000');
      await tester.tap(find.byKey(const Key('cierre_confirmar')));
      await tester.pumpAndSettle();
      expect(m.guardada.abierta, isFalse);
      await tester.tap(find.byKey(const Key('cierre_listo')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(m.papeles, isEmpty);
      expect(find.byType(CerrarCajaEntradasScreen), findsNothing);
      expect(find.byType(VenderEntradasScreen), findsNothing);
    });

    testWidgets('si el papel pedido no abre, la caja queda cerrada y lo dice',
        (tester) async {
      final m = await _montar(tester, fallaElPapel: true);
      await _contar(tester, '25000');
      await tester.tap(find.byKey(const Key('cierre_confirmar')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cierre_imprimir')));
      await tester.pumpAndSettle();
      expect(m.guardada.abierta, isFalse, reason: 'la caja quedó cerrada igual');
      expect(_texto(tester, 'cierre_aviso'),
          'No se pudo abrir el papel del cierre. Probá de nuevo.');
    });

    testWidgets('justo: lo dice así', (tester) async {
      final m = await _montar(tester);
      await _contar(tester, '25000');
      await tester.tap(find.byKey(const Key('cierre_confirmar')));
      await tester.pumpAndSettle();
      expect(m.guardada.diferencia, 0);
      expect(_texto(tester, 'cierre_diferencia'), 'Justo, sin diferencia');
    });

    testWidgets('VOLVER A CONTAR no cierra nada', (tester) async {
      final m = await _montar(tester);
      await _contar(tester, '25000');
      await tester.tap(find.text('VOLVER A CONTAR'));
      await tester.pumpAndSettle();
      expect(m.guardada.abierta, isTrue);
      expect(m.entradas.escrituras, 0);
      expect(find.byKey(const Key('cierre_contado')), findsOneWidget);
    });

    testWidgets('VOLVER A VENDER vuelve a VENDER sin cerrar', (tester) async {
      final m = await _montar(tester);
      await tester.tap(find.byKey(const Key('cierre_volver')));
      await tester.pumpAndSettle();
      expect(m.guardada.abierta, isTrue);
      expect(find.byType(CerrarCajaEntradasScreen), findsNothing);
      expect(find.byType(VenderEntradasScreen), findsOneWidget);
      // Y no pidió abrir otra caja.
      expect(find.text('Abrir la caja de entradas'), findsNothing);
    });

    testWidgets('si la base no anda, lo dice y la caja queda abierta', (tester) async {
      final m = await _montar(tester);
      m.entradas.falla = true;
      await _contar(tester, '25000');
      await tester.tap(find.byKey(const Key('cierre_confirmar')));
      await tester.pumpAndSettle();
      expect(m.guardada.abierta, isTrue);
      expect(_texto(tester, 'cierre_aviso'), 'No se pudo cerrar la caja. Probá de nuevo.');
      expect(find.byKey(const Key('cierre_resultado')), findsNothing);
    });
  });

  group('la caja cerrada', () {
    testWidgets('solo se le agrega la nota: lo contado y la diferencia no cambian',
        (tester) async {
      final m = await _montar(tester);
      await _contar(tester, '26000');
      await tester.tap(find.byKey(const Key('cierre_confirmar')));
      await tester.pumpAndSettle();
      expect(_texto(tester, 'cierre_diferencia'), r'Sobran $ 1.000');
      await tester.tap(find.byKey(const Key('cierre_anotar')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('motivo_texto')), 'sobró de un vuelto');
      await tester.pump();
      await tester.tap(find.byKey(const Key('nota_guardar')));
      await tester.pumpAndSettle();
      expect(m.guardada.notaCierre, 'sobró de un vuelto');
      expect(m.guardada.efectivoContado, 26000);
      expect(m.guardada.diferencia, 1000);
      expect(_texto(tester, 'cierre_nota_guardada'), 'Nota: sobró de un vuelto');
      // No hay manera de volver a contar.
      expect(find.byKey(const Key('cierre_contado')), findsNothing);
    });

    testWidgets('una caja que llega cerrada va directo al cierre', (tester) async {
      await _montar(
        tester,
        directo: true,
        caja: (c) => c.cerrada(
          efectivoContado: 25000,
          diferencia: 0,
          ahora: DateTime.utc(2026, 11, 21, 3),
        ),
      );
      expect(find.byKey(const Key('cierre_contado')), findsNothing);
      expect(_texto(tester, 'cierre_diferencia'), 'Justo, sin diferencia');
      expect(_texto(tester, 'cierre_esperado'), r'$ 25.000');
    });

    testWidgets('IMPRIMIR EL CIERRE lo saca las veces que haga falta', (tester) async {
      final m = await _montar(tester);
      await _contar(tester, '25000');
      await tester.tap(find.byKey(const Key('cierre_confirmar')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byKey(const Key('cierre_imprimir')));
        await tester.pumpAndSettle();
      }
      expect(m.papeles, hasLength(2));
    });
  });

  testWidgets('sin el permiso de vender la función frena igual: no cierra y lo dice',
      (tester) async {
    final m = await _montar(tester, vende: false, directo: true);
    await _contar(tester, '25000');
    await tester.tap(find.byKey(const Key('cierre_confirmar')));
    await tester.pumpAndSettle();
    expect(m.guardada.abierta, isTrue);
    expect(m.entradas.escrituras, 0);
    expect(find.text(kSinPermisoParaVender), findsOneWidget);
  });

  group('el papel del cierre', () {
    Future<DatosDelCierreDeEntradas> datos({bool despues = false, bool larga = false}) async {
      final entradas = EntradasEnMemoria();
      final caja = await _unaNoche(entradas, 'carla');
      final cerrada = await entradas.cerrarCaja(
        caja,
        efectivoContado: 24500,
        diferencia: -500,
        nota: larga
            ? 'faltó un billete de quinientos que se cayó detrás de la caja; lo '
                'buscamos al terminar la noche y no apareció, lo avisamos al jefe'
            : 'faltó un billete',
        quien: 'Carla',
      );
      if (despues) {
        entradas.adelantar(const Duration(hours: 10));
        final perez = entradas.listaVentas.first;
        await entradas.anular(perez, motivo: 'pagó dos veces', devueltas: true, quien: 'Jefe');
      }
      return DatosDelCierreDeEntradas(
        caja: cerrada,
        cuentas: CierreDeEntradas.de(
          cerrada,
          entradas.listaVentas,
          entradas.listaAnulaciones,
        ),
        fiesta: 'INSTITUTO SAN LORENZO',
        fechaFiesta: DateTime(2026, 12, 4),
      );
    }

    test('media A4, una sola hoja, y nada se sale', () async {
      final bytes = await CierreCajaEntradasPdf.armar(await datos(despues: true, larga: true));
      expect(paginasDelPdf(bytes), 1);
      final alto = altoDeLaHoja(bytes);
      expect(alto, closeTo(ReciboDeEntradasPdf.mediaA4, 0.5));
      final ancho = PdfPageFormat.a4.width;
      const costado = ReciboDeEntradasPdf.costado;
      for (final p in palabrasDelPdf(bytes)) {
        expect(p.x, greaterThanOrEqualTo(costado - 0.5),
            reason: '"${p.texto}" empieza antes del margen');
        expect(p.x + p.ancho, lessThanOrEqualTo(ancho - costado + 0.5),
            reason: '"${p.texto}" termina fuera de la hoja');
        expect(p.y, greaterThanOrEqualTo(0), reason: '"${p.texto}" se sale por abajo');
        expect(p.y, lessThanOrEqualTo(alto), reason: '"${p.texto}" se sale por arriba');
      }
    });

    // Lo que se imprime sale con Outfit, que mide distinto que la letra de
    // fábrica: el cierre tiene que entrar en media hoja con la letra de verdad.
    test('con las letras de la app y el logo, entra justo en media hoja', () async {
      final fuentes = (await PdfService.fuentesOutfit())!;
      final logo = await isotipoDeLosPapeles();
      final bytes = await CierreCajaEntradasPdf.armar(
        await datos(despues: true, larga: true),
        fuentes: fuentes,
        logo: logo,
      );
      expect(paginasDelPdf(bytes), 1);
      expect(altoDeLaHoja(bytes), closeTo(ReciboDeEntradasPdf.mediaA4, 0.5));
    });

    // 22-nov-2026 (el usuario: "hacelo como un recibo tal cual" y "que no diga
    // 'Justo, sin diferencia'"): el papel es el recibo de lo que entrega quien
    // cerró. La diferencia la ve el jefe en la pantalla, no en el papel.
    test('es el recibo de lo que entrega quien cerró: de quién, el efectivo contado en '
        'letras, lo cobrado y lo vendido', () async {
      final bytes = await CierreCajaEntradasPdf.armar(await datos());
      final palabras = palabrasDelPdf(bytes);
      final textos = {for (final p in palabras) p.texto};
      for (final esperada in [
        'RECIBO', 'CAJA', 'INSTITUTO', 'Carla', 'CARLA', '04/12/2026', 'Abierta:',
        'Cerrada:', '24.500', 'billete', 'anulada', 'Victor',
      ]) {
        expect(textos, contains(esperada), reason: 'falta "$esperada"');
      }
      final texto = palabras.map((p) => p.texto).join(' ');
      for (final frase in [
        'RECIBO DE CAJA',
        'Entradas · Carla',
        'Recibí de: CARLA',
        'La suma de pesos: VEINTICUATRO MIL QUINIENTOS PESOS',
        'Concepto: Caja de entradas · INSTITUTO SAN LORENZO · fiesta 04/12/2026',
        r'Efectivo contado (con $ 5.000 de cambio) $ 24.500',
        r'Transferencias (con los recargos) $ 10.000',
        r'Entradas vendidas: 3 (3 sueltas y 0 de lugares adicionales) $ 30.000',
        'Ventas: 2 · 1 anulada (no cuentan)',
        r'TOTAL DE ESTE RECIBO $ 24.500',
        r'Total cobrado en la caja: $ 30.000 (efectivo $ 20.000 + transferencia $ 10.000)',
        'Nota: faltó un billete',
      ]) {
        expect(texto, contains(frase), reason: 'falta "$frase"');
      }
      // Cada monto en el renglón de su rótulo.
      Set<String> renglonDe(String rotulo) {
        final y = palabras.firstWhere((p) => p.texto == rotulo).y;
        return {
          for (final p in palabras)
            if ((p.y - y).abs() < 2) p.texto,
        };
      }

      expect(renglonDe('contado'), contains('24.500'));
      expect(renglonDe('Transferencias'), contains('10.000'));
      expect(renglonDe('vendidas:'), contains('30.000'));
      expect(textos, isNot(contains('después')),
          reason: 'sin anulado después del cierre no va esa línea');
    });

    test('no dice la diferencia: ni lo que tenía que haber, ni lo que contó, ni si sobra '
        'o falta', () async {
      for (final d in [await datos(), await datos(despues: true, larga: true)]) {
        expect(d.caja.diferencia, -500, reason: 'la caja cerró con una diferencia');
        final palabras = palabrasDelPdf(await CierreCajaEntradasPdf.armar(d));
        for (final p in palabras) {
          final t = p.texto.toLowerCase();
          for (final prohibida in [
            'justo', 'diferencia', 'faltan', 'falta', 'sobran', 'sobra', 'tenía',
            'contó', 'esperado',
          ]) {
            expect(t, isNot(contains(prohibida)),
                reason: 'el papel dice "${p.texto}": la diferencia la ve el jefe en la '
                    'pantalla, no va en el papel');
          }
        }
        // Lo que tenía que haber (el cambio más el efectivo: $ 25.000) no está.
        expect(palabras.map((p) => p.texto), isNot(contains('25.000')));
      }
    });

    test('lo anulado después del cierre va aparte, y el cierre no cambia', () async {
      final d = await datos(despues: true);
      expect(d.cuentas.hayAnuladoDespues, isTrue);
      expect(d.caja.diferencia, -500);
      final textos = {
        for (final p in palabrasDelPdf(await CierreCajaEntradasPdf.armar(d))) p.texto,
      };
      expect(textos, containsAll(['después', 'corrige)']));
    });
  });
}
