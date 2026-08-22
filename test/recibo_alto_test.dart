// El recibo entra en media hoja A4 **sin** quedarse sin detalle de mora.
//
// `pdf_ajuste_medido_test.dart` mide un cuerpo sintético que escala entero, así
// que daba verde mientras el recibo de producción se desbordaba: ahí el 80% del
// papel era `const` y la escalera solo podía apretar los renglones de mora. El
// recibo Nº FF677977 salió en nivel ≥3 y las dos barras quedaron sin una sola
// línea que dijera de qué cuotas salían los $25.000 cobrados y los $22.200 que
// seguían debiéndose.
//
// Acá se mide `generarReciboAlumno` de verdad, con las fuentes de verdad.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

import 'package:arguello_events/features/common/services/pdf_service.dart';
import 'package:arguello_events/features/eventos/services/concepto_pago_display.dart';
import 'package:arguello_events/features/eventos/services/mora_concepto_rotulo.dart';
import 'package:arguello_events/features/eventos/services/mora_cuota_calculator.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/evento.dart';

double get _mediaA4 => PdfPageFormat.a4.height / 2;

Map<String, dynamic> _pago({
  required String id,
  required String fecha,
  required String concepto,
  required double monto,
  String? lineKind,
}) => {
  'id': id,
  'concepto': concepto,
  'monto': monto,
  'monto_gross': monto,
  'fecha_pago': fecha,
  'medio_pago': 'Efectivo',
  'line_kind': ?lineKind,
  'anulado': 0,
};

Evento _evento() => Evento(
  id: 'ev-alto',
  clienteId: 'cli-alto',
  tipo: 'Egresados',
  fechaEvento: DateTime(2026, 11, 21),
  estado: EstadoEvento.confirmado,
  modalidad: 'masivo',
  cantidadCuotas: 9,
);

