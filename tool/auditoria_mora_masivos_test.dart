// AUDITORÍA DE MORA — SOLO LECTURA. No modifica la base ni encola sync.
// Uso: flutter test tool/auditoria_mora_masivos_test.dart
//
// Compara, alumno por alumno de todos los eventos masivos:
//   - mora que la app está mostrando/cobrando hoy (estado actual de la DB)
//   - mora que corresponde según la lógica "a mes vencido" reconstruida desde
//     el historial de pagos real (cuotas derivadas del gross + replay tracked)
// y clasifica las diferencias.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/core/utils/ar_time.dart';
import 'package:arguello_events/features/eventos/services/cobro_abono_acumulado.dart';
import 'package:arguello_events/features/eventos/services/cronograma_cuotas_utils.dart';
import 'package:arguello_events/features/eventos/services/mora_cuota_calculator.dart';
import 'package:arguello_events/features/eventos/services/mora_tracked_recovery.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

String _dbPath() {
  final home = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      '';
  return '$home${Platform.pathSeparator}Documents${Platform.pathSeparator}'
      'Junior Eventos${Platform.pathSeparator}data.db';
}

String _outPath() {
  final tmp = Platform.environment['TEMP'] ?? Platform.environment['TMP'] ?? '.';
  return '$tmp${Platform.pathSeparator}auditoria_mora.txt';
}

String _f(double v) => v.toStringAsFixed(2);
String _d(DateTime? d) => d == null
    ? '—'
    : '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';

class Fila {
  final String institucion;
  final String evento;
  final String alumno;
  final DateTime? regAr;
  final int cuotasDb;
  final int cuotasReales;
  final int totalCuotas;
  final double saldoDb;
  final double saldoReal;
  final double cuotaBase;
  final DateTime? vencProx;
  final int diasAtraso;
  final double trackedDb;
  final double trackedObj;
  final double offsetDb;
  final double offsetObj;
  final DateTime? exentaHasta;
  final double moraCobrada;
  final double moraActual;
  final double moraCorrecta;
  final List<String> flags;
  final List<String> desgloseActual;
  final List<String> desgloseCorrecto;
  final int cantPagos;
  final DateTime? ultimoPago;

  Fila({
    required this.institucion,
    required this.evento,
    required this.alumno,
    required this.regAr,
    required this.cuotasDb,
    required this.cuotasReales,
    required this.totalCuotas,
    required this.saldoDb,
    required this.saldoReal,
    required this.cuotaBase,
    required this.vencProx,
    required this.diasAtraso,
    required this.trackedDb,
    required this.trackedObj,
    required this.offsetDb,
    required this.offsetObj,
    required this.exentaHasta,
    required this.moraCobrada,
    required this.moraActual,
    required this.moraCorrecta,
    required this.flags,
    required this.desgloseActual,
    required this.desgloseCorrecto,
    required this.cantPagos,
    required this.ultimoPago,
  });

  double get diff => double.parse((moraActual - moraCorrecta).toStringAsFixed(2));
  bool get moraDeMas => diff > 0.5;
  bool get moraDeMenos => diff < -0.5;
}

