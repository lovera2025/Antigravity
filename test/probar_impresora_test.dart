import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/barra/impresion/canal_ble.dart';
import 'package:arguello_events/features/barra/impresion/impresora_bluetooth.dart';
import 'package:arguello_events/features/barra/impresion/modelo_ticket.dart';
import 'package:arguello_events/features/barra/impresion/ticket_esc_pos.dart';
import 'package:arguello_events/features/barra/services/papel_de_la_barra.dart';
import 'package:arguello_events/features/barra/widgets/elegir_impresora_screen.dart';

import 'helpers/barra_en_memoria.dart';

/// Cuatro TP-POS58 emparejadas, todas con el mismo nombre (como en el salón).
class _CuatroImpresoras implements CanalBle {
  static const ids = [
    '86:67:7a:6e:ca:9d',
    '86:67:7a:11:41:07',
    '86:67:7a:22:b2:5e',
    '86:67:7a:33:0f:13',
  ];
  final conectadas = <String>{};

  @override
  Future<void> pedirPermisos() async {}

  @override
  Future<List<DispositivoBle>> emparejados() async => [
        for (final id in ids) DispositivoBle(id: id, nombre: 'TP-POS58', emparejado: true),
      ];

  /// Una búsqueda que no encuentra nada nuevo. No `Stream.empty()`: su `cancel` da un
  /// futuro de fuera del reloj de prueba y la búsqueda no terminaba nunca.
  @override
  Stream<DispositivoBle> buscar() => StreamController<DispositivoBle>().stream;

  @override
  Future<void> dejarDeBuscar() async {}

  @override
  Future<void> conectar(String id) async => conectadas.add(id);

  @override
  Future<void> desconectar(String id) async => conectadas.remove(id);

  @override
  Future<bool> estaConectado(String id) async => conectadas.contains(id);

  @override
  Future<List<CaracteristicaBle>> caracteristicas(String id) async => const [
        CaracteristicaBle(
          servicio: '49535343-fe7d-4ae5-8fa9-9fafd205e455',
          uuid: '49535343-8841-43f4-a8d4-ecbe34729bb3',
          escribe: true,
          escribeSinRespuesta: true,
        ),
      ];

  @override
  Future<int> pedirMtu(String id, int mtu) async => 185;

  @override
  Future<void> escribir(String id, CaracteristicaBle c, Uint8List bytes) async {}

  @override
  Stream<Uint8List> escuchar(String id, CaracteristicaBle c) => const Stream.empty();
}

