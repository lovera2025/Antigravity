// Los papeles de antes y después de la 6.8.1 (spec del 14-nov, sección 8.2.3),
// para que el usuario los vea antes de aprobar: de cada alumno elegido, el
// Estado de cuenta y sus recibos con mora, como salían con la 6.8.0 y como
// salen con la 6.8.1.
//
// "Antes" es lo que hacía la 6.8.0:
//   - el recibo, REIMPRIMIR del renglón de la mora del Estado de cuenta: ese
//     renglón solo, sin cuota ni mes en el recuadro verde;
//   - el Estado de cuenta, con el título del texto guardado y el remanente
//     repartido con la regla de la 6.8.0 (`InferirDeLa680`).
// "Después", el camino de la 6.8.1: el cobro entero (`ReciboDeUnCobro`), con la
// nota de la cuota pagada en partes.
//
// NUNCA abre la base real: trabaja sobre una copia de la copia. Los PDF llevan
// nombres de alumnos: <salida> va fuera del repositorio.
//
//   flutter test tool/papeles_rotulo_mora_muestra_test.dart
//     --dart-define=copia=<data.db copiada con VACUUM INTO>
//     --dart-define=salida=<carpeta fuera del repositorio>
//     --dart-define=alumnos=<id de contrato>;<id de contrato>
//     [--dart-define=desde=2026-11-01]   (los cobros con mora desde ese día)

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/features/common/services/pdf_service.dart';
import 'package:arguello_events/features/eventos/repositories/mora_congelada_repository.dart';
import 'package:arguello_events/features/eventos/services/cobro_abono_acumulado.dart';
import 'package:arguello_events/features/eventos/services/concepto_pago_display.dart';
import 'package:arguello_events/features/eventos/services/mora_concepto_rotulo.dart';
import 'package:arguello_events/features/eventos/services/mora_congelada.dart';
import 'package:arguello_events/features/eventos/services/mora_cuota_calculator.dart';
import 'package:arguello_events/features/eventos/services/mora_tracked_origen.dart';
import 'package:arguello_events/features/eventos/services/recibo_de_un_cobro.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/evento.dart';

import '../test/helpers/inferir_de_la_6_8_0.dart';

const _copia = String.fromEnvironment('copia');
const _salida = String.fromEnvironment('salida');
const _alumnos = String.fromEnvironment('alumnos');
const _desde = String.fromEnvironment('desde', defaultValue: '2026-08-21');

late Directory _pdfs;

/// El Estado de cuenta pide la Outfit con `PdfGoogleFonts`, que la baja de
/// internet; en flutter test no hay red y caía a Helvetica. Se deja la misma
/// letra en la memoria del paquete, desde los archivos de la app (como en
/// `cobro_igual_que_hoy_test.dart`).
Future<void> _letrasComoConInternet() async {
  for (final nombre in ['Outfit-Regular', 'Outfit-Bold']) {
    final f = File('assets${Platform.pathSeparator}google_fonts'
        '${Platform.pathSeparator}$nombre.ttf');
    await PdfBaseCache.defaultCache.add(nombre, f.readAsBytesSync());
  }
}

/// Mueve el PDF que el servicio acaba de dejar a [nombre], en <salida>.
void _guardarComo(String nombre) {
  final hechos = _pdfs.existsSync()
      ? (_pdfs.listSync().whereType<File>().toList()
        ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync())))
      : <File>[];
  if (hechos.isEmpty) {
    print('   (no salió el PDF de $nombre)');
    return;
  }
  final destino = File('$_salida${Platform.pathSeparator}$nombre');
  if (destino.existsSync()) destino.deleteSync();
  hechos.first.renameSync(destino.path);
  print('   $nombre');
}

