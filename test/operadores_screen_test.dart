import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/caja_sesiones/repositories/operadores_caja_repository.dart';
import 'package:arguello_events/features/caja_sesiones/repositories/permisos_operador_repository.dart';
import 'package:arguello_events/features/caja_sesiones/services/pin_de_operador.dart';
import 'package:arguello_events/features/caja_sesiones/widgets/operadores_caja_screen.dart';

import 'helpers/operadores_en_memoria.dart';

const _maxi = 'a0000000-0000-4000-8000-000000000001';
const _juan = 'a0000000-0000-4000-8000-000000000002';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('qué le falta a la ficha', () {
    final maxi = operadorDePrueba(_maxi, 'Maxi', '1234');

    String? problema(String nombre, String pin, {String? id, bool maestro = false}) =>
        problemaDelOperador(
          nombre: nombre,
          pin: pin,
          idPropio: id,
          otros: [maxi],
          esMaestro: maestro,
        );

    test('el nombre y el PIN de al menos 4 dígitos', () {
      expect(problema('  ', '5555'), 'Falta el nombre.');
      expect(problema('Ana', '123'), contains('al menos 4'));
      expect(problema('Ana', '5555'), isNull);
    });

    test('los PIN no chocan: ni el de otro ni el maestro', () {
      expect(problema('Ana', '1234'), 'Ese PIN ya lo tiene Maxi.');
      expect(problema('Ana', '2026', maestro: true), contains('modo jefe'));
    });

    test('el suyo propio sí: editar a Maxi sin cambiarle el PIN', () {
      expect(problema('Maxi', '1234', id: _maxi), isNull);
    });

    test('en palabras, lo que puede hacer', () {
      expect(textoDePermisos(PermisosEfectivos.soloCobros), 'Cobros');
      expect(
        textoDePermisos(const PermisosEfectivos(cobros: true, entradas: true)),
        'Cobros · Entradas',
      );
      expect(textoDePermisos(const PermisosEfectivos()), 'Sin permisos: no puede entrar');
    });
  });

  group('la pantalla', () {
    late OperadoresEnMemoria operadores;
    late PermisosEnMemoria permisos;

    Future<void> abrir(WidgetTester tester, {bool jefe = true}) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          operadoresCajaRepositoryProvider.overrideWithValue(operadores),
          permisosOperadorRepositoryProvider.overrideWithValue(permisos),
          esRolJefeProvider.overrideWith((ref) => jefe),
        ],
        child: const MaterialApp(home: OperadoresCajaScreen()),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> editar(WidgetTester tester, String nombre) async {
      final fila = find.ancestor(of: find.text(nombre), matching: find.byType(ListTile));
      await tester.tap(find.descendant(of: fila, matching: find.byIcon(Icons.edit_outlined)));
      await tester.pumpAndSettle();
    }

    bool tildada(WidgetTester tester, String clave) =>
        tester.widget<CheckboxListTile>(find.byKey(Key(clave))).value!;

    Future<void> guardar(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('operador_guardar')));
      await tester.pumpAndSettle();
    }

    setUp(() {
      operadores = OperadoresEnMemoria([operadorDePrueba(_maxi, 'Maxi', '1234'), operadorDePrueba(_juan, 'Juan', '4321')]);
      permisos = PermisosEnMemoria();
    });

    testWidgets('se llama OPERADORES y dice qué puede hacer cada uno', (tester) async {
      permisos.filas[_juan] = PermisosOperador.para(
        operadorId: _juan,
        permisos: const PermisosEfectivos(),
        ahora: DateTime.utc(2026, 11, 3),
      );
      await abrir(tester);
      expect(find.text('OPERADORES'), findsOneWidget);
      expect(find.text('OPERADORES DE CAJA'), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(const Key('permisos_de_$_maxi'))).data,
        'Cobros',
        reason: 'sin fila, es de Cobros',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('permisos_de_$_juan'))).data,
        'Sin permisos: no puede entrar',
      );
    });

    testWidgets('al abrir a uno de hoy, Cobros viene tildada', (tester) async {
      await abrir(tester);
      await editar(tester, 'Maxi');
      expect(tildada(tester, 'permiso_cobros'), isTrue);
      expect(tildada(tester, 'permiso_entradas'), isFalse);
      expect(tildada(tester, 'permiso_barra'), isFalse);
      expect(find.byKey(const Key('aviso_sin_cobros')), findsNothing);
    });

    testWidgets('guardar a uno de hoy sin tocar nada no le saca Cobros ni escribe',
        (tester) async {
      await abrir(tester);
      await editar(tester, 'Maxi');
      await guardar(tester);
      expect(permisos.filas, isEmpty);
      expect(permisos.guardados, isEmpty);
    });

    testWidgets('darle Entradas queda guardado, a nombre del jefe', (tester) async {
      await abrir(tester);
      await editar(tester, 'Maxi');
      await tester.tap(find.byKey(const Key('permiso_entradas')));
      await tester.pump();
      await guardar(tester);
      expect(permisos.filas[_maxi]!.permisos,
          const PermisosEfectivos(cobros: true, entradas: true));
      expect(permisos.guardados, ['Jefe']);
      expect(find.text('Cobros · Entradas'), findsOneWidget);
    });

    testWidgets('destildar Cobros avisa lo de las PCs viejas, y destildar todo dice que '
        'no va a poder entrar', (tester) async {
      await abrir(tester);
      await editar(tester, 'Maxi');
      await tester.tap(find.byKey(const Key('permiso_cobros')));
      await tester.pump();
      expect(find.byKey(const Key('aviso_sin_cobros')), findsOneWidget);
      expect(find.byKey(const Key('aviso_sin_permisos')), findsOneWidget);
      await guardar(tester);
      expect(permisos.filas[_maxi]!.permisos.ninguno, isTrue);
      expect(find.text('Sin permisos: no puede entrar'), findsOneWidget);
    });

    testWidgets('un PIN repetido se dice adentro, sin perder lo escrito', (tester) async {
      await abrir(tester);
      await tester.tap(find.byKey(const Key('operador_nuevo')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('operador_nombre')), 'Ana');
      await tester.enterText(find.byKey(const Key('operador_pin')), '1234');
      await guardar(tester);
      expect(find.text('Ese PIN ya lo tiene Maxi.'), findsOneWidget);
      expect(operadores.lista, hasLength(2), reason: 'no se guardó');
      expect(find.text('Ana'), findsOneWidget, reason: 'el nombre sigue escrito');
    });

    testWidgets('el PIN maestro tampoco se puede', (tester) async {
      await abrir(tester);
      await tester.tap(find.byKey(const Key('operador_nuevo')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('operador_nombre')), 'Ana');
      await tester.enterText(find.byKey(const Key('operador_pin')), '2026');
      await guardar(tester);
      expect(find.byKey(const Key('operador_problema')), findsOneWidget);
      expect(operadores.lista, hasLength(2));
    });

    testWidgets('uno nuevo sin tocar las casillas es de Cobros, como hasta ahora',
        (tester) async {
      await abrir(tester);
      await tester.tap(find.byKey(const Key('operador_nuevo')));
      await tester.pumpAndSettle();
      expect(tildada(tester, 'permiso_cobros'), isTrue);
      await tester.enterText(find.byKey(const Key('operador_nombre')), 'Ana');
      await tester.enterText(find.byKey(const Key('operador_pin')), '5555');
      await guardar(tester);
      expect(operadores.lista.map((o) => o.nombre), contains('Ana'));
      expect(permisos.filas, isEmpty);
      expect(find.text('Cobros'), findsNWidgets(3));
    });

    testWidgets('sin modo jefe se ve todo, apagado y con el motivo', (tester) async {
      await abrir(tester, jefe: false);
      expect(find.text('Maxi'), findsOneWidget);
      final nuevo = tester.widget<IconButton>(find.byKey(const Key('operador_nuevo')));
      expect(nuevo.onPressed, isNull);
      expect(nuevo.tooltip, 'Solo en modo jefe');
      for (final b in tester.widgetList<IconButton>(find.descendant(
        of: find.byType(ListTile),
        matching: find.byType(IconButton),
      ))) {
        expect(b.onPressed, isNull);
        expect(b.tooltip, 'Solo en modo jefe');
      }
    });
  });
}
