// "Estilo y armado" con los predios con nombre (6.1.0): una tarjeta por
// predio, con su dibujo, y el menú ⋯ para renombrarlo o borrarlo.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';
import 'package:arguello_events/features/plano/modelo/estado_plano.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/predios_del_salon.dart';
import 'package:arguello_events/features/plano/widgets/elegir_plano_dialog.dart';
import 'package:arguello_events/features/plano/widgets/vista_plano.dart';
import 'package:arguello_events/models/predio.dart';

final _ahora = DateTime.utc(2026, 10, 20, 12);
const _idA = 'd0000000-0000-4000-8000-00000000000a';
const _idB = 'd0000000-0000-4000-8000-00000000000b';
const _buenaVista = PlayonReal(frenteM: 20, fondoM: 24, profundidadM: 25);

Predio _predio(String id, String nombre, PlayonReal playon) =>
    PrediosDelSalon.guardarComo(
      nombre: nombre,
      armado: ArmarAMedida.vacio(playon),
      playon: playon,
      guardados: const [],
      hechoPor: 'Jefe',
      ahora: _ahora,
      idNuevo: id,
    ).predio!;

/// Lo que la pantalla haría al renombrar o borrar: anota y contesta.
class _Acciones {
  List<Predio> predios;
  final renombrados = <(String, String)>[];
  final borrados = <String>[];

  _Acciones(this.predios);

  AccionesPredios get acciones => AccionesPredios(
        onRenombrar: (p, nombre) async {
          renombrados.add((p.id, nombre));
          predios = [
            for (final x in predios)
              x.id == p.id
                  ? PrediosDelSalon.renombrar(x, nombre,
                          guardados: predios, hechoPor: 'Jefe', ahora: _ahora)
                      .predio!
                  : x,
          ];
          return (predios: predios, texto: 'Predio renombrado.');
        },
        onBorrar: (p) async {
          borrados.add(p.id);
          predios = [
            for (final x in predios)
              if (x.id != p.id) x,
          ];
          return (predios: predios, texto: 'Predio borrado.');
        },
      );
}

class _Resultado {
  EleccionPlano? eleccion;
  bool cerrado = false;
}

Future<_Resultado> _abrir(
  WidgetTester tester, {
  required List<Predio> predios,
  _Acciones? acciones,
  MedidasPlano medidas = const MedidasPlano(lugarMesaM: 2.3),
  List<OcupantePlano> ocupantes = const [],
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final r = _Resultado();
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: FuentesPlano.linea, useMaterial3: true),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                r.eleccion = await mostrarElegirPlano(
                  context: context,
                  mesasNecesarias: 60,
                  medidas: medidas,
                  ocupantes: ocupantes,
                  predios: predios,
                  accionesPredios: acciones?.acciones,
                );
                r.cerrado = true;
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return r;
}

Future<void> _tocar(WidgetTester tester, String clave) async {
  final donde = find.byKey(Key(clave));
  await tester.ensureVisible(donde);
  await tester.pumpAndSettle();
  await tester.tap(donde);
  await tester.pumpAndSettle();
}