/// IMPRIMIR UNA PRUEBA y el nombre de cada impresora (6.4.0): probarla sin cargar una
/// venta que nadie compró, y saber cuál es cuál entre cuatro que se llaman igual.
void main() {
  late _CuatroImpresoras canal;
  late PapelEnMemoria papel;
  final ahora = DateTime.utc(2026, 11, 9, 1, 15); // dom 08/11 22:15 en Argentina

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    canal = _CuatroImpresoras();
    papel = PapelEnMemoria();
  });

  group('el papel de prueba', () {
    test('el final del id, como en la etiqueta', () {
      expect(finDelId('86:67:7a:6e:ca:9d'), '…CA:9D');
      expect(finDelId('ab'), 'AB');
    });

    test('dice PRUEBA, cuál impresora es, los acentos y la regla; nada de una venta', () {
      final lineas = ModeloTicket.dePrueba(
        nombre: 'Impresora caja 1',
        id: '86:67:7a:6e:ca:9d',
        ahora: ahora,
      );
      final textos = [
        for (final l in lineas)
          switch (l) {
            GrandeTicket() => l.texto,
            TextoTicket() => l.texto,
            _ => '',
          },
      ];
      expect(textos.first, 'PRUEBA DE IMPRESORA');
      expect(lineas.whereType<GrandeTicket>().map((g) => g.texto), ['IMPRESORA CAJA 1']);
      expect(textos, contains('TP-POS58 - ...CA:9D'), reason: 'sin "…": la tabla 850 no lo tiene');
      expect(textos, contains('Dom 08/11/2026 - 22:15'));
      expect(textos, contains(lineaDeAcentos));
      expect(reglaDe32, hasLength(32));
      expect(textos, contains(reglaDe32));
      expect(textos.join(' '), contains('No es una venta'));
      expect(lineas.whereType<LogoTicket>(), isEmpty, reason: 'sin logo: ahorra papel');
      expect(lineas.whereType<QrTicket>(), isEmpty);
      expect(lineas.whereType<RenglonTicket>(), isEmpty, reason: 'ni precios ni totales');
      // Sin nombre puesto, sin la línea grande.
      expect(
        ModeloTicket.dePrueba(nombre: '', id: 'x', ahora: ahora).whereType<GrandeTicket>(),
        isEmpty,
      );
    });

    test('la pantalla no anota nada de la barra: no es una venta ni un vale', () {
      final fuente = File('lib/features/barra/widgets/elegir_impresora_screen.dart')
          .readAsStringSync();
      for (final prohibido in ['anotarVale', 'barra_vales', 'vender(', 'barraDeLaCaja']) {
        expect(fuente, isNot(contains(prohibido)), reason: prohibido);
      }
    });
  });

  Future<ImpresoraBluetooth> abrir(WidgetTester tester, {ImpresoraBluetooth? impresora}) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final i = impresora ?? ImpresoraBluetooth(canal, recordada: const ImpresoraRecordada());
    await tester.pumpWidget(MaterialApp(
      home: ElegirImpresoraScreen(impresora: i, papel: papel, ahora: () => ahora),
    ));
    // Sin impresora elegida, la búsqueda corre 10 s con la ruedita.
    await tester.pump();
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    return i;
  }

  Future<void> tocar(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  testWidgets('las cuatro se llaman igual: cada una muestra el final de su id', (tester) async {
    await abrir(tester);
    for (final id in _CuatroImpresoras.ids) {
      final fila = find.byKey(Key('impresora_encontrada_$id'));
      expect(fila, findsOneWidget);
      expect(find.descendant(of: fila, matching: find.textContaining(finDelId(id))), findsOneWidget);
    }
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('IMPRIMIR UNA PRUEBA saca el papel corto y dice que salió', (tester) async {
    await abrir(tester);
    await tocar(tester, find.descendant(
      of: find.byKey(Key('impresora_encontrada_${_CuatroImpresoras.ids.first}')),
      matching: find.text('CONECTAR'),
    ));
    await tocar(tester, find.byKey(const Key('impresora_probar')));
    expect(papel.papeles, hasLength(1));
    expect(papel.papeles.single.first, 'PRUEBA DE IMPRESORA');
    expect(papel.papeles.single, contains('TP-POS58 - ...CA:9D'));
    expect(find.text(kSalioLaPrueba), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('sin papel, lo dice', (tester) async {
    papel.sinRollo = true;
    await abrir(tester);
    await tocar(tester, find.descendant(
      of: find.byKey(Key('impresora_encontrada_${_CuatroImpresoras.ids.first}')),
      matching: find.text('CONECTAR'),
    ));
    await tocar(tester, find.byKey(const Key('impresora_probar')));
    expect(papel.papeles, isEmpty);
    expect(find.text(kSinPapel), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('el nombre: se pone, sale en el papel, queda al volver y al elegir de nuevo',
      (tester) async {
    final id = _CuatroImpresoras.ids.first;
    await abrir(tester);
    await tocar(tester, find.descendant(
      of: find.byKey(Key('impresora_encontrada_$id')),
      matching: find.text('CONECTAR'),
    ));
    await tester.pump(const Duration(seconds: 11));
    await tocar(tester, find.byKey(const Key('impresora_nombre')));
    await tester.enterText(find.byKey(const Key('impresora_nombre_texto')), 'Impresora caja 3');
    await tocar(tester, find.byKey(const Key('impresora_nombre_guardar')));
    expect(
      tester.widget<Text>(find.byKey(const Key('impresora_elegida_nombre'))).data,
      'Impresora caja 3',
    );
    await tocar(tester, find.byKey(const Key('impresora_probar')));
    expect(papel.papeles.single, contains('IMPRESORA CAJA 3'));

    // Otra vez, con la app recién abierta: el nombre quedó en el equipo.
    await tester.pumpWidget(const SizedBox());
    await abrir(tester);
    expect(
      tester.widget<Text>(find.byKey(const Key('impresora_elegida_nombre'))).data,
      'Impresora caja 3',
    );

    // CAMBIAR: en la lista, esa se reconoce por el nombre.
    await tester.tap(find.byKey(const Key('impresora_cambiar')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 11));
    final fila = find.byKey(Key('impresora_encontrada_$id'));
    expect(find.descendant(of: fila, matching: find.textContaining('Impresora caja 3')), findsOneWidget);
    expect(
      find.descendant(of: fila, matching: find.textContaining('ya la usaste en este equipo')),
      findsOneWidget,
    );
    final otra = find.byKey(Key('impresora_encontrada_${_CuatroImpresoras.ids[1]}'));
    expect(find.descendant(of: otra, matching: find.textContaining('Impresora caja 3')), findsNothing);
    await tester.pump(const Duration(seconds: 11));
  });

  test('sin nombre, la impresora se llama como el aparato', () async {
    final i = ImpresoraBluetooth(canal, recordada: const ImpresoraRecordada());
    const e = ImpresoraElegida(id: 'x', nombre: 'TP-POS58');
    expect(await i.nombreDe(e), 'TP-POS58');
    await i.ponerApodo('x', '  Caja 2  ');
    expect(await i.nombreDe(e), 'Caja 2');
    await i.ponerApodo('x', '');
    expect(await i.nombreDe(e), 'TP-POS58');
  });

  test('un apodo guardado roto no rompe nada', () async {
    SharedPreferences.setMockInitialValues({ImpresoraRecordada.claveApodos: '{no es json'});
    expect(await const ImpresoraRecordada().apodos(), isEmpty);
  });
}
