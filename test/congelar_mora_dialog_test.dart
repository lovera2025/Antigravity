// La pantalla de Congelar la mora (6.2.1): el diálogo con los montos del
// ejemplo de PÉREZ, el aviso celeste para todos, y que solo el jefe tenga el
// botón y pueda guardar.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mora_congelada.dart';
import 'package:arguello_events/features/eventos/widgets/congelar_mora_dialog.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

const _id = 'c0000000-0000-4000-8000-0000000000aa';

final _perez = ContratoAlumno(
  id: _id,
  eventoId: 'e0000000-0000-4000-8000-000000000001',
  nombreAlumno: 'PÉREZ, JUAN',
  cantidadAcompanantes: 0,
  montoTotalPactado: 270000,
  saldoDeudor: 180000,
  cuotasPagadas: 3,
  totalCuotas: 9,
  createdAt: DateTime.utc(2026, 3, 30, 3),
);

Future<void> _abrir(WidgetTester tester, DateTime hoy) async {
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: CongelarMoraDialog(contrato: _perez, moraCobradaHistorial: 0, hoy: hoy),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  tearDown(MoraCongelada.vaciar);

  test('los montos de los botones, antes de tocar', () {
    final congelada = MoraCongelada.nada.congelar(cuotas: {4, 5}, dia: DateTime(2026, 10, 23));
    MoraCongelada.poner(_id, congelada);
    final m = montosAlDescongelar(_perez, congelada,
        cuotas: {4, 5}, moraCobradaHistorial: 0, hoy: DateTime(2026, 11, 2));
    expect(m.mantener, closeTo(25200 + 15900, 0.01));
    expect(m.recalcular, closeTo(28200 + 18900, 0.01));
    // Calcular "Recalcular" no cambia lo congelado.
    expect(MoraCongelada.de(_id).pausas, congelada.pausas);
  });

  test('el texto del aviso', () {
    expect(textoMoraCongelada(MoraCongelada.nada), isNull);
    final t = textoMoraCongelada(
      MoraCongelada.nada.congelar(cuotas: {5, 4}, dia: DateTime(2026, 10, 23)),
    );
    expect(t, contains('Mora congelada desde 23/10'));
    expect(t, endsWith('C4, C5'));
    expect(
      textoMoraCongelada(MoraCongelada.nada.congelar(todas: true, dia: DateTime(2026, 10, 23))),
      endsWith('todas las cuotas'),
    );
  });

  testWidgets('sin nada congelado abre "Congelar" con las cuotas vencidas', (tester) async {
    await _abrir(tester, DateTime(2026, 10, 23));
    expect(find.text('Congelar mora'), findsOneWidget);
    expect(find.byKey(const Key('cuota_4')), findsOneWidget);
    expect(find.byKey(const Key('cuota_6')), findsOneWidget);
    expect(find.text('Queda congelada en \$ 48.000,00'), findsOneWidget);

    // Destildar la 6 baja el monto.
    await tester.tap(find.byKey(const Key('cuota_6')));
    await tester.pump();
    expect(find.text('Queda congelada en \$ 41.100,00'), findsOneWidget);
  });

  testWidgets('con algo congelado abre "Mora congelada" con Mantener y Recalcular', (tester) async {
    MoraCongelada.poner(_id, MoraCongelada.nada.congelar(cuotas: {4, 5}, dia: DateTime(2026, 10, 23)));
    await _abrir(tester, DateTime(2026, 11, 2));
    expect(find.text('Mora congelada'), findsOneWidget);
    expect(find.text('\$ 41.100,00'), findsOneWidget);
    expect(find.text('\$ 47.100,00'), findsOneWidget);
    expect(find.byKey(const Key('congelar_otra')), findsOneWidget);
  });

  testWidgets('el aviso celeste se ve solo si hay algo congelado', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AvisoMoraCongelada(contratoId: _id))));
    expect(find.byKey(const Key('mora_congelada_$_id')), findsNothing);
    MoraCongelada.poner(_id, MoraCongelada.nada.congelar(todas: true, dia: DateTime(2026, 10, 23)));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AvisoMoraCongelada(contratoId: _id, key: Key('otra')))));
    expect(find.byKey(const Key('mora_congelada_$_id')), findsOneWidget);
  });

  group('solo el jefe', () {
    final dialogo = File('lib/features/eventos/widgets/congelar_mora_dialog.dart').readAsStringSync();
    final grilla = File('lib/features/eventos/detalle_evento_masivo_screen.dart').readAsStringSync();

    test('lo único que guarda arranca con el freno de modo jefe', () {
      expect(RegExp(r'\.guardar\(').allMatches(dialogo), hasLength(1));
      final i = dialogo.indexOf('Future<void> _guardar(');
      final cuerpo = dialogo.substring(i, dialogo.indexOf('.guardar(', i));
      expect(cuerpo, contains('if (_frenaSinModoJefe()) return;'));
      expect(dialogo, contains('ref.read(esRolJefeProvider)'));
    });

    test('el copo de nieve de la fila va dentro de "if (modoJefe)"', () {
      final i = grilla.indexOf('icon: Icons.ac_unit');
      expect(i, greaterThan(0));
      final antes = grilla.substring(i - 200, i);
      expect(antes, contains('if (modoJefe)'));
      final abrir = grilla.substring(grilla.indexOf('Future<void> _mostrarCongelarMora('));
      expect(abrir.substring(0, 200), contains('if (!ref.read(esRolJefeProvider)) return;'));
    });

    test('el aviso va en la grilla, en el cobro y en Mi Empresa', () {
      expect(RegExp('AvisoMoraCongelada\\(').allMatches(grilla), hasLength(2));
      final cobro = File('lib/features/mi_empresa/widgets/cobro_masivos_tab.dart').readAsStringSync();
      expect(cobro, contains('AvisoMoraCongelada(contratoId: a.id'));
    });
  });
}
