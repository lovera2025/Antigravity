import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:typed_data';

import 'package:arguello_events/features/barra/central/central_barra.dart' show kPuertoCentralBarra;
import 'package:arguello_events/features/barra/central/central_barra_provider.dart';
import 'package:arguello_events/features/barra/central/panel_central_barra.dart' show kRecuentoDeLaNotebook;
import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/impresion/canal_ble.dart';
import 'package:arguello_events/features/barra/impresion/impresora_bluetooth.dart';
import 'package:arguello_events/features/barra/impresion/ticket_esc_pos.dart';
import 'package:arguello_events/features/barra/jefe/barra_jefe_providers.dart';
import 'package:arguello_events/features/barra/jefe/barra_jefe_screen.dart';
import 'package:arguello_events/features/barra/providers/barra_del_jefe_provider.dart';
import 'package:arguello_events/features/barra/providers/barra_providers.dart';
import 'package:arguello_events/features/barra/services/fiestas_del_jefe.dart';
import 'package:arguello_events/features/barra/widgets/elegir_impresora_screen.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/models/evento.dart';

import 'helpers/barra_en_memoria.dart';
import 'helpers/operadores_en_memoria.dart';

/// La central de la notebook, ya prendida para [eventoId] (sin abrir puertos).
class _CentralPrendida extends CentralDeLaBarra {
  final String eventoId;

  _CentralPrendida(this.eventoId);

  @override
  EstadoCentralBarra build() => EstadoCentralBarra(
        eventoId: eventoId,
        puerto: kPuertoCentralBarra,
        direcciones: ['192.168.0.10'],
        contestaBusqueda: true,
      );

  @override
  Future<void> reanudar(String eventoId, {DateTime? fechaDeLaFiesta}) async {}
}