void main() {
  test('auditoria mora global (solo lectura)', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      _dbPath(),
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );

    final hoy = ArTime.nowAr();
    final hoySolo = DateTime(hoy.year, hoy.month, hoy.day);

    final rows = await db.rawQuery('''
      SELECT c.*,
             cl.nombre_completo AS evento_nombre,
             e.estado           AS evento_estado,
             e.modalidad        AS evento_modalidad
      FROM contratos_alumnos c
      JOIN eventos e   ON e.id = c.evento_id
      LEFT JOIN clientes cl ON cl.id = e.cliente_id
      WHERE e.modalidad = 'masivo'
      ORDER BY c.institucion COLLATE NOCASE,
               cl.nombre_completo COLLATE NOCASE,
               c.nombre_alumno COLLATE NOCASE
    ''');

    final filas = <Fila>[];

    for (final row in rows) {
      final estadoEvento = (row['evento_estado'] as String?) ?? '';
      final c = ContratoAlumno.fromJson(row);

      final pagos = await db.query(
        'pagos_contrato_alumno',
        where: 'contrato_alumno_id = ?',
        whereArgs: [c.id],
        orderBy: 'fecha_pago',
      );
      final activos = pagos
          .where((p) => ((p['anulado'] as num?)?.toInt() ?? 0) == 0)
          .toList();

      // Mora efectivamente cobrada en el historial.
      final moraCobrada = activos.where((p) {
        final lk = (p['line_kind'] as String?)?.trim() ?? '';
        final cl = (p['concepto'] as String? ?? '').toLowerCase();
        return lk == 'interes_mora' ||
            cl.contains('mora') ||
            cl.contains('interés') ||
            cl.contains('interes');
      }).fold<double>(0, (s, p) => s + ((p['monto'] as num?)?.toDouble() ?? 0));

      // Progreso real reconstruido desde los pagos (gross), no desde columnas.
      final recalc = recalcularSaldoDesdePagos(
        montoTotalPactado: c.montoTotalPactado,
        totalCuotas: c.totalCuotas,
        mesaExtraPrecio: c.mesaExtraPrecio,
        sillasExtraPrecioTotal: c.sillasExtraPrecioTotal,
        precioUnitarioMesaExtra: c.precioUnitarioMesaExtra,
        mesaExtraCuotas: c.mesaExtraCuotas,
        mesaExtraCantidad: c.mesaExtraCantidad,
        sillasExtraCuotas: c.sillasExtraCuotas,
        pagos: activos,
      );

      // --- MORA ACTUAL (lo que ve/cobra la app hoy) ---
      final detActual = MoraCuotaCalculator.moraPendienteOperativaDetallada(
        contrato: c,
        moraCobradaHistorial: moraCobrada,
        ahoraAr: hoy,
      );

      // --- MORA CORRECTA (mes vencido + historial real) ---
      final obj = MoraTrackedRecovery.objetivoDesdeHistorial(
        contrato: c,
        pagos: pagos,
      );
      final cuotasReales = recalc.cuotasBase;
      final cCorrecto = c.copyWith(
        cuotasPagadas:
            cuotasReales > c.cuotasPagadas ? cuotasReales : c.cuotasPagadas,
        saldoDeudor: recalc.saldoDeudor,
        moraPendienteTracked: obj.tracked,
        moraCobradaOffset: obj.offset,
      );
      final detCorrecto = MoraCuotaCalculator.moraPendienteOperativaDetallada(
        contrato: cCorrecto,
        moraCobradaHistorial: moraCobrada,
        ahoraAr: hoy,
      );

      final resumen = MoraCuotaCalculator.calcular(c, hoy);
      final prox = CronogramaCuotasUtils.proximaCuotaSecuencial(c, hoy);

      // ---- Flags ----
      final flags = <String>[];
      if (c.esBajaTemporal) flags.add('BAJA');
      if (estadoEvento != 'Confirmado' && estadoEvento != 'Planificacion') {
        flags.add('EVENTO_$estadoEvento');
      }
      if (cuotasReales > c.cuotasPagadas) {
        flags.add(
            'PROGRESO_DESACTUALIZADO(db ${c.cuotasPagadas} < pagos $cuotasReales)');
      }
      if (cuotasReales < c.cuotasPagadas) {
        flags.add(
            'CUOTAS_INFLADAS(db ${c.cuotasPagadas} > pagos $cuotasReales)');
      }
      if ((recalc.saldoDeudor - c.saldoDeudor).abs() > 1.0) {
        flags.add(
            'SALDO_DESCUADRADO(db ${_f(c.saldoDeudor)} vs pagos ${_f(recalc.saldoDeudor)})');
      }
      if (c.saldoDeudor <= 0.01 && c.moraPendienteTracked > 0.01) {
        flags.add('MORA_EN_LIQUIDADO');
      }
      if (c.moraPendienteTracked > 0.01 && c.cuotasPagadas <= 0) {
        flags.add('TRACKED_SIN_CUOTA_LIQUIDADA');
      }
      if (c.moraPendienteTracked > 0.01 && obj.tracked <= 0.01) {
        flags.add('TRACKED_SIN_RESPALDO_HISTORIAL');
      }
      if ((c.moraPendienteTracked - obj.tracked).abs() > 0.5) {
        flags.add(
            'TRACKED_DIVERGE(db ${_f(c.moraPendienteTracked)} vs replay ${_f(obj.tracked)})');
      }
      if ((c.moraCobradaOffset - obj.offset).abs() > 0.5) {
        flags.add(
            'OFFSET_DIVERGE(db ${_f(c.moraCobradaOffset)} vs replay ${_f(obj.offset)})');
      }
      if (c.createdAt != null) {
        final reg = ArTime.toAr(c.createdAt!);
        if (DateTime(reg.year, reg.month, reg.day).isAfter(hoySolo)) {
          flags.add('REG_FUTURO');
        }
      } else {
        flags.add('SIN_REG');
      }
      if (c.moraFechaReferencia != null) {
        flags.add('MORA_CONGELADA(${_d(c.moraFechaReferencia)})');
      }
      if (c.moraExentaHasta != null) {
        flags.add(
            'EXENTA_HASTA(${_d(c.moraExentaHasta)}${c.moraExencionReinicia ? "" : ", permanente"})');
      }

      DateTime? ultPago;
      if (activos.isNotEmpty) {
        final f = activos.last['fecha_pago']?.toString();
        final p = f == null ? null : DateTime.tryParse(f);
        if (p != null) ultPago = ArTime.toAr(p);
      }

      filas.add(Fila(
        institucion: (c.institucion ?? '').trim().isEmpty
            ? ((row['evento_nombre'] as String?) ?? 'Sin institución')
            : c.institucion!.trim(),
        evento: (row['evento_nombre'] as String?) ?? '—',
        alumno: c.nombreAlumno,
        regAr: c.createdAt != null ? ArTime.toAr(c.createdAt!) : null,
        cuotasDb: c.cuotasPagadas,
        cuotasReales: cuotasReales,
        totalCuotas: c.totalCuotas,
        saldoDb: c.saldoDeudor,
        saldoReal: recalc.saldoDeudor,
        cuotaBase: MoraCuotaCalculator.cuotaBaseDe(c),
        vencProx: prox?.vencimiento ?? resumen.fechaVencimientoProximaCuota,
        diasAtraso: resumen.diasMora,
        trackedDb: c.moraPendienteTracked,
        trackedObj: obj.tracked,
        offsetDb: c.moraCobradaOffset,
        offsetObj: obj.offset,
        exentaHasta: c.moraExentaHasta,
        moraCobrada: moraCobrada,
        moraActual: detActual.total,
        moraCorrecta: detCorrecto.total,
        flags: flags,
        desgloseActual: detActual.desglose
            .map((d) => 'C${d.numeroCuota} ${d.mesLabel} '
                '(vto ${_d(d.vencimiento)}, ${d.diasMora}d) \$${_f(d.interesBruto)}')
            .toList(),
        desgloseCorrecto: detCorrecto.desglose
            .map((d) => 'C${d.numeroCuota} ${d.mesLabel} '
                '(vto ${_d(d.vencimiento)}, ${d.diasMora}d) \$${_f(d.interesBruto)}')
            .toList(),
        cantPagos: activos.length,
        ultimoPago: ultPago,
      ));
    }

    await db.close();

    // ------------------- REPORTE -------------------
    final b = StringBuffer();
    void w(String s) => b.writeln(s);

    w('AUDITORÍA DE MORA — EVENTOS MASIVOS');
    w('Fecha de corte (AR): ${_d(hoySolo)}');
    w('Regla: cuota N vence el ÚLTIMO DÍA del mes (mes de alta + N). '
        'Mora corre desde el día siguiente, 1% de la cuota base por día.');
    w('Contratos analizados: ${filas.length}');
    w('');

    final deMas = filas.where((f) => f.moraDeMas).toList()
      ..sort((a, x) => x.diff.compareTo(a.diff));
    final deMenos = filas.where((f) => f.moraDeMenos).toList()
      ..sort((a, x) => a.diff.compareTo(x.diff));
    final conMoraOk = filas
        .where((f) => !f.moraDeMas && !f.moraDeMenos && f.moraCorrecta > 0.5)
        .toList();
    final sinMora = filas
        .where((f) => f.moraActual <= 0.5 && f.moraCorrecta <= 0.5)
        .toList();

    w('=' * 78);
    w('RESUMEN');
    w('=' * 78);
    w('Mora aplicada DE MÁS (no corresponde / sobra): ${deMas.length} alumnos  '
        '— \$${_f(deMas.fold<double>(0, (s, f) => s + f.diff))}');
    w('Mora aplicada DE MENOS (falta cobrar):        ${deMenos.length} alumnos  '
        '— \$${_f(-deMenos.fold<double>(0, (s, f) => s + f.diff))}');
    w('Mora correcta y con mora vigente:             ${conMoraOk.length} alumnos');
    w('Sin mora (correcto):                          ${sinMora.length} alumnos');
    w('');
    w('Mora total que la app muestra hoy:   \$${_f(filas.fold<double>(0, (s, f) => s + f.moraActual))}');
    w('Mora total que corresponde:          \$${_f(filas.fold<double>(0, (s, f) => s + f.moraCorrecta))}');
    w('');

    // Resumen por institución
    w('=' * 78);
    w('POR INSTITUCIÓN');
    w('=' * 78);
    final porInst = <String, List<Fila>>{};
    for (final f in filas) {
      porInst.putIfAbsent(f.institucion, () => []).add(f);
    }
    final instOrden = porInst.keys.toList()..sort();
    for (final inst in instOrden) {
      final g = porInst[inst]!;
      final gMas = g.where((f) => f.moraDeMas).length;
      final gMenos = g.where((f) => f.moraDeMenos).length;
      final actual = g.fold<double>(0, (s, f) => s + f.moraActual);
      final correcta = g.fold<double>(0, (s, f) => s + f.moraCorrecta);
      w('$inst');
      w('   alumnos: ${g.length} | mora app: \$${_f(actual)} | '
          'mora correcta: \$${_f(correcta)} | de más: $gMas | de menos: $gMenos');
    }
    w('');

    void detalle(String titulo, List<Fila> lista) {
      w('=' * 78);
      w(titulo);
      w('=' * 78);
      if (lista.isEmpty) {
        w('(ninguno)');
        w('');
        return;
      }
      String? instActual;
      for (final f in lista) {
        if (f.institucion != instActual) {
          instActual = f.institucion;
          w('');
          w('--- $instActual ---');
        }
        w('');
        w('${f.alumno}   [${f.evento}]');
        w('   Reg (alta): ${_d(f.regAr)}  |  cuotas: ${f.cuotasDb}/${f.totalCuotas} '
            '(según pagos: ${f.cuotasReales})  |  pagos: ${f.cantPagos}'
            '${f.ultimoPago != null ? " (último ${_d(f.ultimoPago)})" : ""}');
        w('   Cuota base: \$${_f(f.cuotaBase)}  |  saldo: \$${_f(f.saldoDb)}'
            '${(f.saldoReal - f.saldoDb).abs() > 1.0 ? " (según pagos \$${_f(f.saldoReal)})" : ""}');
        w('   Próx. vencimiento: ${_d(f.vencProx)}  |  días de atraso: ${f.diasAtraso}');
        w('   MORA QUE MUESTRA LA APP: \$${_f(f.moraActual)}   →   '
            'MORA QUE CORRESPONDE: \$${_f(f.moraCorrecta)}   '
            '(diferencia \$${_f(f.diff)})');
        w('   tracked: \$${_f(f.trackedDb)} (debería \$${_f(f.trackedObj)})  |  '
            'offset: \$${_f(f.offsetDb)} (debería \$${_f(f.offsetObj)})  |  '
            'mora ya cobrada: \$${_f(f.moraCobrada)}');
        if (f.desgloseActual.isNotEmpty) {
          w('   Desglose que aplica hoy:');
          for (final d in f.desgloseActual) {
            w('      $d');
          }
        }
        if (f.desgloseCorrecto.isNotEmpty) {
          w('   Desglose correcto:');
          for (final d in f.desgloseCorrecto) {
            w('      $d');
          }
        }
        if (f.flags.isNotEmpty) w('   MOTIVO: ${f.flags.join(' | ')}');
      }
      w('');
    }

    detalle('A) MORA DE MÁS — no les corresponde (o sobra)', deMas);
    detalle('B) MORA DE MENOS — les falta mora', deMenos);

    // Listado compacto de quienes SÍ deben tener mora.
    w('=' * 78);
    w('C) ALUMNOS QUE SÍ DEBEN TENER MORA (correcta, a mes vencido)');
    w('=' * 78);
    final debenMora = filas.where((f) => f.moraCorrecta > 0.5).toList()
      ..sort((a, x) {
        final i = a.institucion.compareTo(x.institucion);
        return i != 0 ? i : x.moraCorrecta.compareTo(a.moraCorrecta);
      });
    String? instC;
    for (final f in debenMora) {
      if (f.institucion != instC) {
        instC = f.institucion;
        w('');
        w('--- $instC ---');
      }
      w('  ${f.alumno.padRight(38).substring(0, 38)}  '
          'venc ${_d(f.vencProx)}  ${f.diasAtraso.toString().padLeft(3)}d  '
          'mora \$${_f(f.moraCorrecta).padLeft(10)}'
          '${f.moraActual != f.moraCorrecta ? "   (app: \$${_f(f.moraActual)})" : ""}');
    }
    w('');

    // Anomalías estructurales aunque la mora coincida.
    w('=' * 78);
    w('D) INCONSISTENCIAS DE DATOS (revisar aunque la mora dé igual)');
    w('=' * 78);
    final anomalias = filas
        .where((f) => f.flags.any((x) =>
            x.startsWith('PROGRESO_DESACTUALIZADO') ||
            x.startsWith('CUOTAS_INFLADAS') ||
            x.startsWith('SALDO_DESCUADRADO') ||
            x.startsWith('TRACKED_SIN_RESPALDO') ||
            x.startsWith('TRACKED_SIN_CUOTA') ||
            x.startsWith('TRACKED_DIVERGE') ||
            x.startsWith('OFFSET_DIVERGE') ||
            x == 'MORA_EN_LIQUIDADO' ||
            x == 'REG_FUTURO' ||
            x == 'SIN_REG'))
        .toList();
    if (anomalias.isEmpty) {
      w('(ninguna)');
    } else {
      String? instD;
      for (final f in anomalias) {
        if (f.institucion != instD) {
          instD = f.institucion;
          w('');
          w('--- $instD ---');
        }
        w('  ${f.alumno}  → ${f.flags.join(' | ')}');
      }
    }
    w('');

    final out = File(_outPath());
    await out.writeAsString(b.toString());

    // Consola: solo el resumen (el detalle queda en el archivo).
    final lineas = b.toString().split('\n');
    final corte = lineas.indexWhere((l) => l.startsWith('A) MORA DE MÁS'));
    // ignore: avoid_print
    print(lineas.take(corte > 0 ? corte : lineas.length).join('\n'));
    // ignore: avoid_print
    print('\n>>> Reporte completo: ${out.path}');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
