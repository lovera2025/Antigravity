import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/retiro_entradas.dart';
import 'package:arguello_events/features/eventos/widgets/entrega_entradas_dialog.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/entradas_retiro.dart';

ContratoAlumno _alumno() => ContratoAlumno(
      id: 'a',
      eventoId: 'e',
      nombreAlumno: 'BENÍTEZ, JOAQUÍN',
      cantidadAcompanantes: 2,
      nombresAcompanantes: const ['BENÍTEZ, LAURA', 'BENÍTEZ, JORGE'],
      montoTotalPactado: 300000 + 70000 + 24000,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000,
      mesaExtraCantidad: 1,
      sillasExtraCantidad: 3,
      sillasExtraPrecioTotal: 24000,
      cursoDivision: '5° A',
      numeroMesa: MesasExtraUtils.formatearAsignacionMesas(const [13, 14]),
    );

const _alDia = DeudaAlumno(saldoFicha: 0, saldoPagos: 0, mora: 0);

/// Abre el diálogo y lo deja abierto para que el test lo use.
Future<void> _abrir(
  WidgetTester tester, {
  DeudaAlumno deuda = _alDia,
  BloqueoRetiro bloqueo = BloqueoRetiro.ninguno,
  EntradasRetiro? retiro,
  Map<String, List<TramoTalonario>> deOtros = const {},
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => mostrarEntregaEntradasDialog(
                context: context,
                alumno: _alumno(),
                entradas: RetiroEntradas.entradasDe(_alumno()),
                deuda: deuda,
                bloqueo: bloqueo,
                retiro: retiro,
                deOtros: deOtros,
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('si debe, no hay formulario: solo ir a cobrar', (tester) async {
    AccionEntrega? accion;
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async => accion = await mostrarEntregaEntradasDialog(
                context: context,
                alumno: _alumno(),
                entradas: RetiroEntradas.entradasDe(_alumno()),
                deuda: const DeudaAlumno(saldoFicha: 30000, saldoPagos: 30000, mora: 3500),
                bloqueo: BloqueoRetiro.debe,
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Debe'), findsWidgets);
    expect(find.text('CONFIRMAR ENTREGA'), findsNothing);
    await tester.tap(find.text('IR A COBRAR'));
    await tester.pumpAndSettle();
    expect(accion, isA<IrACobrar>());
  });

  testWidgets('sin completar, marca lo que falta y no entrega', (tester) async {
    await _abrir(tester);
    expect(find.text('3'), findsOneWidget); // VIP
    expect(find.text('16'), findsOneWidget); // generales
    await tester.tap(find.text('CONFIRMAR ENTREGA'));
    await tester.pumpAndSettle();
    expect(find.text('Escribí los números del talonario.'), findsOneWidget);
    expect(find.text('Elegí quién retira.'), findsOneWidget);
    expect(find.text('Escribí nombre y apellido.'), findsOneWidget);
    expect(
      find.text('Falta que escriba su nombre y apellido en la planilla.'),
      findsOneWidget,
    );
    // Sigue abierto.
    expect(find.text('CONFIRMAR ENTREGA'), findsOneWidget);
  });

  testWidgets('completo, devuelve la entrega con los números del talonario',
      (tester) async {
    AccionEntrega? accion;
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async => accion = await mostrarEntregaEntradasDialog(
                context: context,
                alumno: _alumno(),
                entradas: RetiroEntradas.entradasDe(_alumno()),
                deuda: _alDia,
                bloqueo: BloqueoRetiro.ninguno,
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Del'), '1043');
    await tester.pump();
    expect(find.text('al 1058'), findsOneWidget);
    await tester.tap(find.text('Madre'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Nombre y apellido de quien retira'),
      'Laura Benítez',
    );
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.tap(
      find.text('Escribió su nombre y apellido en la planilla de papel'),
    );
    await tester.pump();
    await tester.tap(find.text('CONFIRMAR ENTREGA'));
    await tester.pumpAndSettle();

    expect(accion, isA<EntregarEntradas>());
    final e = accion! as EntregarEntradas;
    expect(e.tramos, const [TramoTalonario(1043, 1058)]);
    expect(e.parentesco, ParentescoRetiro.madre);
    expect(e.nombre, 'Laura Benítez');
    expect(e.menores10, 1);
  });

  testWidgets('si los números ya se dieron, no deja entregar', (tester) async {
    await _abrir(
      tester,
      deOtros: {
        'PÉREZ, JUAN': const [TramoTalonario(1050, 1060)],
      },
    );
    await tester.enterText(find.widgetWithText(TextField, 'Del'), '1043');
    await tester.tap(find.text('Padre'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Nombre y apellido de quien retira'),
      'Hugo Benítez',
    );
    await tester.tap(
      find.text('Escribió su nombre y apellido en la planilla de papel'),
    );
    await tester.pump();
    await tester.tap(find.text('CONFIRMAR ENTREGA'));
    await tester.pumpAndSettle();
    expect(
      find.text('El 1050 ya se le dio a PÉREZ, JUAN (1050 al 1060).'),
      findsOneWidget,
    );
    expect(find.text('CONFIRMAR ENTREGA'), findsOneWidget);
  });

  testWidgets('otra persona pide motivo y autorización', (tester) async {
    await _abrir(tester);
    await tester.tap(find.text('Otra persona'));
    await tester.pump();
    expect(
      find.text('Trajo la autorización firmada por la familia'),
      findsOneWidget,
    );
    await tester.tap(find.text('CONFIRMAR ENTREGA'));
    await tester.pumpAndSettle();
    expect(find.text('Escribí por qué no viene un familiar directo.'), findsOneWidget);
    expect(
      find.text('Sin autorización firmada no se entrega a otra persona.'),
      findsOneWidget,
    );
  });

  testWidgets('ya retiró: se ve lo que se llevó y se puede anular con motivo',
      (tester) async {
    final entregado = RetiroEntradas.nuevaEntrega(
      alumno: _alumno(),
      entradas: RetiroEntradas.entradasDe(_alumno()),
      tramos: const [TramoTalonario(1043, 1058)],
      menores10: 1,
      parentesco: ParentescoRetiro.madre,
      nombre: 'Laura Benítez',
      quien: 'Operador',
      ahora: DateTime.utc(2026, 11, 12, 21, 40),
    );
    AccionEntrega? accion;
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async => accion = await mostrarEntregaEntradasDialog(
                context: context,
                alumno: _alumno(),
                entradas: RetiroEntradas.entradasDe(_alumno()),
                deuda: _alDia,
                bloqueo: BloqueoRetiro.ninguno,
                retiro: entregado,
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.textContaining('LAURA BENÍTEZ'), findsOneWidget);
    expect(find.textContaining('1043 al 1058'), findsOneWidget);

    await tester.tap(find.text('ANULAR ENTREGA'));
    await tester.pump();
    await tester.tap(find.text('CONFIRMAR ANULACIÓN'));
    await tester.pump();
    expect(find.text('Escribí el motivo.'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Por qué se anula'),
      'Se equivocó de alumno',
    );
    await tester.tap(find.text('CONFIRMAR ANULACIÓN'));
    await tester.pumpAndSettle();
    expect(accion, isA<AnularEntrega>());
    expect((accion! as AnularEntrega).motivo, 'Se equivocó de alumno');
  });
}
