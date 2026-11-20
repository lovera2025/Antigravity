// El diálogo de la entrega sin cargo, **en dos partes** (20-nov-2026): las
// pulseras VIP con cena y las entradas generales llegan en tandas distintas y se
// entregan cada una con su formulario (`FormularioEntregaParte`), su ✓ y quién
// las retiró. Hasta la 6.9.2 era un solo formulario con las 8 juntas y los
// números obligatorios: estos tests se reescribieron con la regla nueva.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/common/utils/solo_jefe.dart';
import 'package:arguello_events/features/entradas/cuentas/lugares_de_la_familia.dart';
import 'package:arguello_events/features/eventos/services/entrega_por_partes.dart';
import 'package:arguello_events/features/eventos/services/lugares_al_sorteo.dart';
import 'package:arguello_events/features/eventos/services/lugares_pagos.dart';
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/permisos_de_entrega.dart';
import 'package:arguello_events/features/eventos/services/retiro_entradas.dart';
import 'package:arguello_events/features/eventos/widgets/entrega_entradas_dialog.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/entradas_retiro.dart';
import 'package:arguello_events/models/entrega_entradas.dart';

/// BENÍTEZ: 2 acompañantes con nombre (3 VIP y 5 generales), una mesa
/// adicional y 3 sillas extra (11 que se compran aparte).
ContratoAlumno _alumno({List<String>? acompanantes, int? cantidad}) => ContratoAlumno(
      id: 'a',
      eventoId: 'e',
      nombreAlumno: 'BENÍTEZ, JOAQUÍN',
      cantidadAcompanantes: cantidad ?? (acompanantes ?? _dos).length,
      nombresAcompanantes: acompanantes ?? _dos,
      montoTotalPactado: 300000 + 70000 + 24000,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000,
      mesaExtraCantidad: 1,
      sillasExtraCantidad: 3,
      sillasExtraPrecioTotal: 24000,
      cursoDivision: '5° A',
      numeroMesa: MesasExtraUtils.formatearAsignacionMesas(const [13, 14]),
    );

const _dos = ['BENÍTEZ, LAURA', 'BENÍTEZ, JORGE'];

const _alDia = DeudaAlumno(saldoFicha: 0, saldoPagos: 0, mora: 0);

final _hora = DateTime.utc(2026, 11, 20, 15);

EntregaEntradas _entrega(
  ParteEntrega parte, {
  int? cantidad,
  List<TramoTalonario> tramos = const [],
  DateTime? ahora,
  String nombre = 'Laura Benítez',
}) =>
    EntregaEntradas.entrega(
      contratoAlumnoId: 'a',
      eventoId: 'e',
      parte: parte,
      cantidad: cantidad ?? (parte == ParteEntrega.pulseras ? 3 : 5),
      tramos: tramos,
      menores10: parte == ParteEntrega.pulseras ? 1 : 0,
      parentesco: ParentescoRetiro.madre,
      nombre: nombre,
      escribioEnPlanilla: true,
      hechoPor: 'Carla',
      deviceId: 'tablet-1',
      ahora: ahora ?? _hora,
    );

/// Lo de sus lugares adicionales, de los pagos de la mesa y las sillas: la
/// misma cuenta que VENDER.
LugaresDeLaFamilia _lugares({
  double mesa = 70000,
  double sillas = 24000,
  int compradas = 0,
}) {
  final a = _alumno();
  return LugaresDeLaFamilia(
    leCorresponden: APagarDeLaFamilia.de(a, pagos: _pagos(mesa, sillas)).conDescuento,
    pagas: APagarDeLaFamilia.de(a, pagos: _pagos(mesa, sillas)).conDescuentoPagas,
    compradas: compradas,
    textoDeLoQueFalta: APagarDeLaFamilia.de(a, pagos: _pagos(mesa, sillas)).textoAConfirmar,
  );
}

List<Map<String, dynamic>> _pagos(double mesa, double sillas) => [
      {'concepto': 'Cuota Base (9/9)', 'monto': 300000.0, 'monto_gross': 300000.0, 'anulado': 0},
      if (mesa > 0)
        {'concepto': 'Mesa Extra 1', 'monto': mesa, 'monto_gross': mesa, 'anulado': 0},
      if (sillas > 0)
        {'concepto': 'Sillas extra (1/1)', 'monto': sillas, 'monto_gross': sillas, 'anulado': 0},
    ];

