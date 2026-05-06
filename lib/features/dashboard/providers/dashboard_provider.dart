import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../common/utils/currency_extensions.dart';
import '../../../core/database/local_database.dart';
import '../../../core/utils/ar_time.dart';
import '../../../models/contrato_alumno.dart';



class Alerta {
  final String titulo;
  final String mensaje;
  final IconData icono;
  final Color color;
  final bool isFinanciera;

  Alerta({
    required this.titulo,
    required this.mensaje,
    required this.icono,
    this.color = const Color(0xFFD4AF37),
    this.isFinanciera = false,
  });
}

class DashboardStats {
  final int eventosActivos;
  final int eventosMasivosActivos;
  final int eventosParticularesActivos;
  final double ingresosMes;
  final double egresosMes;
  final double saldoPorCobrar;
  final double morosidadReal;
  final List<Alerta> alertas;
  final List<Map<String, dynamic>> proximosEventos;

  DashboardStats({
    required this.eventosActivos,
    required this.eventosMasivosActivos,
    required this.eventosParticularesActivos,
    required this.ingresosMes,
    required this.egresosMes,
    required this.saldoPorCobrar,
    required this.morosidadReal,
    this.alertas = const [],
    this.proximosEventos = const [],
  });

  factory DashboardStats.empty() => DashboardStats(
        eventosActivos: 0,
        eventosMasivosActivos: 0,
        eventosParticularesActivos: 0,
        ingresosMes: 0,
        egresosMes: 0,
        saldoPorCobrar: 0,
        morosidadReal: 0,
        alertas: [],
        proximosEventos: [],
      );
}