MoraCuotaDetalle _vencida(int n, String mes, int dias, double monto) =>
    MoraCuotaDetalle(
      numeroCuota: n,
      vencimiento: DateTime(2026, n + 3, 28),
      diasMora: dias,
      interesBruto: monto,
      mesLabel: mes,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory destino;

  setUp(() {
    destino = Directory.systemTemp.createTempSync('recibo_alto');
    // El PDF se entrega en <docs>/Junior Eventos/PDFs. Se redirige "docs" al
    // temporal: la suite no puede escribir en los papeles reales.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => destino.path,
        );
  });

  tearDown(() {
    if (destino.existsSync()) destino.deleteSync(recursive: true);
  });

  test('un cobro común entra en media hoja sin compactar', () async {
    final contrato = ContratoAlumno(
      id: 'simple-0001',
      eventoId: 'ev-alto',
      nombreAlumno: 'PEREZ, JUAN',
      cantidadAcompanantes: 0,
      montoTotalPactado: 360000,
      saldoDeudor: 320000,
      cuotasPagadas: 1,
      totalCuotas: 9,
      createdAt: DateTime.utc(2026, 3, 30, 3),
    );

    final r = await PdfService.generarReciboAlumno(
      alumno: contrato,
      evento: _evento(),
      montoPagado: 40000,
      saldoPendiente: 320000,
      conceptoCuotas: 'Cuota 1 de 9',
      fechaManual: DateTime(2026, 5, 6, 11, 0),
      esReimpresion: false,
      medioPago: 'Efectivo',
    );

    expect(
      r.alto,
      lessThanOrEqualTo(_mediaA4 + 0.5),
      reason: 'un recibo simple tiene que entrar en media hoja',
    );
    expect(
      r.ajuste.esIntacto,
      isTrue,
      reason: 'sin mora ni extras el papel no debería necesitar compactarse',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
    'el caso VAREIRO entra y conserva el detalle de las dos moras',
    () async {
      final contrato = ContratoAlumno(
        id: 'vareiro-alto',
        eventoId: 'ev-alto',
        nombreAlumno: 'VAREIRO, YOSELIE ANAHI',
        cantidadAcompanantes: 0,
        montoTotalPactado: 360000,
        saldoDeudor: 200000,
        cuotasPagadas: 4,
        totalCuotas: 9,
        createdAt: DateTime.utc(2026, 3, 30, 3),
      );

      final historial = [
        _pago(
          id: 'p1',
          fecha: '2026-05-06T14:00:00.000Z',
          concepto: 'Cuota Base (1/9)',
          monto: 40000,
        ),
        _pago(
          id: 'p2',
          fecha: '2026-08-04T14:06:00.000Z',
          concepto: 'Cuotas base (2-3-4/9)',
          monto: 120000,
        ),
        _pago(
          id: 'p3',
          fecha: '2026-08-04T14:06:01.000Z',
          concepto: 'Mora pendiente cuota 1 (no cobrada al pagar)',
          monto: 25000,
          lineKind: 'interes_mora',
        ),
      ];

      final conceptos = ConceptoPagoDisplay.conceptosPdfDesdePagosLote(
        contrato,
        historial.where((p) => p['id'] != 'p1').toList(),
        historialCompleto: historial,
      );

      final r = await PdfService.generarReciboAlumno(
        alumno: contrato,
        evento: _evento(),
        montoPagado: 145000,
        saldoPendiente: 200000,
        conceptosPagados: conceptos,
        fechaManual: DateTime(2026, 8, 4, 11, 6),
        esReimpresion: true,
        medioPago: 'Efectivo',
        moraPendienteRestante: 22200,
        moraRestanteMedidaEl: DateTime(2026, 8, 21),
        moraPendienteDesglose: [
          _vencida(1, 'Abr', 113, 9800),
          _vencida(5, 'Jul', 51, 7600),
          _vencida(6, 'Ago', 21, 4800),
        ],
      );

      expect(
        r.alto,
        lessThanOrEqualTo(_mediaA4 + 0.5),
        reason: 'el recibo con las dos barras de mora tiene que entrar',
      );
      expect(
        r.ajuste.maxFilasMora,
        greaterThanOrEqualTo(3),
        reason:
            'si para entrar hay que dejar la mora en menos de tres cuotas, '
            'el papel volvió a engordar',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('el peor caso realista entra sin dejar la mora en un solo renglón', () async {
    final contrato = ContratoAlumno(
      id: 'peor-caso-0001',
      eventoId: 'ev-alto',
      nombreAlumno: 'GONZALEZ RODRIGUEZ, MARIA DE LOS ANGELES',
      cantidadAcompanantes: 4,
      montoTotalPactado: 620000,
      saldoDeudor: 310000,
      cuotasPagadas: 5,
      totalCuotas: 9,
      numeroMesa: '12',
      institucion: 'COLEGIO NUESTRA SEÑORA DEL BUEN CONSEJO',
      mesaExtraPrecio: 120000,
      mesaExtraPagado: 40000,
      mesaExtraCuotas: 6,
      sillasExtraCantidad: 12,
      sillasExtraPrecioTotal: 48000,
      sillasExtraPagado: 24000,
      sillasExtraCuotas: 6,
      sillasExtraCuotasPagadas: 3,
      createdAt: DateTime.utc(2026, 1, 30, 3),
    );

    // Seis cuotas vencidas más arrastre: el escenario que estira el papel.
    final r = await PdfService.generarReciboAlumno(
      alumno: contrato,
      evento: _evento(),
      montoPagado: 180000,
      saldoPendiente: 310000,
      conceptoCuotas: 'Cuotas 4 a 6 de 9',
      fechaManual: DateTime(2026, 8, 4, 11, 6),
      esReimpresion: true,
      medioPago: 'Mixto',
      montoEfectivoDetalle: 100000,
      montoTransferenciaDetalle: 80000,
      porcentajeDescuentoLiquidacion: 10,
      moraPendienteRestante: 64300,
      moraRestanteMedidaEl: DateTime(2026, 8, 21),
      moraPendienteDesglose: [
        _vencida(1, 'Abr', 113, 9800),
        _vencida(2, 'May', 92, 8400),
        _vencida(3, 'Jun', 71, 7200),
        _vencida(4, 'Jul', 51, 6100),
      ],
      moraPendienteArrastre: const [
        MoraPendientePreviaDetalle(
          numeroCuota: 5,
          mesLabel: 'Ago 2026',
          montoAtribuido: 18400,
          diasMora: 21,
        ),
        MoraPendientePreviaDetalle(
          numeroCuota: 6,
          mesLabel: 'Sep 2026',
          montoAtribuido: 14400,
          diasMora: 9,
        ),
      ],
    );

    expect(
      r.alto,
      lessThanOrEqualTo(_mediaA4 + 0.5),
      reason: 'mesas, sillas, descuento, pago mixto y seis cuotas en mora',
    );
    expect(
      r.ajuste.maxFilasMora,
      greaterThanOrEqualTo(2),
      reason: 'ni en el peor caso la mora puede quedar en un renglón solo',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
