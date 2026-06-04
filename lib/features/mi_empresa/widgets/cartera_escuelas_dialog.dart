import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/database/local_database.dart';
import '../../../core/utils/ar_time.dart';
import '../../../models/contrato_alumno.dart';
import '../../common/utils/currency_extensions.dart';
import '../../dashboard/providers/dashboard_provider.dart';

/// Diálogo interactivo premium estilo Maestro-Detalle para analizar las
/// deudas y moras pendientes desglosadas por escuela / institución.
class CarteraEscuelasDialog extends ConsumerStatefulWidget {
  const CarteraEscuelasDialog({super.key});

  @override
  ConsumerState<CarteraEscuelasDialog> createState() => _CarteraEscuelasDialogState();
}

class _CarteraEscuelasDialogState extends ConsumerState<CarteraEscuelasDialog> {
  final _searchEscuelaCtrl = TextEditingController();
  final _searchAlumnoCtrl = TextEditingController();
  
  String? _selectedInstitucionId;
  String? _selectedInstitucionNombre;
  
  bool _loadingAlumnos = false;
  List<ContratoAlumno> _alumnosDeuda = [];
  
  // Totales dinámicos cargados para la escuela seleccionada
  double _totalSaldoGlobal = 0.0;
  double _totalVencido = 0.0;
  double _totalAVencer = 0.0;
  double _totalPorCuotaBase = 0.0; // Valor mensual agregado "por vez"

