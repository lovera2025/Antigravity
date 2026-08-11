// Arnés manual: reimprime el recibo Nº 11408158 (VIZGARRA, 08/07/2026) con el
// código de producción, para mirar el papel sin levantar la app ni tocar la base
// ni la red.
//
//   flutter test tool/recibo_muestra_vizgarra_test.dart
//
// El papel original decía "Interés mora (cuota base — este cobro) $3.150" y el
// estado de cuenta del MISMO movimiento decía "Mora pendiente cuota 3 (no
// cobrada al pagar)". Además, como la línea viajaba sin `esMora`, los $3.150 se
// sumaban dentro de "Cuotas del plan".
//
// Entra por `conceptosPdfDesdePagosLote`, que es lo que ahora usan tanto el
// "imprimir recibo" de la grilla como el reimprimir de Finanzas.
//
// Los montos, las fechas y los conceptos son los del papel y de la ficha. El Reg
// (15/03/2026) es el que hace que la cuota 1 venza en Abr 2026, como dice el
// historial; no está verificado contra la base, así que la aritmética de días de
// mora de este arnés es ilustrativa — lo que se mira acá es el rotulado.
//
// No vive en test/ a propósito: guarda un PDF, y eso no tiene que pasar en cada
// corrida de la suite.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/common/services/pdf_service.dart';
import 'package:arguello_events/features/eventos/services/cobro_masivo_conceptos_pdf.dart';
import 'package:arguello_events/features/eventos/services/concepto_pago_display.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/evento.dart';

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
      : Directory.systemTemp.createTempSync('recibo_muestra').path;

  setUp(() {
    // El PDF se guarda en <docs>/Junior Eventos/PDFs. Redirigimos "docs" a la
    // carpeta de salida: la base y los papeles reales quedan intactos.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => destino,
        );
  });

  test('recibo VIZGARRA 08/07/2026 — cuota 4 + arrastre de la cuota 3', () async {
    final fechaCobro = DateTime(2026, 7, 8, 10, 14);

    // Contrato como quedó después del cobro: 4/9, saldo $175.000.
    final contrato = ContratoAlumno(
      id: 'vizgarra-muestra',
      eventoId: 'ev-muestra',
      nombreAlumno: 'VIZGARRA, SONIA',
      cantidadAcompanantes: 0,
      montoTotalPactado: 315000,
      saldoDeudor: 175000,
      cuotasPagadas: 4,
      totalCuotas: 9,
      createdAt: DateTime.utc(2026, 3, 15, 12),
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

    // Historial tal como se lee en el Estado de cuenta de la foto.
    final historial = [
      _pago(
        id: 'p1',
        fecha: '2026-05-11T21:32:00.000Z',
        concepto: 'Cuota Base',
        monto: 70000,
      ),
      _pago(
        id: 'p2',
        fecha: '2026-05-11T21:32:01.000Z',
        concepto: 'Interés mora cuota 1 (vto Abr 2026)',
        monto: 3850,
        lineKind: 'interes_mora',
      ),
      _pago(
        id: 'p3',
        fecha: '2026-06-09T12:08:00.000Z',
        concepto: 'Cuota Base',
        monto: 35000,
      ),
      _pago(
        id: 'p4',
        fecha: '2026-07-08T13:14:00.000Z',
        concepto: 'Cuota Base',
        monto: 35000,
      ),
      _pago(
        id: 'p5',
        fecha: '2026-07-08T13:14:01.000Z',
        concepto: 'Mora pendiente cuota 3 (no cobrada al pagar)',
        monto: 3150,
        lineKind: 'interes_mora',
      ),
    ];

    final lote = historial
        .where((p) => p['id'] == 'p4' || p['id'] == 'p5')
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
      stdout.writeln('   • ${l['display']}  — ${l['monto']}');
      stdout.writeln('     concepto: ${l['concepto']}');
    }

    // Lo que estaba mal en el papel de la foto: la mora contada como plan.
    expect(mora, closeTo(3150, 0.01));
    expect(total - mora, closeTo(35000, 0.01));
    // Y el papel nombra la cuota 3, igual que la ficha.
    expect(
      display.any((l) => (l['cuotaPrevia'] as num?)?.toInt() == 3),
      isTrue,
    );

    // Ficha: el mismo movimiento, como se lee en el Estado de cuenta.
    final filas = ConceptoPagoDisplay.enriquecerPagosHistorial(
      contrato,
      historial,
    );
    final filaMora = filas.firstWhere((f) => f['id'] == 'p5');
    stdout.writeln('── ficha: "${filaMora['concepto_ficha']}"');
    stdout.writeln('          "${filaMora['subtexto_ficha']}"');
    expect(
      filaMora['concepto_ficha'],
      isNot(contains('no cobrada al pagar')),
    );

    await PdfService.generarReciboAlumno(
      alumno: contrato,
      evento: evento,
      montoPagado: total,
      saldoPendiente: 175000,
      conceptosPagados: conceptos,
      fechaManual: fechaCobro,
      esReimpresion: true,
      medioPago: 'Efectivo',
    );

    final pdfs = Directory(
      '$destino${Platform.pathSeparator}Junior Eventos'
      '${Platform.pathSeparator}PDFs',
    );
    stdout.writeln('── PDF en: ${pdfs.path}');
    expect(pdfs.existsSync(), isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
