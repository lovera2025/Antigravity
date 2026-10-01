// La columna MESA de la grilla de masivos, antes y después del sorteo.
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/pago_para_sorteo.dart';
import 'package:arguello_events/features/eventos/widgets/celda_mesa_alumno.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/sillas_reparto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ContratoAlumno _alumno({
  int extras = 0,
  int sillas = 0,
  List<int> mesas = const [],
  bool baja = false,
}) =>
    ContratoAlumno(
      id: 'a',
      eventoId: 'e',
      nombreAlumno: baja ? '[BAJA] PÉREZ, JUAN' : 'PÉREZ, JUAN',
      cantidadAcompanantes: 0,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      sillasExtraCantidad: sillas,
      sillasExtraPrecioTotal: 8000.0 * sillas,
      numeroMesa:
          mesas.isEmpty ? null : MesasExtraUtils.formatearAsignacionMesas(mesas),
    );

Future<void> _mostrar(
  WidgetTester tester,
  ContratoAlumno a, {
  PagoAlumno? pago,
  bool marcarPago = false,
  bool ocultarMontos = false,
  SillasReparto? reparto,
  VoidCallback? onElegirSillas,
  List<String> avisos = const [],
  double ancho = 110,
}) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: ancho,
              child: CeldaMesaAlumno(
                alumno: a,
                reparto: reparto,
                onElegirSillas: onElegirSillas,
                extras: pago == null ? null : ExtrasSegunPago.de(a, pago),
                marcarPago: marcarPago,
                ocultarMontos: ocultarMontos,
                avisos: avisos,
              ),
            ),
          ),
        ),
      ),
    );

/// Todo el texto de la celda, renglón por renglón (los `Text.rich` incluidos).
List<String> _renglones(WidgetTester tester) => [
      for (final t in tester.widgetList<Text>(
        find.descendant(
          of: find.byType(CeldaMesaAlumno),
          matching: find.byType(Text),
        ),
      ))
        t.data ?? t.textSpan!.toPlainText(),
    ];

String _tooltip(WidgetTester tester) =>
    tester.widget<Tooltip>(find.byType(Tooltip)).message!;