  @override
  void initState() {
    super.initState();
    _searchEscuelaCtrl.addListener(() => setState(() {}));
    _searchAlumnoCtrl.addListener(() => setState(() {}));
    
    // Pre-seleccionar la primera institución al cargar si hay datos
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _preseleccionarPrimera();
    });
  }

  @override
  void dispose() {
    _searchEscuelaCtrl.dispose();
    _searchAlumnoCtrl.dispose();
    super.dispose();
  }

  void _preseleccionarPrimera() {
    final statsAsync = ref.read(dashboardStatsProvider);
    statsAsync.whenData((stats) {
      if (stats.deudasPorInstitucion.isNotEmpty) {
        final primera = stats.deudasPorInstitucion.first;
        _seleccionarEscuela(primera.id, primera.nombre);
      }
    });
  }

  Future<void> _seleccionarEscuela(String id, String nombre) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _selectedInstitucionId = id;
      _selectedInstitucionNombre = nombre;
      _loadingAlumnos = true;
      _alumnosDeuda = [];
      _searchAlumnoCtrl.clear();
    });

    try {
      final db = await LocalDatabase.instance;
      // Traemos todos los contratos activos asociados al cliente de la escuela seleccionada
      final rows = await db.rawQuery('''
        SELECT ca.*
        FROM contratos_alumnos ca
        JOIN eventos ev ON ca.evento_id = ev.id
        WHERE ev.cliente_id = ?
          AND ca.nombre_alumno NOT LIKE '[BAJA]%'
          AND ca.saldo_deudor > 0.01
        ORDER BY ca.nombre_alumno COLLATE NOCASE ASC
      ''', [id]);

      final contratos = rows.map((r) => ContratoAlumno.fromJson(r)).toList();
      final now = ArTime.nowAr();

      double sumSaldoGlobal = 0.0;
      double sumVencido = 0.0;
      double sumAVencer = 0.0;
      double sumPorCuota = 0.0;

      for (var c in contratos) {
        sumSaldoGlobal += c.saldoDeudor;

        // Calcular cuota base
        final tCuotas = c.totalCuotas > 0 ? c.totalCuotas : 1;
        final totalBase = (c.montoTotalPactado - c.mesaExtraPrecio - c.sillasExtraPrecioTotal).clamp(0.0, double.infinity);
        final cuotaBase = tCuotas > 0 ? totalBase / tCuotas : 0.0;
        final cuotaBaseR = double.parse(cuotaBase.toStringAsFixed(2));

        // Acumulamos el valor mensual sumado "por vez"
        sumPorCuota += cuotaBaseR;

        // Calcular vencido y a vencer del alumno
        // Sumar morosidad vencida teórica
        int cuotasVencidasCount = 0;
        bool proximaAVencer = false;
        final inscrip = c.createdAt ?? now;
        final inscAr = ArTime.toAr(inscrip);

        for (int k = c.cuotasPagadas + 1; k <= tCuotas; k++) {
          var m = inscAr.month + k;
          var y = inscAr.year;
          while (m > 12) { m -= 12; y++; }
          final vK = DateTime(y, m, DateTime(y, m + 1, 0).day);
          final vKSolo = DateTime(vK.year, vK.month, vK.day);
          final hoySolo = DateTime(now.year, now.month, now.day);

          if (hoySolo.isAfter(vKSolo)) {
            cuotasVencidasCount++;
          } else if (vKSolo.difference(hoySolo).inDays <= 30) {
            proximaAVencer = true;
            break;
          } else {
            break;
          }
        }

        if (cuotasVencidasCount > 0) {
          sumVencido += (cuotasVencidasCount * cuotaBaseR).clamp(0.0, c.saldoDeudor);
        }
        if (proximaAVencer) {
          final double restanteTrasMora = (c.saldoDeudor - (cuotasVencidasCount * cuotaBaseR)).clamp(0.0, c.saldoDeudor);
          sumAVencer += cuotaBaseR.clamp(0.0, restanteTrasMora);
        }
      }

      if (mounted) {
        setState(() {
          _alumnosDeuda = contratos;
          _totalSaldoGlobal = sumSaldoGlobal;
          _totalVencido = sumVencido;
          _totalAVencer = sumAVencer;
          _totalPorCuotaBase = sumPorCuota;
          _loadingAlumnos = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingAlumnos = false);
        messenger.showSnackBar(
          SnackBar(content: Text('Error al cargar alumnos de la escuela: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(dashboardStatsProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    final gold = const Color(0xFFD4AF37);
    final coral = const Color(0xFFE74C3C);
    final emerald = const Color(0xFF2ECC71);
    
    final bgDialog = isDark ? const Color(0xFF131315) : Colors.white;
    final bgCard = isDark ? Colors.white.withValues(alpha: 0.02) : theme.cardColor;
    final borderColor = isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08);

    return Dialog(
      backgroundColor: bgDialog,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 1100,
        height: 650,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: statsAsync.when(
            data: (stats) {
              // Filtrar escuelas
              final queryEscuela = _searchEscuelaCtrl.text.toLowerCase().trim();
              final escuelasFiltradas = stats.deudasPorInstitucion.where((esc) {
                return esc.nombre.toLowerCase().contains(queryEscuela);
              }).toList();

              return Row(
                children: [
                  // ── PANEL IZQUIERDO: LISTA DE ESCUELAS ─────────────────────
                  Container(
                    width: 320,
                    decoration: BoxDecoration(
                      border: Border(right: BorderSide(color: borderColor, width: 1.5)),
                      color: isDark ? const Color(0xFF0F0F11) : Colors.grey.shade50,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Cabecera Panel Izquierdo
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ESCUELAS E INSTITUCIONES',
                                style: GoogleFonts.oswald(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: gold,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Buscador de escuelas
                              TextField(
                                controller: _searchEscuelaCtrl,
                                style: const TextStyle(fontSize: 12),
                                decoration: InputDecoration(
                                  hintText: 'Buscar colegio...',
                                  prefixIcon: const Icon(Icons.search_rounded, size: 16),
                                  suffixIcon: _searchEscuelaCtrl.text.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear_rounded, size: 16),
                                          onPressed: () => _searchEscuelaCtrl.clear(),
                                        )
                                      : null,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(color: borderColor),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(color: borderColor),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(color: gold.withValues(alpha: 0.5)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        // Listado de Escuelas
                        Expanded(
                          child: escuelasFiltradas.isEmpty
                              ? Center(
                                  child: Text(
                                    'No se encontraron escuelas',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark ? Colors.white30 : Colors.black38,
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: escuelasFiltradas.length,
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  separatorBuilder: (context, index) => const SizedBox(height: 6),
                                  itemBuilder: (context, index) {
                                    final esc = escuelasFiltradas[index];
                                    final isSelected = esc.id == _selectedInstitucionId;

                                    return InkWell(
                                      onTap: () => _seleccionarEscuela(esc.id, esc.nombre),
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? gold.withValues(alpha: isDark ? 0.08 : 0.12)
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: isSelected
                                                ? gold.withValues(alpha: 0.3)
                                                : Colors.transparent,
                                            width: 1,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              esc.nombre,
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                                color: isSelected
                                                    ? (isDark ? Colors.white : Colors.black87)
                                                    : (isDark ? Colors.white70 : Colors.black54),
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                  'Subtotal: ${(esc.vencido + esc.aVencer).toCurrency()}',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: esc.vencido > 0.01 ? coral : gold,
                                                  ),
                                                ),
                                                Text(
                                                  'Global: ${esc.saldoGlobal.toCurrency()}',
                                                  style: TextStyle(
                                                    fontSize: 10.5,
                                                    color: isDark ? Colors.white30 : Colors.black38,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),

                  // ── PANEL DERECHO: DETALLE DE DEUDAS Y ALUMNOS ────────────────
                  Expanded(
                    child: Container(
                      color: bgDialog,
                      child: _selectedInstitucionId == null
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.school_outlined, size: 48, color: isDark ? Colors.white10 : Colors.black12),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Seleccione una escuela para ver su desglose',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isDark ? Colors.white30 : Colors.black38,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Cabecera del detalle
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _selectedInstitucionNombre ?? 'DETALLE DE LA INSTITUCIÓN',
                                              style: GoogleFonts.oswald(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: gold,
                                                letterSpacing: 1.0,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Cartera deudora e indicadores financieros agregados.',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: isDark ? Colors.white30 : Colors.black38,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close_rounded),
                                        onPressed: () => Navigator.of(context).pop(),
                                      ),
                                    ],
                                  ),
                                ),

                                // ── INDICADORES CLAVE (KPI CARDS) ─────────────────────
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 24),
                                  child: Row(
                                    children: [
                                      // 1. Saldo Global Deudor
                                      Expanded(
                                        child: _buildKPICard(
                                          title: 'SALDO GLOBAL DEUDOR',
                                          value: _totalSaldoGlobal,
                                          color: gold,
                                          subtitle: 'Total pendiente en contratos',
                                          isDark: isDark,
                                          bgCard: bgCard,
                                          borderColor: borderColor,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // 2. Vencido (Mora Real)
                                      Expanded(
                                        child: _buildKPICard(
                                          title: 'MORA VENCIDA',
                                          value: _totalVencido,
                                          color: coral,
                                          subtitle: 'Cuotas con retraso real',
                                          isDark: isDark,
                                          bgCard: bgCard,
                                          borderColor: borderColor,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // 3. A Vencer (Próx. 30 días)
                                      Expanded(
                                        child: _buildKPICard(
                                          title: 'A VENCER (30 DÍAS)',
                                          value: _totalAVencer,
                                          color: gold,
                                          subtitle: 'Próxima cuota del mes',
                                          isDark: isDark,
                                          bgCard: bgCard,
                                          borderColor: borderColor,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // 4. Valor "Por Vez" (Cuota mensual agregada)
                                      Expanded(
                                        child: _buildKPICard(
                                          title: 'CUOTA AGREGADA',
                                          value: _totalPorCuotaBase,
                                          color: emerald,
                                          subtitle: 'Total "por cuota" mensual',
                                          isDark: isDark,
                                          bgCard: bgCard,
                                          borderColor: borderColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 20),

                                // ── DESGLOSE DE ALUMNOS (SECCIÓN INFERIOR) ─────────────
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 24),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'DESGLOSE DE ALUMNOS CON DEUDA',
                                        style: GoogleFonts.oswald(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: gold,
                                          letterSpacing: 1.0,
                                        ),
                                      ),
                                      // Buscador de alumnos
                                      SizedBox(
                                        width: 250,
                                        height: 36,
                                        child: TextField(
                                          controller: _searchAlumnoCtrl,
                                          style: const TextStyle(fontSize: 11.5),
                                          decoration: InputDecoration(
                                            hintText: 'Buscar alumno...',
                                            prefixIcon: const Icon(Icons.person_search_rounded, size: 15),
                                            suffixIcon: _searchAlumnoCtrl.text.isNotEmpty
                                                ? IconButton(
                                                    icon: const Icon(Icons.clear_rounded, size: 14),
                                                    onPressed: () => _searchAlumnoCtrl.clear(),
                                                  )
                                                : null,
                                            contentPadding: const EdgeInsets.symmetric(vertical: 0),
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(8),
                                              borderSide: BorderSide(color: borderColor),
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(8),
                                              borderSide: BorderSide(color: borderColor),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(8),
                                              borderSide: BorderSide(color: gold.withValues(alpha: 0.5)),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 10),

                                // Listado de Alumnos (Tabla Premium)
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                                    child: _loadingAlumnos
                                        ? Center(child: CircularProgressIndicator(color: gold))
                                        : _buildAlumnosTable(isDark, borderColor, gold, coral, emerald),
                                  ),
                                ),
                              ],
                            ),
                  ),
                ),
              ],
            );
          },
            loading: () => Center(child: CircularProgressIndicator(color: gold)),
            error: (err, st) => Center(
              child: Text(
                'Error al cargar estadísticas: $err',
                style: TextStyle(color: coral),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Tarjeta de KPI Financiero de Alta Gama
  Widget _buildKPICard({
    required String title,
    required double value,
    required Color color,
    required String subtitle,
    required bool isDark,
    required Color bgCard,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white38 : Colors.black45,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.toCurrency(),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 8.5,
              color: isDark ? Colors.white30 : Colors.black38,
            ),
          ),
        ],
      ),
    );
  }

  // Tabla Premium e Interactiva de Alumnos
  Widget _buildAlumnosTable(bool isDark, Color borderColor, Color gold, Color coral, Color emerald) {
    final queryAlumno = _searchAlumnoCtrl.text.toLowerCase().trim();
    final alumnosFiltrados = _alumnosDeuda.where((a) {
      return a.nombreAlumno.toLowerCase().contains(queryAlumno) ||
          (a.cursoDivision ?? '').toLowerCase().contains(queryAlumno);
    }).toList();

    if (alumnosFiltrados.isEmpty) {
      return Center(
        child: Text(
          'No se encontraron alumnos con saldo pendiente',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white24 : Colors.black38,
          ),
        ),
      );
    }

    final headerStyle = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w800,
      color: isDark ? Colors.white38 : Colors.black45,
      letterSpacing: 1.0,
    );

    return Column(
      children: [
        // Cabecera Fija
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.01) : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Expanded(flex: 3, child: Text('ALUMNO', style: headerStyle)),
              Expanded(flex: 2, child: Text('CURSO', style: headerStyle)),
              Expanded(flex: 2, child: Text('PLAN DE PAGO', style: headerStyle, textAlign: TextAlign.center)),
              Expanded(flex: 2, child: Text('MORA VENCIDA', style: headerStyle, textAlign: TextAlign.right)),
              Expanded(flex: 2, child: Text('SALDO GLOBAL', style: headerStyle, textAlign: TextAlign.right)),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // Cuerpo del Listado
        Expanded(
          child: ListView.separated(
            itemCount: alumnosFiltrados.length,
            padding: const EdgeInsets.only(bottom: 12),
            separatorBuilder: (context, index) => const SizedBox(height: 4),
            itemBuilder: (context, index) {
              final a = alumnosFiltrados[index];
              final now = ArTime.nowAr();

              // Calcular cuota base y estado
              final tCuotas = a.totalCuotas > 0 ? a.totalCuotas : 1;
              final totalBase = (a.montoTotalPactado - a.mesaExtraPrecio - a.sillasExtraPrecioTotal).clamp(0.0, double.infinity);
              final cuotaBase = tCuotas > 0 ? totalBase / tCuotas : 0.0;
              final cuotaBaseR = double.parse(cuotaBase.toStringAsFixed(2));

              // Calcular mora vencida acumulada teórica
              int cuotasVencidasCount = 0;
              final inscrip = a.createdAt ?? now;
              final inscAr = ArTime.toAr(inscrip);

              for (int k = a.cuotasPagadas + 1; k <= tCuotas; k++) {
                var m = inscAr.month + k;
                var y = inscAr.year;
                while (m > 12) { m -= 12; y++; }
                final vK = DateTime(y, m, DateTime(y, m + 1, 0).day);
                final vKSolo = DateTime(vK.year, vK.month, vK.day);
                final hoySolo = DateTime(now.year, now.month, now.day);

                if (hoySolo.isAfter(vKSolo)) {
                  cuotasVencidasCount++;
                } else {
                  break;
                }
              }

              final double moraVencida = (cuotasVencidasCount * cuotaBaseR).clamp(0.0, a.saldoDeudor);

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: borderColor.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    // Alumno (Nombre)
                    Expanded(
                      flex: 3,
                      child: Text(
                        a.nombreAlumno,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Curso / División
                    Expanded(
                      flex: 2,
                      child: Text(
                        (a.cursoDivision ?? 'Sin division').trim(),
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white38 : Colors.black45,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Cuotas Pagadas / Totales
                    Expanded(
                      flex: 2,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: a.cuotasPagadas >= tCuotas
                                ? emerald.withValues(alpha: 0.1)
                                : gold.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${a.cuotasPagadas} / $tCuotas cuotas',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: a.cuotasPagadas >= tCuotas ? emerald : gold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Mora Vencida
                    Expanded(
                      flex: 2,
                      child: Text(
                        moraVencida > 0.01 ? moraVencida.toCurrency() : '\$0,00',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: moraVencida > 0.01 ? coral : (isDark ? Colors.white30 : Colors.black38),
                        ),
                      ),
                    ),
                    // Saldo Global
                    Expanded(
                      flex: 2,
                      child: Text(
                        a.saldoDeudor.toCurrency(),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
