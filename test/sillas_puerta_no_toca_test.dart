// Las sillas que se suman la noche de la fiesta (6.4.0) en la oficina: lo que se
// ve en la grilla y en Editar alumno, la traba de sumar sillas extra al
// contrato desde el sorteo, y lo que no tocan.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/widgets/celda_mesa_alumno.dart';
import 'package:arguello_events/features/eventos/widgets/modal_alumno_premium.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/silla_puerta.dart';

String _leer(String ruta) =>
    File(ruta).readAsStringSync().replaceAll('\r\n', '\n');

final _hora = DateTime.utc(2026, 11, 15, 2, 5);

SillaPuerta _silla(String vale, {bool quitada = false}) {
  final s = SillaPuerta(
    id: 's-$vale',
    eventoId: 'e',
    contratoAlumnoId: 'a',
    mesa: 12,
    vale: vale,
    anotadoPor: 'Pato',
    createdAt: _hora,
    updatedAt: _hora,
  );
  return quitada
      ? s.quitada(por: 'Juli', motivo: 'devolvieron el vale', ahora: _hora)
      : s;
}

void main() {
  group('lo que no tocan', () {
    // El sorteo, la planilla, lo pagado, el retiro de entradas y el plano siguen
    // con lo del contrato: las sillas de la puerta solo se muestran.
    for (final ruta in [
      'lib/features/eventos/services/salon_mesas.dart',
      'lib/features/eventos/services/reparto_de_sillas.dart',
      'lib/features/eventos/services/planilla_sorteo.dart',
      'lib/features/eventos/services/pago_para_sorteo.dart',
      'lib/features/eventos/retiro_entradas_screen.dart',
      'lib/features/plano/services/plano_de_la_fiesta.dart',
      'lib/features/eventos/repositories/contratos_repository.dart',
    ]) {
      test(ruta.split('/').last, () {
        final texto = _leer(ruta);
        expect(texto, isNot(contains('sillas_puerta')));
        expect(texto, isNot(contains('SillaPuerta')));
        expect(texto, isNot(contains('sillas_de_la_puerta')));
      });
    }
  });

  group('la traba de la oficina (decisión del 6-nov)', () {
    test('antes del sorteo se suman como siempre', () {
      expect(
        puedeSumarSillasAlContrato(fiestaSorteada: false, esJefe: false),
        isTrue,
      );
    });

    test('con la fiesta sorteada, solo el jefe', () {
      expect(
        puedeSumarSillasAlContrato(fiestaSorteada: true, esJefe: false),
        isFalse,
      );
      expect(
        puedeSumarSillasAlContrato(fiestaSorteada: true, esJefe: true),
        isTrue,
      );
    });

    test('al guardar: bajar o dejar igual se puede; subir, no', () {
      bool trabadas(int antes, int escritas, {bool jefe = false}) =>
          sillasExtraTrabadas(
            fiestaSorteada: true,
            esJefe: jefe,
            antes: antes,
            escritas: escritas,
          );
      expect(trabadas(2, 2), isFalse, reason: 'lo ya cargado no se toca');
      expect(trabadas(2, 1), isFalse);
      expect(trabadas(1, 2), isTrue);
      expect(trabadas(0, 1), isTrue, reason: 'un alta después del sorteo');
      expect(trabadas(1, 2, jefe: true), isFalse);
    });

    test('Editar alumno la usa en el contador y al guardar', () {
      final modal =
          _leer('lib/features/eventos/widgets/modal_alumno_premium.dart');
      expect(modal, contains('sumarTrabado: !_puedeSumarSillas'));
      final i = modal.indexOf('void _submit() async {');
      final guardar = modal.substring(i, modal.indexOf('repo.', i));
      expect(guardar, contains('sillasExtraTrabadas('));
      expect(modal, contains("Key('sillas_solo_en_la_fiesta')"));
    });

    test('la pantalla de la fiesta le dice si ya se sorteó, en el alta y al '
        'editar', () {
      final fiesta =
          _leer('lib/features/eventos/detalle_evento_masivo_screen.dart');
      expect(
        'fiestaSorteada: hayMesasSorteadas(_alumnos)'.allMatchesIn(fiesta),
        2,
      );
    });
  });

  group('la grilla', () {
    final alumno = ContratoAlumno(
      id: 'a',
      eventoId: 'e',
      nombreAlumno: 'PÉREZ, JUAN',
      cantidadAcompanantes: 0,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      sillasExtraCantidad: 1,
      sillasExtraPrecioTotal: 8000,
      numeroMesa: MesasExtraUtils.formatearAsignacionMesas([12]),
    );

    Future<void> mostrar(WidgetTester tester, List<SillaPuerta> sillas) =>
        tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 78,
                child: CeldaMesaAlumno(alumno: alumno, sillasDeLaPuerta: sillas),
              ),
            ),
          ),
        ));

    testWidgets('dice cuántas se sumaron en la puerta, y el detalle en el '
        'tooltip', (tester) async {
      await mostrar(tester, [_silla('2-17'), _silla('2-18', quitada: true)]);
      expect(find.text('+1 en la puerta'), findsOneWidget);
      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip)).message!;
      expect(tooltip, contains('no cambian la cuenta'));
      expect(tooltip, contains('vale 2-17'));
      expect(tooltip, contains('quitada por Juli'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('sin sillas de la puerta, como siempre', (tester) async {
      await mostrar(tester, const []);
      expect(find.byKey(const Key('sillas_en_la_puerta')), findsNothing);
    });

    testWidgets('solo quitadas: no suma nada a la vista', (tester) async {
      await mostrar(tester, [_silla('2-18', quitada: true)]);
      expect(find.byKey(const Key('sillas_en_la_puerta')), findsNothing);
    });
  });
}

extension on String {
  int allMatchesIn(String texto) => RegExp(RegExp.escape(this)).allMatches(texto).length;
}