/// BARRA del jefe de verdad (etapa 7), con la barra y la impresora en memoria: la
/// fiesta primero (abre en la próxima), CATÁLOGO, PRECIOS con el recargo, y CAJAS con
/// anular y reimprimir. En celular, tablet y PC, sin desbordes. Sin modo jefe se ve,
/// pero lo que guarda queda apagado.
void main() {
  late OperadoresEnPrueba operadores;
  late BarraEnPrueba prueba;
  late Evento pinaroli, rotonda, vieja;
  late ProductoBarra fernet, cerveza, agua;

  /// Un viernes de noviembre: la próxima es TÉCNICA PINAROLI, el 4 de diciembre.
  var hoy = DateTime(2026, 11, 20, 15);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    hoy = DateTime(2026, 11, 20, 15);
    operadores = OperadoresEnPrueba();
    prueba = BarraEnPrueba();
    pinaroli = fiestaDePrueba(BarraEnPrueba.id(1), 'TÉCNICA PINAROLI', DateTime(2026, 12, 4, 22));
    rotonda = fiestaDePrueba(BarraEnPrueba.id(2), 'ROTONDA', DateTime(2026, 12, 12, 22));
    vieja = fiestaDePrueba(BarraEnPrueba.id(3), 'LA DE OCTUBRE', DateTime(2026, 10, 30, 22));
    prueba.eventos.addAll([rotonda, vieja, pinaroli]);
    final b = prueba.barra;
    fernet = b.producto('Fernet con Coca', categoria: 'Tragos');
    cerveza = b.producto('Cerveza tirada', categoria: 'Cervezas');
    agua = b.producto('Agua sin gas', categoria: 'Sin alcohol');
  });

  Future<void> abrir(
    WidgetTester tester, {
    Size tamano = const Size(1280, 860),
    bool esJefe = true,
    bool enLaWeb = false,
    PestanaBarraJefe pestana = PestanaBarraJefe.catalogo,
    String? centralPrendida,
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...operadores.reemplazos,
        ...prueba.reemplazos,
        if (centralPrendida != null) centralDeLaBarraProvider.overrideWith(() => _CentralPrendida(centralPrendida)),        barraDelJefeProvider.overrideWithValue(prueba.barra),
        esRolJefeProvider.overrideWithValue(esJefe),
        enLaWebProvider.overrideWithValue(enLaWeb),
        relojDelJefeProvider.overrideWithValue(() => hoy),
        impresoraDeLaBarraProvider.overrideWithValue(ImpresoraBluetooth(_CanalSinNada())),
      ],
      child: MaterialApp(home: BarraJefeScreen(pestanaInicial: pestana)),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tocar(WidgetTester tester, Finder f) async {
    // En el celular lo de abajo de una lista larga no está armado: se desliza hasta verlo.
    if (f.evaluate().isEmpty) {
      await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).last);
    }
    await tester.ensureVisible(f);
    // Un cuadro antes de tocar: si no, el toque va a donde estaba antes de desplazar.
    await tester.pump();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> escribir(WidgetTester tester, Finder f, String texto) async {
    await tester.ensureVisible(f);
    await tester.enterText(f, texto);
    await tester.pumpAndSettle();
  }

  String texto(WidgetTester tester, String clave) =>
      tester.widget<Text>(find.byKey(Key(clave))).data!;

  bool apagado(WidgetTester tester, String clave) {
    final w = tester.widget(find.byKey(Key(clave)));
    return switch (w) {
      ButtonStyleButton b => b.onPressed == null,
      IconButton b => b.onPressed == null,
      _ => fail('$clave no es un botón'),
    };
  }

  group('la fiesta primero', () {
    testWidgets('abre en la próxima, con su fecha', (tester) async {
      await abrir(tester);
      expect(texto(tester, 'jefe_fiesta_nombre'), 'TÉCNICA PINAROLI');
      expect(texto(tester, 'jefe_fiesta_fecha'), 'viernes 4 de diciembre · la próxima');
    });

    testWidgets('CAMBIAR DE FIESTA: las que vienen y las últimas, y cambia', (tester) async {
      await abrir(tester);
      await tocar(tester, find.byKey(const Key('jefe_cambiar_fiesta')));
      expect(find.text('LAS QUE VIENEN'), findsOneWidget);
      expect(find.text('LAS ÚLTIMAS'), findsOneWidget);
      expect(find.byKey(Key('jefe_fiesta_${vieja.id}')), findsOneWidget);
      await tocar(tester, find.byKey(Key('jefe_fiesta_${rotonda.id}')));
      expect(texto(tester, 'jefe_fiesta_nombre'), 'ROTONDA');
      expect(texto(tester, 'jefe_fiesta_fecha'), 'sábado 12 de diciembre');
    });

    test('la de anoche sigue abriendo al día siguiente; las canceladas no aparecen', () {
      final cancelada = Evento(
        id: BarraEnPrueba.id(9),
        clienteId: 'c',
        tipo: 'Recepción',
        fechaEvento: DateTime(2026, 12, 6, 22),
        estado: EstadoEvento.cancelado,
        modalidad: 'masivo',
        encabezadoEvento: 'SE CANCELÓ',
      );
      final f = FiestasDelJefe.de([pinaroli, rotonda, vieja, cancelada], DateTime(2026, 12, 5, 11));
      expect(f.laQueAbre?.id, pinaroli.id);
      expect([for (final e in f.todas) e.id], isNot(contains(cancelada.id)));
      expect(fechaConCuando(pinaroli.fechaEvento, DateTime(2026, 12, 5, 11), esLaQueAbre: true),
          'viernes 4 de diciembre · anoche');
      final despues = FiestasDelJefe.de([pinaroli, rotonda], DateTime(2026, 12, 6, 11));
      expect(despues.laQueAbre?.id, rotonda.id);
      expect(despues.lasUltimas.single.id, pinaroli.id);
    });

    testWidgets('sin fiestas lo dice', (tester) async {
      prueba.eventos.clear();
      await abrir(tester);
      expect(find.byKey(const Key('jefe_sin_fiestas')), findsOneWidget);
    });
  });

  group('CATÁLOGO', () {
    testWidgets('cargar un producto nuevo: queda guardado y sube', (tester) async {
      await abrir(tester);
      await tocar(tester, find.byKey(const Key('jefe_producto_nuevo')));
      expect(find.text('PRODUCTO NUEVO'), findsOneWidget);
      await escribir(tester, find.byKey(const Key('jefe_producto_nombre')), 'Gin tonic');
      await escribir(tester, find.byKey(const Key('jefe_producto_categoria')), 'Tragos');
      await tocar(tester, find.byKey(const Key('jefe_producto_guardar')));
      final gin = prueba.barra.productosGuardados.singleWhere((p) => p.nombre == 'Gin tonic');
      expect(gin.categoria, 'Tragos');
      expect(gin.activo, isTrue);
      expect(prueba.subidasDeLaBarra, contains('barra_productos ${gin.id}'));
      expect(find.byKey(Key('jefe_producto_${gin.id}')), findsOneWidget);
    });

    testWidgets('dar de baja no lo borra: queda en la grilla, al final, DE BAJA', (tester) async {
      await abrir(tester);
      await tocar(tester, find.byKey(Key('jefe_producto_${agua.id}')));
      await tocar(tester, find.byKey(const Key('jefe_producto_baja')));
      final guardada = prueba.barra.productosGuardados.singleWhere((p) => p.id == agua.id);
      expect(guardada.activo, isFalse);
      expect(prueba.barra.productosGuardados, hasLength(3));
      expect(find.text('Sin alcohol · DE BAJA'), findsOneWidget);
      expect(find.text('VOLVER A DAR DE ALTA'), findsOneWidget);
    });

    testWidgets('elegir la foto de la biblioteca y volver a la del nombre', (tester) async {
      await abrir(tester);
      await tocar(tester, find.byKey(Key('jefe_producto_${cerveza.id}')));
      expect(texto(tester, 'jefe_producto_foto_cual'), 'Foto según el nombre');
      await tocar(tester, find.byKey(const Key('jefe_producto_foto')));
      await tocar(tester, find.byKey(const Key('jefe_foto_vodka')));
      expect(texto(tester, 'jefe_producto_foto_cual'), 'Foto elegida de la biblioteca');
      await tocar(tester, find.byKey(const Key('jefe_producto_guardar')));
      expect(prueba.barra.productosGuardados.singleWhere((p) => p.id == cerveza.id).imagenUrl,
          'biblioteca:vodka');

      await tocar(tester, find.byKey(const Key('jefe_producto_foto')));
      await tocar(tester, find.byKey(const Key('jefe_foto_automatica')));
      await tocar(tester, find.byKey(const Key('jefe_producto_guardar')));
      expect(prueba.barra.productosGuardados.singleWhere((p) => p.id == cerveza.id).imagenUrl, isNull);
    });

    testWidgets('en el celular el producto se edita en una ventana', (tester) async {
      await abrir(tester, tamano: const Size(390, 844));
      await tocar(tester, find.byKey(Key('jefe_producto_${fernet.id}')));
      expect(find.byType(Dialog), findsOneWidget);
      await escribir(tester, find.byKey(const Key('jefe_producto_nombre')), 'Fernet Branca con Coca');
      await tocar(tester, find.byKey(const Key('jefe_producto_guardar')));
      expect(find.byType(Dialog), findsNothing);
      expect(prueba.barra.productosGuardados.singleWhere((p) => p.id == fernet.id).nombre,
          'Fernet Branca con Coca');
    });
  });

  group('PRECIOS', () {
    testWidgets('tildar, poner precio, stock y aviso, y el recargo: se guarda todo junto', (tester) async {
      await abrir(tester, pestana: PestanaBarraJefe.precios);
      expect(find.byKey(const Key('jefe_precios_sin_precios')), findsOneWidget);
      expect(texto(tester, 'jefe_recargo_pct'), 'sin');
      await tocar(tester, find.byKey(Key('jefe_va_${fernet.id}')));
      await escribir(tester, find.byKey(Key('jefe_precio_${fernet.id}')), '6000');
      expect(find.text('6.000'), findsWidgets, reason: 'la plata con los puntos');
      await escribir(tester, find.byKey(Key('jefe_stock_${fernet.id}')), '120');
      await escribir(tester, find.byKey(Key('jefe_aviso_${fernet.id}')), '20');
      for (var i = 0; i < 5; i++) {
        await tocar(tester, find.byKey(const Key('jefe_recargo_mas')));
      }
      expect(texto(tester, 'jefe_recargo_pct'), '5 %');
      expect(texto(tester, 'jefe_precios_cambios'), '2 cambios sin guardar');
      expect(prueba.barra.preciosGuardados, isEmpty, reason: 'nada se guarda hasta GUARDAR CAMBIOS');

      await tocar(tester, find.byKey(const Key('jefe_precios_guardar')));
      final p = prueba.barra.preciosGuardados.single;
      expect(p.eventoId, pinaroli.id);
      expect(p.productoId, fernet.id);
      expect(p.precio, 6000);
      expect(p.stockInicial, 120);
      expect(p.avisoStock, 20);
      expect(p.activo, isTrue);
      expect((await prueba.barra.recargo(pinaroli.id))!.pct, 5);
      expect(prueba.subidasDeLaBarra, containsAll(['barra_precios ${p.id}']));
      expect(prueba.subidasDeLaBarra.where((s) => s.startsWith('barra_recargos ')), hasLength(1));
      expect(find.byKey(const Key('jefe_precios_cambios')), findsNothing);
      expect(find.text('Guardado: 1 precio y el recargo.'), findsOneWidget,
          reason: 'el aviso nombra también el recargo (decía solo los precios)');
    });

    testWidgets('si va sin precio no guarda y dice de cuál falta', (tester) async {
      await abrir(tester, pestana: PestanaBarraJefe.precios);
      await tocar(tester, find.byKey(Key('jefe_va_${agua.id}')));
      await tocar(tester, find.byKey(const Key('jefe_precios_guardar')));
      expect(find.text('Falta el precio de Agua sin gas.'), findsOneWidget);
      expect(prueba.barra.preciosGuardados, isEmpty);
    });

    testWidgets('el precio de lista: dice cuánto gano y se guarda junto con lo demás', (tester) async {
      await abrir(tester, pestana: PestanaBarraJefe.precios);
      expect(find.text('PRECIO DE LISTA\n'), findsNothing);
      expect(find.textContaining('lo que me cobra el proveedor'), findsOneWidget, reason: 'se nota qué es');
      await tocar(tester, find.byKey(Key('jefe_va_${cerveza.id}')));
      await escribir(tester, find.byKey(Key('jefe_precio_${cerveza.id}')), '4000');
      expect(texto(tester, 'jefe_gano_${cerveza.id}'), '—', reason: 'sin precio de lista no se sabe');
      await escribir(tester, find.byKey(Key('jefe_lista_${cerveza.id}')), '1500');
      expect(texto(tester, 'jefe_gano_${cerveza.id}'), r'$ 2.500');
      expect(prueba.barra.costosGuardados, isEmpty, reason: 'nada se guarda hasta GUARDAR CAMBIOS');
      await tocar(tester, find.byKey(const Key('jefe_precios_guardar')));
      final c = prueba.barra.costosGuardados.single;
      expect((c.eventoId, c.productoId, c.precioLista), (pinaroli.id, cerveza.id, 1500));
      expect(prueba.subidasDeLaBarra, contains('barra_costos ${c.id}'));
      expect(find.text('Guardado: 1 precio y 1 precio de lista.'), findsOneWidget);
    });

    testWidgets('el precio de lista acepta centavos', (tester) async {
      await abrir(tester, pestana: PestanaBarraJefe.precios);
      await escribir(tester, find.byKey(Key('jefe_lista_${cerveza.id}')), '1333,33');
      await tocar(tester, find.byKey(const Key('jefe_precios_guardar')));
      expect(prueba.barra.costosGuardados.single.precioLista, closeTo(1333.33, 0.001));
    });

    testWidgets('un trago: la receta viene plegada, se arma con el catálogo y sus botellas van aparte', (tester) async {
      final botellaFernet = prueba.barra.producto('Fernet 750', categoria: 'Botellas');
      final coca = prueba.barra.producto('Coca-Cola 2,25', categoria: 'Botellas');
      // Alta, para que la receta y las botellas estén las dos armadas a la vez.
      await abrir(tester, pestana: PestanaBarraJefe.precios, tamano: const Size(1400, 2400));
      final receta = find.byKey(Key('jefe_receta_${fernet.id}'));
      expect(texto(tester, 'jefe_receta_cuantos_${fernet.id}'), 'sin ingredientes');
      expect(find.byKey(Key('jefe_receta_abierta_${fernet.id}')), findsNothing, reason: 'viene plegada');
      expect(find.byKey(Key('jefe_lista_${fernet.id}')), findsOneWidget,
          reason: 'sin receta todavía, su precio de lista se escribe (no dice "\$ 0")');

      await tocar(tester, receta);
      Future<void> agregar(int n, String nombre, String cc) async {
        await tocar(tester, find.byKey(Key('jefe_agregar_ingrediente_${fernet.id}')));
        await tocar(tester, find.byKey(Key('jefe_ingrediente_${fernet.id}_$n')));
        await tocar(tester, find.text(nombre).last);
        await escribir(tester, find.byKey(Key('jefe_cantidad_${fernet.id}_$n')), cc);
      }

      await agregar(0, 'Fernet 750', '200');
      expect(find.byKey(Key('jefe_lista_de_la_receta_${fernet.id}')), findsOneWidget,
          reason: 'con receta, sale de la receta y no se escribe');
      await agregar(1, 'Coca-Cola 2,25', '500');
      // Las botellas salen de la lista y van a su bloque, con el precio de lista y lo que traen.
      expect(find.byKey(const Key('jefe_botellas')), findsOneWidget);
      expect(find.byKey(Key('jefe_va_${botellaFernet.id}')), findsNothing, reason: 'no se vende sola');
      await escribir(tester, find.byKey(Key('jefe_botella_lista_${botellaFernet.id}')), '11740');
      await escribir(tester, find.byKey(Key('jefe_botella_trae_${botellaFernet.id}')), '750');
      expect(texto(tester, 'jefe_receta_cuesta_${fernet.id}'), contains('Falta el precio de lista de Coca-Cola 2,25'));
      await escribir(tester, find.byKey(Key('jefe_botella_lista_${coca.id}')), '3000');
      await escribir(tester, find.byKey(Key('jefe_botella_trae_${coca.id}')), '2250');
      await tocar(tester, find.byKey(Key('jefe_va_${fernet.id}')));
      await escribir(tester, find.byKey(Key('jefe_precio_${fernet.id}')), '10000');
      // 200 cc de 11.740 / 750 + 500 cc de 3.000 / 2.250 = 3.797,33: "más o menos".
      expect(texto(tester, 'jefe_receta_cuesta_${fernet.id}'), r'Cuesta $ 3.797 · ganás $ 6.203 por trago');
      expect(texto(tester, 'jefe_gano_${fernet.id}'), r'$ 6.203');

      await tocar(tester, find.byKey(const Key('jefe_precios_guardar')));
      expect(
        {for (final r in prueba.barra.recetasGuardadas) r.ingredienteId: (r.cantidad, r.unidad, r.activo)},
        {
          botellaFernet.id: (200, UnidadDeReceta.cc, true),
          coca.id: (500, UnidadDeReceta.cc, true),
        },
      );
      expect(
        {for (final c in prueba.barra.costosGuardados) c.productoId: (c.precioLista, c.contenidoCc)},
        {botellaFernet.id: (11740.0, 750), coca.id: (3000.0, 2250)},
      );
      expect(prueba.subidasDeLaBarra.where((s) => s.startsWith('barra_recetas ')), hasLength(2));
    });

    testWidgets('sacar un ingrediente guardado lo apaga, no lo borra', (tester) async {
      final botellaFernet = prueba.barra.producto('Fernet 750', categoria: 'Botellas');
      final coca = prueba.barra.producto('Coca-Cola 2,25', categoria: 'Botellas');
      for (final (id, cc) in [(botellaFernet.id, 200), (coca.id, 500)]) {
        await prueba.barra.guardarReceta(
          RecetaBarra.para(
            eventoId: pinaroli.id,
            productoId: fernet.id,
            ingredienteId: id,
            cantidad: cc,
            unidad: UnidadDeReceta.cc,
            ahora: DateTime(2026, 11, 1),
          ),
          quien: 'Jefe',
        );
      }
      await abrir(tester, pestana: PestanaBarraJefe.precios);
      expect(texto(tester, 'jefe_receta_cuantos_${fernet.id}'), '2 ingredientes');
      await tocar(tester, find.byKey(Key('jefe_receta_${fernet.id}')));
      await tocar(tester, find.byKey(Key('jefe_sacar_${fernet.id}_1')));
      await tocar(tester, find.byKey(const Key('jefe_precios_guardar')));
      expect(prueba.barra.recetasGuardadas, hasLength(2), reason: 'nada se borra');
      expect((await prueba.barra.recetas(pinaroli.id)).single.ingredienteId, botellaFernet.id);
    });

    testWidgets('COPIAR DE OTRA FIESTA trae también el precio de lista y las recetas', (tester) async {
      final botellaFernet = prueba.barra.producto('Fernet 750', categoria: 'Botellas');
      prueba.barra.precio(rotonda.id, fernet, 9000);
      await prueba.barra.guardarCosto(
        CostoBarra.para(
          eventoId: rotonda.id,
          productoId: botellaFernet.id,
          precioLista: 11000,
          contenidoCc: 750,
          ahora: DateTime(2026, 11, 1),
        ),
        quien: 'Jefe',
      );
      await prueba.barra.guardarReceta(
        RecetaBarra.para(
          eventoId: rotonda.id,
          productoId: fernet.id,
          ingredienteId: botellaFernet.id,
          cantidad: 200,
          unidad: UnidadDeReceta.cc,
          ahora: DateTime(2026, 11, 1),
        ),
        quien: 'Jefe',
      );
      await abrir(tester, pestana: PestanaBarraJefe.precios);
      await tocar(tester, find.byKey(const Key('jefe_copiar')));
      await tocar(tester, find.byKey(Key('jefe_copiar_de_${rotonda.id}')));
      expect(find.textContaining('con el precio de lista y las recetas'), findsOneWidget);
      await tocar(tester, find.byKey(const Key('jefe_precios_guardar')));
      final costo = prueba.barra.costosGuardados.where((c) => c.eventoId == pinaroli.id).single;
      expect((costo.productoId, costo.precioLista, costo.contenidoCc), (botellaFernet.id, 11000, 750));
      final receta = (await prueba.barra.recetas(pinaroli.id)).single;
      expect((receta.productoId, receta.ingredienteId, receta.cantidad), (fernet.id, botellaFernet.id, 200));
    });

    testWidgets('sacar un producto de la fiesta no borra su precio: queda sin ofrecerse', (tester) async {
      prueba.barra.precio(pinaroli.id, cerveza, 4000, stock: 200, aviso: 30);
      await abrir(tester, pestana: PestanaBarraJefe.precios);
      await tocar(tester, find.byKey(Key('jefe_va_${cerveza.id}')));
      await tocar(tester, find.byKey(const Key('jefe_precios_guardar')));
      final p = prueba.barra.preciosGuardados.single;
      expect(p.activo, isFalse);
      expect(p.precio, 4000);
      expect(p.stockInicial, 200);
    });

    testWidgets('COPIAR DE OTRA FIESTA trae los precios y el recargo, no el stock, y espera GUARDAR', (tester) async {
      prueba.barra.precio(rotonda.id, fernet, 5500, stock: 100, aviso: 15);
      prueba.barra.precio(rotonda.id, agua, 2000);
      await prueba.barra.guardarRecargo(
        RecargoBarra.para(eventoId: rotonda.id, pct: 8, ahora: DateTime(2026, 11, 1)),
        quien: 'Jefe',
      );
      // Un producto dado de baja con precio en ROTONDA: no se copia, y no se cuenta.
      final champan = prueba.barra.producto('Champán', categoria: 'Botellas');
      await prueba.barra.guardarProducto(champan.conCambios(activo: false), quien: 'Jefe');
      prueba.barra.precio(rotonda.id, champan, 30000);
      await abrir(tester, pestana: PestanaBarraJefe.precios);
      await tocar(tester, find.byKey(const Key('jefe_copiar')));
      expect(
        find.descendant(
          of: find.byKey(Key('jefe_copiar_de_${rotonda.id}')),
          matching: find.textContaining('· 2 precios'),
        ),
        findsOneWidget,
        reason: 'dice los que va a copiar, sin el dado de baja',
      );
      await tocar(tester, find.byKey(Key('jefe_copiar_de_${rotonda.id}')));
      expect(find.textContaining('Se copiaron 2 precios de ROTONDA y su recargo'), findsOneWidget);
      expect(texto(tester, 'jefe_recargo_pct'), '8 %');
      final stock = tester.widget<TextField>(find.byKey(Key('jefe_stock_${fernet.id}')));
      expect(stock.controller!.text, '', reason: 'el stock no se copia');
      expect(prueba.barra.preciosGuardados.where((p) => p.eventoId == pinaroli.id), isEmpty);
      await tocar(tester, find.byKey(const Key('jefe_precios_guardar')));
      final dePinaroli = prueba.barra.preciosGuardados.where((p) => p.eventoId == pinaroli.id).toList();
      expect({for (final p in dePinaroli) p.productoId: p.precio}, {fernet.id: 5500, agua.id: 2000});
      expect((await prueba.barra.recargo(pinaroli.id))!.pct, 8);
    });

    testWidgets('la lista en papel: lo que va, por categoría, y el PDF de 58 mm', (tester) async {
      prueba.barra.precio(pinaroli.id, fernet, 6000);
      prueba.barra.precio(pinaroli.id, cerveza, 4000);
      await prueba.barra.guardarRecargo(
        RecargoBarra.para(eventoId: pinaroli.id, pct: 5, ahora: DateTime(2026, 11, 1)),
        quien: 'Jefe',
      );
      await abrir(tester, pestana: PestanaBarraJefe.precios);
      final papel = find.byKey(const Key('jefe_lista_papel'));
      expect(find.descendant(of: papel, matching: find.text('Fernet con Coca')), findsOneWidget);
      expect(find.descendant(of: papel, matching: find.text(r'$ 6.000')), findsOneWidget);
      expect(find.descendant(of: papel, matching: find.text('CERVEZAS')), findsOneWidget);
      expect(find.descendant(of: papel, matching: find.text('Agua sin gas')), findsNothing);
      expect(find.descendant(of: papel, matching: find.text('Pagando por transferencia: + 5 %')), findsOneWidget);
      await tocar(tester, find.byKey(const Key('jefe_lista_pdf')));
      expect(prueba.pdfs.single.titulo, 'Lista de precios');
      expect(prueba.pdfs.single.nombre, 'Lista de precios - TÉCNICA PINAROLI');
      await tocar(tester, find.byKey(const Key('jefe_lista_imprimir')));
      expect(prueba.papel.papeles.single, contains('LISTA DE PRECIOS'));
    });

    // Lo encontró el recorrido con el mouse (7-nov): la impresora solo se elegía desde
    // VENDER, y en la PC del jefe salía "¿está prendida?" con la impresora al lado.
    testWidgets('si esta PC no tiene impresora elegida, IMPRIMIR LISTA lo dice', (tester) async {
      prueba.barra.precio(pinaroli.id, fernet, 6000);
      prueba.papel.estado = EstadoImpresora.sinElegir;
      await abrir(tester, pestana: PestanaBarraJefe.precios);
      await tocar(tester, find.byKey(const Key('jefe_lista_imprimir')));
      expect(find.text(kSinImpresoraEnEstaPc), findsOneWidget);
      expect(prueba.papel.papeles, isEmpty);
    });

    testWidgets('el ícono de la impresora abre la elección de la impresora de esta PC', (tester) async {
      await abrir(tester, pestana: PestanaBarraJefe.precios);
      // Mientras busca, la ruedita no para: sin pumpAndSettle.
      await tester.tap(find.byKey(const Key('jefe_impresora')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(ElegirImpresoraScreen), findsOneWidget);
      // La búsqueda corre 10 s.
      await tester.pump(const Duration(seconds: 11));
    });
  });

  group('CAJAS', () {
    late CajaBarra marta, lucas;
    late VentaBarra primera, segunda;

    RenglonVenta renglon(ProductoBarra p, double precio, int cantidad) =>
        RenglonVenta(productoId: p.id, nombre: p.nombre, precio: precio, cantidad: cantidad);

    Future<void> armarLaNoche() async {
      // CAJAS se mira la noche de la fiesta (25-nov-2026: una noche por vez): la hora de
      // la PC es la de las ventas, las 23 del 4-dic.
      hoy = DateTime(2026, 12, 4, 23);
      final b = prueba.barra;
      b.precio(pinaroli.id, fernet, 6000, stock: 10, aviso: 4);
      b.precio(pinaroli.id, cerveza, 4000, stock: 100, aviso: 10);
      marta = await b.abrirCaja(eventoId: pinaroli.id, operadorId: 'm', operadorNombre: 'Marta', numeroCaja: 1);
      primera = await b.vender(
        caja: marta,
        renglones: [renglon(fernet, 6000, 3)],
        medio: MedioBarra.efectivo,
        efectivo: 18000,
        quien: 'Marta',
      );
      segunda = await b.vender(
        caja: marta,
        renglones: [renglon(cerveza, 4000, 2)],
        medio: MedioBarra.transferencia,
        transferencia: 8400,
        recargo: 400,
        recargoPct: 5,
        quien: 'Marta',
      );
      for (final v in [primera, segunda]) {
        await b.anotarVale(ValeBarra.salio(
          venta: v,
          bebidas: [for (final r in v.renglones) BebidaDelVale(r.cantidad, r.nombre)],
          porSeparado: false,
          hechoPor: 'Marta',
          ahora: DateTime(2026, 12, 4, 23),
        ));
      }
      lucas = await b.abrirCaja(eventoId: pinaroli.id, operadorId: 'l', operadorNombre: 'Lucas', numeroCaja: 2);
      await b.vender(
        caja: lucas,
        renglones: [renglon(fernet, 6000, 4)],
        medio: MedioBarra.efectivo,
        efectivo: 24000,
        quien: 'Lucas',
      );
      lucas = await b.cerrarCaja(lucas, efectivoContado: 23500, diferencia: -500, quien: 'Lucas');
    }

    testWidgets('los totales, una tarjeta por caja y el stock con lo que está en aviso arriba', (tester) async {
      await armarLaNoche();
      await abrir(tester, pestana: PestanaBarraJefe.cajas);
      expect(texto(tester, 'jefe_kpi_total_valor'), r'$ 50.400');
      expect(texto(tester, 'jefe_kpi_ventas_valor'), '3');
      expect(texto(tester, 'jefe_kpi_diferencia_valor'), r'Faltan $ 500');
      expect(find.byKey(Key('jefe_caja_${marta.id}')), findsOneWidget);
      expect(find.byKey(Key('jefe_caja_${lucas.id}')), findsOneWidget);
      expect(find.text(r'Contó $ 23.500 · Faltan $ 500'), findsOneWidget);
      // Fernet: 10 cargados, 7 vendidos entre las dos cajas → quedan 3, en aviso (desde 4).
      expect(find.text('Quedan 3 de 10'), findsOneWidget);
      final fernetY = tester.getTopLeft(find.byKey(Key('jefe_stock_${fernet.id}'))).dy;
      final cervezaY = tester.getTopLeft(find.byKey(Key('jefe_stock_${cerveza.id}'))).dy;
      expect(fernetY, lessThan(cervezaY), reason: 'lo que está en aviso, arriba');
    });

    testWidgets('el jefe anula cualquier venta, con motivo, y deja de contar', (tester) async {
      await armarLaNoche();
      // Alta: con la plata de la caja arriba (27-nov), el total queda a la vista al anular.
      await abrir(tester, pestana: PestanaBarraJefe.cajas, tamano: const Size(1280, 1500));
      await tocar(tester, find.byKey(Key('jefe_caja_${marta.id}')));
      await tocar(tester, find.byKey(Key('jefe_anular_${primera.id}')));
      await escribir(tester, find.byKey(const Key('motivo_texto')), 'se cobró dos veces');
      await tocar(tester, find.byKey(const Key('motivo_anular')));
      final a = prueba.barra.anulacionesGuardadas.single;
      expect(a.ventaId, primera.id);
      expect(a.motivo, 'se cobró dos veces');
      expect(a.hechoPor, 'Jefe');
      expect(prueba.subidasDeLaBarra, contains('barra_anulaciones ${a.id}'));
      expect(find.byKey(Key('jefe_anulada_${primera.id}')), findsOneWidget);
      expect(texto(tester, 'jefe_kpi_total_valor'), r'$ 32.400');
    });

    testWidgets('SACAR EFECTIVO: con motivo, a su nombre, sube, y lo que tiene que haber baja', (tester) async {
      await armarLaNoche();
      await abrir(tester, pestana: PestanaBarraJefe.cajas);
      await tocar(tester, find.byKey(Key('jefe_caja_${marta.id}')));
      expect(texto(tester, 'jefe_caja_tiene_que_haber'), r'$ 18.000');
      await tocar(tester, find.byKey(const Key('jefe_caja_sacar_efectivo')));
      expect(apagado(tester, 'mov_confirmar'), isTrue, reason: 'sin monto ni motivo no se anota');
      await escribir(tester, find.byKey(const Key('mov_monto')), '10000');
      expect(apagado(tester, 'mov_confirmar'), isTrue, reason: 'el motivo es obligatorio');
      await tocar(tester, find.byKey(const Key('mov_rapido_0')));
      expect(find.text(r'SACAR $ 10.000'), findsOneWidget, reason: 'el botón dice cuánto');
      await tocar(tester, find.byKey(const Key('mov_confirmar')));
      final m = prueba.barra.movimientosDeCajaGuardados.single;
      expect((m.tipo, m.monto, m.motivo, m.hechoPor, m.cajaBarraId),
          (TipoMovimientoDeCaja.retiro, 10000, 'Mucho efectivo en la caja', 'Jefe', marta.id));
      expect(prueba.subidasDeLaBarra, contains('barra_caja_movimientos ${m.id}'));
      expect(texto(tester, 'jefe_caja_tiene_que_haber'), r'$ 8.000');
      expect(texto(tester, 'jefe_caja_plata_aviso'), contains(r'sacaste $ 10.000 de la Caja 1'));
      expect(find.byKey(Key('jefe_caja_movimiento_${m.id}')), findsOneWidget, reason: 'queda en lo que se hizo con la plata');
    });

    testWidgets('DAR CAMBIO suma y Corregir resta, cada uno con su fila', (tester) async {
      await armarLaNoche();
      await abrir(tester, pestana: PestanaBarraJefe.cajas);
      await tocar(tester, find.byKey(Key('jefe_caja_${marta.id}')));
      await tocar(tester, find.byKey(const Key('jefe_caja_dar_cambio')));
      await escribir(tester, find.byKey(const Key('mov_monto')), '5000');
      await escribir(tester, find.byKey(const Key('mov_motivo')), 'sin billetes chicos');
      await tocar(tester, find.byKey(const Key('mov_confirmar')));
      expect(texto(tester, 'jefe_caja_tiene_que_haber'), r'$ 23.000');
      await tocar(tester, find.byKey(const Key('jefe_caja_corregir')));
      await tocar(tester, find.byKey(const Key('mov_menos')));
      await escribir(tester, find.byKey(const Key('mov_monto')), '2000');
      await escribir(tester, find.byKey(const Key('mov_motivo')), 'el cambio se dio de más');
      await tocar(tester, find.byKey(const Key('mov_confirmar')));
      expect(texto(tester, 'jefe_caja_tiene_que_haber'), r'$ 21.000');
      expect(
        [for (final m in prueba.barra.movimientosDeCajaGuardados) (m.tipo, m.monto)],
        [(TipoMovimientoDeCaja.cambio, 5000), (TipoMovimientoDeCaja.ajusteCambio, -2000)],
      );
    });

    testWidgets('una caja cerrada no tiene SACAR EFECTIVO ni DAR CAMBIO', (tester) async {
      await armarLaNoche();
      await abrir(tester, pestana: PestanaBarraJefe.cajas);
      await tocar(tester, find.byKey(Key('jefe_caja_${lucas.id}')));
      expect(find.byKey(const Key('jefe_caja_sacar_efectivo')), findsNothing);
      expect(find.byKey(const Key('jefe_caja_dar_cambio')), findsNothing);
      expect(find.byKey(const Key('jefe_caja_tiene_que_haber')), findsOneWidget, reason: 'la plata se ve igual');
    });

    testWidgets('la tarjeta dice lo que sacó la encargada, y avisa si algo llegó después del cierre', (tester) async {
      await armarLaNoche();
      await prueba.barra.anotarMovimientoDeCaja(
        MovimientoDeCaja.nuevo(
          eventoId: pinaroli.id,
          cajaBarraId: marta.id,
          tipo: TipoMovimientoDeCaja.retiro,
          monto: 10000,
          motivo: 'Mucho efectivo',
          ahora: DateTime(2026, 12, 4, 23, 30),
        ),
        quien: 'Romi',
      );
      // Un retiro de la caja de Lucas que a su tablet le llegó después de cerrar: contó
      // 23.500 y anotó "faltan 500"; con el retiro, da justo.
      prueba.barra.movimientosDeCajaGuardados.add(MovimientoDeCaja.nuevo(
        eventoId: pinaroli.id,
        cajaBarraId: lucas.id,
        tipo: TipoMovimientoDeCaja.retiro,
        monto: 500,
        motivo: 'Para pagar el hielo',
        ahora: DateTime(2026, 12, 4, 23, 30),
      ));
      await abrir(tester, pestana: PestanaBarraJefe.cajas);
      expect(find.byKey(Key('jefe_caja_retirado_${marta.id}')), findsOneWidget);
      expect(find.text(r'-$ 10.000'), findsWidgets);
      expect(texto(tester, 'jefe_caja_cambio_despues_${lucas.id}'), contains('justo, sin diferencia'));
      expect(find.text(r'Contó $ 23.500 · Faltan $ 500'), findsOneWidget, reason: 'lo anotado al cerrar no se toca');
      expect(find.byKey(Key('jefe_caja_cambio_despues_${marta.id}')), findsNothing, reason: 'la abierta, no');
    });

    testWidgets('el jefe reimprime cualquier venta, no solo la última, y las veces que haga falta', (tester) async {
      await armarLaNoche();
      await abrir(tester, pestana: PestanaBarraJefe.cajas);
      await tocar(tester, find.byKey(Key('jefe_caja_${marta.id}')));
      for (var vez = 1; vez <= 2; vez++) {
        await tocar(tester, find.byKey(Key('jefe_reimprimir_${primera.id}')));
        await escribir(tester, find.byKey(const Key('motivo_texto')), 'se le mojó');
        await tocar(tester, find.byKey(const Key('motivo_reimprimir')));
      }
      expect(prueba.papel.papeles, hasLength(2));
      expect(prueba.papel.papeles.first, contains('*** COPIA ***'));
      final copias = prueba.barra.valesGuardados.where((v) => v.esCopia).toList();
      expect([for (final c in copias) c.copiaNumero], [1, 2]);
      expect([for (final c in copias) c.hechoPor], ['Jefe', 'Jefe']);
      expect(find.text('Salió la copia.'), findsOneWidget);
    });

    testWidgets('sin impresora elegida en esta PC, reimprimir lo dice antes de pedir el motivo', (tester) async {
      await armarLaNoche();
      prueba.papel.estado = EstadoImpresora.sinElegir;
      await abrir(tester, pestana: PestanaBarraJefe.cajas);
      await tocar(tester, find.byKey(Key('jefe_caja_${marta.id}')));
      await tocar(tester, find.byKey(Key('jefe_reimprimir_${primera.id}')));
      expect(find.byKey(const Key('motivo_texto')), findsNothing);
      expect(find.text(kSinImpresoraEnEstaPc), findsOneWidget);
      expect(prueba.papel.papeles, isEmpty);
    });

    testWidgets('VER CIERRE: el cierre como el papel, y el PDF de 58 mm', (tester) async {
      await armarLaNoche();
      await abrir(tester, pestana: PestanaBarraJefe.cajas);
      await tocar(tester, find.byKey(Key('jefe_caja_${lucas.id}')));
      await tocar(tester, find.byKey(const Key('jefe_ver_cierre')));
      final papel = find.byKey(const Key('jefe_cierre_papel'));
      expect(find.descendant(of: papel, matching: find.text('CIERRE DE CAJA - BARRA')), findsOneWidget);
      expect(find.descendant(of: papel, matching: find.text(r'Faltan $ 500')), findsOneWidget);
      await tocar(tester, find.byKey(const Key('jefe_cierre_pdf')));
      expect(prueba.pdfs.single.titulo, 'Cierre de caja');
      expect(prueba.pdfs.single.lineas.whereType<TextoTicket>().map((t) => t.texto), contains('HISTORIAL'));
    });

    // El papel corto y el detalle en la app (11-nov-2026).
    List<String> izquierdasDelUltimoPapel() =>
        [for (final r in prueba.papel.enCrudo.last.whereType<RenglonTicket>()) r.izquierda];

    testWidgets('IMPRIMIR el cierre pregunta qué papel: el corto va por categoría', (tester) async {
      await armarLaNoche();
      await abrir(tester, pestana: PestanaBarraJefe.cajas);
      await tocar(tester, find.byKey(Key('jefe_caja_${marta.id}')));
      await tocar(tester, find.byKey(const Key('jefe_ver_cierre')));
      await tocar(tester, find.byKey(const Key('jefe_cierre_imprimir')));
      expect(find.text('¿Qué papel imprimo?'), findsOneWidget);
      await tocar(tester, find.byKey(const Key('papel_corto')));
      expect(izquierdasDelUltimoPapel(), containsAll(['3 x Tragos', '2 x Cervezas']));
      expect(izquierdasDelUltimoPapel(), isNot(contains('3 x Fernet con Coca')));

      await tocar(tester, find.byKey(const Key('jefe_cierre_imprimir')));
      await tocar(tester, find.byKey(const Key('papel_con_cada_bebida')));
      expect(izquierdasDelUltimoPapel(), containsAll(['3 x Fernet con Coca', '2 x Cerveza tirada']));
      expect(prueba.papel.papeles, hasLength(2));
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('en una caja, LO VENDIDO muestra cada bebida por categoría', (tester) async {
      await armarLaNoche();
      await abrir(tester, pestana: PestanaBarraJefe.cajas);
      await tocar(tester, find.byKey(Key('jefe_caja_${marta.id}')));
      // Abre en VENTAS, como siempre.
      expect(find.byKey(Key('jefe_venta_${primera.id}')), findsOneWidget);
      await tocar(tester, find.byKey(const Key('jefe_pestana_vendido')));
      expect(find.byKey(Key('jefe_venta_${primera.id}')), findsNothing);
      final lista = find.byKey(const Key('jefe_vendido_lista'));
      for (final t in ['3 · TRAGOS', '3 x Fernet con Coca', '2 · CERVEZAS', '2 x Cerveza tirada', '5 unidades']) {
        expect(find.descendant(of: lista, matching: find.text(t)), findsOneWidget, reason: t);
      }
      // El total de las bebidas va sin el recargo, que se dice aparte.
      expect(find.descendant(of: lista, matching: find.text(r'$ 26.000')), findsOneWidget);
      expect(find.text('Recargos por transferencia (aparte)'), findsOneWidget);
      await tocar(tester, find.byKey(const Key('jefe_pestana_ventas')));
      expect(find.byKey(Key('jefe_venta_${primera.id}')), findsOneWidget);
    });

    testWidgets('el filtro de ventas: con Transferencia queda la lista para Mercado Pago', (tester) async {
      await armarLaNoche();
      final mixta = await prueba.barra.vender(
        caja: marta,
        renglones: [renglon(fernet, 6000, 1)],
        medio: MedioBarra.mixto,
        efectivo: 4000,
        transferencia: 2000,
        quien: 'Marta',
      );
      await abrir(tester, pestana: PestanaBarraJefe.cajas);
      await tocar(tester, find.byKey(Key('jefe_caja_${marta.id}')));
      expect(find.textContaining(r'Mixto · E $ 4.000 · T $ 2.000'), findsOneWidget);

      await tocar(tester, find.byKey(const Key('jefe_filtro_transferencia')));
      expect(find.byKey(Key('jefe_venta_${primera.id}')), findsNothing, reason: 'la de efectivo no');
      expect(find.byKey(Key('jefe_venta_${segunda.id}')), findsOneWidget);
      expect(find.byKey(Key('jefe_venta_${mixta.id}')), findsOneWidget, reason: 'la mixta también transfirió');
      expect(
        texto(tester, 'jefe_filtro_resumen'),
        r'Por transferencia: 2 ventas · $ 10.400. Comparalo con Mercado Pago.',
      );

      await tocar(tester, find.byKey(const Key('jefe_filtro_efectivo')));
      expect(find.byKey(Key('jefe_venta_${primera.id}')), findsOneWidget);
      expect(find.byKey(Key('jefe_venta_${segunda.id}')), findsNothing);
      await tocar(tester, find.byKey(const Key('jefe_filtro_anuladas')));
      expect(find.byKey(const Key('jefe_filtro_vacio')), findsOneWidget);
      await tocar(tester, find.byKey(const Key('jefe_filtro_todas')));
      expect(find.byKey(Key('jefe_venta_${primera.id}')), findsOneWidget);
    });

    testWidgets('LO VENDIDO DE LA FIESTA: todas las cajas juntas, con PDF y papel corto', (tester) async {
      await armarLaNoche();
      await abrir(tester, pestana: PestanaBarraJefe.cajas);
      await tocar(tester, find.byKey(const Key('jefe_vendido_fiesta')));
      final papel = find.byKey(const Key('jefe_vendido_fiesta_papel'));
      expect(find.descendant(of: papel, matching: find.text('LO VENDIDO - BARRA')), findsOneWidget);
      // De qué noche son (25-nov-2026): las cajas de prueba de otro día no entran.
      expect(find.descendant(of: papel, matching: find.text('Las 2 cajas del 4/12')), findsOneWidget);
      // Fernet: 3 de Marta y 4 de Lucas.
      expect(find.descendant(of: papel, matching: find.text('7 x Fernet con Coca')), findsOneWidget);
      await tocar(tester, find.byKey(const Key('jefe_vendido_fiesta_pdf')));
      expect(prueba.pdfs.single.titulo, 'Lo vendido de la fiesta');
      await tocar(tester, find.byKey(const Key('jefe_vendido_fiesta_imprimir')));
      await tocar(tester, find.byKey(const Key('papel_corto')));
      expect(izquierdasDelUltimoPapel(), containsAll(['7 x Tragos', '2 x Cervezas']));
      expect(izquierdasDelUltimoPapel(), isNot(contains('7 x Fernet con Coca')));
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('una fiesta sin cajas lo dice', (tester) async {
      await abrir(tester, pestana: PestanaBarraJefe.cajas);
      expect(find.byKey(const Key('jefe_sin_cajas')), findsOneWidget);
    });
  });

  group('sin modo jefe', () {
    testWidgets('se ve todo, y lo que guarda queda apagado', (tester) async {
      prueba.barra.precio(pinaroli.id, fernet, 6000);
      await abrir(tester, esJefe: false);
      expect(find.byKey(const Key('jefe_sin_modo_jefe')), findsOneWidget);
      expect(apagado(tester, 'jefe_producto_nuevo'), isTrue);
      await tocar(tester, find.byKey(Key('jefe_producto_${fernet.id}')));
      expect(apagado(tester, 'jefe_producto_guardar'), isTrue);
      expect(apagado(tester, 'jefe_producto_baja'), isTrue);

      await tocar(tester, find.byKey(const Key('jefe_pestana_precios')));
      expect(apagado(tester, 'jefe_va_${fernet.id}'), isTrue);
      expect(apagado(tester, 'jefe_recargo_mas'), isTrue);
      expect(apagado(tester, 'jefe_copiar'), isTrue);
      expect(apagado(tester, 'jefe_lista_pdf'), isFalse, reason: 'mirar y sacar la lista sí');
    });

    // 26-nov-2026: la plata de las cajas la ven solo la encargada y el jefe (antes, sin
    // modo jefe, CAJAS mostraba las ventas con anular y reimprimir apagados).
    testWidgets('CAJAS no muestra la plata: lo dice', (tester) async {
      hoy = DateTime(2026, 12, 4, 23); // la noche de las ventas
      final b = prueba.barra;
      final caja = await b.abrirCaja(eventoId: pinaroli.id, operadorId: 'm', operadorNombre: 'Marta', numeroCaja: 1);
      await b.vender(
        caja: caja,
        renglones: [RenglonVenta(productoId: fernet.id, nombre: fernet.nombre, precio: 6000, cantidad: 1)],
        medio: MedioBarra.efectivo,
        efectivo: 6000,
        quien: 'Marta',
      );
      await abrir(tester, esJefe: false, pestana: PestanaBarraJefe.cajas);
      expect(find.byKey(const Key('cajas_sin_permiso')), findsOneWidget);
      expect(find.byKey(Key('jefe_caja_${caja.id}')), findsNothing);
      expect(find.textContaining(r'$'), findsNothing);
    });
  });

  /// La web del iPhone (etapa 8): lo mismo, sin impresora, y CAJAS se relee sola.
  group('en la web', () {
    late CajaBarra caja;
    late VentaBarra venta;

    Future<void> unaNoche() async {
      final b = prueba.barra;
      b.precio(pinaroli.id, fernet, 6000, stock: 10, aviso: 4);
      caja = await b.abrirCaja(eventoId: pinaroli.id, operadorId: 'm', operadorNombre: 'Marta', numeroCaja: 1);
      venta = await b.vender(
        caja: caja,
        renglones: [RenglonVenta(productoId: fernet.id, nombre: fernet.nombre, precio: 6000, cantidad: 1)],
        medio: MedioBarra.efectivo,
        efectivo: 6000,
        quien: 'Marta',
      );
    }

    Future<void> otraVentaEnLaNube() => prueba.barra.vender(
          caja: caja,
          renglones: [RenglonVenta(productoId: fernet.id, nombre: fernet.nombre, precio: 6000, cantidad: 2)],
          medio: MedioBarra.efectivo,
          efectivo: 12000,
          quien: 'Marta',
        );

    testWidgets('sin impresora: ni el ícono, ni IMPRIMIR LISTA, ni REIMPRIMIR, ni IMPRIMIR el cierre; los PDF sí',
        (tester) async {
      await unaNoche();
      await abrir(tester, enLaWeb: true, pestana: PestanaBarraJefe.precios, tamano: const Size(390, 844));
      expect(find.byKey(const Key('jefe_impresora')), findsNothing);
      expect(find.byKey(const Key('jefe_lista_imprimir')), findsNothing);
      expect(find.byKey(const Key('jefe_lista_pdf')), findsOneWidget);

      await tocar(tester, find.byKey(const Key('jefe_pestana_cajas')));
      await tocar(tester, find.byKey(Key('jefe_caja_${caja.id}')));
      expect(find.byKey(Key('jefe_reimprimir_${venta.id}')), findsNothing);
      expect(find.byKey(Key('jefe_anular_${venta.id}')), findsOneWidget, reason: 'anular desde el iPhone sí');
      await tocar(tester, find.byKey(const Key('jefe_ver_cierre')));
      expect(find.byKey(const Key('jefe_cierre_imprimir')), findsNothing);
      expect(find.byKey(const Key('jefe_cierre_pdf')), findsOneWidget);
    });

    testWidgets('CAJAS se relee sola cada 30 segundos: una venta que subió aparece sin tocar nada', (tester) async {
      await unaNoche();
      await abrir(tester, enLaWeb: true, pestana: PestanaBarraJefe.cajas, tamano: const Size(390, 844));
      expect(texto(tester, 'jefe_kpi_ventas_valor'), '1');
      expect(texto(tester, 'jefe_en_vivo'), contains('cada 30 segundos'));
      await otraVentaEnLaNube();
      await tester.pump(const Duration(seconds: 29));
      expect(texto(tester, 'jefe_kpi_ventas_valor'), '1', reason: 'todavía no releyó');
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(texto(tester, 'jefe_kpi_ventas_valor'), '2');
      expect(texto(tester, 'jefe_kpi_total_valor'), r'$ 18.000');
    });

    testWidgets('deslizar hacia abajo relee ya', (tester) async {
      await unaNoche();
      await abrir(tester, enLaWeb: true, pestana: PestanaBarraJefe.cajas, tamano: const Size(390, 844));
      await otraVentaEnLaNube();
      expect(find.byKey(const Key('jefe_cajas_releer')), findsOneWidget);
      await tester.drag(find.byKey(const Key('jefe_en_vivo')), const Offset(0, 300));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(texto(tester, 'jefe_kpi_ventas_valor'), '2');
    });

    testWidgets('en la PC no hay relectura cada 30 segundos ni deslizar: la rehace el sync', (tester) async {
      await unaNoche();
      await abrir(tester, pestana: PestanaBarraJefe.cajas);
      expect(find.byKey(const Key('jefe_cajas_releer')), findsNothing);
      expect(texto(tester, 'jefe_en_vivo'), contains('cuando las cajas suben sus ventas'));
      await otraVentaEnLaNube();
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(texto(tester, 'jefe_kpi_ventas_valor'), '1');
    });

    testWidgets('en la PC con la central prendida, dice que se pone al día por la red del salón', (tester) async {
      await unaNoche();
      await abrir(tester, pestana: PestanaBarraJefe.cajas, centralPrendida: pinaroli.id);
      expect(find.byKey(const Key('central_barra_apagar')), findsOneWidget, reason: 'la central se ve prendida');
      expect(texto(tester, 'jefe_en_vivo'), contains('por la red del salón, haya internet o no'));
      expect(texto(tester, 'jefe_en_vivo'), isNot(contains('cuando las cajas suben sus ventas')));
    });

    testWidgets('lo de la notebook se recuenta solo: al subir, pasa a "Todo subido"', (tester) async {
      await unaNoche();
      await abrir(tester, pestana: PestanaBarraJefe.cajas, centralPrendida: pinaroli.id);
      expect(texto(tester, 'central_barra_esta_notebook'), contains('subiendo'),
          reason: 'la caja y la venta de la noche todavía no subieron');
      prueba.barra.subioTodo();
      await tester.pump(kRecuentoDeLaNotebook);
      await tester.pump();
      expect(texto(tester, 'central_barra_esta_notebook'), 'Esta notebook: Todo subido');
      operadores.conexion.cambiar(AppConnectivity.offline);
      await tester.pump();
      await tester.pump();
      expect(texto(tester, 'central_barra_esta_notebook'), 'Esta notebook: sin internet · nada por subir');
    });

    testWidgets('con la central prendida para otra fiesta, esta dice lo de siempre', (tester) async {
      await unaNoche();
      await abrir(tester, pestana: PestanaBarraJefe.cajas, centralPrendida: rotonda.id);
      expect(find.byKey(const Key('central_barra_prender')), findsOneWidget);
      expect(texto(tester, 'jefe_en_vivo'), contains('cuando las cajas suben sus ventas'));
    });
  });

  group('en cada tamaño', () {
    for (final (nombre, tamano) in [
      ('un celular', const Size(390, 844)),
      ('una tablet parada', const Size(800, 1280)),
      ('la PC', const Size(1280, 860)),
    ]) {
      testWidgets('en $nombre las tres pestañas no se desbordan', (tester) async {
        hoy = DateTime(2026, 12, 4, 23); // la noche de las ventas
        prueba.barra.precio(pinaroli.id, fernet, 6000, stock: 10, aviso: 4);
        final caja = await prueba.barra.abrirCaja(
          eventoId: pinaroli.id,
          operadorId: 'm',
          operadorNombre: 'Marta',
          numeroCaja: 1,
        );
        await prueba.barra.vender(
          caja: caja,
          renglones: [RenglonVenta(productoId: fernet.id, nombre: fernet.nombre, precio: 6000, cantidad: 2)],
          medio: MedioBarra.efectivo,
          efectivo: 12000,
          quien: 'Marta',
        );
        await abrir(tester, tamano: tamano);
        expect(tester.takeException(), isNull);
        for (final p in ['precios', 'cajas']) {
          await tocar(tester, find.byKey(Key('jefe_pestana_$p')));
          expect(tester.takeException(), isNull, reason: p);
        }
        await tocar(tester, find.byKey(Key('jefe_caja_${caja.id}')));
        expect(tester.takeException(), isNull);
      });
    }
  });
}

/// Un Bluetooth sin ningún aparato: para abrir la elección de la impresora en un test.
class _CanalSinNada implements CanalBle {
  @override
  Future<void> pedirPermisos() async {}

  @override
  Future<List<DispositivoBle>> emparejados() async => const [];

  @override
  Stream<DispositivoBle> buscar() => const Stream.empty();

  @override
  Future<void> dejarDeBuscar() async {}

  @override
  Future<void> conectar(String id) async => throw StateError('no hay ninguna');

  @override
  Future<void> desconectar(String id) async {}

  @override
  Future<bool> estaConectado(String id) async => false;

  @override
  Future<List<CaracteristicaBle>> caracteristicas(String id) async => const [];

  @override
  Future<int> pedirMtu(String id, int mtu) async => 20;

  @override
  Future<void> escribir(String id, CaracteristicaBle c, Uint8List bytes) async {}

  @override
  Stream<Uint8List> escuchar(String id, CaracteristicaBle c) => const Stream.empty();
}
