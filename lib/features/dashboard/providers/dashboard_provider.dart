import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../common/utils/currency_extensions.dart';
import '../../../core/database/local_database.dart';


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
      SELECT SUM(monto) as total FROM transacciones WHERE fecha_pago >= ?
    ''', [firstDayOfMonth]);
    
    final pagosRes = await db.rawQuery('''
      SELECT SUM(monto) as total FROM pagos_contrato_alumno WHERE fecha_pago >= ?
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

    for (var row in contratosRes) {
      final double saldo = (row['saldo_deudor'] as num?)?.toDouble() ?? 0;
      totalSaldo += saldo;

      if (saldo < 0.01) continue; // alumno liquidado, nada que alertar

      final String eventoId = row['evento_id'].toString();
      final int diaVencimiento = (row['dia_vencimiento_mensual'] as int?) ?? 10;
      final int totalCuotas = (row['total_cuotas'] as int?) ?? 9;
      final int cuotasPagadas = (row['cuotas_pagadas'] as int?) ?? 0;
      final double montoTotal = (row['monto_total_pactado'] as num?)?.toDouble() ?? 0;
      nombresEventoMap[eventoId] = row['cliente_nombre']?.toString() ?? 'Institución';

      // Calcular cuántas cuotas ya deberían haber vencido desde que se creó el contrato
      final String? createdAtStr = row['created_at']?.toString();
      DateTime fechaInicio = createdAtStr != null
          ? (DateTime.tryParse(createdAtStr) ?? now)
          : now;

      // Mes de inicio del contrato
      final inicioMes = DateTime(fechaInicio.year, fechaInicio.month, 1);
      final mesCorriente = DateTime(now.year, now.month, 1);

      // Diferencia en meses desde inicio
      int mesesTranscurridos = (mesCorriente.year - inicioMes.year) * 12 +
          (mesCorriente.month - inicioMes.month);

      // Si el día de vencimiento de este mes ya pasó, el mes actual también vence
      if (now.day >= diaVencimiento) {
        mesesTranscurridos += 1;
      }

      // Cuotas esperadas = min(meses transcurridos, total_cuotas)
      final int cuotasEsperadas = mesesTranscurridos.clamp(0, totalCuotas);

      // Mora real: cuántas cuotas faltan pagar de las ya vencidas
      final int cuotasEnMora = (cuotasEsperadas - cuotasPagadas).clamp(0, totalCuotas);

      if (cuotasEnMora > 0 && montoTotal > 0.01 && totalCuotas > 0) {
        final double cuotaMensual = montoTotal / totalCuotas;
        final double montoMora = cuotaMensual * cuotasEnMora;
        morosidadReal += montoMora;
        moraPorEvento[eventoId] = (moraPorEvento[eventoId] ?? 0) + montoMora;
        alumnosConMoraPorEvento[eventoId] = (alumnosConMoraPorEvento[eventoId] ?? 0) + 1;
      }
    }

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
    final particularesRes = await db.rawQuery('''
      SELECT 
        e.id, e.tipo, e.fecha_evento,
        c.nombre_completo as cliente_nombre,
        (SELECT SUM(precio_final_acordado) FROM eventos_servicios WHERE evento_id = e.id) as presupuesto,
        (SELECT SUM(monto) FROM transacciones WHERE evento_id = e.id) as recaudado
      FROM eventos e
      JOIN clientes c ON e.cliente_id = c.id
      WHERE e.modalidad = 'particular' AND e.estado IN ('Confirmado', 'Planificacion')
    ''');

    for (var ev in particularesRes) {
      final double presupuesto = (ev['presupuesto'] as num?)?.toDouble() ?? 0;
      final double recaudado = (ev['recaudado'] as num?)?.toDouble() ?? 0;
      final double saldoReal = (presupuesto - recaudado).clamp(0.0, presupuesto);
      
      if (saldoReal > 0.01) {
        totalSaldo += saldoReal;
        final String nombreCli = ev['cliente_nombre']?.toString() ?? 'Cliente';
        final String? fechaStr = ev['fecha_evento']?.toString();
        DateTime? fechaEvento = fechaStr != null ? DateTime.tryParse(fechaStr) : null;

        if (fechaEvento != null && fechaEvento.isBefore(now)) {
          morosidadReal += saldoReal;
          alertas.add(Alerta(
            titulo: 'MORA EN EVENTO PARTICULAR',
            mensaje: '⚠️ $nombreCli: Mora crítica de ${saldoReal.toCurrency()}.',
            icono: Icons.warning_amber_rounded,
            color: Colors.redAccent,
            isFinanciera: true,
          ));
        } else if (recaudado < (presupuesto * 0.30) - 0.01) {
          final double faltante = (presupuesto * 0.30) - recaudado;
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
