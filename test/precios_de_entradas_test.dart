// PRECIOS: el jefe pone el precio de la entrada de una fiesta (etapa 3 del spec
// del 13-nov, sección 6). El diálogo de verdad, con la venta de entradas en
// memoria.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/common/utils/solo_jefe.dart';
import 'package:arguello_events/features/entradas/cuentas/precio_de_entradas.dart';
import 'package:arguello_events/features/entradas/datos/entradas_repositorio.dart';
import 'package:arguello_events/features/entradas/widgets/precios_de_entradas_dialog.dart';
import 'package:arguello_events/features/eventos/services/lugares_al_sorteo.dart';
import 'package:arguello_events/models/sorteo_mesas_registro.dart';

import 'helpers/entradas_en_memoria.dart';

const _fiesta = 'e0000000-0000-4000-8000-000000000001';

void main() {
  late EntradasEnMemoria entradas;

  /// Lo que devolvió el diálogo al cerrarse.
  ConfigEntradas? devuelto;
  var cerrado = false;

  setUp(() {
    entradas = EntradasEnMemoria();
    devuelto = null;
    cerrado = false;
  });

  Future<void> abrir(
    WidgetTester tester, {
    bool jefe = true,
    FotoDeLosLugares? lugares,
    RevisarLugares? revisarLugares,
  }) async {
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...entradas.reemplazos,
        esRolJefeProvider.overrideWith((ref) => jefe),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  devuelto = await mostrarPreciosDeEntradas(
                    context,
                    eventoId: _fiesta,
                    fiesta: 'PUERTO VIEJO',
                    quien: 'Jefe',
                    lugares: lugares,
                    revisarLugares: revisarLugares,
                  );
                  cerrado = true;
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  String escrito(WidgetTester tester, String clave) =>
      tester.widget<TextField>(find.byKey(Key(clave))).controller!.text;

  Future<void> poner(WidgetTester tester, String clave, String texto) async {
    await tester.enterText(find.byKey(Key(clave)), texto);
    await tester.pump();
  }

  Future<void> guardar(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('precios_guardar')));
    await tester.pumpAndSettle();
  }

  String? problema(WidgetTester tester) {
    final f = find.byKey(const Key('precios_problema'));
    return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
  }

  group('el día de la anticipada', () {
    test('se escribe 28/11/2026 y se guarda 2026-11-28', () {
      expect(PrecioDeEntradas.diaDeTexto('28/11/2026'), '2026-11-28');
      expect(PrecioDeEntradas.diaDeTexto(' 5/1/2027 '), '2027-01-05');
      expect(PrecioDeEntradas.diaDeTexto('28-11-2026'), '2026-11-28');
      expect(PrecioDeEntradas.textoDelDia('2026-11-28'), '28/11/2026');
      expect(PrecioDeEntradas.textoDelDia(null), '');
    });

    test('un día que no existe no se acepta', () {
      expect(PrecioDeEntradas.diaDeTexto('31/02/2026'), isNull);
      expect(PrecioDeEntradas.diaDeTexto('28/11'), isNull);
      expect(PrecioDeEntradas.diaDeTexto('mañana'), isNull);
      expect(PrecioDeEntradas.diaDeTexto(''), isNull);
    });
  });

  testWidgets('una fiesta sin nada: vacía, con el 50 % y sin recargo, y dice que sin '
      'precio no se vende', (tester) async {
    await abrir(tester);
    expect(find.text('Precios de las entradas'), findsOneWidget);
    expect(find.text('PUERTO VIEJO'), findsOneWidget);
    expect(escrito(tester, 'precio_valor'), '');
    expect(escrito(tester, 'precio_anticipada'), '');
    expect(escrito(tester, 'precio_hasta'), '');
    expect(escrito(tester, 'precio_lugares'), '50');
    expect(escrito(tester, 'precio_recargo'), '0');
    expect(
      tester.widget<CheckboxListTile>(find.byKey(const Key('precio_a_mano'))).value,
      isFalse,
      reason: 'el vendedor no descuenta hasta que el jefe lo tilde',
    );
    expect(find.text('Sin precio, esta fiesta no se puede vender.'), findsOneWidget);
    expect(find.byKey(const Key('precio_cada_una')), findsNothing);
  });

  testWidgets('la cuenta de los lugares adicionales va a la vista, y sigue lo que se '
      'escribe', (tester) async {
    await abrir(tester);
    await poner(tester, 'precio_valor', '10000');
    expect(find.text(r'Cada una: $ 5.000'), findsOneWidget);
    expect(find.byKey(const Key('precio_sin_valor')), findsNothing);
    await poner(tester, 'precio_lugares', '40');
    expect(find.text(r'Cada una: $ 6.000'), findsOneWidget);
    // La anticipada no la cambia: sale siempre del valor de la entrada.
    await poner(tester, 'precio_anticipada', '8000');
    expect(find.text(r'Cada una: $ 6.000'), findsOneWidget);
  });

  testWidgets('guardar deja el precio con quién lo puso, y al volver a abrir está todo',
      (tester) async {
    await abrir(tester);
    await poner(tester, 'precio_valor', '10000');
    await poner(tester, 'precio_anticipada', '8000');
    await poner(tester, 'precio_hasta', '28/11/2026');
    await poner(tester, 'precio_recargo', '5');
    await tester.tap(find.byKey(const Key('precio_a_mano')));
    await tester.pump();
    await guardar(tester);

    expect(cerrado, isTrue);
    final c = entradas.configs[_fiesta]!;
    expect(devuelto!.toMap(), c.toMap());
    expect(c.valorEntrada, 10000);
    expect(c.precioAnticipada, 8000);
    expect(c.anticipadaHasta, '2026-11-28');
    expect(c.descuentoLugaresPct, 50);
    expect(c.recargoPct, 5);
    expect(c.descuentoAMano, isTrue);
    expect(c.hechoPor, 'Jefe');
    expect(entradas.escrituras, 1);

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(escrito(tester, 'precio_valor'), '10000');
    expect(escrito(tester, 'precio_anticipada'), '8000');
    expect(escrito(tester, 'precio_hasta'), '28/11/2026');
    expect(escrito(tester, 'precio_recargo'), '5');
    expect(
      tester.widget<CheckboxListTile>(find.byKey(const Key('precio_a_mano'))).value,
      isTrue,
    );
  });

  testWidgets('guardar sin cambiar nada no escribe', (tester) async {
    entradas.conPrecio(_fiesta, anticipada: 8000, hasta: '2026-11-28');
    final antes = entradas.configs[_fiesta]!.toMap();
    await abrir(tester);
    await guardar(tester);
    expect(cerrado, isTrue);
    expect(entradas.escrituras, 0);
    expect(entradas.configs[_fiesta]!.toMap(), antes,
        reason: 'ni quién ni cuándo cambian');
  });

  testWidgets('la anticipada va con su día, las dos cosas o ninguna', (tester) async {
    await abrir(tester);
    await poner(tester, 'precio_valor', '10000');
    await poner(tester, 'precio_anticipada', '8000');
    await guardar(tester);
    expect(problema(tester), contains('las dos cosas o ninguna'));
    expect(cerrado, isFalse, reason: 'no se cierra: no se pierde lo escrito');

    await poner(tester, 'precio_hasta', '31/02/2026');
    expect(problema(tester), isNull, reason: 'al corregir, el aviso se va');
    await guardar(tester);
    expect(problema(tester), contains('Ese día no existe'));

    await poner(tester, 'precio_anticipada', '');
    await poner(tester, 'precio_hasta', '28/11/2026');
    await guardar(tester);
    expect(problema(tester), contains('las dos cosas o ninguna'));
    expect(entradas.escrituras, 0);
    expect(entradas.configs, isEmpty);
  });

  testWidgets('la anticipada necesita el valor, y los porcentajes van de 0 a 100',
      (tester) async {
    await abrir(tester);
    await poner(tester, 'precio_anticipada', '8000');
    await poner(tester, 'precio_hasta', '28/11/2026');
    await guardar(tester);
    expect(problema(tester), contains('primero poné el valor de la entrada'));

    await poner(tester, 'precio_valor', '10000');
    await poner(tester, 'precio_lugares', '120');
    await guardar(tester);
    expect(problema(tester), contains('va de 0 a 100'));
    expect(find.byKey(const Key('precio_cada_una')), findsNothing);

    await poner(tester, 'precio_lugares', '50');
    await poner(tester, 'precio_recargo', '250');
    await guardar(tester);
    expect(problema(tester), 'El recargo va de 0 a 100.');
    expect(entradas.escrituras, 0);
  });

  testWidgets('se puede dejar sin precio: la fiesta deja de poder venderse',
      (tester) async {
    entradas.conPrecio(_fiesta);
    await abrir(tester);
    await poner(tester, 'precio_valor', '');
    expect(find.text('Sin precio, esta fiesta no se puede vender.'), findsOneWidget);
    await guardar(tester);
    expect(cerrado, isTrue);
    expect(entradas.configs[_fiesta]!.tienePrecio, isFalse);
  });

  testWidgets('cambiar el precio no toca ninguna venta hecha', (tester) async {
    entradas.conPrecio(_fiesta);
    final caja = await entradas.abrirCaja(eventoId: _fiesta, operadorNombre: 'F1');
    final venta = await entradas.vender(
      caja: caja,
      compradorNombre: 'COMPRADORA, UNA',
      renglones: [
        RenglonEntradas.suelta(nombre: 'Entrada', precioLista: 10000, cantidad: 2),
      ],
      medio: MedioBarra.efectivo,
      efectivo: 20000,
      quien: 'F1',
    );
    final antes = venta.toMap();

    await abrir(tester);
    await poner(tester, 'precio_valor', '15000');
    await guardar(tester);
    expect(entradas.configs[_fiesta]!.valorEntrada, 15000);
    expect(entradas.listaVentas.single.toMap(), antes);
    expect(entradas.listaVentas.single.renglones.single.precio, 10000);
  });

  testWidgets('sin modo jefe se ve todo, con GUARDAR apagado y el motivo',
      (tester) async {
    entradas.conPrecio(_fiesta);
    await abrir(tester, jefe: false);
    expect(escrito(tester, 'precio_valor'), '10000');
    final boton =
        tester.widget<FilledButton>(find.byKey(const Key('precios_guardar')));
    expect(boton.onPressed, isNull);
    expect(find.byTooltip(kSoloEnModoJefe), findsOneWidget);
    await poner(tester, 'precio_valor', '1');
    await tester.tap(find.byKey(const Key('precios_guardar')), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(entradas.escrituras, 0);
    expect(entradas.configs[_fiesta]!.valorEntrada, 10000);
  });

  testWidgets('si la base no anda, lo dice en palabras y no se cierra', (tester) async {
    await abrir(tester);
    await poner(tester, 'precio_valor', '10000');
    entradas.falla = true;
    await guardar(tester);
    expect(problema(tester), 'No se pudieron guardar los precios. Probá de nuevo.');
    expect(cerrado, isFalse);
    // Vuelve a andar: se guarda con lo que estaba escrito.
    entradas.falla = false;
    await guardar(tester);
    expect(cerrado, isTrue);
    expect(entradas.configs[_fiesta]!.valorEntrada, 10000);
  });

  // 17-nov-2026: el descuento de los lugares es para lo que la familia tenía
  // cargado al sorteo. PRECIOS dice qué rige en esa fiesta.
  group('a qué le toca el descuento de los lugares', () {
    // 12/11/2026 21:40 en Argentina.
    final sorteoEl = DateTime.utc(2026, 11, 13, 0, 40);
    SorteoMesasRegistro sorteo({Map<String, String>? lugares}) =>
        SorteoMesasRegistro(
          id: 's',
          eventoId: _fiesta,
          tipo: TipoRegistroSorteo.sorteo,
          resultado: const {'a': '12'},
          lugares: lugares,
          createdAt: sorteoEl,
        );
    final sinAnotar = LugaresAlSorteo.vigente([sorteo()]);
    final anotados = LugaresAlSorteo.vigente([sorteo(lugares: const {})]);

    testWidgets('sin el dato no dice nada (quien lo abre de otro lado)',
        (tester) async {
      await abrir(tester);
      expect(find.byKey(const Key('precio_lugares_sin_sorteo')), findsNothing);
      expect(find.byKey(const Key('precio_lugares_anotados')), findsNothing);
      expect(find.byKey(const Key('precio_lugares_sin_revisar')), findsNothing);
    });

    testWidgets('una fiesta sin sortear: vale para lo cargado el día del sorteo',
        (tester) async {
      await abrir(tester, lugares: FotoDeLosLugares.sinSorteo);
      expect(
        tester.widget<Text>(find.byKey(const Key('precio_lugares_sin_sorteo'))).data,
        contains('el día del sorteo'),
      );
      expect(find.byKey(const Key('precio_revisar_lugares')), findsNothing);
    });

    testWidgets('con los lugares anotados dice de qué sorteo, con día y hora',
        (tester) async {
      await abrir(tester, lugares: anotados);
      final texto = tester
          .widget<Text>(find.byKey(const Key('precio_lugares_anotados')))
          .data!;
      expect(texto, contains('al sorteo del 12/11/2026 21:40 hs'));
      expect(texto, contains('paga la entrada entera'));
      expect(find.byKey(const Key('precio_revisar_lugares')), findsNothing);
    });

    testWidgets('sorteada antes de la regla: avisa que todo va con descuento y '
        'ofrece REVISAR LA LISTA', (tester) async {
      var abiertas = 0;
      await abrir(
        tester,
        lugares: sinAnotar,
        revisarLugares: (_) async {
          abiertas++;
          return null;
        },
      );
      expect(find.byKey(const Key('precio_lugares_sin_revisar')), findsOneWidget);
      expect(find.textContaining('todo va con descuento'), findsOneWidget);
      await tester.tap(find.byKey(const Key('precio_revisar_lugares')));
      await tester.pumpAndSettle();
      expect(abiertas, 1);
      // No cambió nada: sigue avisando.
      expect(find.byKey(const Key('precio_lugares_sin_revisar')), findsOneWidget);
      expect(cerrado, isFalse);
    });

    testWidgets('aceptada la lista, PRECIOS pasa a decir qué sorteo rige, sin '
        'cerrarse ni perder lo escrito', (tester) async {
      await abrir(
        tester,
        lugares: sinAnotar,
        revisarLugares: (_) async => anotados,
      );
      await poner(tester, 'precio_valor', '12000');
      await tester.tap(find.byKey(const Key('precio_revisar_lugares')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('precio_lugares_sin_revisar')), findsNothing);
      expect(find.byKey(const Key('precio_lugares_anotados')), findsOneWidget);
      expect(escrito(tester, 'precio_valor'), '12000');
      expect(cerrado, isFalse);
    });

    testWidgets('sin quien abra la lista, avisa pero no pone el botón',
        (tester) async {
      await abrir(tester, lugares: sinAnotar);
      expect(find.byKey(const Key('precio_lugares_sin_revisar')), findsOneWidget);
      expect(find.byKey(const Key('precio_revisar_lugares')), findsNothing);
    });
  });
}