final dashboardStatsProvider = FutureProvider<DashboardStats>((ref) async {
  try {
    final db = await LocalDatabase.instance;
    final now = DateTime.now();
    final firstDayOfMonth = DateTime(now.year, now.month, 1).toIso8601String();

    // 1. Eventos Activos
    final eventosRes = await db.rawQuery('''
      SELECT e.*, c.nombre_completo as cliente_nombre
      FROM eventos e
      JOIN clientes c ON e.cliente_id = c.id
      WHERE e.estado NOT IN ('Finalizado', 'Cancelado')
    ''');
    
    final List<Map<String, dynamic>> eventosData = eventosRes.map((e) {
      return {
        ...e,
        'clientes': {'nombre_completo': e['cliente_nombre']}
      };
    }).toList();
    
    final totalEventos = eventosData.length;
    final int masivos = eventosData.where((e) => e['modalidad'] == 'masivo').length;
    final int particulares = eventosData.where((e) => e['modalidad'] == 'particular').length;

    // 2. Ingresos del Mes (Transacciones + Pagos Contrato)
    final transRes = await db.rawQuery('''
      SELECT SUM(monto) as total FROM transacciones WHERE fecha_pago >= ? AND COALESCE(anulado, 0) = 0
    ''', [firstDayOfMonth]);
    
    final pagosRes = await db.rawQuery('''
      SELECT SUM(monto) as total FROM pagos_contrato_alumno WHERE fecha_pago >= ? AND COALESCE(anulado, 0) = 0
    ''', [firstDayOfMonth]);

    final double totalIngresos = (double.tryParse(transRes.first['total']?.toString() ?? '0') ?? 0) +
                                (double.tryParse(pagosRes.first['total']?.toString() ?? '0') ?? 0);

    // 3. Egresos del Mes
    final egresosRes = await db.rawQuery('''
      SELECT SUM(monto) as total FROM egresos WHERE fecha >= ?
    ''', [firstDayOfMonth]);
    final double totalEgresos = double.tryParse(egresosRes.first['total']?.toString() ?? '0') ?? 0;

    // 4 & 5. Saldo por Cobrar y Morosidad
    double totalSaldo = 0.0;
    double morosidadReal = 0.0;
    List<Alerta> alertas = [];

    // --- SECCIÓN MASIVOS ---
    final contratosRes = await db.rawQuery('''
      SELECT ca.*, ev.tipo as evento_tipo, c.nombre_completo as cliente_nombre
      FROM contratos_alumnos ca
      JOIN eventos ev ON ca.evento_id = ev.id
      JOIN clientes c ON ev.cliente_id = c.id
      WHERE ev.estado IN ('Confirmado', 'Planificacion')
      AND ca.nombre_alumno NOT LIKE '[BAJA]%'
    ''');

    final Map<String, double> moraPorEvento = {};
    final Map<String, int> alumnosConMoraPorEvento = {};
    final Map<String, String> nombresEventoMap = {};
    double saldoAVencerProximamente = 0.0;
    
    for (var row in contratosRes) {
      final double saldoTotal = (row['saldo_deudor'] as num?)?.toDouble() ?? 0;
      if (saldoTotal < 0.01) continue;

      final String eventoId = row['evento_id'].toString();
      nombresEventoMap[eventoId] = row['cliente_nombre']?.toString() ?? 'Institución';

      final c = ContratoAlumno.fromJson(Map<String, dynamic>.from(row));
      final inscrip = c.createdAt ?? now;
      final inscAr = ArTime.toAr(inscrip);
      final tCuotas = c.totalCuotas > 0 ? c.totalCuotas : 1;
      
      // Cálculo de cuota base
      final totalBase = (c.montoTotalPactado - c.mesaExtraPrecio - c.sillasExtraPrecioTotal).clamp(0.0, double.infinity);
      final cuotaBase = tCuotas > 0 ? totalBase / tCuotas : 0.0;
      final cuotaBaseR = double.parse(cuotaBase.toStringAsFixed(2));

      int cuotasVencidasCount = 0;
      bool proximaAVencer = false;

      for (int k = c.cuotasPagadas + 1; k <= tCuotas; k++) {
        // Usamos la misma lógica que MoraCuotaCalculator para determinar vencimiento (último día del mes k)
        var m = inscAr.month + k;
        var y = inscAr.year;
        while (m > 12) { m -= 12; y++; }
        final vK = DateTime(y, m, DateTime(y, m + 1, 0).day);
        final vKSolo = DateTime(vK.year, vK.month, vK.day);
        final hoySolo = DateTime(now.year, now.month, now.day);

        if (hoySolo.isAfter(vKSolo)) {
          cuotasVencidasCount++;
        } else if (vKSolo.difference(hoySolo).inDays <= 30) {
          // Si no está vencida pero vence en los próximos 30 días
          proximaAVencer = true;
          break; // solo contamos la inmediata a vencer
        } else {
          break; // muy lejos en el futuro
        }
      }

      if (cuotasVencidasCount > 0) {
        final double montoMora = (cuotasVencidasCount * cuotaBaseR).clamp(0.0, saldoTotal);
        morosidadReal += montoMora;
        moraPorEvento[eventoId] = (moraPorEvento[eventoId] ?? 0) + montoMora;
        alumnosConMoraPorEvento[eventoId] = (alumnosConMoraPorEvento[eventoId] ?? 0) + 1;
      }

      if (proximaAVencer) {
        // Sumamos la cuota que está por vencer en el horizonte de 30 días
        final double restanteTrasMora = (saldoTotal - (cuotasVencidasCount * cuotaBaseR)).clamp(0.0, saldoTotal);
        saldoAVencerProximamente += cuotaBaseR.clamp(0.0, restanteTrasMora);
      }
    }

    // El total saldo que mostramos en el HUD será la suma de lo vencido + lo que vence pronto
    totalSaldo = morosidadReal + saldoAVencerProximamente;

    // Alertas Masivos
    for (var entry in alumnosConMoraPorEvento.entries) {
      final evId = entry.key;
      final cant = entry.value;
      final totalMora = moraPorEvento[evId] ?? 0;
      final nombre = nombresEventoMap[evId] ?? 'Evento';

      alertas.add(Alerta(
        titulo: 'GESTIÓN DE COBROS: $nombre',
        mensaje: '⚠️ $cant ${cant == 1 ? 'alumno' : 'alumnos'} con mora vencida (${totalMora.toCurrency()}).',
        icono: Icons.warning_amber_rounded,
        color: Colors.redAccent,
        isFinanciera: true,
      ));
    }


    // --- SECCIÓN PARTICULARES ---
    // DISTINCT dedup: sync can leave duplicate rows in eventos_servicios (different id, same content).
    final particularesRes = await db.rawQuery('''
      SELECT 
        e.id, e.tipo, e.fecha_evento, e.bonificacion_global_pct,
        (SELECT SUM(pfa * cant) FROM (
           SELECT DISTINCT servicio_id, precio_final_acordado as pfa, cantidad as cant, grupo, combo_orden
           FROM eventos_servicios WHERE evento_id = e.id
        )) as presupuesto_base,
        (SELECT SUM(monto) FROM transacciones WHERE evento_id = e.id AND COALESCE(anulado, 0) = 0) as recaudado,
        c.nombre_completo as cliente_nombre
      FROM eventos e
      JOIN clientes c ON e.cliente_id = c.id
      WHERE e.modalidad = 'particular' AND e.estado IN ('Confirmado', 'Planificacion')
    ''');

    for (var ev in particularesRes) {
      final double presupuestoBase = (ev['presupuesto_base'] as num?)?.toDouble() ?? 0;
      final double bonificacionPct = (ev['bonificacion_global_pct'] as num?)?.toDouble() ?? 0;
      final double presupuestoFinal = presupuestoBase * (1 - (bonificacionPct / 100));
      
      final double recaudado = (ev['recaudado'] as num?)?.toDouble() ?? 0;
      final double saldoReal = (presupuestoFinal - recaudado).clamp(0.0, double.infinity);
      
      if (saldoReal > 0.01) {
        final String? fechaStr = ev['fecha_evento']?.toString();
        DateTime? fechaEvento = fechaStr != null ? DateTime.tryParse(fechaStr) : null;
        final String nombreCli = ev['cliente_nombre']?.toString() ?? 'Cliente';

        if (fechaEvento != null && fechaEvento.isBefore(now)) {
          // Evento pasado con saldo = Mora Crítica
          morosidadReal += saldoReal;
          totalSaldo += saldoReal;
          alertas.add(Alerta(
            titulo: 'MORA EN EVENTO PARTICULAR',
            mensaje: '⚠️ $nombreCli: Mora crítica de ${saldoReal.toCurrency()}.',
            icono: Icons.warning_amber_rounded,
            color: Colors.redAccent,
            isFinanciera: true,
          ));
        } else if (fechaEvento != null && fechaEvento.difference(now).inDays <= 30) {
          // Evento próximo (30 días) = Saldo a vencer
          totalSaldo += saldoReal;
        } else if (recaudado < (presupuestoFinal * 0.30) - 0.01) {
          // Seña pendiente (aunque el evento esté lejos)
          final double faltante = (presupuestoFinal * 0.30) - recaudado;
          alertas.add(Alerta(
            titulo: 'SEÑA PENDIENTE',
            mensaje: '⚠️ $nombreCli: Seña del 30% pendiente (${faltante.toCurrency()}).',
            icono: Icons.payments_outlined,
            color: Colors.orangeAccent,
            isFinanciera: true,
          ));
        }
      }
    }

    // Alertas Próximos Eventos
    for (var ev in eventosData) {
      if (ev['fecha_evento'] != null) {
        try {
          final fechaEv = DateTime.parse(ev['fecha_evento']);
          final diff = fechaEv.difference(now).inDays;
          if (diff >= 0 && diff <= 7) {
            alertas.add(Alerta(
              titulo: 'EVENTO CERCANO',
              mensaje: 'Faltan $diff días para el evento de ${ev['clientes']?['nombre_completo']}.',
              icono: Icons.timer_outlined,
              color: const Color(0xFFD4AF37),
            ));
          }
        } catch (_) {}
      }
    }

    // --- SECCIÓN PRESUPUESTOS ---
    final presupuestosRes = await db.rawQuery('''
      SELECT p.*, c.nombre_completo as cliente_nombre
      FROM presupuestos p
      LEFT JOIN clientes c ON p.cliente_id = c.id
      WHERE p.estado = 'activo'
    ''');

    for (var p in presupuestosRes) {
      final String? fechaStr = p['fecha_vencimiento']?.toString();
      if (fechaStr != null) {
        final fechaVenc = DateTime.tryParse(fechaStr);
        if (fechaVenc != null && fechaVenc.isBefore(now)) {
          final nombreCli = p['cliente_nombre'] ?? 'Cliente';
          alertas.add(Alerta(
            titulo: 'PRESUPUESTO VENCIDO',
            mensaje: '⌛ El presupuesto de $nombreCli ha expirado. ¡Turno de re-contactar!.',
            icono: Icons.timer_off_outlined,
            color: const Color(0xFFD4AF37),
          ));
        }
      }
    }

    // --- SECCIÓN AVISOS Y OBLIGACIONES ---
    try {
      final obligacionesRes = await db.rawQuery('''
        SELECT * FROM obligaciones_pago WHERE estado = 'pendiente'
      ''');
      final fmtFecha = DateFormat('dd/MM/yyyy');
      for (var o in obligacionesRes) {
        final titulo = o['titulo']?.toString().trim().isNotEmpty == true
            ? o['titulo']!.toString().trim()
            : 'Obligación sin título';
        final tipo = o['tipo_obligacion']?.toString() ?? 'empresa';
        final montoEst = (o['monto_estimado'] as num?)?.toDouble() ?? 0.0;
        final fStr = o['fecha_vencimiento']?.toString();
        if (fStr != null) {
          final fVenc = DateTime.tryParse(fStr);
          if (fVenc != null) {
            final hoy = DateTime(now.year, now.month, now.day);
            final fv = DateTime(fVenc.year, fVenc.month, fVenc.day);
            final dias = fv.difference(hoy).inDays;

            final alcance = tipo == 'empresa'
                ? 'Cuenta o servicio de la empresa.'
                : 'Gasto o cuenta personal (no es de la empresa).';
            final montoTxt = montoEst > 0.01
                ? ' Monto referencia: ${montoEst.toCurrency()}.'
                : '';
            final fechaLeg = fmtFecha.format(fv);

            final prefix = tipo == 'empresa' ? 'EMPRESA' : 'PERSONAL';
            final alertTitle = 'PAGO: $prefix · $titulo';

            if (dias < 0) {
              alertas.add(Alerta(
                titulo: alertTitle,
                mensaje:
                    '$alcance La fecha de pago era el $fechaLeg y ya pasó hace ${dias.abs()} día(s). '
                    'Revisá si ya lo pagaste y registrá el pago en Finanzas → Avisos.$montoTxt',
                icono: Icons.error_outline,
                color: Colors.redAccent,
                isFinanciera: false,
              ));
            } else if (dias == 0) {
              alertas.add(Alerta(
                titulo: alertTitle,
                mensaje:
                    '$alcance Hoy ($fechaLeg) vence el pago de «$titulo». '
                    'No lo dejes pasar: entrá a Finanzas → pestaña Avisos y marcá cuando pagues.$montoTxt',
                icono: Icons.warning_amber_rounded,
                color: Colors.redAccent,
                isFinanciera: false,
              ));
            } else if (dias <= 3) {
              alertas.add(Alerta(
                titulo: alertTitle,
                mensaje:
                    '$alcance Quedan $dias día(s) hasta el vencimiento ($fechaLeg) para «$titulo». '
                    'Anticipate y anotá el pago en Avisos cuando esté hecho.$montoTxt',
                icono: Icons.timer_outlined,
                color: Colors.orangeAccent,
                isFinanciera: false,
              ));
            }
          }
        }
      }
    } catch (_) {}

    // Próximos 5 eventos
    final proximosEventos = eventosData
        .where((e) => e['fecha_evento'] != null)
        .where((e) {
          final fecha = DateTime.tryParse(e['fecha_evento'] ?? '');
          return fecha != null && fecha.isAfter(now);
        })
        .toList()
      ..sort((a, b) => a['fecha_evento'].compareTo(b['fecha_evento']));

    return DashboardStats(
      eventosActivos: totalEventos,
      eventosMasivosActivos: masivos,
      eventosParticularesActivos: particulares,
      ingresosMes: totalIngresos,
      egresosMes: totalEgresos,
      saldoPorCobrar: totalSaldo,
      morosidadReal: morosidadReal,
      alertas: alertas,
      proximosEventos: proximosEventos.take(5).toList(),
    );
  } catch (e) {
    debugPrint('❌ Error en dashboardStatsProvider (SQLite): $e');
    return DashboardStats.empty();
  }
});
