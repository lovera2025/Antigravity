import 'package:arguello_events/features/eventos/services/cronograma_cuotas_utils.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:flutter_test/flutter_test.dart';

ContratoAlumno _contratoLezcano() => ContratoAlumno(
      id: 'lezcano',
      eventoId: 'evt',
      nombreAlumno: 'LEZCANO, BLAS',
      cantidadAcompanantes: 0,
      montoTotalPactado: 270000,
      saldoDeudor: 240000,
      cuotasPagadas: 1,
      totalCuotas: 9,
      createdAt: DateTime.utc(2026, 3, 30, 12, 0, 0),
      moraPendienteTracked: 0,
      moraCobradaOffset: 32700,
      moraExentaHasta: DateTime(2026, 7, 31),
    );

ContratoAlumno _contratoAlDia() => ContratoAlumno(
      id: 'aldia',
      eventoId: 'evt',
      nombreAlumno: 'ALUMNO AL DIA',
      cantidadAcompanantes: 0,
      montoTotalPactado: 270000,
      saldoDeudor: 180000,
      cuotasPagadas: 3,
      totalCuotas: 9,
      createdAt: DateTime.utc(2026, 3, 30, 12, 0, 0),
    );

void main() {
  group('CronogramaCuotasUtils', () {
    test('Lezcano: 2 cuotas impagas vencidas al 7-jul', () {
      expect(
        CronogramaCuotasUtils.cuotasImpagasVencidas(
          _contratoLezcano(),
          DateTime(2026, 7, 7),
        ),
        2,
      );
      expect(
        CronogramaCuotasUtils.cronogramaAlDia(
          _contratoLezcano(),
          DateTime(2026, 7, 7),
        ),
        isFalse,
      );
    });

    test('Lezcano: estado CUOTAS ATRASADAS con mora \$0', () {
      final ui = CronogramaCuotasUtils.resolverEstadoUi(
        contrato: _contratoLezcano(),
        moraEnMora: false,
        moraPendientePesos: 0,
        ahoraAr: DateTime(2026, 7, 7),
      );
      expect(ui.kind, ContratoEstadoDeudaKind.cuotasAtrasadas);
      expect(ui.texto, 'CUOTAS ATRASADAS');
    });

    test('Lezcano: próximo vencimiento futuro cuota 4 = 31-jul', () {
      final futuro = CronogramaCuotasUtils.proximoVencimientoFuturo(
        _contratoLezcano(),
        DateTime(2026, 7, 7),
      );
      expect(futuro, isNotNull);
      expect(futuro!.numeroCuota, 4);
      expect(futuro.vencimiento.day, 31);
      expect(futuro.vencimiento.month, 7);
    });

    test('Lezcano: líneas informativas con mora congelada', () {
      final lineas = CronogramaCuotasUtils.lineasInformativas(
        _contratoLezcano(),
        ahoraAr: DateTime(2026, 7, 7),
        moraPendientePesos: 0,
      );
      expect(lineas.cuotaPendiente, contains('2/9'));
      expect(lineas.cuotaPendiente, contains('vencida'));
      expect(lineas.proximoVencimiento, contains('31'));
      expect(lineas.moraCongeladaHasta, isNotNull);
    });

    test('Alumno con 3 cuotas pagadas al 7-jul: cronograma al día', () {
      expect(
        CronogramaCuotasUtils.cronogramaAlDia(
          _contratoAlDia(),
          DateTime(2026, 7, 7),
        ),
        isTrue,
      );
      final ui = CronogramaCuotasUtils.resolverEstadoUi(
        contrato: _contratoAlDia(),
        moraEnMora: false,
        moraPendientePesos: 0,
        ahoraAr: DateTime(2026, 7, 7),
      );
      expect(ui.kind, ContratoEstadoDeudaKind.alDia);
    });

    // El plan saldado no salda la mora. Cobrar la última cuota sin el interés
    // deja saldo cero y el arrastre en ficha; mientras ese caso caía en
    // LIQUIDADO, la celda de la grilla decía "LIQUIDADO" en verde y dos
    // renglones más abajo "Mora pendiente: $1.200".
    group('plan saldado con mora en ficha', () {
      ContratoAlumno saldado({required double tracked}) => ContratoAlumno(
        id: 'riquelme',
        eventoId: 'evt',
        nombreAlumno: 'RIQUELME, AYLEN PRISCILA',
        cantidadAcompanantes: 0,
        montoTotalPactado: 340000,
        saldoDeudor: 0,
        cuotasPagadas: 9,
        totalCuotas: 9,
        createdAt: DateTime.utc(2026, 3, 30, 12, 0, 0),
        moraPendienteTracked: tracked,
      );

      test('con mora pendiente NO dice LIQUIDADO', () {
        final ui = CronogramaCuotasUtils.resolverEstadoUi(
          contrato: saldado(tracked: 1200),
          // `calcular().enMora` da false sin saldo: por eso el estado no puede
          // depender de esa bandera para este caso.
          moraEnMora: false,
          moraPendientePesos: 1200,
          ahoraAr: DateTime(2026, 8, 24),
        );
        expect(ui.kind, ContratoEstadoDeudaKind.planSaldadoConMora);
        expect(ui.texto, isNot(contains('LIQUIDADO')));
        expect(ui.color, isNot(CronogramaCuotasUtils.colorLiquidado));
      });

      test('sin mora sigue diciendo LIQUIDADO, como siempre', () {
        final ui = CronogramaCuotasUtils.resolverEstadoUi(
          contrato: saldado(tracked: 0),
          moraEnMora: false,
          moraPendientePesos: 0,
          ahoraAr: DateTime(2026, 8, 24),
        );
        expect(ui.kind, ContratoEstadoDeudaKind.liquidado);
        expect(ui.texto, 'LIQUIDADO');
      });

      test('con saldo, el estado no cambió en nada (no-regresión)', () {
        // Los 623 contratos con saldo son el 100% de lo que se cobra por día:
        // el arreglo no puede tocarles el estado.
        final atrasado = CronogramaCuotasUtils.resolverEstadoUi(
          contrato: _contratoLezcano(),
          moraEnMora: false,
          moraPendientePesos: 5000,
          ahoraAr: DateTime(2026, 7, 7),
        );
        expect(atrasado.kind, ContratoEstadoDeudaKind.cuotasAtrasadas);

        final enMora = CronogramaCuotasUtils.resolverEstadoUi(
          contrato: _contratoLezcano(),
          moraEnMora: true,
          moraPendientePesos: 5000,
          ahoraAr: DateTime(2026, 7, 7),
        );
        expect(enMora.kind, ContratoEstadoDeudaKind.moraVencida);

        final alDia = CronogramaCuotasUtils.resolverEstadoUi(
          contrato: _contratoAlDia(),
          moraEnMora: false,
          moraPendientePesos: 0,
          ahoraAr: DateTime(2026, 7, 7),
        );
        expect(alDia.kind, ContratoEstadoDeudaKind.alDia);
      });
    });

    test('excluidoDeRegUnificado detecta BUENA VISTA y PUERTO VIEJO', () {
      expect(
        CronogramaCuotasUtils.excluidoDeRegUnificado(
          clienteNombre: 'COLEGIO BUENA VISTA',
        ),
        isTrue,
      );
      expect(
        CronogramaCuotasUtils.excluidoDeRegUnificado(
          eventoTipo: 'PUERTO VIEJO RECEPCION',
        ),
        isTrue,
      );
      expect(
        CronogramaCuotasUtils.excluidoDeRegUnificado(
          clienteNombre: 'NORMAL MARIANO I LOZA',
        ),
        isFalse,
      );
    });
  });
}
