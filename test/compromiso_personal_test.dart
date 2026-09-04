// El saldo de una cuenta pendiente no se guarda: se deriva.
//
// `saldo = monto_total − suma de los egresos con ese compromiso_id`. Guardarlo
// sería una segunda fuente de verdad para la misma plata, y quedaría mintiendo
// en cuanto alguien editara o borrara un pago. Toda la lógica vive en el modelo
// justo para poder probarla acá, sin base ni Supabase.
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/mi_empresa/models/compromiso_personal.dart';

CompromisoPersonal _cuenta({
  double total = 100000,
  String tipo = kTipoCompromisoTrabajo,
  String estado = kEstadoCompromisoActivo,
}) {
  return CompromisoPersonal(
    id: '00000000-0000-0000-0000-000000000001',
    persona: 'Maxi',
    tipo: tipo,
    concepto: 'Sonido del sábado',
    montoTotal: total,
    fechaInicio: DateTime.utc(2026, 8, 12),
    estado: estado,
  );
}

void main() {
  group('saldo', () {
    test('descuenta lo pagado', () {
      expect(_cuenta().saldo(60000), 40000);
    });

    test('sin pagos, debe todo', () {
      expect(_cuenta().saldo(0), 100000);
    });

    test('nunca es negativo, aunque se pague de más', () {
      expect(_cuenta().saldo(130000), 0);
    });
  });

  group('estaSaldado', () {
    test('con el total exacto', () {
      expect(_cuenta().estaSaldado(100000), isTrue);
    });

    test('faltando un peso, no', () {
      expect(_cuenta().estaSaldado(99999), isFalse);
    });

    test('tolera el redondeo de los REAL de SQLite', () {
      // Sin la tolerancia de un centavo, una cuenta pagada entera podía quedar
      // debiendo $0,000001 para siempre y no marcarse nunca como saldada.
      expect(_cuenta().estaSaldado(99999.995), isTrue);
    });

    test('pagando de más también está saldada', () {
      expect(_cuenta().estaSaldado(130000), isTrue);
    });
  });

  group('progreso', () {
    test('proporcional a lo pagado', () {
      expect(_cuenta().progreso(25000), 0.25);
    });

    test('no pasa de 1 con sobrepago', () {
      expect(_cuenta().progreso(130000), 1);
    });

    test('con monto total 0 la cuenta ya está cumplida', () {
      // Sin este caso la barra haría 0/0 y quedaría en NaN.
      final c = _cuenta(total: 0);
      expect(c.progreso(0), 1);
      expect(c.estaSaldado(0), isTrue);
      expect(c.saldo(0), 0);
    });
  });

  group('huboSobrepago', () {
    test('se detecta', () {
      expect(_cuenta().huboSobrepago(130000), isTrue);
    });

    test('pagar justo no es sobrepago', () {
      expect(_cuenta().huboSobrepago(100000), isFalse);
    });
  });

  group('etiquetaSaldado', () {
    test('sale del tipo', () {
      expect(_cuenta(tipo: kTipoCompromisoTrabajo).etiquetaSaldado, 'TRABAJO PAGADO');
      expect(_cuenta(tipo: kTipoCompromisoProducto).etiquetaSaldado, 'PRODUCTO PAGADO');
    });

    test("los de tipo Otro dicen SALDADO, que 'OTRO PAGADO' no se entiende", () {
      expect(_cuenta(tipo: kTipoCompromisoOtro).etiquetaSaldado, 'SALDADO');
    });
  });

  group('CompromisoConSaldo', () {
    test('sigue abierto mientras falte plata', () {
      final c = CompromisoConSaldo(compromiso: _cuenta(), pagado: 60000);
      expect(c.saldo, 40000);
      expect(c.sigueAbierto, isTrue);
      expect(c.estaSaldado, isFalse);
    });

    test('deja de estar abierto al saldarse', () {
      final c = CompromisoConSaldo(compromiso: _cuenta(), pagado: 100000);
      expect(c.sigueAbierto, isFalse);
    });

    test('una cancelada a mano no cuenta como abierta aunque deba', () {
      final c = CompromisoConSaldo(
        compromiso: _cuenta(estado: kEstadoCompromisoCancelado),
        pagado: 0,
      );
      expect(c.saldo, 100000);
      expect(c.sigueAbierto, isFalse);
    });
  });

  group('fromMap / toMap', () {
    test('ida y vuelta conserva los campos', () {
      final original = _cuenta();
      final vuelta = CompromisoPersonal.fromMap(original.toMap());
      expect(vuelta.id, original.id);
      expect(vuelta.persona, 'Maxi');
      expect(vuelta.tipo, kTipoCompromisoTrabajo);
      expect(vuelta.concepto, 'Sonido del sábado');
      expect(vuelta.montoTotal, 100000);
      expect(vuelta.estado, kEstadoCompromisoActivo);
      expect(vuelta.fechaInicio, DateTime.utc(2026, 8, 12));
    });

    test('una fila incompleta no rompe: cae en los valores por defecto', () {
      final c = CompromisoPersonal.fromMap({
        'id': 'abc',
        'persona': 'Rodri',
        'monto_total': 500,
      });
      expect(c.tipo, kTipoCompromisoTrabajo);
      expect(c.estado, kEstadoCompromisoActivo);
      expect(c.montoTotal, 500);
    });
  });
}
