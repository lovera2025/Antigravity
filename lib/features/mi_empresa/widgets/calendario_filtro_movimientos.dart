import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/utils/ar_time.dart';

/// Qué recorte de tiempo está mirando un historial: todo, un mes o un día.
@immutable
class RangoFiltroMovimientos {
  /// `null` = sin filtro (todo el historial).
  final DateTime? mes;

  /// `null` = el mes entero. Con valor, ese día exacto (calendario AR).
  final DateTime? dia;

  const RangoFiltroMovimientos({this.mes, this.dia});

  const RangoFiltroMovimientos.todo() : mes = null, dia = null;

  bool get esTodo => mes == null && dia == null;

  /// Clave `aaaa-mm-dd` del día **argentino** de una fecha guardada en UTC.
  ///
  /// Las fechas se persisten en UTC y se muestran en hora argentina, así que un
  /// gasto de las 22:00 de un martes está guardado como miércoles 01:00 UTC. Se
  /// compara sobre los componentes ya convertidos y no vía [ArTime.mismoDia],
  /// que aplica el offset a los dos lados y solo cierra si la máquina está en
  /// huso argentino. Así el día que se lee en la fila es el mismo por el que
  /// filtra, corra donde corra.
  static String claveDiaAr(DateTime fechaUtc) {
    final a = ArTime.toAr(fechaUtc);
    return '${a.year}-${a.month.toString().padLeft(2, '0')}-'
        '${a.day.toString().padLeft(2, '0')}';
  }

  static String claveMesAr(DateTime fechaUtc) {
    final a = ArTime.toAr(fechaUtc);
    return '${a.year}-${a.month.toString().padLeft(2, '0')}';
  }

  /// `true` si [fechaUtc] entra en el recorte actual.
  bool contiene(DateTime? fechaUtc) {
    if (esTodo) return true;
    if (fechaUtc == null) return false;
    final d = dia;
    if (d != null) {
      final k = claveDiaAr(fechaUtc);
      return k ==
          '${d.year}-${d.month.toString().padLeft(2, '0')}-'
              '${d.day.toString().padLeft(2, '0')}';
    }
    final m = mes!;
    return claveMesAr(fechaUtc) ==
        '${m.year}-${m.month.toString().padLeft(2, '0')}';
  }

  String get etiqueta {
    if (esTodo) return 'Todo el historial';
    final d = dia;
    if (d != null) {
      return '${d.day} de ${_mesNombre(d.month).toLowerCase()} de ${d.year}';
    }
    return '${_mesNombre(mes!.month)} ${mes!.year}';
  }

  static String _mesNombre(int m) => const [
        'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
        'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
      ][m - 1];
}

/// Grilla mensual para filtrar un historial: tocás un día y filtra ese día,
/// tocás el mes y filtra el mes, `TODO` limpia.
///
/// Los días sin movimientos van apagados y no responden al tacto: la grilla
/// muestra dónde hay algo antes de que lo busques.
class CalendarioFiltroMovimientos extends StatefulWidget {
  /// Fechas (UTC) de los movimientos disponibles, para marcar los días con datos.
  final List<DateTime> fechas;
  final RangoFiltroMovimientos valor;
  final ValueChanged<RangoFiltroMovimientos> onChanged;
  final bool isDark;
  final Color accent;

  const CalendarioFiltroMovimientos({
    super.key,
    required this.fechas,
    required this.valor,
    required this.onChanged,
    required this.isDark,
    required this.accent,
  });

  @override
  State<CalendarioFiltroMovimientos> createState() =>
      _CalendarioFiltroMovimientosState();
}