void main() {
  const alDia = PagoAlumno(base: 30000, mesas: 19530, sillas: 24000);

  group('antes del sorteo', () {
    testWidgets('solo la del contrato: "1 mesa", sin destacar', (tester) async {
      await _mostrar(tester, _alumno());
      expect(_renglones(tester), ['1 mesa']);
    });

    testWidgets('con una agregada: "1 mesa +1 extra"', (tester) async {
      await _mostrar(tester, _alumno(extras: 1));
      expect(_renglones(tester), ['1 mesa +1 extra']);
      // La agregada va en negrita y en otro color que la del contrato.
      final span = tester
          .widget<Text>(
            find.descendant(
              of: find.byType(CeldaMesaAlumno),
              matching: find.byType(Text),
            ),
          )
          .textSpan! as TextSpan;
      final partes = span.children!.cast<TextSpan>();
      expect(partes[1].text, ' +1 extra');
      expect(partes[1].style!.fontWeight, FontWeight.w900);
      expect(partes[1].style!.color, isNot(partes[0].style!.color));
    });

    testWidgets('las sillas dicen solo cuántas son, sin reparto y sin toque',
        (tester) async {
      var toques = 0;
      await _mostrar(
        tester,
        _alumno(extras: 1, sillas: 3),
        onElegirSillas: () => toques++,
      );
      expect(_renglones(tester), ['1 mesa +1 extra', '+3 sillas']);
      expect(find.byType(InkWell), findsNothing);
      await tester.tap(find.text('+3 sillas'));
      expect(toques, 0);
      expect(
        _tooltip(tester),
        contains('se elige con las mesas ya sorteadas'),
      );
    });

    testWidgets('aunque ya haya un reparto guardado, no se muestra todavía',
        (tester) async {
      await _mostrar(
        tester,
        _alumno(extras: 1, sillas: 3),
        reparto: SillasReparto(
          id: 'r',
          contratoAlumnoId: 'a',
          sillasPrincipal: 2,
          sillasExtra: 3,
          mesas: 2,
          createdAt: DateTime(2026, 10, 1),
          updatedAt: DateTime(2026, 10, 1),
        ),
      );
      expect(_renglones(tester), ['1 mesa +1 extra', '+3 sillas']);
    });

    testWidgets('una sola silla, en singular', (tester) async {
      await _mostrar(tester, _alumno(sillas: 1));
      expect(_renglones(tester), ['1 mesa', '+1 silla']);
    });

    testWidgets('a los de baja no se les reserva nada: el guion de siempre',
        (tester) async {
      await _mostrar(tester, _alumno(extras: 1, baja: true), pago: alDia);
      expect(_renglones(tester), ['-']);
    });
  });

  group('antes del sorteo, con el filtro de pagos puesto', () {
    testWidgets('sin pago de la base: sin mesa', (tester) async {
      await _mostrar(
        tester,
        _alumno(extras: 1),
        pago: PagoAlumno.nada,
        marcarPago: true,
      );
      expect(_renglones(tester), ['1 mesa +1 extra', 'sin pago: sin mesa']);
      expect(_tooltip(tester), contains('el sorteo no le da mesa'));
    });

    testWidgets('la agregada sin pagar', (tester) async {
      await _mostrar(
        tester,
        _alumno(extras: 1),
        pago: const PagoAlumno(base: 30000),
        marcarPago: true,
      );
      expect(_renglones(tester), ['1 mesa +1 extra', 'extra sin pagar']);
      expect(_tooltip(tester), contains('solo la de su contrato'));
    });

    testWidgets('la agregada en cuotas y las sillas pagadas', (tester) async {
      await _mostrar(
        tester,
        _alumno(extras: 1, sillas: 3),
        pago: alDia,
        marcarPago: true,
      );
      expect(
        _renglones(tester),
        ['1 mesa +1 extra', 'extra en cuotas', '+3 sillas · pagadas'],
      );
      expect(_tooltip(tester), contains('el sorteo le da 2 mesas'));
    });

    testWidgets('solo la del contrato y con la base pagada: un tilde',
        (tester) async {
      await _mostrar(
        tester,
        _alumno(),
        pago: const PagoAlumno(base: 30000),
        marcarPago: true,
      );
      expect(_renglones(tester), ['1 mesa']);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('sin el filtro, la celda no habla de pagos', (tester) async {
      await _mostrar(
        tester,
        _alumno(extras: 1, sillas: 3),
        pago: PagoAlumno.nada,
      );
      expect(_renglones(tester), ['1 mesa +1 extra', '+3 sillas']);
    });
  });

  group('el detalle al pasar el mouse', () {
    testWidgets('lo cargado y lo pagado de cada cosa', (tester) async {
      await _mostrar(tester, _alumno(extras: 1, sillas: 3), pago: alDia);
      final t = _tooltip(tester);
      expect(t, contains('Sin mesa asignada todavía.'));
      expect(t, contains('Mesas: 1 del contrato + 1 agregada'));
      expect(t, contains('70.000'));
      expect(t, contains('19.530'));
      expect(t, contains('Sillas: 3 extra'));
      expect(t, contains('24.000'));
    });

    testWidgets('con los montos ocultos dice el estado, sin plata',
        (tester) async {
      await _mostrar(
        tester,
        _alumno(extras: 1, sillas: 3),
        pago: alDia,
        ocultarMontos: true,
      );
      final t = _tooltip(tester);
      expect(t, contains('1 agregada (en cuotas)'));
      expect(t, contains('3 extra (pagadas)'));
      expect(t, isNot(contains('70.000')));
      expect(t, isNot(contains('19.530')));
    });

    testWidgets('los avisos del alumno van al final', (tester) async {
      await _mostrar(
        tester,
        _alumno(),
        pago: alDia,
        avisos: const ['3 personas para 2 lugares'],
      );
      expect(_tooltip(tester), contains('⚠ 3 personas para 2 lugares'));
    });
  });

  group('con las mesas ya sorteadas', () {
    testWidgets('los números, como siempre', (tester) async {
      await _mostrar(tester, _alumno(extras: 1, mesas: [12, 13]));
      expect(_renglones(tester), ['12-13 (1 extra)']);
    });

    testWidgets('varias formas de repartir: a confirmar, y se toca',
        (tester) async {
      var toques = 0;
      await _mostrar(
        tester,
        _alumno(extras: 1, sillas: 3, mesas: [12, 13]),
        onElegirSillas: () => toques++,
        ancho: 220,
      );
      expect(
        _renglones(tester),
        ['12-13 (1 extra)', '+3 sillas: a confirmar'],
      );
      await tester.tap(find.text('+3 sillas: a confirmar'));
      expect(toques, 1);
    });

    testWidgets('una sola forma: sale sola de la cantidad, sin tilde',
        (tester) async {
      await _mostrar(tester, _alumno(sillas: 2, mesas: [12]), ancho: 220);
      expect(_renglones(tester), ['12', '+2 sillas: 2P']);
      expect(find.byIcon(Icons.check_circle), findsNothing);
    });

    testWidgets('elegido: el reparto con su tilde', (tester) async {
      await _mostrar(
        tester,
        _alumno(extras: 1, sillas: 3, mesas: [12, 13]),
        reparto: SillasReparto(
          id: 'r',
          contratoAlumnoId: 'a',
          sillasPrincipal: 2,
          sillasExtra: 3,
          mesas: 2,
          createdAt: DateTime(2026, 10, 1),
          updatedAt: DateTime(2026, 10, 1),
        ),
        ancho: 220,
      );
      expect(_renglones(tester), ['12-13 (1 extra)', '+3 sillas: 2P · 1A']);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });
  });

  testWidgets('entra en la columna angosta de la grilla sin desbordar',
      (tester) async {
    // La columna MESA mide el 8 % de la tabla: unos 80 px en una laptop.
    await _mostrar(
      tester,
      _alumno(extras: 2, sillas: 4),
      pago: const PagoAlumno(base: 30000, mesas: 10000),
      marcarPago: true,
      ancho: 78,
    );
    expect(tester.takeException(), isNull);
  });
}
