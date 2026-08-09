// Arnés manual: emite el recibo Nº 0661293D con el código de producción, para
// mirar el papel sin levantar la app ni tocar la base ni la red.
//
//   flutter test tool/recibo_muestra_bernel_test.dart
//
// No vive en test/ a propósito: guarda un PDF y lo abre, y eso no tiene que
// pasar en cada corrida de la suite.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/common/services/pdf_service.dart';
import 'package:arguello_events/features/eventos/services/cobro_masivo_conceptos_pdf.dart';
import 'package:arguello_events/features/eventos/services/cobro_mora_resolver.dart';
import 'package:arguello_events/features/eventos/services/mora_concepto_rotulo.dart';
import 'package:arguello_events/features/eventos/services/mora_cuota_calculator.dart';
import 'package:arguello_events/features/eventos/services/mora_tracked_origen.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/evento.dart';

/// Carpeta de salida: se pasa por -Dsalida=... o cae en el temporal del sistema.
const _salida = String.fromEnvironment('salida', defaultValue: '');

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

  test('recibo BERNEL 07/08/2026 — cobro de toda la mora', () async {
    final fechaCobro = DateTime(2026, 8, 7, 17, 30);
    final diaAr = DateTime(2026, 8, 7);

    // Contrato tal como estaba antes del cobro.
    final pre = ContratoAlumno(
      id: 'bernel-muestra',
      eventoId: 'ev-muestra',
      nombreAlumno: 'BERNEL, LUCILA FATIMA',
      cantidadAcompanantes: 0,
      montoTotalPactado: 270000,
      saldoDeudor: 180000,
      cuotasPagadas: 3,
      totalCuotas: 9,
      institucion: 'SAGRADO CORAZON',
      createdAt: DateTime.utc(2026, 3, 15, 12),
      // C2 ($6.900) y C3 ($8.100): cuotas ya pagadas sin cobrarles el interés.
      moraPendienteTracked: 15000,
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

    final arrastre = [
      const MoraPendientePreviaDetalle(
        numeroCuota: 2,
        mesLabel: 'May 2026',
        montoAtribuido: 6900,
        diasMora: 23,
        moraDebida: 6900,
      ),
      const MoraPendientePreviaDetalle(
        numeroCuota: 3,
        mesLabel: 'Jun 2026',
        montoAtribuido: 8100,
        diasMora: 27,
        moraDebida: 8100,
      ),
    ];

    // Cuota 4 vencida: $2.100 (7 días). Total de mora a cobrar: $17.100.
    final calendario = MoraCuotaCalculator.calcularDesglose(pre, diaAr);
    final moraTotal =
        calendario.fold<double>(0, (s, d) => s + d.interesBruto) + 15000;

    // Mismo armado que el modal de cobro masivo.
    final preview = MoraConceptoRotulo.construirPreviewMora(
      montoTotal: moraTotal,
      detallesCalendario: calendario,
      montoPendientePrevias: 15000,
      lineKind: 'interes_mora',
      detallePendiente: arrastre,
    );
    final conceptos = conceptosFinalesDesdePreviewMasivo(
      previewConceptos: [preview],
      esLineaCargoCanal: (c) => c['lineKind'] == 'cargo_canal_ref',
      esLineaInteresMora: (c) => c['lineKind'] == 'interes_mora',
      cPagadas: 3,
      tCuotas: 9,
      mPagadas: 0,
      mCuotas: 1,
      sPagadas: 0,
      sCuotas: 1,
    );

    // Cobro de sola mora: el plan no se mueve.
    final resuelta = resolverMoraDeCobro(
      contratoPre: pre,
      contratoPost: pre,
      moraCobradaHistorial: 0,
      moraEsteCobro: moraTotal,
      cuotasBaseLiquidadasEnCobro: 0,
      cuotasBasePagadasPostCobro: 3,
      saldoDeudorPost: 180000,
      fechaCobroAr: diaAr,
      formatoMonto: (v) => '\$${v.toStringAsFixed(2)}',
      trackedDetalle: arrastre,
    );

    stdout.writeln('── mora cobrada:   \$${moraTotal.toStringAsFixed(2)}');
    stdout.writeln(
      '── mora que queda: \$${resuelta.moraPendientePost.toStringAsFixed(2)}',
    );
    stdout.writeln('── aviso rojo:     "${resuelta.moraPendienteOrigen}"');
    for (final c in conceptos) {
      stdout.writeln('   • ${c['concepto']} — ${c['monto']}');
    }

    await PdfService.generarReciboAlumno(
      alumno: resuelta.contratoPatch,
      evento: evento,
      montoPagado: moraTotal,
      saldoPendiente: 180000,
      conceptosPagados: conceptos,
      fechaManual: fechaCobro,
      esReimpresion: false,
      moraPendienteRestante: resuelta.moraPendientePost,
      moraPendienteOrigen: resuelta.moraPendienteOrigen,
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
