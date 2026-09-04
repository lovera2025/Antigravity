// Una bonificación es crédito imputado al evento, no plata recibida.
//
// Se guarda como transacción para que la cuenta del evento cierre en cero, y la
// pantalla del evento ya lo mostraba bien: "Total imputado" arriba, y debajo
// "Efectivo recibido" y "Bonificaciones" por separado.
//
// Mi Empresa era el único lugar que las mezclaba: las contaba como cobrado. Y
// como se guardan sin medio de pago, caían en el bucket de EFECTIVO — que es
// contra lo que se compara la caja física. Eran $869.500 de efectivo que el
// sistema decía tener y en la caja no estaban (RAMON CACERES $720.000 el
// 15/04/2026 y Maria y Jose $149.500 el 13/06/2026).
//
// La regla vive en una sola función para que no se escriba distinto en cada
// consulta que la necesite.
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/models/transaccion.dart';

Transaccion _t(String? concepto) => Transaccion(
      id: '00000000-0000-0000-0000-000000000001',
      eventoId: '00000000-0000-0000-0000-000000000002',
      monto: 1000,
      concepto: concepto,
    );

void main() {
  group('conceptoEsBonificacion', () {
    test('reconoce el concepto que escribe el diálogo de pago', () {
      expect(
        conceptoEsBonificacion('Bonificación global (10% sobre presupuesto total)'),
        isTrue,
      );
      expect(conceptoEsBonificacion('Bonificación Especial'), isTrue);
    });

    test('no depende de mayúsculas ni del acento final', () {
      // El corte es en "bonificaci", justo antes de donde el acento cambia.
      expect(conceptoEsBonificacion('BONIFICACION'), isTrue);
      expect(conceptoEsBonificacion('bonificación'), isTrue);
      expect(conceptoEsBonificacion('Bonificaciones varias'), isTrue);
    });

    test('un cobro normal no es bonificación', () {
      for (final c in ['PAGO TOTAL', 'SALDO', 'seña', 'cuota 1', 'adelanto']) {
        expect(conceptoEsBonificacion(c), isFalse, reason: c);
      }
    });

    test('null y vacío no son bonificación', () {
      expect(conceptoEsBonificacion(null), isFalse);
      expect(conceptoEsBonificacion(''), isFalse);
    });
  });

  group('la plata recibida excluye las bonificaciones', () {
    test('el caso de RAMON CACERES', () {
      // Presupuesto $7.200.000: entraron $6.480.000 y $720.000 fueron descuento.
      final movimientos = [
        _t('SEÑA'),
        _t('saldo cancelado'),
        _t('Bonificación global (10% sobre presupuesto total)'),
      ];

      final recibidos = movimientos.where((t) => !t.esBonificacion).toList();

      expect(recibidos.length, 2);
      expect(
        movimientos.where((t) => t.esBonificacion).length,
        1,
        reason: 'la bonificación cierra la cuenta del evento pero no es plata',
      );
    });
  });
}
