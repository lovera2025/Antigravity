// STOCK, la pantalla del repositor de barra (28-nov-2026, para la Técnica del 4-dic),
// montada de verdad con la barra en memoria: lo que hay en cada barra y en el depósito,
// REPONER, FALTANTE, ANOTAR LO QUE HAY, ENTRÓ MERCADERÍA y VOY EN CAMINO. La encargada la
// ve para mirar. Sin plata en ninguna parte.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/barra/cuentas/reglas_de_la_barra.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/providers/barra_del_jefe_provider.dart';
import 'package:arguello_events/features/barra/repositor/stock_de_las_barras_screen.dart';
import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/models/evento.dart';

import 'helpers/barra_en_memoria.dart';
import 'helpers/operadores_en_memoria.dart';

const _nico = 'a0000000-0000-4000-8000-000000000009';

/// Quién usa el aparato, que puede cambiar con una ventana abierta.
class _Rol extends Notifier<RolEnLaBarra?> {
  @override
  RolEnLaBarra? build() => RolEnLaBarra.repositor;

  void poner(RolEnLaBarra? r) => state = r;
}

final _rol = NotifierProvider<_Rol, RolEnLaBarra?>(_Rol.new);

void main() {
  late OperadoresEnPrueba operadores;
  late BarraEnPrueba prueba;
  late Evento fiesta;
  late ProductoBarra speed, cerveza, agua;
  late CajaBarra cajaDeLaUno, cajaDeLaDos;

  // La noche de la fiesta (4-dic, 23:30 en Argentina).
  final ahora = DateTime.utc(2026, 12, 5, 2, 30);

  BarraEnMemoria b() => prueba.barra;

  Future<void> reparto(ProductoBarra p, String barra, int arranque, {int? aviso}) => b().guardarReparto(
        StockEnLaBarra.para(
          eventoId: fiesta.id,
          productoId: p.id,
          barra: barra,
          arranque: arranque,
          aviso: aviso,
          ahora: ahora,
        ),
        quien: 'Jefe',
      );

  Future<void> vender(CajaBarra caja, ProductoBarra p, int cantidad) => b().vender(
        caja: caja,
        renglones: [RenglonVenta(productoId: p.id, nombre: p.nombre, precio: 5000, cantidad: cantidad)],
        medio: MedioBarra.efectivo,
        efectivo: 5000.0 * cantidad,
        quien: 'Marta',
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    operadores = OperadoresEnPrueba();
    operadores.operadores.lista.add(operadorDePrueba(_nico, 'Nico', '5555'));
    prueba = BarraEnPrueba();
    fiesta = fiestaDePrueba(BarraEnPrueba.id(1), 'TÉCNICA PINAROLI', DateTime(2026, 12, 4, 22));
    prueba.eventos.add(fiesta);
    speed = b().producto('Speed', categoria: 'Sin alcohol');
    cerveza = b().producto('Cerveza lata', categoria: 'Cervezas');
    agua = b().producto('Agua', categoria: 'Sin alcohol');
    // El stock general del jefe y el reparto: lo que no reparte es el depósito.
    b().precio(fiesta.id, speed, 5000, stock: 96);
    b().precio(fiesta.id, cerveza, 4000, stock: 240);
    b().precio(fiesta.id, agua, 2500, stock: 20);
    await reparto(speed, 'Barra 1', 24, aviso: 6);
    await reparto(speed, 'Barra 2', 24, aviso: 6);
    await reparto(cerveza, 'Barra 1', 60, aviso: 10);
    await reparto(cerveza, 'Barra 2', 60, aviso: 10);
    cajaDeLaUno = await b().abrirCaja(
      eventoId: fiesta.id,
      operadorId: 'm',
      operadorNombre: 'Marta',
      numeroCaja: 1,
      sede: 'Barra 1',
    );
    cajaDeLaDos = await b().abrirCaja(
      eventoId: fiesta.id,
      operadorId: 'l',
      operadorNombre: 'Lu',
      numeroCaja: 7,
      sede: 'Barra 2',
    );
    await vender(cajaDeLaUno, speed, 3);
    b().otrosSinSubir.clear();
    prueba.subidasDeLaBarra.clear();
  });

  Future<ProviderContainer> abrir(
    WidgetTester tester, {
    RolEnLaBarra? rol = RolEnLaBarra.repositor,
    Size tamano = const Size(900, 1300),
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...operadores.reemplazos,
        ...prueba.reemplazos,
        barraDelJefeProvider.overrideWithValue(prueba.barra),
        rolEnLaBarraProvider.overrideWith((ref) => ref.watch(_rol)),
        relojDeLaBarraProvider.overrideWithValue(() => ahora),
        enLaWebProvider.overrideWithValue(false),
      ],
      child: MaterialApp(home: StockDeLasBarrasScreen(fiesta: fiesta)),
    ));
    final c = ProviderScope.containerOf(tester.element(find.byType(StockDeLasBarrasScreen)));
    await c.read(appRoleProvider.notifier).entrarComoBarra(
          operadores.operadores.lista.single,
          const PermisosEfectivos(repositorBarra: true),
        );
    c.read(_rol.notifier).poner(rol);
    await tester.pumpAndSettle();
    return c;
  }

  Future<void> tocar(WidgetTester tester, String clave, {int veces = 1}) async {
    for (var i = 0; i < veces; i++) {
      await tester.ensureVisible(find.byKey(Key(clave)));
      await tester.pump();
      await tester.tap(find.byKey(Key(clave)));
      await tester.pumpAndSettle();
    }
  }

  String texto(WidgetTester tester, String clave) => tester.widget<Text>(find.byKey(Key(clave))).data!;

  bool apagado(WidgetTester tester, String clave) =>
      tester.widget<ButtonStyleButton>(find.byKey(Key(clave))).onPressed == null;

  List<String> loQueSeLee(WidgetTester tester) => [
        for (final t in tester.widgetList<Text>(find.byType(Text))) t.data ?? t.textSpan?.toPlainText() ?? '',
      ];

  List<MovimientoDeStock> anotados() => b().movimientosGuardados;

  group('lo que se ve', () {
    testWidgets('cada barra con lo que le queda, y el depósito con lo que no se repartió',
        (tester) async {
      await abrir(tester);
      // Abre en la Barra 1: arrancó con 24 y vendió 3.
      expect(texto(tester, 'stock_queda_${speed.id}'), 'Quedan 21');
      expect(texto(tester, 'stock_detalle_${speed.id}'), 'Arrancó con 24 · vendió 3');
      expect(texto(tester, 'stock_queda_${cerveza.id}'), 'Quedan 60');
      // El agua no se repartió: no se lleva en ninguna barra.
      expect(find.byKey(Key('stock_fila_${agua.id}')), findsNothing);

      await tocar(tester, 'stock_lugar_2');
      expect(texto(tester, 'stock_queda_${speed.id}'), 'Quedan 24', reason: 'lo que vendió la Barra 1 no le baja a la 2');

      await tocar(tester, 'stock_lugar_deposito');
      expect(texto(tester, 'stock_queda_${speed.id}'), 'Quedan 48');
      expect(texto(tester, 'stock_detalle_${speed.id}'), 'El jefe cargó 96 · a las barras 48');
      expect(texto(tester, 'stock_queda_${cerveza.id}'), 'Quedan 120');
    });

    testWidgets('no hay plata en ninguna parte', (tester) async {
      await abrir(tester);
      for (final lugar in ['stock_lugar_1', 'stock_lugar_2', 'stock_lugar_deposito']) {
        await tocar(tester, lugar);
        for (final t in loQueSeLee(tester)) {
          expect(t, isNot(contains(r'$')), reason: t);
        }
      }
      await tocar(tester, 'stock_reponer');
      for (final t in loQueSeLee(tester)) {
        expect(t, isNot(contains(r'$')), reason: t);
      }
    });

    testWidgets('dice hasta cuándo está al día lo que se ve', (tester) async {
      await abrir(tester);
      expect(texto(tester, 'stock_al_dia'), startsWith('Al día hasta las '));
    });

    testWidgets('sin reparto del jefe, lo dice y no ofrece nada', (tester) async {
      b().repartosGuardados.clear();
      await abrir(tester);
      expect(find.byKey(const Key('stock_sin_reparto')), findsOneWidget);
      expect(find.byKey(const Key('stock_reponer')), findsNothing);
    });

    testWidgets('en un celular entra sin cortes', (tester) async {
      await abrir(tester, tamano: const Size(390, 844));
      expect(tester.takeException(), isNull);
      await tocar(tester, 'stock_reponer');
      expect(tester.takeException(), isNull);
    });
  });

  group('REPONER', () {
    testWidgets('del depósito a una barra: baja del depósito, sube en la barra, queda a su '
        'nombre y se manda a subir', (tester) async {
      await abrir(tester);
      await tocar(tester, 'stock_reponer');
      await tocar(tester, 'reponer_producto_1'); // Speed (el primero es Cerveza lata)
      expect(texto(tester, 'reponer_del_jefe'), 'Speed: el jefe cargó 96 al principio · en el depósito quedan 48.');
      expect(texto(tester, 'reponer_cantidad_valor'), '12');
      expect(texto(tester, 'reponer_cuenta'), 'La cuenta da 33 (tenía 21 + 12).');
      await tocar(tester, 'reponer_guardar');

      final m = anotados().single;
      expect((m.tipo, m.cantidad, m.desde, m.hacia), (TipoMovimientoDeStock.reposicion, 12, kDeposito, 'Barra 1'));
      expect(m.hechoPor, 'Nico');
      expect(m.contadas, isNull, reason: 'dejó la cuenta del programa: no es un conteo');
      expect(prueba.subidasDeLaBarra, ['barra_stock_movimientos ${m.id}']);
      expect(texto(tester, 'stock_dicho'), 'Anotado: 12 Speed a la Barra 1.');
      expect(texto(tester, 'stock_queda_${speed.id}'), 'Quedan 33');
      expect(texto(tester, 'stock_detalle_${speed.id}'), 'Arrancó con 24 · entró 12 · vendió 3');
      await tocar(tester, 'stock_lugar_deposito');
      expect(texto(tester, 'stock_queda_${speed.id}'), 'Quedan 36');
    });

    testWidgets('el depósito es el límite: más no deja', (tester) async {
      await abrir(tester);
      await tocar(tester, 'stock_reponer');
      await tocar(tester, 'reponer_producto_1'); // Speed (el primero es Cerveza lata)
      await tocar(tester, 'reponer_cantidad_mas_24', veces: 2);
      expect(texto(tester, 'reponer_cantidad_valor'), '60');
      expect(texto(tester, 'reponer_error'), 'En el depósito quedan 48: no se puede reponer más.');
      expect(apagado(tester, 'reponer_guardar'), isTrue);
      expect(anotados(), isEmpty);
    });

    testWidgets('de la otra barra hace falta decir por qué, y como mucho lo que esa barra tiene',
        (tester) async {
      await abrir(tester);
      await tocar(tester, 'stock_reponer');
      await tocar(tester, 'reponer_producto_1'); // Speed (el primero es Cerveza lata)
      await tocar(tester, 'reponer_desde_1');
      expect(texto(tester, 'reponer_error'), 'Para pasar de una barra a otra, decí por qué.');
      expect(apagado(tester, 'reponer_guardar'), isTrue);
      await tester.enterText(find.byKey(const Key('reponer_nota')), 'En la 2 casi no lo piden');
      await tester.pumpAndSettle();
      await tocar(tester, 'reponer_guardar');
      final m = anotados().single;
      expect((m.tipo, m.desde, m.hacia, m.cantidad), (TipoMovimientoDeStock.traspaso, 'Barra 2', 'Barra 1', 12));
      expect(m.nota, 'En la 2 casi no lo piden');
      expect(texto(tester, 'stock_queda_${speed.id}'), 'Quedan 33');
      await tocar(tester, 'stock_lugar_2');
      expect(texto(tester, 'stock_queda_${speed.id}'), 'Quedan 12');
    });

    testWidgets('si contó otra cosa pide qué pasó, y queda anotado como un conteo', (tester) async {
      await abrir(tester);
      await tocar(tester, 'stock_reponer');
      await tocar(tester, 'reponer_producto_1'); // Speed (el primero es Cerveza lata)
      // La cuenta da 33; contó 31.
      await tocar(tester, 'reponer_quedan_menos', veces: 2);
      expect(texto(tester, 'reponer_no_da'), 'Contaste 2 menos que la cuenta. ¿Qué pasó con esas?');
      expect(apagado(tester, 'reponer_guardar'), isTrue);
      await tocar(tester, 'reponer_motivo_1'); // Congelada
      await tocar(tester, 'reponer_guardar');
      final m = anotados().single;
      expect((m.contadas, m.ajuste, m.motivo), (31, -2, 'Congelada'));
      expect(m.foto, isNotNull, reason: 'lleva hasta dónde conocía este equipo');
      expect(texto(tester, 'stock_queda_${speed.id}'), 'Quedan 31');
    });

    testWidgets('la llave: si deja de ser repositor con la ventana abierta, no se guarda', (tester) async {
      final c = await abrir(tester);
      await tocar(tester, 'stock_reponer');
      await tocar(tester, 'reponer_producto_1'); // Speed (el primero es Cerveza lata)
      c.read(_rol.notifier).poner(RolEnLaBarra.cajera);
      await tester.pumpAndSettle();
      await tocar(tester, 'reponer_guardar');
      expect(anotados(), isEmpty);
      expect(texto(tester, 'stock_dicho'), 'El stock lo anota el repositor.');
    });
  });

  group('lo vendido sin stock se descuenta de lo que se reponga', () {
    testWidgets('quedó en negativo: lo dice, y al reponer muestra la cuenta', (tester) async {
      // La Barra 2 vendió 26 con 24: 2 de más (sin señal no se frena).
      await vender(cajaDeLaDos, speed, 26);
      await abrir(tester);
      expect(texto(tester, 'stock_sin_stock_titulo'), 'Sin stock: no se puede vender');
      await tocar(tester, 'stock_lugar_2');
      expect(texto(tester, 'stock_queda_${speed.id}'), 'SIN STOCK · se vendieron 2 de más');
      await tocar(tester, 'stock_reponer_${speed.id}_2');
      expect(texto(tester, 'reponer_cuenta'),
          'Se vendieron 2 sin stock: 12 que traés − 2 ya vendidas = quedan 10.');
      await tocar(tester, 'reponer_guardar');
      expect(texto(tester, 'stock_queda_${speed.id}'), 'Quedan 10');
    });
  });

  group('VOY EN CAMINO', () {
    testWidgets('sin stock en una barra: avisa que va, se ve, y al reponer se cumple solo',
        (tester) async {
      await vender(cajaDeLaDos, speed, 24);
      await abrir(tester);
      final clave = '${speed.id}_2';
      expect(texto(tester, 'stock_alerta_$clave'), 'Speed · Barra 2');
      await tocar(tester, 'stock_voy_$clave');
      expect(texto(tester, 'stock_en_camino_$clave'), 'EN CAMINO · Nico');
      expect(find.byKey(Key('stock_voy_$clave')), findsNothing);
      final aviso = anotados().single;
      expect((aviso.tipo, aviso.hacia, aviso.avisosPrevios), (TipoMovimientoDeStock.enCamino, 'Barra 2', 0));
      expect(texto(tester, 'stock_dicho'), 'Avisado a la Barra 2: vas en camino con Speed.');

      await tocar(tester, 'stock_reponer_$clave');
      await tocar(tester, 'reponer_guardar');
      expect(anotados().last.respondeA, aviso.id, reason: 'la reposición contesta el aviso');
      expect(find.byKey(Key('stock_alerta_$clave')), findsNothing, reason: 'ya tiene stock');
    });

    testWidgets('YA NO VOY saca el aviso', (tester) async {
      await vender(cajaDeLaDos, speed, 24);
      await abrir(tester);
      final clave = '${speed.id}_2';
      await tocar(tester, 'stock_voy_$clave');
      await tocar(tester, 'stock_ya_no_voy_$clave');
      expect(find.byKey(Key('stock_en_camino_$clave')), findsNothing);
      expect(find.byKey(Key('stock_voy_$clave')), findsOneWidget);
      expect(anotados().last.tipo, TipoMovimientoDeStock.enCaminoNo);
    });

    testWidgets('"Está quedando poco" sale con el aviso que puso el jefe para esa barra', (tester) async {
      // A la Barra 1 le quedan 21; con 16 más vendidas quedan 5, y el aviso es 6.
      await vender(cajaDeLaUno, speed, 16);
      await abrir(tester);
      expect(find.byKey(const Key('stock_poco_titulo')), findsOneWidget);
      expect(texto(tester, 'stock_alerta_${speed.id}_1'), 'Speed · Barra 1 · quedan 5');
      // Con poco no hay "voy en camino": es para cuando no queda nada.
      expect(find.byKey(Key('stock_voy_${speed.id}_1')), findsNothing);
      expect(find.byKey(Key('stock_reponer_${speed.id}_1')), findsOneWidget);
    });
  });

  group('FALTANTE', () {
    testWidgets('pide el motivo; con "Otro", también qué pasó; y resta del stock', (tester) async {
      await abrir(tester);
      await tocar(tester, 'stock_faltante');
      expect(texto(tester, 'faltante_error'), 'Elegí el motivo.');
      expect(apagado(tester, 'faltante_guardar'), isTrue);
      await tocar(tester, 'faltante_motivo_4'); // Otro
      expect(texto(tester, 'faltante_error'), 'Contá qué pasó.');
      await tocar(tester, 'faltante_motivo_0'); // Rota
      await tocar(tester, 'faltante_cantidad_mas');
      await tocar(tester, 'faltante_guardar');
      final m = anotados().single;
      expect((m.tipo, m.cantidad, m.desde, m.motivo), (TipoMovimientoDeStock.faltante, 2, 'Barra 1', 'Rota'));
      // Speed no es el primero por nombre: el primero es Cerveza lata.
      expect(m.productoId, cerveza.id);
      expect(texto(tester, 'stock_queda_${cerveza.id}'), 'Quedan 58');
      expect(texto(tester, 'stock_detalle_${cerveza.id}'), 'Arrancó con 60 · faltó 2');
    });

    testWidgets('no pueden faltar más de las que hay', (tester) async {
      await abrir(tester);
      await tocar(tester, 'stock_faltante');
      await tocar(tester, 'faltante_producto_1'); // Speed: quedan 21
      await tocar(tester, 'faltante_motivo_0');
      await tocar(tester, 'faltante_cantidad_mas', veces: 21);
      expect(texto(tester, 'faltante_error'), 'Hay 21: no pueden faltar más.');
      expect(apagado(tester, 'faltante_guardar'), isTrue);
    });
  });

  group('ANOTAR LO QUE HAY', () {
    testWidgets('si da la cuenta se guarda; si no, pide qué pasó', (tester) async {
      await abrir(tester);
      await tocar(tester, 'stock_contar');
      await tocar(tester, 'conteo_producto_1'); // Speed
      expect(texto(tester, 'conteo_cuenta'), 'La cuenta del programa da 21.');
      expect(texto(tester, 'conteo_contadas_valor'), '21');
      await tocar(tester, 'conteo_contadas_menos');
      expect(texto(tester, 'conteo_no_da'), 'Falta 1. ¿Qué pasó?');
      expect(apagado(tester, 'conteo_guardar'), isTrue);
      await tocar(tester, 'conteo_motivo_3'); // Se perdió
      await tocar(tester, 'conteo_guardar');
      final m = anotados().single;
      expect((m.tipo, m.hacia, m.contadas, m.ajuste, m.motivo),
          (TipoMovimientoDeStock.conteo, 'Barra 1', 20, -1, 'Se perdió'));
      expect(texto(tester, 'stock_queda_${speed.id}'), 'Quedan 20');
    });
  });

  group('ENTRÓ MERCADERÍA', () {
    testWidgets('solo en el depósito, diciendo de dónde vino; recién ahí se puede reponer más',
        (tester) async {
      await abrir(tester);
      expect(find.byKey(const Key('stock_entrada')), findsNothing, reason: 'en una barra no');
      await tocar(tester, 'stock_lugar_deposito');
      await tocar(tester, 'stock_entrada');
      expect(texto(tester, 'entrada_error'), 'Decí de dónde vino.');
      expect(apagado(tester, 'entrada_guardar'), isTrue);
      await tester.enterText(find.byKey(const Key('entrada_de_donde')), 'Lo trajo el proveedor');
      await tester.pumpAndSettle();
      await tocar(tester, 'entrada_producto_1'); // Speed
      await tocar(tester, 'entrada_guardar');
      final m = anotados().single;
      expect((m.tipo, m.hacia, m.cantidad, m.nota), (TipoMovimientoDeStock.entrada, kDeposito, 12, 'Lo trajo el proveedor'));
      expect(texto(tester, 'stock_queda_${speed.id}'), 'Quedan 60');
      expect(texto(tester, 'stock_detalle_${speed.id}'), 'El jefe cargó 96 · a las barras 48 · entró 12');
    });
  });

  group('los movimientos', () {
    testWidgets('quedan escritos con la hora, quién y la nota, el más nuevo arriba', (tester) async {
      await abrir(tester);
      await tocar(tester, 'stock_movimientos');
      expect(find.byKey(const Key('movimientos_vacio')), findsOneWidget);
      await tester.tap(find.text('CERRAR'));
      await tester.pumpAndSettle();

      await tocar(tester, 'stock_reponer');
      await tocar(tester, 'reponer_producto_1'); // Speed
      await tester.enterText(find.byKey(const Key('reponer_nota')), 'De la heladera del fondo');
      await tester.pumpAndSettle();
      await tocar(tester, 'reponer_guardar');
      await tocar(tester, 'stock_faltante');
      await tocar(tester, 'faltante_motivo_1');
      await tocar(tester, 'faltante_guardar');

      await tocar(tester, 'stock_movimientos');
      final leido = loQueSeLee(tester).join('\n');
      expect(leido, contains('Speed · depósito → Barra 1'));
      expect(leido, contains('+12'));
      expect(leido, contains('"De la heladera del fondo" · Nico'));
      expect(leido, contains('Cerveza lata · Barra 1 · Congelada'));
      expect(leido, contains('−1'));
      // El más nuevo arriba.
      final primero = find.descendant(of: find.byKey(const Key('movimiento_0')), matching: find.byType(Text));
      expect(tester.widget<Text>(primero.first).data, contains('Congelada'));
    });
  });

  group('quién anota', () {
    testWidgets('la encargada la ve para mirar: no tiene ningún botón que anote', (tester) async {
      await vender(cajaDeLaDos, speed, 24);
      await abrir(tester, rol: RolEnLaBarra.encargada);
      expect(find.byKey(const Key('stock_solo_mirar')), findsOneWidget);
      expect(texto(tester, 'stock_queda_${speed.id}'), 'Quedan 21');
      for (final clave in [
        'stock_reponer',
        'stock_faltante',
        'stock_contar',
        'stock_entrada',
        'stock_voy_${speed.id}_2',
        'stock_reponer_${speed.id}_2',
      ]) {
        expect(find.byKey(Key(clave)), findsNothing, reason: clave);
      }
      // Lo que falta, sí lo ve.
      expect(find.byKey(Key('stock_alerta_${speed.id}_2')), findsOneWidget);
      expect(find.byKey(const Key('stock_movimientos')), findsOneWidget);
    });

    testWidgets('el jefe anota como el repositor; la cajera, nada', (tester) async {
      await abrir(tester, rol: RolEnLaBarra.jefe);
      expect(find.byKey(const Key('stock_reponer')), findsOneWidget);
      expect(find.byKey(const Key('stock_solo_mirar')), findsNothing);
      await abrir(tester, rol: RolEnLaBarra.cajera);
      expect(find.byKey(const Key('stock_reponer')), findsNothing);
    });
  });
}
