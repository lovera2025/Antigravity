import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/common/utils/solo_jefe.dart';
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/permisos_de_entrega.dart';
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
  PermisosDeEntrega permisos = const PermisosDeEntrega.oficina(esJefe: true),
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
                permisos: permisos,
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
                permisos: const PermisosDeEntrega.oficina(esJefe: true),
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
    // Solo la mesa del contrato va sin cargo: 8 lugares, 3 con cena y 5
    // generales. Las 11 de la mesa adicional y las sillas extra, aparte.
    expect(find.text('5'), findsOneWidget); // generales
    expect(
      find.text('Las 11 entradas de su mesa adicional y sus 3 sillas extra no van '
          'sin cargo: se compran aparte, al 50 %.'),
      findsOneWidget,
    );
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
                permisos: const PermisosDeEntrega.oficina(esJefe: true),
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
    expect(find.text('al 1047'), findsOneWidget);
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
    expect(e.tramos, const [TramoTalonario(1043, 1047)]);
    expect(e.parentesco, ParentescoRetiro.madre);
    expect(e.nombre, 'Laura Benítez');
    expect(e.menores10, 1);
  });

  testWidgets('si los números ya se dieron, no deja entregar', (tester) async {
    await _abrir(
      tester,
      deOtros: {
        'PÉREZ, JUAN': const [TramoTalonario(1045, 1060)],
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
      find.text('El 1045 ya se le dio a PÉREZ, JUAN (1045 al 1060).'),
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
      tramos: const [TramoTalonario(1043, 1047)],
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
                permisos: const PermisosDeEntrega.oficina(esJefe: true),
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
    expect(find.textContaining('1043 al 1047'), findsOneWidget);

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

  /// Abre el diálogo con [permisos] y devuelve lo que eligió quien atiende.
  Future<AccionEntrega? Function()> abrirCon(
    WidgetTester tester, {
    required PermisosDeEntrega permisos,
    DeudaAlumno deuda = const DeudaAlumno(saldoFicha: 70000, saldoPagos: 70000, mora: 0),
    BloqueoRetiro bloqueo = BloqueoRetiro.debe,
    EntradasRetiro? retiro,
    Listenable? cuentaCambio,
  }) async {
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
                deuda: deuda,
                bloqueo: bloqueo,
                permisos: permisos,
                retiro: retiro,
                cuentaCambio: cuentaCambio,
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return () => accion;
  }

  group('el mostrador de Entradas', () {
    const sinCobros = PermisosDeEntrega.mostrador(tieneCobros: false);
    const conCobros = PermisosDeEntrega.mostrador(tieneCobros: true);

    testWidgets('si debe y no tiene Cobros: que pase por caja, con el monto, y ENTENDIDO',
        (tester) async {
      final accion = await abrirCon(tester, permisos: sinCobros);
      expect(find.text('Debe \$ 70.000,00'), findsOneWidget);
      expect(find.textContaining('Que pase por caja a saldar todo'), findsOneWidget);
      expect(find.text('IR A COBRAR'), findsNothing);
      expect(find.text('PASAR A CAJA'), findsNothing);
      await tester.tap(find.text('ENTENDIDO'));
      await tester.pumpAndSettle();
      expect(accion(), isA<MandarACaja>());
    });

    testWidgets('con Cobros también: PASAR A CAJA', (tester) async {
      final accion = await abrirCon(tester, permisos: conCobros);
      expect(find.text('IR A COBRAR'), findsNothing);
      await tester.tap(find.text('PASAR A CAJA'));
      await tester.pumpAndSettle();
      expect(accion(), isA<PasarACaja>());
    });

    testWidgets('las mesas que no coinciden: sin EDITAR ALUMNO, y que lo revise el jefe',
        (tester) async {
      await abrirCon(
        tester,
        permisos: sinCobros,
        deuda: _alDia,
        bloqueo: BloqueoRetiro.mesasNoCoinciden,
      );
      expect(find.text('EDITAR ALUMNO'), findsNothing);
      expect(find.textContaining('Pedile al jefe que lo revise.'), findsOneWidget);
    });

    testWidgets('al día: el formulario, sin "Cambiar acompañantes"', (tester) async {
      await abrirCon(tester, permisos: sinCobros, deuda: _alDia, bloqueo: BloqueoRetiro.ninguno);
      expect(find.text('CONFIRMAR ENTREGA'), findsOneWidget);
      expect(find.text('Cambiar acompañantes'), findsNothing);
    });

    testWidgets('si pagó con el diálogo abierto, se cierra para volver a abrirlo',
        (tester) async {
      final cambio = ValueNotifier(0);
      final accion = await abrirCon(tester, permisos: sinCobros, cuentaCambio: cambio);
      cambio.value++;
      await tester.pumpAndSettle();
      expect(accion(), isA<VolverAAbrir>());
    });

    testWidgets('con el formulario abierto no se cierra solo', (tester) async {
      final cambio = ValueNotifier(0);
      final accion = await abrirCon(
        tester,
        permisos: sinCobros,
        deuda: _alDia,
        bloqueo: BloqueoRetiro.ninguno,
        cuentaCambio: cambio,
      );
      cambio.value++;
      await tester.pumpAndSettle();
      expect(find.text('CONFIRMAR ENTREGA'), findsOneWidget);
      expect(accion(), isNull);
    });
  });

  testWidgets('sin modo jefe, ANULAR ENTREGA se ve apagado con el motivo', (tester) async {
    final entregado = RetiroEntradas.nuevaEntrega(
      alumno: _alumno(),
      entradas: RetiroEntradas.entradasDe(_alumno()),
      tramos: const [TramoTalonario(1043, 1047)],
      menores10: 0,
      parentesco: ParentescoRetiro.madre,
      nombre: 'Laura Benítez',
      quien: 'Operador',
      ahora: DateTime.utc(2026, 11, 12, 21, 40),
    );
    await abrirCon(
      tester,
      permisos: const PermisosDeEntrega.oficina(esJefe: false),
      deuda: _alDia,
      bloqueo: BloqueoRetiro.ninguno,
      retiro: entregado,
    );
    final boton = tester.widget<OutlinedButton>(find.byKey(const Key('entrega_anular_apagado')));
    expect(boton.onPressed, isNull);
    expect(find.text(kSoloEnModoJefe), findsOneWidget);
    expect(find.textContaining('el jefe anula esta entrega'), findsNothing,
        reason: 'la cuenta no cambió');
  });
}
