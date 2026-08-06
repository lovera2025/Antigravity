import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/cierre_caja/services/cobro_agrupado.dart';
import 'package:arguello_events/features/cierre_caja/services/datos_cierre_sesion.dart';
import 'package:arguello_events/features/mi_empresa/models/ingreso_detallado.dart';

/// Las garantías de la hoja de cierre que se pueden verificar sin renderizar:
/// que no se pierde ni un peso ni una fila, y que las dos mitades cierran entre
/// sí. El alto medido del PDF se cubre a ojo en la verificación manual (paso 6b),
/// porque medirlo acá necesita las fuentes descargadas y volvería el test
/// dependiente de la red.
List<IngresoDetallado> _cobros(int cantidad, {int desdeMinuto = 0}) {
  final base = DateTime.utc(2026, 8, 5, 9, 0);
  final out = <IngresoDetallado>[];
  for (var i = 0; i < cantidad; i++) {
    // Un cobro por alumno, cada uno con 3 líneas a milisegundos de distancia:
    // el caso real que motivó agrupar.
    final t = base.add(Duration(minutes: desdeMinuto + i));
    final transferencia = i % 4 == 0;
    for (var l = 0; l < 3; l++) {
      out.add(
        IngresoDetallado(
          id: 'p-$i-$l',
          fuente: 'Masivo',
          fecha: t.add(Duration(milliseconds: l * 30)),
          monto: 1000 + l * 111.11,
          concepto: l == 2
              ? 'Interés mora cuota ${l + 1} (vto Jun 2026)'
              : 'Cuota Base (${l + 1}/9)',
          alumnoOCliente: 'APELLIDO$i, NOMBRE COMPUESTO LARGO',
          nombreEvento: 'Egresados',
          medioPago: transferencia ? 'Transferencia' : 'Efectivo',
          sesionCajaId: 's-1',
          contratoAlumnoId: 'c-$i',
        ),
      );
    }
  }
  return out;
}

double _r2(double v) => double.parse(v.toStringAsFixed(2));

void main() {
  group('hoja de cierre · garantías de datos', () {
    for (final n in [0, 5, 20, 60, 130, 200]) {
      test('$n cobros · no se pierde ni un peso ni una fila', () {
        final ingresos = _cobros(n);
        final ef = cobrosDeMedio(ingresos, transferencia: false);
        final tr = cobrosDeMedio(ingresos, transferencia: true);

        // Ninguna fila se cae: cada cobro aparece en al menos un bucket.
        expect(ef.length + tr.length, n);

        // Ningún peso se pierde ni se duplica entre los dos bloques.
        final suma = _r2([...ef, ...tr].fold<double>(0, (s, c) => s + c.monto));
        expect(suma, _r2(ingresos.fold<double>(0, (s, i) => s + i.monto)));

        // Y todas las líneas de la base siguen representadas.
        expect(
          [...ef, ...tr].fold<int>(0, (s, c) => s + c.lineas.length),
          ingresos.length,
        );
      });
    }

    test('las dos mitades de la hoja cierran entre sí', () {
      // La mitad de abajo suma filas por bucket; la de arriba muestra el neto.
      // Si no coinciden, la hoja se contradice y sirve para contar mal.
      final ingresos = _cobros(40);
      final datos = DatosCierreSesion(
        ingresos: ingresos,
        efectivoBruto: _r2(
          ingresos
              .where((i) => i.medioPago != 'Transferencia')
              .fold<double>(0, (s, i) => s + i.monto),
        ),
        transferenciaBruta: _r2(
          ingresos
              .where((i) => i.medioPago == 'Transferencia')
              .fold<double>(0, (s, i) => s + i.monto),
        ),
      );

      final sumaEf = _r2(
        cobrosDeMedio(
          ingresos,
          transferencia: false,
        ).fold<double>(0, (s, c) => s + c.monto),
      );
      final sumaTr = _r2(
        cobrosDeMedio(
          ingresos,
          transferencia: true,
        ).fold<double>(0, (s, c) => s + c.monto),
      );

      expect(sumaEf - datos.egresosEfectivo, datos.efectivoNeto);
      expect(sumaTr - datos.egresosTransferencia, datos.transferenciaNeta);
      expect(_r2(sumaEf + sumaTr), _r2(datos.totalNeto));
    });

    test('el efectivo esperado es cambio inicial + neto', () {
      // La cifra que muestra el aviso previo y contra la que se compara el
      // arqueo. Con el bruto en su lugar, el arqueo daría diferencia siempre.
      const datos = DatosCierreSesion(
        efectivoBruto: 271111.08,
        egresosEfectivo: 5000,
      );
      expect(datos.efectivoNeto, 266111.08);
      expect(datos.efectivoEsperado(20000), 286111.08);
    });

    test('sesión vacía: totales en cero y sin filas, sin explotar', () {
      const datos = DatosCierreSesion();
      expect(datos.vacio, isTrue);
      expect(datos.totalNeto, 0);
      expect(cobrosDeMedio(const [], transferencia: false), isEmpty);
      expect(cobrosDeMedio(const [], transferencia: true), isEmpty);
    });

    test('el día normal conserva el resumen de conceptos', () {
      final ef = cobrosDeMedio(_cobros(12), transferencia: false);
      expect(ef, isNotEmpty);
      for (final c in ef) {
        expect(c.resumenConceptos.isNotEmpty, isTrue);
        expect(c.resumenConceptos, isNot('—'));
      }
    });
  });
}