/// Abre el diálogo y devuelve lo que eligió quien atiende (null mientras siga
/// abierto).
Future<AccionEntrega? Function()> _abrir(
  WidgetTester tester, {
  ContratoAlumno? alumno,
  DeudaAlumno deuda = _alDia,
  BloqueoRetiro bloqueo = BloqueoRetiro.ninguno,
  EntradasRetiro? retiro,
  List<EntregaEntradas> renglones = const [],
  Map<String, List<TramoTalonario>> deOtros = const {},
  PermisosDeEntrega permisos = const PermisosDeEntrega.oficina(esJefe: true),
  VentaAlCincuenta? venta,
  Listenable? cuentaCambio,
}) async {
  AccionEntrega? accion;
  final a = alumno ?? _alumno();
  await tester.binding.setSurfaceSize(const Size(1200, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => accion = await mostrarEntregaEntradasDialog(
                context: context,
                alumno: a,
                entradas: RetiroEntradas.entradasDe(a),
                estado: EstadoDeLaEntrega.deAlumno(a, retiro: retiro, renglones: renglones),
                deuda: deuda,
                bloqueo: bloqueo,
                permisos: permisos,
                retiro: retiro,
                renglones: renglones,
                deOtros: deOtros,
                cuentaCambio: cuentaCambio,
                venta: venta,
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
  return () => accion;
}

Future<void> _entregarCon(WidgetTester tester, ParteEntrega p) async {
  await tester.tap(find.byKey(Key('entrega_entregar_${p.clave}')));
  await tester.pumpAndSettle();
}

/// Completa quién retira: Madre, "Laura Benítez" y el tilde de la planilla.
Future<void> _quienRetira(WidgetTester tester, {String quien = 'Madre'}) async {
  await tester.tap(find.text(quien));
  await tester.enterText(
    find.widgetWithText(TextField, 'Nombre y apellido de quien retira'),
    'Laura Benítez',
  );
  await tester.tap(find.text('Escribió su nombre y apellido en la planilla de papel'));
  await tester.pump();
}

Future<void> _confirmar(WidgetTester tester, ParteEntrega p) async {
  await tester.ensureVisible(find.byKey(Key('entrega_confirmar_${p.clave}')));
  await tester.tap(find.byKey(Key('entrega_confirmar_${p.clave}')));
  await tester.pumpAndSettle();
}

void main() {
  group('las dos partes', () {
    testWidgets('al día: pulseras y generales, cada una con su ENTREGAR', (tester) async {
      await _abrir(tester);
      expect(find.text('Pagó todo: cuotas, extras y mora'), findsOneWidget);
      expect(find.text('Pulseras VIP con cena · 3'), findsOneWidget);
      // Separados por un punto (revisión del 20-nov-2026): con comas, que los
      // nombres ya llevan, no se podía contar cuántas pulseras eran.
      expect(find.text('El egresado · BENÍTEZ, LAURA · BENÍTEZ, JORGE'), findsOneWidget);
      expect(find.text('Entradas generales · 5'), findsOneWidget);
      expect(find.byKey(const Key('entrega_entregar_pulseras')), findsOneWidget);
      expect(find.byKey(const Key('entrega_entregar_generales')), findsOneWidget);
      // Solo la mesa del contrato va sin cargo: las 11 de la mesa adicional y
      // las sillas extra, aparte.
      expect(
        find.text('Las 11 entradas de su mesa adicional y sus 3 sillas extra no van '
            'sin cargo: se compran aparte, al 50 %.'),
        findsOneWidget,
      );
    });

    testWidgets('acompañantes sin nombre: "N sin nombre"', (tester) async {
      await _abrir(tester, alumno: _alumno(acompanantes: const ['BENÍTEZ, LAURA'], cantidad: 3));
      expect(find.text('Pulseras VIP con cena · 4'), findsOneWidget);
      expect(find.text('El egresado · BENÍTEZ, LAURA · 2 sin nombre'), findsOneWidget);
      expect(find.text('Entradas generales · 4'), findsOneWidget);
      // Más de 2 acompañantes: lo dice el renglón, como VENDER (antes lo decía
      // el formulario al abrirse).
      expect(
        tester.widget<Text>(find.byKey(const Key('entrega_mas_de_dos'))).data,
        'Tiene 3 acompañantes con cena (el máximo es 2): confirmalo con el jefe.',
      );
    });

    testWidgets('las pulseras: sin completar, marca lo que falta y no entrega',
        (tester) async {
      final accion = await _abrir(tester);
      await _entregarCon(tester, ParteEntrega.pulseras);
      // El formulario ya no repite cuántas y quiénes (revisión del 20-nov-2026):
      // lo dice el renglón de la parte, justo arriba.
      expect(find.text('3 pulseras VIP con cena'), findsNothing);
      expect(find.text('Pulseras VIP con cena · 3'), findsOneWidget);
      expect(find.text('Menores de 10 (no llevan entrada)'), findsOneWidget);
      // Las pulseras van sin número.
      expect(find.text('Vienen con número'), findsNothing);
      await _confirmar(tester, ParteEntrega.pulseras);
      expect(find.text('Elegí quién retira.'), findsOneWidget);
      expect(find.text('Escribí nombre y apellido.'), findsOneWidget);
      expect(find.text('Falta que escriba su nombre y apellido en la planilla.'),
          findsOneWidget);
      expect(accion(), isNull, reason: 'sigue abierto');
    });

    testWidgets('las pulseras, completas: la parte, la cantidad fija y los menores',
        (tester) async {
      final accion = await _abrir(tester);
      await _entregarCon(tester, ParteEntrega.pulseras);
      await _quienRetira(tester);
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await _confirmar(tester, ParteEntrega.pulseras);
      final e = accion()! as EntregarUnaParte;
      expect(e.datos.parte, ParteEntrega.pulseras);
      expect(e.datos.cantidad, 3);
      expect(e.datos.tramos, isEmpty);
      expect(e.datos.menores10, 1);
      expect(e.datos.parentesco, ParentescoRetiro.madre);
      expect(e.datos.nombre, 'Laura Benítez');
      expect(e.datos.escribioEnPlanilla, isTrue);
    });

    testWidgets('las generales sin número: "Vienen con número" viene sin tildar',
        (tester) async {
      final accion = await _abrir(tester);
      await _entregarCon(tester, ParteEntrega.generales);
      // Cuántas lo dice el renglón: el formulario no lo repite.
      expect(find.text('5 entradas generales'), findsNothing);
      expect(find.text('Entradas generales · 5'), findsOneWidget);
      expect(find.text('Menores de 10 (no llevan entrada)'), findsNothing);
      expect(find.widgetWithText(TextField, 'Del'), findsNothing);
      await _quienRetira(tester, quien: 'Padre');
      await _confirmar(tester, ParteEntrega.generales);
      final e = accion()! as EntregarUnaParte;
      expect(e.datos.parte, ParteEntrega.generales);
      expect(e.datos.cantidad, 5);
      expect(e.datos.tramos, isEmpty);
      expect(e.datos.parentesco, ParentescoRetiro.padre);
    });

    testWidgets('las generales con número: "del" y el "al" calculado', (tester) async {
      final accion = await _abrir(tester);
      await _entregarCon(tester, ParteEntrega.generales);
      await tester.tap(find.text('Vienen con número'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'Del'), '1043');
      await tester.pump();
      expect(find.text('al 1047'), findsOneWidget);
      await _quienRetira(tester);
      await _confirmar(tester, ParteEntrega.generales);
      final e = accion()! as EntregarUnaParte;
      expect(e.datos.tramos, const [TramoTalonario(1043, 1047)]);
    });

    testWidgets('tildado y sin escribir el número, no entrega', (tester) async {
      final accion = await _abrir(tester);
      await _entregarCon(tester, ParteEntrega.generales);
      await tester.tap(find.text('Vienen con número'));
      await tester.pump();
      await _quienRetira(tester);
      await _confirmar(tester, ParteEntrega.generales);
      expect(find.textContaining('Escribí los números del talonario'), findsOneWidget);
      expect(accion(), isNull);
    });

    testWidgets('el talonario salta: dos tramos', (tester) async {
      final accion = await _abrir(tester);
      await _entregarCon(tester, ParteEntrega.generales);
      await tester.tap(find.text('Vienen con número'));
      await tester.pump();
      await tester.tap(find.text('El talonario salta: dos tramos'));
      await tester.pump();
      final campos = find.widgetWithText(TextField, 'Del');
      await tester.enterText(campos.first, '1043');
      await tester.enterText(find.widgetWithText(TextField, 'Al'), '1044');
      await tester.enterText(find.widgetWithText(TextField, 'Del').last, '2001');
      await tester.pump();
      expect(find.text('al 2003'), findsOneWidget);
      await _quienRetira(tester);
      await _confirmar(tester, ParteEntrega.generales);
      final e = accion()! as EntregarUnaParte;
      expect(e.datos.tramos,
          const [TramoTalonario(1043, 1044), TramoTalonario(2001, 2003)]);
    });

    testWidgets('si los números ya se dieron a otra familia, no deja entregar',
        (tester) async {
      final accion = await _abrir(
        tester,
        deOtros: {'PÉREZ, JUAN': const [TramoTalonario(1045, 1060)]},
      );
      await _entregarCon(tester, ParteEntrega.generales);
      await tester.tap(find.text('Vienen con número'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'Del'), '1043');
      await _quienRetira(tester, quien: 'Padre');
      await _confirmar(tester, ParteEntrega.generales);
      expect(find.text('El 1045 ya se le dio a PÉREZ, JUAN (1045 al 1060).'),
          findsOneWidget);
      expect(accion(), isNull);
    });

    testWidgets('otra persona pide motivo y autorización', (tester) async {
      await _abrir(tester);
      await _entregarCon(tester, ParteEntrega.pulseras);
      await tester.tap(find.text('Otra persona'));
      await tester.pump();
      expect(find.text('Trajo la autorización firmada por la familia'), findsOneWidget);
      await _confirmar(tester, ParteEntrega.pulseras);
      expect(find.text('Escribí por qué no viene un familiar directo.'), findsOneWidget);
      expect(find.text('Sin autorización firmada no se entrega a otra persona.'),
          findsOneWidget);
    });

    testWidgets('una parte entregada: su ✓, quién y cuándo; la otra con ENTREGAR',
        (tester) async {
      await _abrir(tester, renglones: [_entrega(ParteEntrega.pulseras)]);
      expect(find.byKey(const Key('entrega_hecha_pulseras')), findsOneWidget);
      expect(find.text('✓ Entregadas'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('entrega_quien_pulseras'))).data,
        'Madre LAURA BENÍTEZ, el 20/11/2026 12:00 hs (lo registró Carla)',
      );
      expect(find.text('Menores de 10: 1'), findsOneWidget);
      expect(find.byKey(const Key('entrega_entregar_pulseras')), findsNothing);
      expect(find.byKey(const Key('entrega_entregar_generales')), findsOneWidget);
      expect(find.text('✓ Todo entregado'), findsNothing);
    });

    testWidgets('las dos partes: "✓ Todo entregado", con los números si vinieron',
        (tester) async {
      await _abrir(tester, renglones: [
        _entrega(ParteEntrega.pulseras),
        _entrega(
          ParteEntrega.generales,
          tramos: const [TramoTalonario(1043, 1047)],
          ahora: _hora.add(const Duration(days: 2)),
        ),
      ]);
      expect(find.text('✓ Todo entregado'), findsOneWidget);
      expect(find.text('✓ Entregadas'), findsNWidgets(2));
      expect(find.text('Del 1043 al 1047'), findsOneWidget);
      expect(find.byKey(const Key('entrega_entregar_pulseras')), findsNothing);
      expect(find.byKey(const Key('entrega_entregar_generales')), findsNothing);
    });

    testWidgets('una entrega de las 8 juntas (6.9.x) cuenta como las dos partes',
        (tester) async {
      final vieja = RetiroEntradas.nuevaEntrega(
        alumno: _alumno(),
        entradas: RetiroEntradas.entradasDe(_alumno()),
        tramos: const [TramoTalonario(1043, 1047)],
        menores10: 1,
        parentesco: ParentescoRetiro.madre,
        nombre: 'Laura Benítez',
        quien: 'Operador',
        ahora: DateTime.utc(2026, 11, 12, 21, 40),
      );
      await _abrir(tester, retiro: vieja);
      expect(find.text('✓ Todo entregado'), findsOneWidget);
      expect(find.text('Del 1043 al 1047'), findsOneWidget);
    });

    testWidgets('con 8 o más con cena no hay generales', (tester) async {
      await _abrir(
        tester,
        alumno: _alumno(acompanantes: List.generate(8, (i) => 'ACOMPAÑANTE $i')),
      );
      expect(find.text('Pulseras VIP con cena · 9'), findsOneWidget);
      expect(find.text('No lleva: las 8 de la mesa son con cena.'), findsOneWidget);
      expect(find.byKey(const Key('entrega_entregar_generales')), findsNothing);
    });
  });

  group('anular, solo el jefe', () {
    final dos = [
      _entrega(ParteEntrega.pulseras),
      _entrega(ParteEntrega.generales, ahora: _hora.add(const Duration(days: 1))),
    ];

    testWidgets('una parte, con motivo', (tester) async {
      final accion = await _abrir(tester, renglones: dos);
      await tester.tap(find.byKey(const Key('entrega_anular')));
      await tester.pump();
      // Vienen elegidas las dos: se saca una.
      await tester.tap(find.byKey(const Key('entrega_anular_pulseras')));
      await tester.pump();
      await tester.tap(find.text('CONFIRMAR ANULACIÓN'));
      await tester.pump();
      expect(find.text('Escribí el motivo.'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Por qué se anula'),
        'Se anotaron mal los números',
      );
      await tester.tap(find.text('CONFIRMAR ANULACIÓN'));
      await tester.pumpAndSettle();
      final a = accion()! as AnularEntrega;
      expect(a.partes, {ParteEntrega.generales});
      expect(a.motivo, 'Se anotaron mal los números');
    });

    testWidgets('todo', (tester) async {
      final accion = await _abrir(tester, renglones: dos);
      await tester.tap(find.byKey(const Key('entrega_anular')));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'Por qué se anula'),
        'Se equivocó de alumno',
      );
      await tester.tap(find.text('CONFIRMAR ANULACIÓN DE TODO'));
      await tester.pumpAndSettle();
      expect((accion()! as AnularEntrega).partes,
          {ParteEntrega.pulseras, ParteEntrega.generales});
    });

    testWidgets('sin modo jefe se ve apagado, con el motivo', (tester) async {
      await _abrir(
        tester,
        renglones: dos,
        permisos: const PermisosDeEntrega.oficina(esJefe: false),
      );
      final boton =
          tester.widget<OutlinedButton>(find.byKey(const Key('entrega_anular_apagado')));
      expect(boton.onPressed, isNull);
      expect(find.text(kSoloEnModoJefe), findsOneWidget);
      expect(find.text('CONFIRMAR ANULACIÓN'), findsNothing);
    });

    testWidgets('si la cuenta cambió después de entregar, se avisa en su parte',
        (tester) async {
      // Se llevó 3 pulseras; hoy tiene un acompañante más.
      await _abrir(
        tester,
        alumno: _alumno(acompanantes: const [..._dos, 'ABUELA']),
        renglones: dos,
        permisos: const PermisosDeEntrega.oficina(esJefe: false),
      );
      expect(find.text('Cambió la cuenta después de entregar'), findsNWidgets(2));
      expect(find.textContaining('el jefe anula esta parte'), findsWidgets);
    });

    testWidgets('una parte anulada dice cuándo, quién y por qué', (tester) async {
      final anulacion = EntregaEntradas.anulacion(
        contratoAlumnoId: 'a',
        eventoId: 'e',
        parte: ParteEntrega.pulseras,
        cantidad: 3,
        motivo: 'se equivocó de familia',
        hechoPor: 'Jefe',
        deviceId: 'pc',
        ahora: _hora.add(const Duration(hours: 1)),
      );
      await _abrir(tester, renglones: [_entrega(ParteEntrega.pulseras), anulacion]);
      expect(find.textContaining('Tuvo una entrega anulada'), findsOneWidget);
      expect(find.textContaining('por Jefe: se equivocó de familia'), findsOneWidget);
      // Se ofrece lo de esa vez para no volver a tipearlo.
      await _entregarCon(tester, ParteEntrega.pulseras);
      expect(
        tester
            .widget<TextField>(
                find.widgetWithText(TextField, 'Nombre y apellido de quien retira'))
            .controller!
            .text,
        'LAURA BENÍTEZ',
      );
    });
  });

  group('si debe, no se le entrega', () {
    testWidgets('en la oficina: sin ENTREGAR, solo ir a cobrar', (tester) async {
      final accion = await _abrir(
        tester,
        deuda: const DeudaAlumno(saldoFicha: 30000, saldoPagos: 30000, mora: 3500),
        bloqueo: BloqueoRetiro.debe,
      );
      expect(find.textContaining('Debe'), findsWidgets);
      expect(find.byKey(const Key('entrega_entregar_pulseras')), findsNothing);
      expect(find.byKey(const Key('entrega_entregar_generales')), findsNothing);
      expect(find.text('Pendiente'), findsNWidgets(2));
      await tester.tap(find.text('IR A COBRAR'));
      await tester.pumpAndSettle();
      expect(accion(), isA<IrACobrar>());
    });

    testWidgets('con una parte ya entregada, la otra espera al pago', (tester) async {
      await _abrir(
        tester,
        deuda: const DeudaAlumno(saldoFicha: 8000, saldoPagos: 8000, mora: 0),
        bloqueo: BloqueoRetiro.debe,
        renglones: [_entrega(ParteEntrega.pulseras)],
      );
      expect(find.text('✓ Entregadas'), findsOneWidget);
      expect(find.text('Pendiente'), findsOneWidget);
      expect(find.byKey(const Key('entrega_entregar_generales')), findsNothing);
    });
  });

  group('el mostrador de Entradas', () {
    const sinCobros = PermisosDeEntrega.mostrador(tieneCobros: false);
    const conCobros = PermisosDeEntrega.mostrador(tieneCobros: true);
    const debe = DeudaAlumno(saldoFicha: 70000, saldoPagos: 70000, mora: 0);

    testWidgets('si debe y no tiene Cobros: que pase por caja, con el monto, y ENTENDIDO',
        (tester) async {
      final accion = await _abrir(
        tester,
        permisos: sinCobros,
        deuda: debe,
        bloqueo: BloqueoRetiro.debe,
      );
      expect(find.text('Debe \$ 70.000,00'), findsOneWidget);
      expect(find.textContaining('Que pase por caja a saldar todo'), findsOneWidget);
      expect(find.text('IR A COBRAR'), findsNothing);
      expect(find.text('PASAR A CAJA'), findsNothing);
      await tester.tap(find.text('ENTENDIDO'));
      await tester.pumpAndSettle();
      expect(accion(), isA<MandarACaja>());
    });

    testWidgets('con Cobros también: PASAR A CAJA', (tester) async {
      final accion = await _abrir(
        tester,
        permisos: conCobros,
        deuda: debe,
        bloqueo: BloqueoRetiro.debe,
      );
      expect(find.text('IR A COBRAR'), findsNothing);
      await tester.tap(find.text('PASAR A CAJA'));
      await tester.pumpAndSettle();
      expect(accion(), isA<PasarACaja>());
    });

    testWidgets('las mesas que no coinciden: sin EDITAR ALUMNO, y que lo revise el jefe',
        (tester) async {
      await _abrir(tester, permisos: sinCobros, bloqueo: BloqueoRetiro.mesasNoCoinciden);
      expect(find.text('EDITAR ALUMNO'), findsNothing);
      expect(find.textContaining('Pedile al jefe que lo revise.'), findsOneWidget);
    });

    testWidgets('al día: las dos partes, sin "Cambiar acompañantes"', (tester) async {
      await _abrir(tester, permisos: sinCobros);
      expect(find.byKey(const Key('entrega_entregar_pulseras')), findsOneWidget);
      expect(find.text('Cambiar acompañantes'), findsNothing);
    });

    testWidgets('si pagó con el diálogo abierto, se cierra para volver a abrirlo',
        (tester) async {
      final cambio = ValueNotifier(0);
      final accion = await _abrir(
        tester,
        permisos: sinCobros,
        deuda: debe,
        bloqueo: BloqueoRetiro.debe,
        cuentaCambio: cambio,
      );
      cambio.value++;
      await tester.pumpAndSettle();
      expect(accion(), isA<VolverAAbrir>());
    });

    testWidgets('con el formulario abierto no se cierra solo', (tester) async {
      final cambio = ValueNotifier(0);
      final accion = await _abrir(tester, permisos: sinCobros, cuentaCambio: cambio);
      await _entregarCon(tester, ParteEntrega.pulseras);
      cambio.value++;
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('entrega_confirmar_pulseras')), findsOneWidget);
      expect(accion(), isNull);
    });
  });

  // 6.9.0, sección 9.3 del spec del 13-nov, con la regla del 20-nov-2026: se le
  // vende solo lo que ya está pago entero, cosa por cosa (la mesa adicional y
  // las sillas extra de BENÍTEZ, 11 entradas al 50 %).
  group('lo de sus lugares adicionales', () {
    testWidgets('sin la venta andando (sin precio, o en la web) se ve como siempre',
        (tester) async {
      await _abrir(tester);
      expect(find.byKey(const Key('entrega_al_cincuenta')), findsOneWidget);
      expect(find.byKey(const Key('entrega_compro')), findsNothing);
      expect(find.byKey(const Key('entrega_venderle')), findsNothing);
    });

    testWidgets('pagas enteras, con el permiso: cuántas compró y VENDERLE ESAS ENTRADAS',
        (tester) async {
      final accion = await _abrir(
        tester,
        venta: VentaAlCincuenta(lugares: _lugares(compradas: 4), puedeVender: true),
      );
      expect(tester.widget<Text>(find.byKey(const Key('entrega_compro'))).data,
          'Ya compró 4: le quedan 7.');
      expect(find.byKey(const Key('entrega_a_confirmar')), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('entrega_venderle')));
      await tester.tap(find.byKey(const Key('entrega_venderle')));
      await tester.pumpAndSettle();
      expect(accion(), isA<VenderAlCincuenta>());
    });

    testWidgets('la mesa adicional sin pagar entera: no se ofrece, y dice "a confirmar"',
        (tester) async {
      await _abrir(
        tester,
        venta: VentaAlCincuenta(lugares: _lugares(mesa: 30000, sillas: 0), puedeVender: true),
      );
      expect(find.byKey(const Key('entrega_venderle')), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(const Key('entrega_a_confirmar'))).data,
        'La mesa adicional y las 3 sillas extra están a confirmar: falta '
        'pagarlas en caja.',
      );
    });

    testWidgets('la mesa paga y las sillas no: le vende las de la mesa', (tester) async {
      await _abrir(
        tester,
        venta: VentaAlCincuenta(lugares: _lugares(sillas: 0), puedeVender: true),
      );
      expect(tester.widget<Text>(find.byKey(const Key('entrega_compro'))).data,
          'Todavía no compró ninguna.');
      expect(find.byKey(const Key('entrega_venderle')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('entrega_a_confirmar'))).data,
        'Las 3 sillas extra están a confirmar: falta pagarlas en caja.',
      );
    });

    // Revisión del 20-nov-2026: compró 3 de las de su mesa adicional antes de
    // pagarla (la 6.9.x las vendía igual) y las otras 5 esperan el pago. Decía
    // "Ya compró las 3.", que suena a que terminó.
    testWidgets('compró algunas y las otras esperan el pago: no dice que terminó',
        (tester) async {
      await _abrir(
        tester,
        venta: VentaAlCincuenta(
          lugares: _lugares(mesa: 0, sillas: 24000, compradas: 3),
          puedeVender: true,
        ),
      );
      // Las sillas están pagas (3), y las compró; la mesa (8) no está paga.
      expect(tester.widget<Text>(find.byKey(const Key('entrega_compro'))).data,
          'Ya compró 3; las otras 8 esperan que se pague en caja.');
      expect(find.byKey(const Key('entrega_venderle')), findsNothing);
    });

    testWidgets('si ya compró todas, no ofrece vender', (tester) async {
      await _abrir(
        tester,
        venta: VentaAlCincuenta(lugares: _lugares(compradas: 11), puedeVender: true),
      );
      expect(tester.widget<Text>(find.byKey(const Key('entrega_compro'))).data,
          'Ya compró las 11.');
      expect(find.byKey(const Key('entrega_venderle')), findsNothing);
      expect(find.byKey(const Key('entrega_se_las_vende')), findsNothing);
    });

    testWidgets('sin el permiso dice quién se las vende', (tester) async {
      await _abrir(
        tester,
        venta: VentaAlCincuenta(lugares: _lugares(), puedeVender: false),
      );
      expect(find.byKey(const Key('entrega_venderle')), findsNothing);
      expect(find.text('Se las vende quien tiene la caja de entradas.'), findsOneWidget);
    });

    testWidgets('con lo sin cargo ya retirado, lo pago se le vende igual', (tester) async {
      await _abrir(
        tester,
        renglones: [
          _entrega(ParteEntrega.pulseras),
          _entrega(ParteEntrega.generales, ahora: _hora.add(const Duration(days: 1))),
        ],
        venta: VentaAlCincuenta(lugares: _lugares(), puedeVender: true),
      );
      expect(find.text('✓ Todo entregado'), findsOneWidget);
      expect(find.byKey(const Key('entrega_venderle')), findsOneWidget);
    });

    testWidgets('debe la base, pero la mesa adicional está paga: esa se le vende',
        (tester) async {
      await _abrir(
        tester,
        deuda: const DeudaAlumno(saldoFicha: 100000, saldoPagos: 100000, mora: 0),
        bloqueo: BloqueoRetiro.debe,
        venta: VentaAlCincuenta(lugares: _lugares(), puedeVender: true),
      );
      expect(find.byKey(const Key('entrega_entregar_pulseras')), findsNothing);
      expect(find.byKey(const Key('entrega_venderle')), findsOneWidget);
    });

    testWidgets('con las mesas mal cargadas no se ofrece: la cuenta puede estar mal',
        (tester) async {
      await _abrir(
        tester,
        bloqueo: BloqueoRetiro.mesasNoCoinciden,
        venta: VentaAlCincuenta(lugares: _lugares(), puedeVender: true),
      );
      expect(find.byKey(const Key('entrega_venderle')), findsNothing);
    });

    // Revisión independiente del 20-nov-2026: con "debe", la deuda tapaba el
    // freno de las mesas y se ofrecía venderle las de una mesa sin número.
    testWidgets('si debe y además tiene las mesas mal cargadas, tampoco se ofrece',
        (tester) async {
      await _abrir(
        tester,
        // La mesa adicional cargada, sin su número en el salón.
        alumno: _alumno().copyWith(
          numeroMesa: MesasExtraUtils.formatearAsignacionMesas(const [13]),
        ),
        deuda: const DeudaAlumno(saldoFicha: 30000, saldoPagos: 30000, mora: 0),
        bloqueo: BloqueoRetiro.debe,
        venta: VentaAlCincuenta(lugares: _lugares(), puedeVender: true),
      );
      expect(find.byKey(const Key('entrega_venderle')), findsNothing);
    });

    testWidgets('si debe y sus mesas están bien, se ofrece lo ya pagado', (tester) async {
      await _abrir(
        tester,
        deuda: const DeudaAlumno(saldoFicha: 30000, saldoPagos: 30000, mora: 0),
        bloqueo: BloqueoRetiro.debe,
        venta: VentaAlCincuenta(lugares: _lugares(), puedeVender: true),
      );
      expect(find.byKey(const Key('entrega_venderle')), findsOneWidget);
    });

    testWidgets('lo agregado después del sorteo: el precio del día, sin descuento',
        (tester) async {
      // Sin la foto del sorteo todo va con descuento; con la mesa y las sillas
      // agregadas después, sin descuento.
      final a = _alumno();
      await tester.binding.setSurfaceSize(const Size(1200, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => mostrarEntregaEntradasDialog(
                context: context,
                alumno: a,
                entradas: const EntradasDeAlumno(
                  mesas: 2,
                  sillas: 3,
                  vip: 3,
                  alSorteo: LugaresCargados(1, 0),
                ),
                estado: EstadoDeLaEntrega.deAlumno(a, renglones: const []),
                deuda: _alDia,
                bloqueo: BloqueoRetiro.ninguno,
                permisos: const PermisosDeEntrega.oficina(esJefe: true),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('entrega_al_cincuenta'))).data,
        'Las 11 entradas de su mesa adicional y sus 3 sillas extra no van sin '
        'cargo. Lo agregó después del sorteo: pagan el precio del día, sin '
        'descuento.',
      );
    });
  });
}