class _CalendarioFiltroMovimientosState
    extends State<CalendarioFiltroMovimientos> {
  late DateTime _mesVisible;

  @override
  void initState() {
    super.initState();
    _mesVisible = _mesInicial();
  }

  DateTime _mesInicial() {
    final v = widget.valor;
    if (v.dia != null) return DateTime(v.dia!.year, v.dia!.month);
    if (v.mes != null) return DateTime(v.mes!.year, v.mes!.month);
    // Sin filtro: arrancar donde está el movimiento más reciente, no en un mes
    // vacío que obligue a navegar hacia atrás.
    if (widget.fechas.isNotEmpty) {
      final masReciente = widget.fechas.reduce((a, b) => a.isAfter(b) ? a : b);
      final ar = ArTime.toAr(masReciente);
      return DateTime(ar.year, ar.month);
    }
    final hoy = ArTime.nowAr();
    return DateTime(hoy.year, hoy.month);
  }

  /// Días del mes visible que tienen al menos un movimiento.
  Set<int> get _diasConDatos {
    final pref = '${_mesVisible.year}-'
        '${_mesVisible.month.toString().padLeft(2, '0')}-';
    final out = <int>{};
    for (final f in widget.fechas) {
      final k = RangoFiltroMovimientos.claveDiaAr(f);
      if (k.startsWith(pref)) out.add(int.parse(k.substring(8)));
    }
    return out;
  }

  void _mover(int meses) {
    setState(() {
      _mesVisible = DateTime(_mesVisible.year, _mesVisible.month + meses);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final accent = widget.accent;
    final conDatos = _diasConDatos;
    final v = widget.valor;

    final primero = DateTime(_mesVisible.year, _mesVisible.month, 1);
    final diasEnMes =
        DateTime(_mesVisible.year, _mesVisible.month + 1, 0).day;
    // weekday: 1 = lunes … 7 = domingo. La grilla arranca en lunes.
    final huecoInicial = primero.weekday - 1;

    final mesSeleccionado = v.dia == null &&
        v.mes != null &&
        v.mes!.year == _mesVisible.year &&
        v.mes!.month == _mesVisible.month;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black12,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _flecha(Icons.chevron_left_rounded, () => _mover(-1), isDark),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => widget.onChanged(
                    RangoFiltroMovimientos(mes: _mesVisible),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      '${RangoFiltroMovimientos._mesNombre(_mesVisible.month)} '
                      '${_mesVisible.year}',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.oswald(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: mesSeleccionado
                            ? accent
                            : (isDark ? Colors.white70 : Colors.black87),
                      ),
                    ),
                  ),
                ),
              ),
              _flecha(Icons.chevron_right_rounded, () => _mover(1), isDark),
              const SizedBox(width: 4),
              _chipTodo(v.esTodo, accent, isDark),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final d in const ['L', 'M', 'M', 'J', 'V', 'S', 'D'])
                Expanded(
                  child: Text(
                    d,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white30 : Colors.black26,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          ...List.generate(((huecoInicial + diasEnMes) / 7).ceil(), (fila) {
            return Row(
              children: List.generate(7, (col) {
                final n = fila * 7 + col - huecoInicial + 1;
                if (n < 1 || n > diasEnMes) {
                  return const Expanded(child: SizedBox(height: 30));
                }
                return Expanded(
                  child: _celdaDia(
                    n,
                    tieneDatos: conDatos.contains(n),
                    seleccionado: v.dia != null &&
                        v.dia!.year == _mesVisible.year &&
                        v.dia!.month == _mesVisible.month &&
                        v.dia!.day == n,
                    accent: accent,
                    isDark: isDark,
                  ),
                );
              }),
            );
          }),
        ],
      ),
    );
  }

  Widget _flecha(IconData icon, VoidCallback onTap, bool isDark) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          icon,
          size: 18,
          color: isDark ? Colors.white54 : Colors.black45,
        ),
      ),
    );
  }

  Widget _chipTodo(bool activo, Color accent, bool isDark) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => widget.onChanged(const RangoFiltroMovimientos.todo()),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: activo
              ? accent.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: activo
                ? accent.withValues(alpha: 0.5)
                : (isDark ? Colors.white24 : Colors.black26),
          ),
        ),
        child: Text(
          'TODO',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            color: activo
                ? accent
                : (isDark ? Colors.white54 : Colors.black45),
          ),
        ),
      ),
    );
  }

  Widget _celdaDia(
    int n, {
    required bool tieneDatos,
    required bool seleccionado,
    required Color accent,
    required bool isDark,
  }) {
    final color = seleccionado
        ? Colors.white
        : tieneDatos
            ? (isDark ? Colors.white : Colors.black87)
            : (isDark ? Colors.white24 : Colors.black26);

    return SizedBox(
      height: 30,
      child: Center(
        child: InkWell(
          // Cualquier día se puede tocar, tenga o no movimientos. Antes los
          // días vacíos no respondían y el clic quedaba muerto: parecía que el
          // calendario estaba roto. Ahora filtra igual y la lista explica que
          // ese día no hubo nada, que es una respuesta y no un silencio.
          onTap: () => widget.onChanged(
            RangoFiltroMovimientos(
              mes: _mesVisible,
              dia: DateTime(_mesVisible.year, _mesVisible.month, n),
            ),
          ),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: seleccionado ? accent : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  '$n',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: tieneDatos ? FontWeight.w800 : FontWeight.w400,
                    color: color,
                  ),
                ),
                if (tieneDatos && !seleccionado)
                  Positioned(
                    bottom: 1,
                    child: Container(
                      width: 3,
                      height: 3,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