String _tarjetaDe(String id) => 'armado_${ArmarAMedida.claveDePredio(id)}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(cargarFuentesPlano);

  final a = _predio(_idA, 'Buena Vista', _buenaVista);
  final b = _predio(_idB, 'Arenas', PlayonReal.costaSurubi);

  testWidgets('una tarjeta por predio, después del salón vacío, con su dibujo',
      (tester) async {
    await _abrir(tester, predios: [a, b]);
    final vacio = tester.getRect(
      find.byKey(const Key('armado_${ArmarAMedida.claveVacio}')),
    );
    final aMedida = tester.getRect(
      find.byKey(const Key('armado_${ArmarAMedida.claveArmado}')),
    );
    for (final id in [_idA, _idB]) {
      expect(find.byKey(Key(_tarjetaDe(id))), findsOneWidget);
      expect(find.byKey(Key('dibujo_predio_$id')), findsOneWidget);
      final r = tester.getRect(find.byKey(Key(_tarjetaDe(id))));
      // En el Wrap: después del vacío y antes de "A medida".
      expect(r.top > vacio.top || r.left > vacio.left, isTrue);
      expect(aMedida.top > r.top || aMedida.left > r.left, isTrue);
    }
    expect(
      find.descendant(
        of: find.byKey(Key(_tarjetaDe(_idA))),
        matching: find.text('20 × 24 × 25 m · sin mesas'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('elegirlo y LISTO: su espacio sin mesas, la distancia de la '
      'fiesta y sus medidas', (tester) async {
    final r = await _abrir(tester, predios: [a, b]);
    await _tocar(tester, _tarjetaDe(_idA));
    expect(find.byKey(const Key('nota_predio')), findsOneWidget);
    expect(find.byKey(const Key('nota_vacio')), findsNothing);
    await _tocar(tester, 'listo');
    final e = r.eleccion!;
    expect(e.armado.clave, 'predio@$_idA');
    expect(e.armado.nombre, 'Buena Vista');
    expect(e.armado.mesas, isEmpty);
    expect(e.armado.lugarOriginalM, 2.3);
    expect(e.playon, _buenaVista);
  });

  testWidgets('sin elegir un predio, LISTO no lleva medidas', (tester) async {
    final r = await _abrir(tester, predios: [a]);
    await _tocar(tester, 'listo');
    expect(r.eleccion!.armado.clave, ArmarAMedida.claveVacio);
    expect(r.eleccion!.playon, isNull);
  });

  testWidgets('con familias sentadas, el predio queda apagado con el motivo',
      (tester) async {
    await _abrir(
      tester,
      predios: [a],
      ocupantes: const [
        OcupantePlano(id: 'x', nombre: 'GÓMEZ, SOFÍA', numeros: [1]),
      ],
    );
    await _tocar(tester, _tarjetaDe(_idA));
    expect(find.byKey(const Key('nota_predio')), findsNothing,
        reason: 'no se eligió');
    expect(
      find.descendant(
        of: find.byKey(Key(_tarjetaDe(_idA))),
        matching: find.text('Ya hay familias con mesa: se quedarían sin la suya.'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('uno borrado o que no se puede leer no se ofrece', (tester) async {
    final borrado = PrediosDelSalon.borrar(b, hechoPor: 'Jefe', ahora: _ahora);
    final roto = Predio.fromMap(
      _predio('d0000000-0000-4000-8000-00000000000c', 'Roto',
              PlayonReal.costaSurubi)
          .toMap()
        ..['armado_json'] = '{}',
    );
    await _abrir(tester, predios: [a, borrado, roto]);
    expect(find.byKey(Key(_tarjetaDe(_idA))), findsOneWidget);
    expect(find.byKey(Key(_tarjetaDe(_idB))), findsNothing);
    expect(find.byKey(Key(_tarjetaDe(roto.id))), findsNothing);
  });

  testWidgets('sin acciones no hay menú ⋯', (tester) async {
    await _abrir(tester, predios: [a]);
    expect(find.byKey(const Key('menu_predio_$_idA')), findsNothing);
  });

  testWidgets('Renombrar desde el menú ⋯: lo guarda la pantalla y se ve',
      (tester) async {
    final acciones = _Acciones([a, b]);
    await _abrir(tester, predios: [a, b], acciones: acciones);
    await _tocar(tester, 'menu_predio_$_idA');
    await _tocar(tester, 'renombrar_predio');
    expect(find.text('Renombrar el predio'), findsOneWidget);
    // Con el nombre de otro, no.
    await tester.enterText(find.byKey(const Key('nombre_predio')), 'arenas');
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('listo_predio'))).enabled,
      isFalse,
    );
    await tester.enterText(
      find.byKey(const Key('nombre_predio')),
      'Buena Vista II',
    );
    await tester.pump();
    await _tocar(tester, 'listo_predio');
    expect(acciones.renombrados, [(_idA, 'Buena Vista II')]);
    expect(
      tester.widget<Text>(find.byKey(const Key('aviso_predios'))).data,
      'Predio renombrado.',
    );
    expect(
      find.descendant(
        of: find.byKey(Key(_tarjetaDe(_idA))),
        matching: find.text('Buena Vista II'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Borrar se pide dos veces; si era el elegido, vuelve el salón '
      'vacío', (tester) async {
    final acciones = _Acciones([a, b]);
    final r = await _abrir(tester, predios: [a, b], acciones: acciones);
    await _tocar(tester, _tarjetaDe(_idA));
    await _tocar(tester, 'menu_predio_$_idA');
    await _tocar(tester, 'borrar_predio');
    expect(find.text('¿Borrar el predio "Buena Vista"?'), findsOneWidget);
    expect(acciones.borrados, isEmpty, reason: 'falta confirmarlo');
    await tester.tap(find.text('CANCELAR').last);
    await tester.pumpAndSettle();
    expect(acciones.borrados, isEmpty);

    await _tocar(tester, 'menu_predio_$_idA');
    await _tocar(tester, 'borrar_predio');
    await _tocar(tester, 'confirmar_borrar_predio');
    expect(acciones.borrados, [_idA]);
    expect(find.byKey(Key(_tarjetaDe(_idA))), findsNothing);
    expect(find.byKey(Key(_tarjetaDe(_idB))), findsOneWidget);
    await _tocar(tester, 'listo');
    expect(r.eleccion!.armado.clave, ArmarAMedida.claveVacio);
  });

  testWidgets('el estilo elegido dibuja también el predio', (tester) async {
    await _abrir(tester, predios: [a]);
    await _tocar(tester, _tarjetaDe(_idA));
    // Las tarjetas de estilo muestran el salón elegido: el del predio. Más
    // el dibujo chico de su tarjeta.
    final claves = [
      for (final v in tester.widgetList<VistaPlano>(find.byType(VistaPlano)))
        v.armado.clave,
    ];
    expect(claves.where((c) => c == 'predio@$_idA').length,
        EstiloPlano.values.length + 1);
  });
}
