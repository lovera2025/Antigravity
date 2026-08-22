// Arnés manual: reimprime el recibo Nº FF677977 (VAREIRO, 04/08/2026) con el
// código de producción, para mirar el papel sin levantar la app ni tocar la base
// ni la red.
//
//   flutter test tool/recibo_muestra_vareiro_test.dart
//
// El papel original decía, sobre un cobro de $25.000 de mora:
//
//   • Mora no cobrada al pagar (cuotas ya pagadas)   $19.400
//   • Mora cuota 1                                    $5.600
//   MORA COBRADA EN ESTE PAGO — $25.000
//   Corresponde a la mora de la cuota 1 (no cobrada al pagar).
//
// Tres cosas mal: el recuadro nombraba la cuota 1 por los $25.000 cuando de ahí
// salían $5.600; los $19.400 no decían de dónde eran; y en ningún lado decía que
// había sido un pago parcial de una mora de $47.200.
//
// Lo que se mira acá es el rotulado. Los montos y las fechas son los del papel;
// el Reg no está verificado contra la base, así que la aritmética de días de
// mora de este arnés es ilustrativa.
//
// No vive en test/ a propósito: guarda un PDF, y eso no tiene que pasar en cada
// corrida de la suite.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/common/services/pdf_service.dart';
import 'package:arguello_events/features/eventos/services/cobro_masivo_conceptos_pdf.dart';
import 'package:arguello_events/features/eventos/services/concepto_pago_display.dart';
import 'package:arguello_events/features/eventos/services/mora_cuota_calculator.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/evento.dart';

/// Cuota vencida todavía impaga, para el desglose del aviso rojo.
MoraCuotaDetalle _vencida(int n, String mes, int dias, double monto) =>
    MoraCuotaDetalle(
      numeroCuota: n,
      vencimiento: DateTime(2026, n + 3, 28),
      diasMora: dias,
      interesBruto: monto,
      mesLabel: mes,
    );

/// Carpeta de salida: se pasa por -Dsalida=... o cae en el temporal del sistema.
const _salida = String.fromEnvironment('salida', defaultValue: '');

Map<String, dynamic> _pago({
  required String id,
  required String fecha,
  required String concepto,
  required double monto,
  String medio = 'Efectivo',
  String? lineKind,
}) => {
  'id': id,
  'concepto': concepto,
  'monto': monto,
  'monto_gross': monto,
  'fecha_pago': fecha,
  'medio_pago': medio,
  if (lineKind != null) 'line_kind': lineKind,
  'anulado': 0,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final destino = _salida.isNotEmpty
      ? _salida
      : Directory.systemTemp.createTempSync('recibo_vareiro').path;

  setUp(() {
    // El PDF se guarda en <docs>/Junior Eventos/PDFs. Redirigimos "docs" a la
    // carpeta de salida: la base y los papeles reales quedan intactos.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => destino,
        );
  });

  test('recibo VAREIRO 04/08/2026 — cuotas 2-3-4 + mora parcial', () async {
    final fechaCobro = DateTime(2026, 8, 4, 11, 6);

    final contrato = ContratoAlumno(
      id: 'vareiro-muestra',
      eventoId: 'ev-muestra',
      nombreAlumno: 'VAREIRO, YOSELIE ANAHI',
      cantidadAcompanantes: 0,
      montoTotalPactado: 360000,
      saldoDeudor: 200000,
      cuotasPagadas: 4,
      totalCuotas: 9,
      createdAt: DateTime.utc(2026, 3, 30, 3),
    );

    final evento = Evento(
      id: 'ev-muestra',
      clienteId: 'cli-muestra',
      tipo: 'Egresados',
      fechaEvento: DateTime(2026, 11, 21),
      estado: EstadoEvento.confirmado,
      modalidad: 'masivo',
      cantidadCuotas: 9,
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

    final lote = historial
        .where((p) => p['id'] == 'p2' || p['id'] == 'p3')
        .toList();

    final conceptos = ConceptoPagoDisplay.conceptosPdfDesdePagosLote(
      contrato,
      lote,
      historialCompleto: historial,
    );

    final display = lineasDisplayParaPdf(conceptos);
    final mora = moraSeleccionadaPdf(display);
    final total = display.fold<double>(
      0,
      (s, l) => s + (l['monto'] as num).toDouble(),
    );

    stdout.writeln('── total del recibo: \$${total.toStringAsFixed(2)}');
    stdout.writeln('── cuotas del plan:  \$${(total - mora).toStringAsFixed(2)}');
    stdout.writeln('── mora:             \$${mora.toStringAsFixed(2)}');
    for (final l in display) {
      final marca = l['arrastre'] == true ? 'arrastre' : 'cobro';
      stdout.writeln('   • [$marca] ${l['display']}  — ${l['monto']}');
      if ((l['subtexto'] as String?)?.isNotEmpty ?? false) {
        stdout.writeln('       ${l['subtexto']}');
      }
    }

    expect(mora, closeTo(25000, 0.01));
    expect(total - mora, closeTo(120000, 0.01));

    // Los renglones de arrastre no repiten el título del bloque.
    final arrastre = display.where((l) => l['arrastre'] == true).toList();
    expect(arrastre, isNotEmpty);
    for (final l in arrastre) {
      expect(
        l['display'] as String,
        isNot(contains('Mora no cobrada al pagar')),
        reason: 'eso ya lo dice el título del bloque',
      );
    }

    // Impresión original: se conoce lo que quedó, así que el verde puede decir
    // de cuánto era y el rojo cuánto falta.
    await PdfService.generarReciboAlumno(
      alumno: contrato,
      evento: evento,
      montoPagado: total,
      saldoPendiente: 200000,
      conceptosPagados: conceptos,
      fechaManual: fechaCobro,
      esReimpresion: false,
      medioPago: 'Efectivo',
      moraPendienteRestante: 22200,
      moraPendienteDesglose: [_vencida(5, 'Ago', 4, 22200)],
    );

    // Y la reimpresión del mismo cobro. El aviso rojo va **fechado**: el número
    // es el de hoy, no el de aquel día. Omitirlo era peor —el papel mostraba
    // los $25.000 que entraron y nada de los $22.200 que seguían debiéndose, y
    // se leía como si el pago hubiera saldado la mora.
    await PdfService.generarReciboAlumno(
      alumno: contrato.copyWith(
        nombreAlumno: 'VAREIRO, YOSELIE ANAHI (REIMPRESION)',
      ),
      evento: evento,
      montoPagado: total,
      saldoPendiente: 200000,
      conceptosPagados: conceptos,
      fechaManual: fechaCobro,
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

    final pdfs = Directory(
      '$destino${Platform.pathSeparator}Junior Eventos'
      '${Platform.pathSeparator}PDFs',
    );
    stdout.writeln('── PDF en: ${pdfs.path}');
    expect(pdfs.existsSync(), isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