String _archivo(String s) => s
    .replaceAll(RegExp(r'[^A-Za-zÁÉÍÓÚÑáéíóúñ0-9 ,_-]'), '')
    .replaceAll(' ', '_');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('los papeles de antes y después', () async {
    expect(_copia, isNotEmpty, reason: 'Falta --dart-define=copia=...');
    expect(_salida, isNotEmpty, reason: 'Falta --dart-define=salida=...');
    expect(_alumnos, isNotEmpty, reason: 'Falta --dart-define=alumnos=...');
    final real = '${Platform.environment['USERPROFILE']}\\Documents\\'
        'Junior Eventos\\data.db';
    expect(File(_copia).absolute.path.toLowerCase(),
        isNot(File(real).absolute.path.toLowerCase()),
        reason: 'Nunca sobre la base real: solo sobre una copia.');

    final temp = Directory.systemTemp.createTempSync('papeles_rotulo');
    final copia = '${temp.path}${Platform.pathSeparator}copia.db';
    File(_copia).copySync(copia);
    _pdfs = Directory(
      '${temp.path}${Platform.pathSeparator}Junior Eventos'
      '${Platform.pathSeparator}PDFs',
    );
    Directory(_salida).createSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => temp.path,
    );

    await _letrasComoConInternet();
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(copia);
    try {
      await MoraCongeladaRepository.cargarRegistroEn(db);
      for (final id in _alumnos.split(';').map((s) => s.trim())) {
        if (id.isEmpty) continue;
        final filas = await db.query('contratos_alumnos',
            where: 'id = ?', whereArgs: [id]);
        if (filas.isEmpty) {
          print('No está el contrato $id');
          continue;
        }
        final c = ContratoAlumno.fromJson(Map<String, dynamic>.from(filas.first));
        final ev = await db.query('eventos',
            where: 'id = ?', whereArgs: [c.eventoId]);
        final eventoJson = Map<String, dynamic>.from(ev.first);
        // Con su institución, como lo arma Mi Empresa → Finanzas.
        final cl = await db.query('clientes',
            where: 'id = ?', whereArgs: [eventoJson['cliente_id']]);
        if (cl.isNotEmpty) {
          eventoJson['clientes'] = Map<String, dynamic>.from(cl.first);
        }
        final evento = Evento.fromJson(eventoJson);
        final pagos = (await db.query('pagos_contrato_alumno',
                where: 'contrato_alumno_id = ?', whereArgs: [c.id]))
            .map((p) => Map<String, dynamic>.from(p))
            .toList();
        final vivos = pagos
            .where((p) => ((p['anulado'] as num?)?.toInt() ?? 0) == 0)
            .toList();
        final nombre = _archivo(c.nombreAlumno);
        print(c.nombreAlumno);

        final moraHist = ReciboDeUnCobro.moraCobradaHistorial(pagos);
        final tracked = c.moraPendienteTracked.clamp(0.0, double.infinity);

        // El Estado de cuenta, antes y después.
        for (final despues in [false, true]) {
          final enriquecidos =
              ConceptoPagoDisplay.enriquecerPagosHistorial(c, vivos);
          if (!despues) {
            for (final p in enriquecidos) {
              if (!ConceptoPagoDisplay.esMora(p)) continue;
              final f = MoraConceptoRotulo.rotuloFichaMora(
                p['concepto_detallado'] as String? ?? p['concepto'] as String,
              );
              p['concepto_ficha'] = f.titulo;
              p.remove('subtexto_ficha');
              if (f.subtexto != null) p['subtexto_ficha'] = f.subtexto;
            }
          }
          var plan = 0.0, mora = 0.0, cargo = 0.0;
          for (final p in enriquecidos) {
            final m = (p['monto'] as num).toDouble();
            if (ConceptoPagoDisplay.esMora(p)) {
              mora += m;
            } else if (ConceptoPagoDisplay.esCargoCanal(p)) {
              cargo += m;
            } else {
              plan += m;
            }
          }
          final arrastre = tracked <= 0.01
              ? const <MoraPendientePreviaDetalle>[]
              : despues
                  ? MoraTrackedOrigen.inferir(
                      contratoBase: c,
                      pagos: pagos,
                      trackedMonto: tracked,
                      recorte: MoraOrigenRecorte.loQueQueda,
                    )
                  : InferirDeLa680.inferir(
                      contratoBase: c,
                      pagos: pagos,
                      trackedMonto: tracked,
                      recorte: MoraOrigenRecorte.loQueQueda,
                    );
          await PdfService.generarEstadoCuentaAlumno(
            alumno: c,
            evento: evento,
            pagos: enriquecidos,
            totalPlanAbonado: plan,
            totalMoraCobrada: mora,
            totalCargoCanal: cargo,
            moraPendiente: MoraCuotaCalculator.moraPendienteOperativa(
              contrato: c,
              moraCobradaHistorial: moraHist,
            ),
            arrastreMora: arrastre,
          );
          _guardarComo(
            '${nombre}_estado_de_cuenta_${despues ? 'despues' : 'antes'}.pdf',
          );
        }

        // Los recibos de los cobros con mora desde [_desde].
        final hoy = ReciboDeUnCobro.moraDeHoy(
          contrato: c,
          historial: pagos,
          moraCobradaHistorial: moraHist,
        );
        final filasMora = vivos
            .where((p) =>
                ConceptoPagoDisplay.esMora(p) &&
                (p['fecha_pago']?.toString() ?? '').compareTo(_desde) >= 0)
            .toList()
          ..sort((a, b) => (a['fecha_pago'] as String)
              .compareTo(b['fecha_pago'] as String));
        final hechos = <String>{};
        for (final fila in filasMora) {
          final lote = ReciboDeUnCobro.lineasDelCobro(pagos, fila);
          final clave = lote.map((p) => p['id']).join(',');
          if (!hechos.add(clave)) continue;
          final fecha = DateTime.parse(fila['fecha_pago'] as String);
          final dia = (fila['fecha_pago'] as String).substring(0, 10);
          final alDia = progresoAlDia(contrato: c, pagos: pagos, hasta: fecha);

          // Antes: REIMPRIMIR del renglón de la mora, ese renglón solo.
          final monto = (fila['monto'] as num).toDouble();
          await PdfService.generarReciboAlumno(
            alumno: c,
            evento: evento,
            montoPagado: monto,
            saldoPendiente: alDia.saldoDeudor,
            conceptosPagados: [
              {
                'concepto': fila['concepto'],
                'monto': monto,
                'esMora': true,
                'esCargoCanal': false,
              },
            ],
            fechaManual: fecha,
            esReimpresion: true,
            cuotasPagadasAlDia: alDia.cuotasBase,
            medioPago: fila['medio_pago'] as String?,
            moraPendienteRestante: hoy.total,
            moraPendienteOrigen: hoy.origen,
            moraPendienteDesglose: hoy.desglose,
            moraPendienteArrastre: hoy.arrastre,
            moraRestanteMedidaEl: DateTime.now(),
          );
          _guardarComo('${nombre}_recibo_${dia}_antes.pdf');

          // Después: el cobro entero, con la nota.
          final cobro = ReciboDeUnCobro.armar(
            contrato: c,
            lote: lote,
            historial: pagos,
          );
          await PdfService.generarReciboAlumno(
            alumno: c,
            evento: evento,
            montoPagado: cobro.montoPagado,
            saldoPendiente: alDia.saldoDeudor,
            conceptosPagados: cobro.conceptos,
            fechaManual: cobro.fecha ?? fecha,
            esReimpresion: true,
            cuotasPagadasAlDia: alDia.cuotasBase,
            medioPago: cobro.medioPago,
            montoEfectivoDetalle: cobro.montoEfectivo,
            montoTransferenciaDetalle: cobro.montoTransferencia,
            porcentajeDescuentoLiquidacion: cobro.porcentajeDescuento,
            moraPendienteRestante: hoy.total,
            moraPendienteOrigen: hoy.origen,
            moraPendienteDesglose: hoy.desglose,
            moraPendienteArrastre: hoy.arrastre,
            moraRestanteMedidaEl: DateTime.now(),
            notasMoraPorCuota:
                ReciboDeUnCobro.conNotas(contrato: c, historial: pagos),
          );
          _guardarComo('${nombre}_recibo_${dia}_despues.pdf');
        }
      }
    } finally {
      MoraCongelada.vaciar();
      await db.close();
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {}
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}
